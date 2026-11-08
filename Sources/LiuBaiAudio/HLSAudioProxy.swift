import Foundation
import LiuBaiCore
import Network

/// Gives AVPlayer a native HLS view of DASH's existing AAC fragments. Bound to
/// loopback only, with an unguessable path; no files, video, or account cookies.
final class HLSAudioProxy: @unchecked Sendable {
    let index: DASHAudioIndex
    let client: AudioRangeClient
    private let remoteURL: URL
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "app.liubai.audio-hls")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var cancelled = false
    private(set) var url: URL!
    // All startup state callbacks execute on the listener's serial queue.
    private final class StartState: @unchecked Sendable { var resumed = false }
    var transferredBytes: Int64 { client.transferredBytes }

    static func prepare(url: URL) async throws -> HLSAudioProxy? {
        let client = AudioRangeClient()
        do {
            let prefix = try await client.data(url: url, range: AudioByteRange(offset: 0, length: 65_536))
            try Task.checkCancellation()
            guard let index = try DASHAudioIndex.parse(prefix) else { client.cancel(); return nil }
            let proxy = HLSAudioProxy(index: index, client: client, remoteURL: url)
            do { try await proxy.start(); try Task.checkCancellation(); return proxy }
            catch { proxy.cancel(); throw error }
        } catch { client.cancel(); throw error }
    }

    private init(index: DASHAudioIndex, client: AudioRangeClient, remoteURL: URL) {
        self.index = index; self.client = client; self.remoteURL = remoteURL
    }

    private func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let startup = StartState()
            listener.stateUpdateHandler = { [weak self] state in
                guard !startup.resumed else { return }
                switch state {
                case .ready:
                    startup.resumed = true
                    guard let self, let port = listener.port else { continuation.resume(throwing: URLError(.cannotConnectToHost)); return }
                    self.url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/index.m3u8")!
                    continuation.resume()
                case .failed(let error): startup.resumed = true; continuation.resume(throwing: error)
                case .cancelled: startup.resumed = true; continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, !self.cancelled else { connection.cancel(); return }
                let id = UUID()
                self.connections[id] = connection
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .failed, .cancelled:
                        self?.jobs.removeValue(forKey: id)?.cancel()
                        self?.connections.removeValue(forKey: id)
                    default: break
                    }
                }
                connection.start(queue: self.queue)
                self.receive(connection, id: id, header: Data())
            }
            listener.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, header: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - header.count) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var header = header
            if let bytes { header.append(bytes) }
            if let delimiter = header.range(of: Data("\r\n\r\n".utf8)),
               let text = String(data: header[..<delimiter.lowerBound], encoding: .utf8) {
                self.handle(text, connection: connection, id: id)
            } else if error != nil || complete || header.count >= 8192 { connection.cancel() }
            else { self.receive(connection, id: id, header: header) }
        }
    }

    private func handle(_ header: String, connection: NWConnection, id: UUID) {
        let lines = header.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count == 3, ["GET", "HEAD"].contains(first[0]), first[1].hasPrefix("/\(token)/") else {
            respond(connection, status: 404, data: Data()); return
        }
        let name = String(first[1].dropFirst(token.count + 2))
        let headOnly = first[0] == "HEAD"
        let rangeHeader = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if name == "index.m3u8" {
            respond(connection, data: index.playlist, contentType: "application/vnd.apple.mpegurl", headOnly: headOnly)
        } else if name == "init.mp4" {
            serve(index.initialization, rangeHeader: rangeHeader, connection: connection, headOnly: headOnly)
        } else if name.hasPrefix("segment-"), name.hasSuffix(".m4s"),
                  let number = Int(name.dropFirst(8).dropLast(4)), index.segments.indices.contains(number) {
            let segment = index.segments[number]
            guard let selected = localRange(rangeHeader, length: segment.range.length) else { respond(connection, status: 416, data: Data()); return }
            jobs[id] = Task { [weak self] in
                guard let self else { return }
                do {
                    let range = AudioByteRange(offset: segment.range.offset + selected.offset, length: selected.length)
                    let bytes = try await client.data(url: remoteURL, range: range)
                    queue.async { [weak self] in
                        guard let self, !self.cancelled else { connection.cancel(); return }
                        self.jobs.removeValue(forKey: id)
                        self.respond(connection, status: rangeHeader == nil ? 200 : 206, data: bytes, contentType: "audio/mp4", headOnly: headOnly,
                                     contentRange: rangeHeader == nil ? nil : "bytes \(selected.offset)-\(selected.end)/\(segment.range.length)")
                    }
                } catch {
                    queue.async { [weak self] in self?.jobs.removeValue(forKey: id); self?.respond(connection, status: 502, data: Data()) }
                }
            }
        } else { respond(connection, status: 404, data: Data()) }
    }

    private func localRange(_ value: String?, length: Int64) -> AudioByteRange? {
        guard let value else { return AudioByteRange(offset: 0, length: length) }
        guard value.hasPrefix("bytes=") else { return nil }
        let pieces = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2, let start = Int64(pieces[0]), start >= 0, start < length else { return nil }
        let end = pieces[1].isEmpty ? length - 1 : (Int64(pieces[1]) ?? -1)
        guard end >= start else { return nil }
        return AudioByteRange(offset: start, length: min(end, length - 1) - start + 1)
    }

    private func serve(_ bytes: Data, rangeHeader: String?, connection: NWConnection, headOnly: Bool) {
        guard let range = localRange(rangeHeader, length: Int64(bytes.count)) else { respond(connection, status: 416, data: Data()); return }
        respond(connection, status: rangeHeader == nil ? 200 : 206, data: bytes.subdata(in: Int(range.offset)..<Int(range.offset + range.length)),
                contentType: "audio/mp4", headOnly: headOnly,
                contentRange: rangeHeader == nil ? nil : "bytes \(range.offset)-\(range.end)/\(bytes.count)")
    }

    private func respond(_ connection: NWConnection, status: Int = 200, data: Data, contentType: String = "text/plain", headOnly: Bool = false, contentRange: String? = nil) {
        let reason = [200: "OK", 206: "Partial Content", 404: "Not Found", 416: "Range Not Satisfiable", 502: "Bad Gateway"][status] ?? "Error"
        var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nAccept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if let contentRange { header += "Content-Range: \(contentRange)\r\n" }
        header += "\r\n"
        var response = Data(header.utf8)
        if !headOnly { response.append(data) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    func cancel() {
        client.cancel()
        queue.async { [self] in
            guard !cancelled else { return }
            cancelled = true
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel(); listener = nil
            jobs.values.forEach { $0.cancel() }; jobs.removeAll()
            connections.values.forEach { $0.cancel() }; connections.removeAll()
        }
    }
}
