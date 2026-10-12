// What's playing, for the island. The state and its timing follow boring.notch's MusicManager
// (managers/MusicManager.swift, GPL-3.0, commit e2654ee; created by Harsh Vardhan Goswami): the idle
// wait after a pause, the estimated playback position, the artwork's average color
// (extensions/NSImage+Extensions.swift, by Richard Kunkli). Zephydian changes: it reads the copied
// Vorssaint adapter's `watch` mode (app/NowPlaying, one perl process that prints a JSON line per
// change and takes commands on stdin) instead of boring.notch's per-app controllers; the color is
// averaged over a 64-pixel copy of the artwork.

import AppKit
import SwiftUI

/// The song macOS reports as Now Playing, kept live while the island is on.
@Observable
final class IslandMusic {
    static let shared = IslandMusic()

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var artwork: NSImage?
    /// The artwork's average color (white without artwork).
    private(set) var color: NSColor = .white
    private(set) var isPlaying = false
    /// Paused for a while (or nothing playing): the closed island stops showing it.
    private(set) var isIdle = true
    private(set) var duration: Double = 0
    /// The position when `timestamp` was taken, moving at `rate`.
    private(set) var elapsed: Double = 0
    private(set) var rate: Double = 0
    private(set) var timestamp = Date()
    /// The player's bundle identifier (its icon, and the app a click on the artwork opens).
    private(set) var bundleID: String?
    private(set) var canSeek = false
    private(set) var canSkipNext = true
    private(set) var canSkipPrevious = true

    var hasTrack: Bool { !title.isEmpty }
    /// Shown in the closed island.
    var isLive: Bool { hasTrack && !isIdle }

    /// How long a paused song stays in the closed island (boring.notch's default wait).
    private static let idleDelay: Duration = .seconds(3)

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var pid: Int32?
    @ObservationIgnored private var revision: String?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var includeOtherPlayers = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var restarts: [Date] = []

    // MARK: Running

    /// Starts following Now Playing (music apps only, or every player).
    func start(includeOtherPlayers: Bool) {
        if running, includeOtherPlayers == self.includeOtherPlayers { return }
        stop()
        running = true
        self.includeOtherPlayers = includeOtherPlayers
        launch()
    }

    func stop() {
        running = false
        restartTask?.cancel()
        idleTask?.cancel()
        let process = self.process
        self.process = nil
        // Closing its input ends the adapter.
        try? input?.close()
        input = nil
        process?.terminate()
        buffer = Data()
        clear()
    }

