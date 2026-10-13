import AppKit
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// Finds out whether a newer Zephydian has been released, and (from 26.3) installs it.
/// The check reads only GitHub's public "latest release" record for the repository: the version,
/// its notes and the zip's address. Nothing about the Mac or the person is sent (an ephemeral
/// session, a plain User-Agent). It runs about once a day while the switch is on, and on Check Now.
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

    static let latestURL = URL(string: "https://api.github.com/repos/ahmastan/zephydian/releases/latest")!

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
        // Debug only, for trying updates: `defaults write ~/Library/Preferences/com.ahmastan.zephydian.plist debug.pretendVersion 0.8.0`
        // (the full path: with the old sandbox container still on disk, `defaults` writes into that instead).
        if let pretend = UserDefaults.standard.string(forKey: "debug.pretendVersion"), !pretend.isEmpty { return pretend }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Zephydian", "Accept": "application/vnd.github+json"]
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

    /// Reads the latest release and notes whether it's newer than this copy.
    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            var request = URLRequest(url: Self.latestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure(description: "GitHub didn't answer (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            let release = try Self.parse(data)
            lastChecked = Date()
            defaults.set(lastChecked, forKey: "app.updates.lastChecked")
            if let release, Self.isNewer(release.version, than: Self.currentVersion) {
                let isNew = available?.version != release.version
                available = release
                state = .idle
                if isNew, defaults.string(forKey: "app.updates.announced") != release.version {
                    defaults.set(release.version, forKey: "app.updates.announced")
                    notify(release)
                }
            } else {
                available = nil
                state = .upToDate
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            state = .failed("You're offline.")
        } catch let failure as Failure {
            state = .failed(failure.description)
        } catch {
            state = .failed("The check didn't work: \(error.localizedDescription)")
        }
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// The release from GitHub's JSON; nil if it has no zip.
    nonisolated static func parse(_ data: Data) throws -> Release? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw Failure(description: "GitHub's answer wasn't understood.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let body = json["body"] as? String ?? ""
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlText = zip["browser_download_url"] as? String, let zipURL = URL(string: urlText),
              zipURL.scheme == "https", zipURL.host == "github.com" else { return nil }
        // "SHA-256 of the zip: `621b…`"
        var sha: String?
        var lines: [Substring] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("SHA-256 of the zip:"), let start = line.firstIndex(of: "`"),
               let end = line[line.index(after: start)...].firstIndex(of: "`") {
                sha = String(line[line.index(after: start)..<end]).lowercased()
            } else {
                lines.append(line)
            }
        }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/ahmastan/zephydian/releases/tag/\(tag)")!
        return Release(version: version,
                       notes: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                       zipURL: zipURL, zipSize: zip["size"] as? Int ?? 0,
                       sha256: sha.flatMap { $0.count == 64 ? $0 : nil }, pageURL: page)
    }

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
        content.title = "Zephydian \(version) is available"
        content.body = "Click to see what's new and update."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil))
    }

    // MARK: Installing (26.3)

    /// Where Homebrew keeps the cask, if this copy is the one Homebrew installed (the cask puts it in
    /// /Applications; another copy elsewhere updates from the zip).
    nonisolated static var homebrew: (caskroom: String, brew: String)? {
        guard Bundle.main.bundlePath == "/Applications/Zephydian.app" else { return nil }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let caskroom = prefix + "/Caskroom/zephydian", brew = prefix + "/bin/brew"
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

    /// Updates through Homebrew or from the zip, then restarts. The old app stays if anything fails.
    func installUpdate() async {
        guard let release = available, install != .installing else { return }
        if case .downloading = install { return }
        guard Self.canInstall else {
            install = .failed("This copy isn't in Applications (it runs from Xcode or a build folder), so it can't update itself.")
            return
        }
        if let brew = Self.homebrew {
            install = .installing
            let result = await Task.detached(priority: .userInitiated) { Self.run(brew.brew, ["upgrade", "--cask", "zephydian"]) }.value
            guard result.status == 0 else {
                install = .failed("Homebrew couldn't update it: " + (result.output.split(separator: "\n").last.map(String.init) ?? "exit \(result.status)"))
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
        let work = fm.temporaryDirectory.appending(path: "zephydian-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let zipFile = work.appending(path: "update.zip")
        try zip.write(to: zipFile)
        guard run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path]).status == 0 else {
            throw Failure(description: "The download couldn't be unpacked.")
        }
        let app = work.appending(path: "Zephydian.app", directoryHint: .isDirectory)
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == "com.ahmastan.zephydian",
              info["CFBundleShortVersionString"] as? String == version else {
            throw Failure(description: "The download isn't the expected Zephydian \(version).")
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
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.ahmastan.zephydian.app.update")
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
