import AVFoundation

/// A game pack's sounds (SDK 10): short files from its `assets/` (WAV or MP3), played with low
/// latency and allowed to overlap (a key's release can start while the next press is still ringing).
/// The audio engine exists only while the pack is on screen with its sound on; `stop()` frees it.
final class PackSound {
    /// Each player plays one sound at a time; a few keep fast typing from cutting sounds short.
    private static let voices = 8
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private let bundle: PackBundle
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    /// Files that couldn't be read, so they aren't tried on every key.
    private var missing: Set<String> = []

    init(bundle: PackBundle) { self.bundle = bundle }

    // MARK: The person's choice

    /// On or off for this game, remembered per pack. Off until the person switches it on.
    static func key(_ packID: String) -> String { "pack.\(packID).sound" }
    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key(bundle.id)) }

    func setOn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.key(bundle.id))
        if !on { stop() }
    }

    // MARK: Playing

    func play(_ name: String, volume: Double) {
        guard isOn, let buffer = buffer(name), runningEngine() != nil else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(min(max(volume, 0), 1))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Reads the files ahead of time, so the first key press isn't late.
    func preload(_ names: [String]) {
        for name in names.prefix(64) { _ = buffer(name) }
        if isOn { _ = runningEngine() }
    }

    /// Stops the engine (the panel hid, the game closed, or the sound was switched off).
    func stop() {
        engine?.stop()
        engine = nil
        players = []
    }

    /// The engine, made when needed. macOS stops it when the output changes (headphones in or out),
    /// and then the next sound makes a new one.
    private func runningEngine() -> AVAudioEngine? {
        if let engine, engine.isRunning { return engine }
        stop()
        let engine = AVAudioEngine()
        players = (0..<Self.voices).map { _ in AVAudioPlayerNode() }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
        }
        do { try engine.start() } catch { players = []; return nil }
        self.engine = engine
        return engine
    }

    private func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let buffer = buffers[name] { return buffer }
        guard !missing.contains(name), buffers.count < 64 else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["wav", "mp3"].contains(ext), let url = bundle.assetURL(name),
              let buffer = Self.read(url) else {
            missing.insert(name)
            return nil
        }
        buffers[name] = buffer
        return buffer
    }

    /// The whole file (at most 2 seconds) in the players' format: mixed to mono and, if needed,
    /// resampled to 44.1 kHz (straight lines between samples, plenty for short effects).
    private static func read(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let rate = file.processingFormat.sampleRate
        let frames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(rate * 2)))
        guard frames > 0, rate > 0, let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: source, frameCount: frames)) != nil, let channels = source.floatChannelData else { return nil }
        if source.format == format { return source }

        let count = Int(source.frameLength), channelCount = Int(source.format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        for c in 0..<channelCount {
            for i in 0..<count { mono[i] += channels[c][i] / Float(channelCount) }
        }
        let step = rate / format.sampleRate
        let outCount = Int(Double(count) / step)
        guard outCount > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(outCount)),
              let out = output.floatChannelData?[0] else { return nil }
        for i in 0..<outCount {
            let position = Double(i) * step
            let j = Int(position), fraction = Float(position - Double(j))
            let a = mono[min(j, count - 1)], b = mono[min(j + 1, count - 1)]
            out[i] = a + (b - a) * fraction
        }
        output.frameLength = AVAudioFrameCount(outCount)
        return output
    }
}