    private func launch() {
        guard running,
              let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appending(path: "libZephydianNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = [script.path, library.path, includeOtherPlayers ? "watch_all" : "watch"]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        // A write after the adapter quit must fail quietly instead of killing Zephydian with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if data.isEmpty { handle.readabilityHandler = nil } else { self?.receive(data) }
                }
            }
        }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.ended(ended) }
            }
        }
        do { try process.run() } catch { return }
        self.process = process
        self.input = input.fileHandleForWriting
    }

    /// The adapter stopped by itself: start it again, at most five times a minute.
    private func ended(_ ended: Process) {
        guard ended === process, running else { return }
        process = nil
        input = nil
        buffer = Data()
        let now = Date()
        restarts = restarts.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard restarts.count <= 5 else { clear(); return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    // MARK: Commands

    func togglePlay() { send("toggle") }
    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to position: Double) {
        guard canSeek, position.isFinite else { return }
        let clamped = min(max(0, position), max(0, duration))
        send("seek \(clamped)")
        elapsed = clamped
        timestamp = Date()
    }

    /// Opens the player (a click on the artwork).
    func openPlayer() {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Basic controls go to the player the last reply came from.
    private func send(_ command: String) {
        guard let input, let pid, let revision else { return }
        let line = "play \(pid) \(revision) \(command)\n"
        try? input.write(contentsOf: Data(line.utf8))
    }

    /// Where the song is now.
    func position(at date: Date = Date()) -> Double {
        guard isPlaying else { return min(elapsed, duration) }
        let estimated = elapsed + date.timeIntervalSince(timestamp) * rate
        return min(max(0, estimated), duration)
    }

    // MARK: Replies

    private func receive(_ data: Data) {
        buffer.append(data)
        // A runaway line (more than artwork's limit) is dropped.
        if buffer.count > 20 * 1024 * 1024 { buffer = Data(); return }
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            apply(reply)
        }
    }

    private func apply(_ reply: [String: Any]) {
        // Command results and errors aren't states.
        guard reply["error"] == nil, reply["sources"] != nil || reply["kMRMediaRemoteNowPlayingInfoTitle"] != nil else { return }
        let newTitle = String(((reply["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !newTitle.isEmpty else { clear(); return }
        let changed = newTitle != title
        let hadTrack = !title.isEmpty
        title = newTitle
        artist = String(((reply["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? "").prefix(200))
        album = String(((reply["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? "").prefix(200))
        duration = max(0, reply["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0)
        rate = max(0, reply["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0)
        elapsed = max(0, reply["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0)
        timestamp = Date()
        let playing = reply["isPlaying"] as? Bool ?? (rate > 0)
        if let number = reply["pid"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { pid = number.int32Value }
        revision = reply["playbackRevision"] as? String
        bundleID = reply["displayID"] as? String
        canSeek = reply["canSeek"] as? Bool ?? false
        canSkipNext = reply["canSkipNext"] as? Bool ?? true
        canSkipPrevious = reply["canSkipPrevious"] as? Bool ?? true

        if let encoded = reply["artworkBase64"] as? String {
            setArtwork(Data(base64Encoded: encoded).flatMap { $0.count <= 12 * 1024 * 1024 ? NSImage(data: $0) : nil })
        } else if reply["artworkUnchanged"] as? Bool != true, changed || artwork != nil {
            setArtwork(nil)
        }
        setPlaying(playing)
        // A new song while one was already showing (not the first one found).
        if changed, hadTrack, playing { onNewTrack() }
    }

    /// The track changed while playing (the Dynamic Island's New song indicator).
    @ObservationIgnored var onNewTrack: () -> Void = {}

    private func setArtwork(_ image: NSImage?) {
        withAnimation(.smooth) { artwork = image }
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            withAnimation(.smooth) { color = .white }
            return
        }
        Task { [weak self] in
            let average = await Task.detached(priority: .utility) { IslandColors.average(of: cgImage) }.value
            guard let self, self.artwork === image else { return }
            withAnimation(.smooth) { self.color = average }
        }
    }

    /// Playing shows at once; a pause leaves the closed island after the idle wait.
    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        idleTask?.cancel()
        if playing {
            if isIdle { withAnimation(.smooth) { isIdle = false } }
        } else {
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: Self.idleDelay)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.smooth) { self.isIdle = !self.isPlaying }
            }
        }
    }

    private func clear() {
        idleTask?.cancel()
        withAnimation(.smooth) {
            title = ""; artist = ""; album = ""
            artwork = nil; color = .white
            isPlaying = false; isIdle = true
            duration = 0; elapsed = 0; rate = 0
        }
        bundleID = nil; pid = nil; revision = nil
        canSeek = false; canSkipNext = true; canSkipPrevious = true
    }
}

/// The artwork's color (boring.notch's averageColor, over a small copy).
nonisolated enum IslandColors {
    static func average(of image: CGImage) -> NSColor {
        let side = 64
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return .white }
        let total = side * side
        let pointer = data.bindMemory(to: UInt32.self, capacity: total)
        var red: UInt64 = 0, green: UInt64 = 0, blue: UInt64 = 0
        for i in 0..<total {
            let color = pointer[i]
            red += UInt64(color & 0xFF)
            green += UInt64((color >> 8) & 0xFF)
            blue += UInt64((color >> 16) & 0xFF)
        }
        let averageRed = CGFloat(red) / CGFloat(total) / 255.0
        let averageGreen = CGFloat(green) / CGFloat(total) / 255.0
        let averageBlue = CGFloat(blue) / CGFloat(total) / 255.0

        let minBrightness: CGFloat = 0.5
        if averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03 {
            // If it's near black, just return a gray color with the minimum brightness
            return NSColor(white: minBrightness, alpha: 1.0)
        }
        var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < minBrightness {
            // Increase brightness while maintaining hue and reducing saturation
            let saturationScale = brightness / minBrightness
            color = NSColor(hue: hue, saturation: saturation * saturationScale, brightness: minBrightness, alpha: alpha)
        }
        return color
    }
}

extension Color {
    /// boring.notch's ensureMinimumBrightness (NSImage+Extensions.swift): lifts a dark tint so it reads on black.
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1, let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        guard perceivedBrightness > 0 else { return Color(white: factor) }
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
