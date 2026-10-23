// Parts of the window set-up and placement are copied from boring.notch's boringNotchApp.swift
// (github.com/TheBoredTeam/boring.notch, GPL-3.0, commit e2654ee; created by Harsh Vardhan Goswami).
// Zephdeck changes: the display choice is Vorssaint's (NotchDisplay: automatic, built-in, main,
// follow the pointer, every display; the pointer is checked by a light timer only while following
// it across several displays, instead of Vorssaint's mouse monitors), run as a Zephdeck feature engine, our
// own full-screen check instead of MacroVisionKit, no lock-screen (SkyLight) window, and no private
// CGS space (B-33: in it, clicks on the island also reached the window behind; the panel's level
// above the menu bar on all Spaces keeps it on top).

import AppKit
import SwiftUI

/// The Dynamic Island: a black island around the camera notch (or a simulated one at the top centre
/// of a display without a notch) that shows what's live and opens into tabs. Runs only while the
/// feature is on: a window per display it shows on, two notifications, a display-change observer
/// and the now-playing reader (one perl process that waits for macOS's change notifications);
/// nothing is polled, except the pointer's display four times a second while following it.
final class IslandEngine: FeatureEngine {
    static weak var current: IslandEngine?

    /// One island: its model and window, on one display.
    private final class Island {
        let model: IslandModel
        let window: IslandWindow
        init(model: IslandModel, window: IslandWindow) {
            self.model = model
            self.window = window
        }
    }

    private let appSettings: SettingsStore
    private var islands: [Island] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var fullScreenCheck: Task<Void, Never>?
    private var pointerTimer: Timer?
    private let dragDetector = IslandDragDetector()
    private var running = false

    /// The island you're using: the one on the pointer's display, else the first.
    private var model: IslandModel? { primary?.model }
    private var primary: Island? {
        let mouse = NSEvent.mouseLocation
        return islands.first { $0.model.screen.map { NSMouseInRect(mouse, $0.frame, false) } ?? false } ?? islands.first
    }

    /// The island shows a Shelf, so it takes over from Zephdeck's floating Shelf (the owner's rule):
    /// drags, the Shelf's shortcut and its menu bar item open the island's Shelf instead.
    static var handlesShelf: Bool { current != nil && IslandSettings.shared.showsShelf }

    /// Opens the island on its Shelf (a drag starting, the Shelf's shortcut).
    func openShelf() {
        guard let model else { return }
        if model.state == .closed {
            withAnimation(IslandMotion.open) { model.openForDrop() }
        } else {
            model.droppedOnShelf()
        }
        model.watchUntilPointerLeaves()
    }

    init(appSettings: SettingsStore) {
        self.appSettings = appSettings
    }

    func start() {
        Self.current = self
        running = true
        followDisplay()
        observe()
        checkFullScreen()
        followMusicSetting()
        followShelf()
        followSize()
        followClosedShape()
        followMenus()
        followPrivacy()
        IslandNotices.shared.start()
        IslandBattery.shared.start()
        IslandCalendar.shared.start()
        IslandTimers.shared.start()
        // The island shows a recording itself, so Capture's floating pill stays away (the owner's choice).
        ScreenRecorder.showsPill = { false }
        // Captures can include the island (B-39): pickable only while open, and closed once a capture
        // that held it open is over and the pointer is away.
        ScreenCapture.isOwnWindowPickable = { [weak self] window in
            guard let self, let island = self.islands.first(where: { $0.window === window }) else { return true }
            return island.model.state == .open
        }
        ScreenCapture.holdsEnded = { [weak self] in self?.islands.forEach { $0.model.closeIfPointerLeft() } }
    }

    // MARK: Displays (Vorssaint's NotchDisplay)

