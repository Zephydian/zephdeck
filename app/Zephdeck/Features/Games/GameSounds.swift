import AVFoundation

/// Plays a game's short sounds (WAV or MP3) with low latency, allowed to overlap (a key's release can
/// start while the next press is still ringing). The audio engine exists only while sounds are
/// playing on screen; `stop()` frees it. Whether a game may play at all is `GameSounds`' business.
final class SoundPlayer {
    /// Each player plays one sound at a time; a few keep fast typing from cutting sounds short.
    private static let voices = 8
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// Finds a sound's file by name, or nil.
    private let resolve: (String) -> URL?
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    /// Files that couldn't be read, so they aren't tried on every key.
    private var missing: Set<String> = []

    init(resolve: @escaping (String) -> URL?) { self.resolve = resolve }

    // MARK: Playing

    func play(_ name: String, volume: Double = 1) {
        guard let buffer = buffer(name), runningEngine() != nil else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(min(max(volume, 0), 1))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Reads the files ahead of time, so the first key press isn't late.
    func preload(_ names: [String]) {
        for name in names.prefix(64) { _ = buffer(name) }
        _ = runningEngine()
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
        guard ["wav", "mp3"].contains(ext), let url = resolve(name),
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

/// Whether a game may make sound: the "Game sounds" switch in Settings (off at first) and the game's
/// own speaker (on unless switched off for that game). Both have to be on.
enum GameSounds {
    static let masterKey = "gameSounds"
    /// The app's settings, so switching a game on from inside it also shows in Settings.
    static weak var settings: SettingsStore?

    static var masterOn: Bool { settings?.gameSounds ?? UserDefaults.standard.bool(forKey: masterKey) }

    /// The game's own switch, under `key` (built-in games `sound.<id>`, packs `pack.<id>.sound`).
    static func gameOn(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static func isOn(_ key: String) -> Bool { masterOn && gameOn(key) }

    /// The speaker button, or a game's own Sound switch. Switching a game on also switches game
    /// sounds on, since that's clearly what the person wants.
    static func set(_ key: String, on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        if on && !masterOn {
            if let settings { settings.gameSounds = true } else { UserDefaults.standard.set(true, forKey: masterKey) }
        }
    }
}

/// A built-in game's sounds: inside the app for the games that come installed (Snake, Stackr, Five,
/// named `<id>-<sound>.wav`), and in the game's sound set otherwise (downloaded from the Library
/// with the game, as the pack `<id>-sounds`).
final class GameSoundBank {
    let id: String
    var key: String { "sound.\(id)" }
    private lazy var player = SoundPlayer { [id] name in
        let base = (name as NSString).deletingPathExtension
        return Bundle.main.url(forResource: "\(id)-\(base)", withExtension: "wav")
            ?? Self.soundSetFolder(id).map { $0.appending(path: "assets/\(base).wav") }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    init(_ id: String) { self.id = id }

    /// True when the game has sounds on this Mac (shipped in the app, or its sound set installed).
    var isAvailable: Bool {
        Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil)?.contains { $0.lastPathComponent.hasPrefix("\(id)-") } == true
            || Self.soundSetFolder(id) != nil
    }

    func play(_ name: String, volume: Double = 1) {
        guard GameSounds.isOn(key) else { return }
        player.play(name + ".wav", volume: volume)
    }

    /// The game was paused or hidden: the audio engine goes away until the next sound.
    func stop() { player.stop() }

    static func soundSetFolder(_ id: String) -> URL? {
        let folder = PackLibrary.packsDirectory.appending(path: "\(id)-sounds", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path) ? folder : nil
    }
}
