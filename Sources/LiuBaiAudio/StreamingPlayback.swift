import AVFoundation
import Foundation

/// AVPlayer's throughput prediction assumes it owns the HTTP transfer. With a
/// resource-loader delegate, Apple requires disabling that prediction; otherwise
/// long progressive audio can remain in "minimizing stalls" for a long time.
@MainActor
public final class StreamingPlayback {
    public let player = AVPlayer()
    public private(set) var wantsToPlay = false
    private var observations: [NSKeyValueObservation] = []
    private var stallObserver: NSObjectProtocol?

    public init() { player.automaticallyWaitsToMinimizeStalling = false }

    @discardableResult
    public func replace(with asset: AVAsset) -> AVPlayerItem {
        clear()
        // Native HLS owns its HTTP transfers and can recover from a stall.
        // Only the progressive custom-loader fallback opts out of prediction.
        let scheme = (asset as? AVURLAsset)?.url.scheme
        player.automaticallyWaitsToMinimizeStalling = scheme == "http" || scheme == "https"
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        item.preferredForwardBufferDuration = 5
        player.replaceCurrentItem(with: item)
        observations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.wantsToPlay, self.player.currentItem === item, item.status == .readyToPlay else { return }
                    self.player.playImmediately(atRate: 1)
                }
            },
            item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in self?.recoverIfBuffered(item) }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in self?.recoverIfBuffered(item) }
            }
        ]
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recoverIfBuffered(item) }
        }
        return item
    }

    public func play() { wantsToPlay = true; player.play() }
    public func pause() { wantsToPlay = false; player.pause() }

    public func clear() {
        pause()
        observations.forEach { $0.invalidate() }; observations.removeAll()
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func recoverIfBuffered(_ item: AVPlayerItem) {
        guard wantsToPlay, player.currentItem === item, item.status == .readyToPlay,
              player.timeControlStatus != .playing else { return }
        let position = player.currentTime().seconds
        guard position.isFinite else { return }
        let available = item.loadedTimeRanges.map(\.timeRangeValue).first { range in
            let start = range.start.seconds
            return start <= position + 0.1 && CMTimeRangeGetEnd(range).seconds > position
        }.map { CMTimeRangeGetEnd($0).seconds - position } ?? 0
        let remaining = item.duration.seconds - position
        // Disabling the prediction also disables automatic recovery after an
        // empty buffer. Resume on fresh bytes, unless the user explicitly paused.
        if available >= 1 || (remaining.isFinite && remaining > 0 && available >= remaining - 0.05) {
            player.playImmediately(atRate: 1)
        }
    }
}
