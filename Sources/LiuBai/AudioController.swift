import AVFoundation
import Combine
import Foundation
import LiuBaiAudio
import LiuBaiCore
import MediaPlayer

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var wantsToPlay = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published private(set) var bitrate = 0
    var onEnded: (() -> Void)?
    var onActivityChange: (() -> Void)?

    private let client: BilibiliClient
    private let playback = StreamingPlayback()
    private var player: AVPlayer { playback.player }
    private var resource: AudioResource?
    private var loadTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var requestID = UUID()
    private var urls: [URL] = []
    private var urlIndex = 0
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var volume: Float = 0.65

    init(client: BilibiliClient) {
        self.client = client
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = self.player.timeControlStatus
                self.onActivityChange?()
                self.isPlaying = status == .playing && self.player.currentItem != nil && self.wantsToPlay
                if status == .playing { self.isLoading = false }
                else if self.wantsToPlay { self.isLoading = true }
                self.updateNowPlaying()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = self.player.currentTime().seconds
                if seconds.isFinite { self.position = max(0, seconds) }
                if let value = self.player.currentItem?.duration.seconds, value.isFinite && value > 0 { self.duration = value }
                self.updateNowPlaying()
            }
        }
        configureRemoteCommands()
    }

    func load(_ track: Track, autoplay: Bool = true) {
        onActivityChange?()
        loadTask?.cancel()
        clearItem()
        requestID = UUID()
        let id = requestID
        currentTrack = track
        position = 0; duration = track.duration; bitrate = 0
        errorMessage = nil; isLoading = true; wantsToPlay = autoplay
        loadTask = Task { [weak self, client] in
            do {
                let stream = try await client.audio(for: track)
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.urls = stream.urls; self.urlIndex = 0; self.bitrate = stream.bandwidth
                self.installCurrentURL()
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.isLoading = false; self.wantsToPlay = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggle() {
        if wantsToPlay { pause() }
        else if let currentTrack, player.currentItem == nil { load(currentTrack) }
        else if currentTrack != nil { resume() }
    }
    func pause() {
        onActivityChange?()
        wantsToPlay = false
        playback.pause()
        isPlaying = false
        isLoading = false
        updateNowPlaying()
    }
    func resume() {
        guard currentTrack != nil else { return }
        if player.currentItem == nil {
            if let currentTrack { load(currentTrack) }
            return
        }
        wantsToPlay = true
        isLoading = !isPlaying
        playback.play()
    }
    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, duration > 0 else { return }
        let value = min(max(0, seconds), duration)
        position = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setVolume(_ value: Float) { volume = min(1, max(0, value)); player.volume = volume }
    func stop() {
        onActivityChange?()
        loadTask?.cancel(); requestID = UUID()
        clearItem()
        currentTrack = nil; wantsToPlay = false; isLoading = false; position = 0; duration = 0; errorMessage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func installCurrentURL(resumingAt seconds: TimeInterval = 0) {
        clearItem()
        guard urls.indices.contains(urlIndex) else { return }
        isLoading = wantsToPlay
        let url = urls[urlIndex], index = urlIndex, id = requestID
        loadTask = Task { [weak self] in
            do {
                let resource = try await AudioResource.streaming(url: url)
                guard !Task.isCancelled, let self, self.requestID == id, self.urlIndex == index else { resource.cancel(); return }
                self.install(resource, resumingAt: seconds)
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id, self.urlIndex == index else { return }
                self.tryNextURL(resumingAt: seconds)
            }
        }
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.requestID == id, self.urlIndex == index,
                  self.wantsToPlay, !self.isPlaying else { return }
            self.loadTask?.cancel()
            self.tryNextURL(resumingAt: seconds)
        }
    }

    private func install(_ resource: AudioResource, resumingAt seconds: TimeInterval) {
        self.resource = resource
        let item = playback.replace(with: resource.asset)
        player.volume = volume
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .readyToPlay {
                    self.isLoading = self.wantsToPlay && !self.isPlaying
                    if item.duration.seconds.isFinite && item.duration.seconds > 0 { self.duration = item.duration.seconds }
                    if seconds > 0 {
                        self.player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.player.currentItem === item, self.wantsToPlay else { return }
                                self.playback.play()
                            }
                        }
                    }
                } else if item.status == .failed {
                    self.tryNextURL(resumingAt: max(seconds, self.position))
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.onActivityChange?()
                self.isPlaying = false; self.wantsToPlay = false
                self.onEnded?()
            }
        }
        if wantsToPlay && seconds <= 0 { playback.play() }
        updateNowPlaying()
    }

    private func tryNextURL(resumingAt seconds: TimeInterval) {
        if urlIndex + 1 < urls.count {
            urlIndex += 1
            installCurrentURL(resumingAt: seconds)
        } else {
            onActivityChange?()
            isLoading = false; wantsToPlay = false
            errorMessage = "音频加载未成功，请检查网络后重试。"
            clearItem()
        }
    }

    private func clearItem() {
        startupTask?.cancel(); startupTask = nil
        playback.pause()
        itemObservation?.invalidate(); itemObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playback.clear()
        resource?.cancel(); resource = nil
        isPlaying = false
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }
    private func updateNowPlaying() {
        guard let currentTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
