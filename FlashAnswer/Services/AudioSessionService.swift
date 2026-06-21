import AVFoundation

/// Plays a silent audio loop to keep the app alive in background.
class AudioSessionService {
    private var player: AVAudioPlayer?

    func startBackgroundAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                  mode: .default,
                                  options: [.mixWithOthers, .defaultToSpeaker])
        try? session.setActive(true)

        // Generate silent PCM data (0.1s, 44100 Hz, mono, 16-bit)
        let sampleRate = 44100
        let duration = 0.1
        let numSamples = Int(Double(sampleRate) * duration)
        var silentData = Data(count: numSamples * 2) // 16-bit = 2 bytes per sample

        // WAV header (44 bytes)
        var wav = Data()
        func append32LE(_ v: UInt32) { var x = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &x, Array.init)) }
        func append16LE(_ v: UInt16) { var x = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &x, Array.init)) }
        wav.append(contentsOf: "RIFF".utf8)
        append32LE(UInt32(36 + silentData.count))
        wav.append(contentsOf: "WAVEfmt ".utf8)
        append32LE(16)
        append16LE(1)  // PCM
        append16LE(1)  // mono
        append32LE(UInt32(sampleRate))
        append32LE(UInt32(sampleRate * 2))
        append16LE(2)
        append16LE(16)
        wav.append(contentsOf: "data".utf8)
        append32LE(UInt32(silentData.count))
        wav.append(silentData)

        player = try? AVAudioPlayer(data: wav)
        player?.numberOfLoops = -1 // infinite
        player?.volume = 0.001
        player?.play()
    }

    func stop() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
