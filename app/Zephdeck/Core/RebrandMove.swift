import AppKit
import SwiftUI

/// Brings Zephydian's settings and data over to Zephdeck, once.
///
/// Up to 1.0.1 the app was called Zephydian, with the bundle ID com.ahmastan.zephydian. Zephdeck
/// (1.1.0) has its own bundle ID, so macOS gives it fresh preferences and the first launch copies
/// everything across:
///
///     ~/Library/Preferences/com.ahmastan.zephydian.plist   → Zephdeck's preferences (settings, scores, saved games)
///     ~/Library/Application Support/Zephydian              → ~/Library/Application Support/Zephdeck
///                                                            (notes, installed packs, pack data)
///
/// The old preferences and folder are copied, never changed, so they stay as a backup. It runs
/// before `StorageMove`, whose done-flags come over with the settings. Then it switches the login
/// item back on if Zephydian had one (the 1.0.1 update switched it off and left a note), gives
/// Screenshot's chosen folder a bookmark of Zephdeck's own, and says hello once (`showWelcome`).
enum RebrandMove {
    enum Outcome: Equatable {
        /// Already done, or nothing to bring over (a fresh install).
        case nothing
        case moved
        /// The files couldn't be copied. The old folder is untouched; the next launch tries again.
        case failed(String)
    }

    struct Paths {
        /// Application Support.
        var applicationSupport: URL
        /// Zephdeck's preferences domain (the bundle ID).
        var domain: String
        /// Zephydian's preferences domain.
        var oldDomain = "com.ahmastan.zephydian"

        static var live: Paths {
            Paths(applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                  domain: Bundle.main.bundleIdentifier ?? "com.zephydian.zephdeck")
        }
    }

    static let preferencesKey = "rebrand.movedPreferences"
    static let filesKey = "rebrand.movedFiles"
    /// Left by Zephydian 1.0.1 when it switched its own login item off for Zephdeck.
    static let loginItemKey = "rebrand.wasLoginItem"
    /// The welcome window is waiting to be shown (set when anything came over).
    static let welcomeKey = "rebrand.showWelcome"

    /// Runs at launch, before anything reads settings or files.
    @discardableResult
    static func runIfNeeded(paths: Paths = .live, defaults: UserDefaults = .standard,
                            fileManager fm: FileManager = .default) -> Outcome {
        if defaults.bool(forKey: preferencesKey), defaults.bool(forKey: filesKey) { return .nothing }
        var didSomething = false

        if !defaults.bool(forKey: preferencesKey) {
            if importPreferences(paths: paths, defaults: defaults) {
                didSomething = true
                rebookmarkFolders(defaults)
                defaults.set(true, forKey: welcomeKey)
            }
            defaults.set(true, forKey: preferencesKey)
        }

        if !defaults.bool(forKey: filesKey) {
            let source = paths.applicationSupport.appending(path: "Zephydian", directoryHint: .isDirectory)
            if fm.fileExists(atPath: source.path) {
                do {
                    try StorageMove.copyFolder(source, to: paths.applicationSupport.appending(path: "Zephdeck", directoryHint: .isDirectory),
                                               fileManager: fm)
                    didSomething = true
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            defaults.set(true, forKey: filesKey)
        }
        return didSomething ? .moved : .nothing
    }

    /// Zephydian's settings win over anything already in Zephdeck's domain, which only a test run
    /// could have written. Returns whether there was anything to import.
    private static func importPreferences(paths: Paths, defaults: UserDefaults) -> Bool {
        guard let old = defaults.persistentDomain(forName: paths.oldDomain), !old.isEmpty else { return false }
        let current = defaults.persistentDomain(forName: paths.domain) ?? [:]
        defaults.setPersistentDomain(current.merging(old) { _, zephydian in zephydian }, forName: paths.domain)
        return true
    }

    /// A security-scoped bookmark belongs to the app that made it, so Zephydian's bookmark of
    /// Screenshot's folder is read without its scope (Zephdeck isn't sandboxed) and made again.
    static func rebookmarkFolders(_ defaults: UserDefaults) {
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix("pack.") && key.hasSuffix(".screenshot.folder") {
            var stale = false
            guard let data = value as? Data,
                  let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
                  let fresh = try? url.bookmarkData(options: .withSecurityScope) else { continue }
            defaults.set(fresh, forKey: key)
        }
    }

    /// After launch: the login item, and the welcome window if anything came over.
    static func finish(defaults: UserDefaults = .standard, openPermissions: @escaping () -> Void) {
        if defaults.bool(forKey: loginItemKey) {
            defaults.removeObject(forKey: loginItemKey)
            try? LaunchAtLogin.set(true)
        }
        if defaults.bool(forKey: welcomeKey) {
            defaults.removeObject(forKey: welcomeKey)
            WelcomeWindow.show(openPermissions: openPermissions)
        }
    }

    /// Tells the person their data stayed in the old folder, and where.
    static func reportFailure(_ message: String, paths: Paths = .live) {
        let alert = NSAlert()
        alert.messageText = "Zephdeck couldn't bring over your notes and packs"
        alert.informativeText = "They're safe in Zephydian's folder, and Zephdeck will try again next time it opens. (\(message))"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show Old Folder")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([paths.applicationSupport.appending(path: "Zephydian", directoryHint: .isDirectory)])
        }
    }
}

/// "Zephydian is now Zephdeck": shown once, on the first launch after the rename.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show(openPermissions: @escaping () -> Void) {
        guard window == nil else { return }
        let close = {
            window?.close()
        }
        let view = RebrandWelcomeView(
            openPermissions: { close(); openPermissions() },
            done: { close() })
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Zephdeck"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                DockPresence.remove("welcome")
                Self.window = nil
            }
        }
        Self.window = window
        DockPresence.add("welcome")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct RebrandWelcomeView: View {
    var openPermissions: () -> Void
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("MenuBarIcon").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 26, height: 26).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Zephydian is now Zephdeck").font(.title3.bold())
            }
            Text("Same app, new name. Your settings, notes, packs and shortcuts came along.")
            Text("Because the name changed, macOS asks for its permissions again (Accessibility, Screen Recording…) the next time a feature needs them.")
                .foregroundStyle(.secondary)
            Text("Zephdeck is made by Zephydian.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Open Permissions…", action: openPermissions)
                Button("Got It", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 400)
    }
}
