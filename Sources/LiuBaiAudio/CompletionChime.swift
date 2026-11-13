import AVFoundation
import Foundation

/// A regular audio player mixes a short tone with AVPlayer. It does not use the
/// system alert-sound channel, change audio sessions, or pause the music player.
@MainActor
public final class CompletionChime {
    private var player: AVAudioPlayer?
    public init() {}
    @discardableResult
    public func play(volume: Float = 0.65) -> Bool {
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
        let duration = 1.25
        let count = Int(Double(rate) * duration)
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            var signal = 0.0
            for (onset, pitch) in [(0.0, 659.25), (0.58, 783.99)] {
                let elapsed = time - onset
                guard elapsed >= 0, elapsed < 0.67 else { continue }
                let fadeIn = min(1, elapsed / 0.012)
                let fadeOut = min(1, (0.67 - elapsed) / 0.14)
                let envelope = fadeIn * fadeOut * exp(-3 * elapsed)
                signal += (sin(2 * .pi * pitch * elapsed) + 0.35 * sin(2 * .pi * pitch * 1.5 * elapsed)) * envelope * 0.48
            }
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
