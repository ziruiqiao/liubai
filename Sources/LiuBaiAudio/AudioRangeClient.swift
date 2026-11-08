import Foundation
import LiuBaiCore

/// Bounded, memory-only range reads. Reject an ignored Range header before
/// accepting its body, so an uncooperative CDN cannot download an entire song.
final class AudioRangeClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession!
    private var requests: [Int: Request] = [:]
    private var cancelled = false
    private var received: Int64 = 0
    var transferredBytes: Int64 { lock.withLock { received } }
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false
        func bind(_ task: URLSessionTask) { lock.withLock { self.task = task; if cancelled { task.cancel() } } }
        func cancel() { lock.withLock { cancelled = true; task?.cancel() } }
    }
    private final class Request {
        let task: URLSessionDataTask
        let range: AudioByteRange
        let continuation: CheckedContinuation<Data, Error>
        var data = Data()
        var expectedLength: Int64 = 0
        init(task: URLSessionDataTask, range: AudioByteRange, continuation: CheckedContinuation<Data, Error>) {
            self.task = task; self.range = range; self.continuation = continuation
        }
    }

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func data(url: URL, range: AudioByteRange) async throws -> Data {
        try Task.checkCancellation()
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !cancelled, !Task.isCancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            var request = URLRequest(url: url)
            request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BilibiliClient.referer, forHTTPHeaderField: "Referer")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("bytes=\(range.offset)-\(range.end)", forHTTPHeaderField: "Range")
            let task = session.dataTask(with: request)
            requests[task.taskIdentifier] = Request(task: task, range: range, continuation: continuation)
            lock.unlock()
            cancellation.bind(task)
            task.resume()
        }
        }, onCancel: { cancellation.cancel() })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard let request = requests[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else { lock.unlock(); completionHandler(.cancel); return }
        let parts = (http.value(forHTTPHeaderField: "Content-Range") ?? "").split(separator: " ").last?.split(separator: "/").first?.split(separator: "-") ?? []
        let first = parts.first.flatMap { Int64($0) }, last = parts.last.flatMap { Int64($0) }
        guard http.statusCode == 206, parts.count == 2, first == request.range.offset,
              let last, last >= request.range.offset, last <= request.range.end else {
            requests.removeValue(forKey: dataTask.taskIdentifier)
            lock.unlock()
            request.continuation.resume(throwing: BilibiliError.network(http.statusCode))
            completionHandler(.cancel)
            return
        }
        request.expectedLength = last - request.range.offset + 1
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let request = requests[dataTask.taskIdentifier] else { lock.unlock(); return }
        received += Int64(data.count)
        guard Int64(request.data.count) + Int64(data.count) <= request.expectedLength else {
            requests.removeValue(forKey: dataTask.taskIdentifier)
            lock.unlock()
            request.continuation.resume(throwing: BilibiliError.invalidResponse)
            dataTask.cancel(); return
        }
        request.data.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let request = lock.withLock { requests.removeValue(forKey: task.taskIdentifier) }
        guard let request else { return }
        if let error { request.continuation.resume(throwing: error) }
        else if Int64(request.data.count) != request.expectedLength { request.continuation.resume(throwing: BilibiliError.invalidResponse) }
        else { request.continuation.resume(returning: request.data) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pending = Array(requests.values); requests.removeAll()
        lock.unlock()
        pending.forEach { $0.task.cancel(); $0.continuation.resume(throwing: CancellationError()) }
        session.invalidateAndCancel()
    }
}
