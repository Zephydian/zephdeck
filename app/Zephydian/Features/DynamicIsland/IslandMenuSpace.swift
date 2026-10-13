// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Follows Vorssaint's menu space (readMenuSpace and NotchMenuBarLayout.sideRoom in
// Services/Notch/NotchService.swift and NotchSupport.swift, commit 1d32501): once a second, how much
// of the menu bar beside the notch is free of the front app's menus and the menu bar icons, so the
// closed island's activity can give way when Show over the menus is off. Zephydian changes: menus
// read through Accessibility (skipped without it) and icons from the window list, off the main thread;
// the room is the smaller side's; checked only while the switch is off and the island is on.

import AppKit
import ApplicationServices

@Observable
final class IslandMenuSpace {
    static let shared = IslandMenuSpace()

    /// Free room beside the notch, by display (the smaller of the two sides).
    private(set) var rooms: [CGDirectDisplayID: CGFloat] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var measuring = false

    func room(on screen: NSScreen?) -> CGFloat? {
        guard let screen else { return nil }
        return rooms[Self.displayID(screen)]
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measure() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        measure()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rooms = [:]
    }

    /// A display, in the window list's top-left coordinates, with its notch's width.
    struct Display: Sendable {
        let id: CGDirectDisplayID
        let frame: CGRect
        let notchWidth: CGFloat
    }

    private func measure() {
        guard !measuring, let main = NSScreen.screens.first else { return }
        measuring = true
        let displays = NSScreen.screens.map { screen in
            Display(id: Self.displayID(screen),
                    frame: CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY,
                                  width: screen.frame.width, height: screen.frame.maxY - screen.visibleFrame.maxY),
                    notchWidth: IslandSizing.closedSize(on: screen).width)
        }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let trusted = AXIsProcessTrusted()
        Task { [weak self] in
            // Asking another app (its menus) can wait on it, so never on the main thread (19.9).
            let rooms = await Task.detached(priority: .utility) { Self.rooms(displays, pid: trusted ? pid : nil) }.value
            guard let self else { return }
            self.measuring = false
            guard self.timer != nil else { return }
            if rooms != self.rooms { self.rooms = rooms }
        }
    }

    private nonisolated static func rooms(_ displays: [Display], pid: pid_t?) -> [CGDirectDisplayID: CGFloat] {
        let menusEnd = pid.flatMap(menusEnd)   // relative to the left edge of the display with the menus
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var result: [CGDirectDisplayID: CGFloat] = [:]
        for display in displays {
            let notchMin = display.frame.midX - display.notchWidth / 2
            let notchMax = display.frame.midX + display.notchWidth / 2
            // Menu bar icons: status-level windows in this display's bar, right of the notch's middle.
            var iconsStart = display.frame.maxX
            for info in windows {
                guard (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                      let dict = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dict),
                      bounds.height <= display.frame.height + 2, abs(bounds.minY - display.frame.minY) < 2,
                      bounds.midX > display.frame.midX, bounds.maxX <= display.frame.maxX + 1 else { continue }
                iconsStart = min(iconsStart, bounds.minX)
            }
            let right = iconsStart - notchMax
            let left = menusEnd.map { notchMin - (display.frame.minX + $0) } ?? .infinity
            result[display.id] = max(0, min(left, right))
        }
        return result
    }

    /// Where the front app's menus end, from its display's left edge (Accessibility).
    private nonisolated static func menusEnd(_ pid: pid_t) -> CGFloat? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement], let last = items.last else { return nil }
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(last, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(last, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        // The menus are on the main display's bar; every bar lays them out the same from its left edge.
        let mainLeft = CGDisplayBounds(CGMainDisplayID()).minX
        return point.x + extent.width - mainLeft
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
