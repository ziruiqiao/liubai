import AVFoundation
import Foundation
import LiuBaiCore
import UniformTypeIdentifiers

/// Supplies authenticated HTTP ranges through AVFoundation's public resource
/// loader API. It streams bytes to AVPlayer without a video view or local download.
public final class AudioResource {
    public let asset: AVURLAsset
    private let loader: AudioResourceLoader?
    private let proxy: HLSAudioProxy?
    public var transferredBytes: Int64 { loader.map { loader in loader.queue.sync { loader.transferredBytes } } ?? proxy?.transferredBytes ?? 0 }
    public var usesIndexedSegments: Bool { proxy != nil }

    public static func streaming(url: URL) async throws -> AudioResource {
        if let proxy = try await HLSAudioProxy.prepare(url: url) { return AudioResource(proxy: proxy) }
        return AudioResource(url: url)
    }

    private init(proxy: HLSAudioProxy) {
        self.proxy = proxy
        loader = nil
        asset = AVURLAsset(url: proxy.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
    }

    public init(url: URL) {
        let loader = AudioResourceLoader(remoteURL: url)
        self.loader = loader
        proxy = nil
        asset = AVURLAsset(url: URL(string: "liubai-audio://stream/\(UUID().uuidString).m4a")!, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
    }
    public func cancel() { asset.cancelLoading(); loader?.invalidate(); proxy?.cancel() }
    deinit { loader?.invalidate(); proxy?.cancel() }
}

private final class AudioResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    let queue = DispatchQueue(label: "app.liubai.audio-ranges")
    private let remoteURL: URL
    private var contexts: [Int: Context] = [:]
    private var invalidated = false
    private let diagnose = ProcessInfo.processInfo.environment["LIUBAI_TRACE_AUDIO"] == "1"
    fileprivate var transferredBytes: Int64 = 0
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 24 * 3600
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.underlyingQueue = queue
        return URLSession(configuration: configuration, delegate: self, delegateQueue: operationQueue)
    }()

    private final class Context {
        let request: AVAssetResourceLoadingRequest
        let task: URLSessionDataTask
        let offset: Int64
        var bytesToSkip: Int64 = 0
        init(request: AVAssetResourceLoadingRequest, task: URLSessionDataTask, offset: Int64) {
            self.request = request; self.task = task; self.offset = offset
        }
    }

    init(remoteURL: URL) { self.remoteURL = remoteURL; super.init() }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard !invalidated else { return false }
        let data = loadingRequest.dataRequest
        let offset = max(data?.currentOffset ?? 0, data?.requestedOffset ?? 0)
        if diagnose { print("Audio range request: offset=\(offset) length=\(data?.requestedLength ?? 0) toEnd=\(data?.requestsAllDataToEndOfResource ?? false) info=\(loadingRequest.contentInformationRequest != nil)") }
        var request = URLRequest(url: remoteURL)
        request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BilibiliClient.referer, forHTTPHeaderField: "Referer")
        if let data, !data.requestsAllDataToEndOfResource {
            let end = data.requestedOffset + Int64(data.requestedLength) - 1
            request.setValue("bytes=\(offset)-\(max(offset, end))", forHTTPHeaderField: "Range")
        } else if data != nil {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        } else { request.setValue("bytes=0-1", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        contexts[task.taskIdentifier] = Context(request: loadingRequest, task: task, offset: offset)
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        guard let pair = contexts.first(where: { $0.value.request === loadingRequest }) else { return }
        contexts.removeValue(forKey: pair.key)
        pair.value.task.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let context = contexts[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); return
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            contexts.removeValue(forKey: dataTask.taskIdentifier)
            context.request.finishLoading(with: BilibiliError.network(http.statusCode))
            completionHandler(.cancel); return
        }
        let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? ""
        if diagnose { print("Audio range response: \(http.statusCode) \(contentRange)") }
        let length = contentRange.split(separator: "/").last.flatMap { Int64($0) } ?? response.expectedContentLength
        if let information = context.request.contentInformationRequest {
            information.contentType = UTType.mpeg4Audio.identifier
            information.contentLength = max(0, length)
            information.isByteRangeAccessSupported = http.statusCode == 206 || http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
        }
        // Some CDNs ignore Range. Discard preceding bytes instead of returning
        // incorrect offsets to the decoder.
        if http.statusCode == 200 { context.bytesToSkip = context.offset }
        completionHandler(.allow)
        if context.request.dataRequest == nil {
            contexts.removeValue(forKey: dataTask.taskIdentifier)
            context.request.finishLoading()
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let context = contexts[dataTask.taskIdentifier], let request = context.request.dataRequest else { return }
        transferredBytes += Int64(data.count)
        var bytes = data
        if context.bytesToSkip > 0 {
            let skip = min(Int64(bytes.count), context.bytesToSkip)
            context.bytesToSkip -= skip
            bytes = bytes.dropFirst(Int(skip))
        }
        guard !bytes.isEmpty else { return }
        if !request.requestsAllDataToEndOfResource {
            let remaining = max(0, request.requestedOffset + Int64(request.requestedLength) - request.currentOffset)
            bytes = bytes.prefix(Int(min(remaining, Int64(bytes.count))))
        }
        if !bytes.isEmpty { request.respond(with: bytes) }
        if !request.requestsAllDataToEndOfResource && request.currentOffset >= request.requestedOffset + Int64(request.requestedLength) {
            contexts.removeValue(forKey: dataTask.taskIdentifier)
            context.request.finishLoading()
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let context = contexts.removeValue(forKey: task.taskIdentifier) else { return }
        if let error { context.request.finishLoading(with: error) }
        else { context.request.finishLoading() }
    }

    func invalidate() {
        queue.async { [self] in
            guard !invalidated else { return }
            invalidated = true
            for context in contexts.values {
                context.request.finishLoading(with: URLError(.cancelled))
                context.task.cancel()
            }
            contexts.removeAll()
            session.invalidateAndCancel()
        }
    }
}
