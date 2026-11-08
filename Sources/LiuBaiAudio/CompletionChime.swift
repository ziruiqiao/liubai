import AVFoundation
import Foundation

/// A regular audio player mixes a short tone with AVPlayer. It does not use the
/// system alert-sound channel, change audio sessions, or pause the music player.
@MainActor
public final class CompletionChime {
    private var player: AVAudioPlayer?
    public init() {}
    @discardableResult
    public func play(volume: Float = 0.12) -> Bool {
        do {
            let player = try AVAudioPlayer(data: Self.wave())
            player.volume = max(0, min(1, volume))
            player.prepareToPlay()
            self.player = player
            return player.play()
        } catch { return false }
    }
    public var isPlaying: Bool { player?.isPlaying ?? false }

    private static func wave() -> Data {
        let rate = 44_100
        let duration = 0.55
        let count = Int(Double(rate) * duration)
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            let fadeIn = min(1, time / 0.018)
            let fadeOut = min(1, (duration - time) / 0.12)
            let envelope = fadeIn * fadeOut * exp(-4 * time)
            let signal = (sin(2 * .pi * 659.25 * time) + 0.45 * sin(2 * .pi * 987.77 * time)) * envelope * 0.45
            var value = Int16(max(-32767, min(32767, signal * 32767))).littleEndian
            withUnsafeBytes(of: &value) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func word(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func dword(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); dword(UInt32(36 + samples.count)); data.append(Data("WAVEfmt ".utf8))
        dword(16); word(1); word(1); dword(UInt32(rate)); dword(UInt32(rate * 2)); word(2); word(16)
        data.append(Data("data".utf8)); dword(UInt32(samples.count)); data.append(samples)
        return data
    }
}