    /// The display choice and the hide-in-full-screen switch.
    private func followDisplay() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking { _ = (settings.display, settings.hideInFullScreen) } onChange: { [weak self] in
            Task { @MainActor in self?.followDisplay() }
        }
        syncIslands()
        syncPointerTimer()
        checkFullScreen()
    }

    /// The displays the island shows on now.
    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard let main = screens.first else { return [] }
        let builtIn = screens.first { CGDisplayIsBuiltin(Self.displayID($0)) != 0 }
        switch IslandSettings.shared.display {
        case .main:
            return [main]
        case .builtIn:
            // A laptop with its lid closed has no built-in display, so the island hides; a Mac without
            // one keeps the main display (Vorssaint's rule).
            if let builtIn { return [builtIn] }
            return IslandSettingsView.hasBattery() ? [] : [main]
        case .automatic:
            if let builtIn, IslandSizing.hasNotch(builtIn) { return [builtIn] }
            return [screens.first(where: { IslandSizing.hasNotch($0) }) ?? main]
        case .pointer:
            // It stays where it is until the pointer settles on another display.
            if let current = islands.first?.model.screen,
               let same = screens.first(where: { Self.displayID($0) == Self.displayID(current) }) { return [same] }
            return [screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? main]
        case .all:
            return screens
        }
    }

    /// One island per target display: kept where it already is, made for a new display, closed for
    /// one it left.
    private func syncIslands() {
        let targets = targetScreens()
        var kept: [Island] = []
        var spare = islands
        for screen in targets {
            let id = Self.displayID(screen)
            if let index = spare.firstIndex(where: { $0.model.screen.map(Self.displayID) == id }) {
                kept.append(spare.remove(at: index))
            } else if let index = spare.firstIndex(where: { $0.model.state == .closed }) ?? spare.indices.first {
                // A display changed (following the pointer): the island moves there.
                let island = spare.remove(at: index)
                island.model.screen = screen
                kept.append(island)
            } else {
                let model = IslandModel(screen: screen)
                kept.append(Island(model: model, window: makeWindow(model: model)))
            }
        }
        for island in spare { tearDown(island) }
        islands = kept
        islands.forEach(place)
    }

    private func tearDown(_ island: Island) {
        island.window.orderOut(nil)
        island.window.contentView = nil
        island.window.close()
    }

    /// Following the pointer across several displays: a light check of where it is, only then.
    private func syncPointerTimer() {
        let follows = IslandSettings.shared.display == .pointer && NSScreen.screens.count > 1
        guard follows else { pointerTimer?.invalidate(); pointerTimer = nil; return }
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    /// Moves the island to the pointer's display once it's there and the island is closed (an open
    /// island finishes where it is, as Vorssaint's does).
    private func followPointer() {
        guard let island = islands.first, island.model.state == .closed, !island.model.peeking,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              Self.displayID(screen) != island.model.screen.map(Self.displayID) else { return }
        island.model.screen = screen
        place(island)
        checkFullScreen()
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    // MARK: Following settings

    /// Drags are watched only while the island shows a Shelf.
    private func followShelf() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking { _ = settings.showsShelf } onChange: { [weak self] in
            Task { @MainActor in self?.followShelf() }
        }
        dragDetector.onContentDragStarted = { [weak self] in self?.openShelf() }
        if settings.showsShelf { dragDetector.start() } else { dragDetector.stop() }
    }

    /// The windows take the open island's size (the Size setting) and stay centred on the notch.
    private func followSize() {
        guard running else { return }
        let size = withObservationTracking { IslandSizing.windowSize } onChange: { [weak self] in
            Task { @MainActor in self?.followSize() }
        }
        for island in islands {
            if island.window.frame.size != size { island.window.setContentSize(size) }
            place(island)
            if island.model.state == .open { island.model.open() }   // already open: only takes the new size
        }
    }

    /// The closed size follows the notch fit and the capsule's shape and fit.
    private func followClosedShape() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking {
            _ = (settings.cameraFit, settings.silhouette, settings.capsuleFit.width, settings.capsuleFit.height)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followClosedShape() }
        }
        islands.forEach { $0.model.refreshClosedSize() }
    }

    /// Show in screenshots and videos off: macOS leaves the islands out of every capture and screen share.
    private func followPrivacy() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking { _ = settings.showInCaptures } onChange: { [weak self] in
            Task { @MainActor in self?.followPrivacy() }
        }
        islands.forEach { $0.window.sharingType = settings.showInCaptures ? .readOnly : .none }
    }

    /// Show over the menus off: the room beside the notch is checked once a second.
    private func followMenus() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking { _ = settings.coversMenus } onChange: { [weak self] in
            Task { @MainActor in self?.followMenus() }
        }
        if settings.coversMenus { IslandMenuSpace.shared.stop() } else { IslandMenuSpace.shared.start() }
    }

    /// The music reader runs while the island is on; switching other players on or off restarts it.
    private func followMusicSetting() {
        guard running else { return }
        let settings = IslandSettings.shared
        withObservationTracking { _ = settings.otherPlayers } onChange: { [weak self] in
            Task { @MainActor in self?.followMusicSetting() }
        }
        IslandMusic.shared.start(includeOtherPlayers: settings.otherPlayers)
    }

    func stop() {
        if Self.current === self { Self.current = nil }
        running = false
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        fullScreenCheck?.cancel()
        pointerTimer?.invalidate()
        pointerTimer = nil
        IslandMusic.shared.stop()
        IslandNotices.shared.stop()
        IslandMenuSpace.shared.stop()
        dragDetector.stop()
        IslandBattery.shared.stop()
        IslandCalendar.shared.stop()
        IslandTimers.shared.stop()
        ScreenRecorder.showsPill = { true }
        ScreenCapture.isOwnWindowPickable = { _ in true }
        ScreenCapture.holdsEnded = {}
        IslandCameraSession.shared.stop()
        islands.forEach(tearDown)
        islands = []
    }

    /// Opens or closes the island (the Settings page's button).
    func toggle() {
        guard let model else { return }
        withAnimation(IslandMotion.to(open: model.state != .open)) {
            if model.state == .open { model.close() } else { model.open() }
        }
    }

    private func makeWindow(model: IslandModel) -> IslandWindow {
        let rect = NSRect(x: 0, y: 0, width: IslandSizing.windowSize.width, height: IslandSizing.windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = IslandWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        let host = NSHostingView(
            rootView: IslandView(model: model)
                .environment(appSettings)
        )
        // The engine alone sizes the window (B-37/B-38): by default SwiftUI resizes it too, keeping
        // its old limits, so a resized island ended up off centre or cut off.
        host.sizingOptions = []
        window.contentView = host
        window.sharingType = IslandSettings.shared.showInCaptures ? .readOnly : .none
        window.orderFrontRegardless()
        return window
    }

    /// Top centre of its display.
    private func place(_ island: Island) {
        let model = island.model, window = island.window
        if model.state == .closed { model.close() }
        guard let screenFrame = model.screen?.frame else {
            window.alphaValue = 0
            return
        }
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Displays came or went (or the lid closed): the islands follow, and their sizes too.
                self.islands.forEach { $0.model.screen = $0.model.screen.flatMap { old in
                    NSScreen.screens.first { Self.displayID($0) == Self.displayID(old) } } }
                self.syncIslands()
                self.syncPointerTimer()
                self.checkFullScreen()
            }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreen() }
            }))
        }
    }

    /// Whether a full-screen window covers each island's display. Checked when the Space or the
    /// front app changes (twice: right away, and after the Space animation settles).
    private func checkFullScreen() {
        fullScreenCheck?.cancel()
        fullScreenCheck = Task { [weak self] in
            for delay in [0.05, 0.8] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                for island in self.islands {
                    let fullScreen = Self.isFullScreen(on: island.model.screen)
                    if island.model.isFullScreen != fullScreen { island.model.isFullScreen = fullScreen }
                }
            }
        }
    }

    /// A normal-level window of the front app that covers the whole display (window bounds need no
    /// permission, unlike titles).
    private static func isFullScreen(on screen: NSScreen?) -> Bool {
        guard let screen, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // Window bounds are in global coordinates with the origin at the main display's top left.
        let frame = screen.frame
        let target = CGRect(x: frame.minX, y: main.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return list.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.insetBy(dx: -1, dy: -1).contains(target)
        }
    }
}
