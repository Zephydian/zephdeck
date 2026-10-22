import AppKit
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// Finds out whether a newer Zephdeck has been released, and installs it.
/// The check never uses GitHub's API, which allows only 60 anonymous requests an hour per internet
/// connection (B-53): the version comes from where the releases page's "latest" link leads, and
/// only when it's newer are the Homebrew cask (the zip's SHA-256) and that version's CHANGELOG
/// section read, both plain files. Nothing about the Mac or the person is sent (an ephemeral
/// session, a plain User-Agent). It runs about once a day while the switch is on, and on Check Now;
/// a failed check retries by itself after half an hour.
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// A published version newer than this one.
    struct Release: Equatable {
        let version: String
        /// The release notes, without the SHA-256 line.
        let notes: String
        let zipURL: URL
        let zipSize: Int
        /// From the "SHA-256 of the zip: `…`" line the release workflow writes.
        let sha256: String?
        let pageURL: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, failed(String)
    }

    static let latestURL = URL(string: "https://github.com/zephydian/zephdeck/releases/latest")!
    static let caskURL = URL(string: "https://raw.githubusercontent.com/zephydian/homebrew-tap/main/Casks/zephdeck.rb")!
    static func changelogURL(_ version: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/zephydian/zephdeck/v\(version)/CHANGELOG.md")!
    }
    static func zipURL(_ version: String) -> URL {
        URL(string: "https://github.com/zephydian/zephdeck/releases/download/v\(version)/Zephdeck-\(version).zip")!
    }

    private(set) var available: Release?
    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    /// The daily check (Settings → General). On by default.
    var autoCheck: Bool {
        didSet {
            defaults.set(autoCheck, forKey: "app.updates.auto")
            scheduleDailyCheck()
        }
    }

    /// Installing: downloading (0…1), putting it in place, or what went wrong.
    enum Install: Equatable {
        case none, downloading(Double), installing, failed(String)
    }

    private(set) var install: Install = .none
    /// The What's new sheet is up (on Settings → General).
    var showsWhatsNew = false

    /// Opens Settings on General with the What's new sheet (set by AppDelegate).
    @ObservationIgnored var openSettingsGeneral: () -> Void = {}

    /// From the menu bar item, the panel's banner and the notification.
    func requestWhatsNew() {
        openSettingsGeneral()
        showsWhatsNew = true
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?

    /// This copy's version (CFBundleShortVersionString).
    static var currentVersion: String {
        #if DEBUG
        // Debug only, for trying updates: `defaults write ~/Library/Preferences/com.zephydian.zephdeck.plist debug.pretendVersion 0.8.0`
        // (the full path: with the old sandbox container still on disk, `defaults` writes into that instead).
        if let pretend = UserDefaults.standard.string(forKey: "debug.pretendVersion"), !pretend.isEmpty { return pretend }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Zephdeck"]
        session = URLSession(configuration: config)
        autoCheck = defaults.object(forKey: "app.updates.auto") as? Bool ?? true
        lastChecked = defaults.object(forKey: "app.updates.lastChecked") as? Date
    }

    /// At launch: schedule the daily check, and check now if the last one is over a day old.
    func start() {
        scheduleDailyCheck()
        guard autoCheck else { return }
        if lastChecked.map({ Date().timeIntervalSince($0) > 20 * 60 * 60 }) ?? true {
            Task { await check() }
        }
    }

    /// Finds the latest version and, when it's newer than this copy, its details.
    func check() async {
        guard state != .checking else { return }
        state = .checking
        retry?.cancel()
        do {
            let latest = try await latestVersion()
            lastChecked = Date()
            defaults.set(lastChecked, forKey: "app.updates.lastChecked")
            guard Self.isNewer(latest, than: Self.currentVersion) else {
                available = nil
                state = .upToDate
                return
            }
            let release = try await details(latest)
            let isNew = available?.version != release.version
            available = release
            state = .idle
            if isNew, defaults.string(forKey: "app.updates.announced") != release.version {
                defaults.set(release.version, forKey: "app.updates.announced")
                notify(release)
            }
        } catch {
            let message: String
            if let error = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed].contains(error.code) {
                message = "You're offline."
            } else if let failure = error as? Failure {
                message = failure.description
            } else {
                message = error.localizedDescription
            }
            state = .failed(message)
            scheduleRetry()
        }
    }

    /// Retries a failed check after half an hour (while the daily check is on).
    @ObservationIgnored private var retry: Task<Void, Never>?
    private func scheduleRetry() {
        retry?.cancel()
        guard autoCheck else { return }
        retryAt = Date().addingTimeInterval(30 * 60)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30 * 60))
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    /// When a failed check will be tried again.
    private(set) var retryAt: Date?

    /// The newest version: where github.com's "latest release" link leads (…/releases/tag/v0.9.1).
    private func latestVersion() async throws -> String {
        var request = URLRequest(url: Self.latestURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let tag = http.url?.lastPathComponent, tag.hasPrefix("v") else {
            throw Failure(description: "GitHub didn't say which version is the latest.")
        }
        return String(tag.dropFirst())
    }

    /// The zip's fingerprint from the Homebrew cask, and the notes from that version's CHANGELOG.
    private func details(_ version: String) async throws -> Release {
        let cask = try await text(Self.caskURL)
        guard let sha = Self.caskValue("sha256", in: cask), Self.caskValue("version", in: cask) == version else {
            throw Failure(description: "Zephdeck \(version) is still being published.")
        }
        let changelog = (try? await text(Self.changelogURL(version))) ?? ""
        return Release(version: version, notes: Self.changelogSection(version, in: changelog),
                       zipURL: Self.zipURL(version), zipSize: 0, sha256: sha.count == 64 ? sha.lowercased() : nil,
                       pageURL: URL(string: "https://github.com/zephydian/zephdeck/releases/tag/v\(version)")!)
    }

    private func text(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(description: "GitHub didn't answer.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// `version "0.9.1"` → 0.9.1 (the cask's own lines).
    nonisolated static func caskValue(_ key: String, in cask: String) -> String? {
        for line in cask.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key + " \""), let start = trimmed.firstIndex(of: "\""),
                  let end = trimmed[trimmed.index(after: start)...].firstIndex(of: "\"") else { continue }
            return String(trimmed[trimmed.index(after: start)..<end])
        }
        return nil
    }

    /// The lines under "## [0.9.1] - …" up to the next "## [".
    nonisolated static func changelogSection(_ version: String, in changelog: String) -> String {
        var out: [Substring] = []
        var inside = false
        for line in changelog.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## [") {
                if inside { break }
                inside = line.hasPrefix("## [\(version)]")
                continue
            }
            if inside { out.append(line) }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// "0.10.0" is newer than "0.9.1": compared number by number.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Notification (26.2)

    nonisolated static let notificationID = "app.update"

    /// One notification per new version; clicking it opens What's new.
    private func notify(_ release: Release) {
        let version = release.version
        // Called on the notification center's queue: not main-actor isolated (B-29).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { @Sendable granted, _ in
            guard granted else { return }
            Self.post(version)
        }
    }

    nonisolated private static func post(_ version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Zephdeck \(version) is available"
        content.body = "Click to see what's new and update."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil))
    }

    // MARK: Installing (26.3)

    /// Where Homebrew keeps the cask, if this copy is the one Homebrew installed (the cask puts it in
    /// /Applications; another copy elsewhere updates from the zip).
    nonisolated static var homebrew: (caskroom: String, brew: String)? {
        guard Bundle.main.bundlePath == "/Applications/Zephdeck.app" else { return nil }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let caskroom = prefix + "/Caskroom/zephdeck", brew = prefix + "/bin/brew"
            if FileManager.default.fileExists(atPath: caskroom), FileManager.default.isExecutableFile(atPath: brew) {
                return (caskroom, brew)
            }
        }
        return nil
    }

    /// An installed copy (in an Applications folder) can update itself; one run from Xcode or a
    /// build folder can't.
    static var canInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Homebrew finished but didn't install the new version, so the sheet offers the download instead.
    private(set) var homebrewMissed = false

    /// Updates through Homebrew or from the zip, then restarts. The old app stays if anything fails.
    /// `fromDownload` skips Homebrew (after it missed the new version).
    func installUpdate(fromDownload: Bool = false) async {
        guard let release = available, install != .installing else { return }
        if case .downloading = install { return }
        guard Self.canInstall else {
            install = .failed("This copy isn't in Applications (it runs from Xcode or a build folder), so it can't update itself.")
            return
        }
        if !fromDownload, let brew = Self.homebrew {
            install = .installing
            homebrewMissed = false
            let result = await Task.detached(priority: .userInitiated) { () -> (status: Int32, output: String) in
                // Homebrew refreshes its taps only once a day, so it may not know the new version yet (B-57).
                _ = Self.run(brew.brew, ["update", "--quiet"])
                return Self.run(brew.brew, ["upgrade", "--cask", "zephdeck"])
            }.value
            guard result.status == 0 else {
                install = .failed("Homebrew couldn't update it: " + (result.output.split(separator: "\n").last.map(String.init) ?? "exit \(result.status)"))
                return
            }
            // A successful run can still leave the old version in place: restart only into the new one.
            guard Self.installedVersion(at: Bundle.main.bundleURL) == release.version else {
                homebrewMissed = true
                install = .failed("Homebrew didn't find Zephdeck \(release.version) yet. Try again in a few minutes, or install the download instead.")
                return
            }
            relaunch()
            return
        }
        do {
            let data = try await download(release)
            install = .installing
            let target = Bundle.main.bundleURL
            try await Task.detached(priority: .userInitiated) {
                try Self.replace(app: target, with: data, version: release.version)
            }.value
            relaunch()
        } catch let failure as Failure {
            install = .failed(failure.description)
        } catch {
            install = .failed("The update didn't work: \(error.localizedDescription)")
        }
    }

    /// The zip, with progress, checked against its size and SHA-256.
    private func download(_ release: Release) async throws -> Data {
        guard let sha = release.sha256 else { throw Failure(description: "The release has no fingerprint to check the download against.") }
        install = .downloading(0)
        let (bytes, response) = try await session.bytes(from: release.zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(description: "The download didn't start.") }
        let expected = max(release.zipSize, Int(response.expectedContentLength), 1)
        var data = Data()
        data.reserveCapacity(expected)
        var lastShown = 0
        for try await byte in bytes {
            data.append(byte)
            if data.count - lastShown > 256 * 1024 {
                lastShown = data.count
                install = .downloading(min(1, Double(data.count) / Double(expected)))
            }
            if data.count > 200 * 1024 * 1024 { throw Failure(description: "The download is far bigger than expected.") }
        }
        guard release.zipSize == 0 || data.count == release.zipSize else { throw Failure(description: "The download is incomplete.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == sha else { throw Failure(description: "The download doesn't match the release's fingerprint, so it wasn't installed.") }
        install = .downloading(1)
        return data
    }

    /// Unzips the new version beside the old one, checks it, then swaps them (the old app goes to
    /// the Trash, and comes back if the swap fails).
    nonisolated private static func replace(app target: URL, with zip: Data, version: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "zephdeck-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let zipFile = work.appending(path: "update.zip")
        try zip.write(to: zipFile)
        guard run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path]).status == 0 else {
            throw Failure(description: "The download couldn't be unpacked.")
        }
        let app = work.appending(path: "Zephdeck.app", directoryHint: .isDirectory)
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == "com.zephydian.zephdeck",
              info["CFBundleShortVersionString"] as? String == version else {
            throw Failure(description: "The download isn't the expected Zephdeck \(version).")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw Failure(description: "The new app's signature didn't check out.")
        }
        var trashed: NSURL?
        try fm.trashItem(at: target, resultingItemURL: &trashed)
        do {
            try fm.moveItem(at: app, to: target)
        } catch {
            if let back = trashed as URL? { try? fm.moveItem(at: back, to: target) }
            throw Failure(description: "The new version couldn't be put in place: \(error.localizedDescription)")
        }
    }

    /// The version of the app on disk, read from its Info.plist each time (Bundle caches it).
    nonisolated static func installedVersion(at app: URL) -> String? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    /// Opens the (new) app once this one has quit, then quits.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(filePath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        try? task.run()
        // macOS won't quit an app while a sheet is open (the update test waited forever with What's
        // new still up), so the sheet closes first; if something else still holds the quit, exit.
        showsWhatsNew = false
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
            try? await Task.sleep(for: .seconds(3))
            exit(0)
        }
    }

    /// Runs a tool and returns its exit status and output (call it off the main thread).
    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    /// About once a day at a quiet moment, only while the switch is on.
    private func scheduleDailyCheck() {
        guard autoCheck else {
            scheduler?.invalidate()
            scheduler = nil
            return
        }
        guard scheduler == nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.zephydian.zephdeck.app.update")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 2 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                if let self, self.lastChecked.map({ Date().timeIntervalSince($0) > 20 * 60 * 60 }) ?? true {
                    await self.check()
                }
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }
}
