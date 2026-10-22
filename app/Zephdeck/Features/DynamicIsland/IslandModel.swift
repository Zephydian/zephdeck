//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//
// Copied into Zephdeck from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee). Zephdeck changes: an @Observable model for one island on the main display;
// full-screen state is set by the engine (boring.notch used MacroVisionKit); the camera, shelf,
// battery popover, hello animation and drop targeting moved out or were left out; displays without
// a notch can hide the closed island while nothing is live; Zephdeck's tabs, grid and Keep Open.

import AppKit
import SwiftUI

enum IslandState {
    case closed
    case open
}

@Observable
final class IslandModel {
    private(set) var state: IslandState = .closed
    /// The display the island is on (the one with the menu bar).
    var screen: NSScreen? {
        didSet { closedSize = IslandSizing.closedSize(on: screen); if state == .closed { size = closedSize } }
    }
    /// The current size: the notch's while closed, the open island's while open.
    private(set) var size: CGSize
    private(set) var closedSize: CGSize
    /// A full-screen app is in front on the island's display.
    var isFullScreen = false
    /// Something is showing in the closed island (music; a timer and a recording come with their stages).
    var isLive: Bool { !liveTabs.isEmpty }
    /// A short alert (battery) is showing; it shows even over full-screen apps.
    var isAlerting: Bool { IslandBattery.shared.alert != nil || IslandTimers.shared.doneAlert != nil }
    /// Music shows in the closed island (At rest: Music).
    var showsMusicClosed: Bool { settings.restWith == .music && IslandMusic.shared.isLive }
    /// The battery shows in the closed island (At rest: Battery, on a Mac with one).
    var showsBatteryRest: Bool { settings.restWith == .battery && IslandBattery.shared.hasBattery }

    /// The tabs of what's live, most important first (a recording, a timer, music; 22-D7).
    var liveTabs: [IslandTab] {
        var tabs: [IslandTab] = []
        if IslandCapture.isRecording { tabs.append(.capture) }
        if IslandTimers.shared.isLive { tabs.append(.timers) }
        if IslandCalendar.shared.upcoming != nil { tabs.append(.calendar) }
        if showsMusicClosed { tabs.append(.music) }
        return tabs
    }

    /// Preview on hover: the closed island shows its strip of tabs (Vorssaint's peek).
    private(set) var peeking = false

    func peek() { if state == .closed { peeking = true } }
    func endPeek() { peeking = false }

    /// The open island's page.
    private(set) var tab: IslandTab = .home
    /// The grid of tabs is showing instead of the tab.
    var showingGrid = false
    /// Keep Open: leaving the island doesn't close it.
    var pinned = false
    /// The header's menu is up; the pointer leaving for it doesn't close the island.
    var menuOpen = false
    /// The pointer is on a button beside the island, which counts as the island.
    @ObservationIgnored var overSideButtons = false
    @ObservationIgnored private var leaveCheck: Task<Void, Never>?

    /// The pointer left a side button: close unless it went back to the island (or another button).
    func closeIfPointerLeft() {
        leaveCheck?.cancel()
        leaveCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, self.state == .open, !self.pinned, !self.menuOpen, !ScreenCapture.isHolding,
                  !self.overSideButtons, !self.isPointerInside() else { return }
            withAnimation(IslandMotion.close) { self.close() }
        }
    }

    @ObservationIgnored private let settings = IslandSettings.shared

    init(screen: NSScreen?) {
        closedSize = IslandSizing.closedSize(on: screen)
        size = IslandSizing.closedSize(on: screen)
        self.screen = screen
    }

    var hasNotch: Bool { IslandSizing.hasNotch(screen) }

    /// The closed island floats as a capsule below the top of the screen (no notch, Capsule chosen).
    var floatsAsCapsule: Bool { state == .closed && IslandSizing.floatsAsCapsule(screen) }
    /// The space above the closed capsule.
    var capsuleTop: CGFloat { state == .closed ? IslandSizing.capsuleTop(screen) : 0 }

    /// The closed size again after a fit or the shape changed.
    func refreshClosedSize() {
        closedSize = IslandSizing.closedSize(on: screen)
        if state == .closed { size = closedSize }
    }

    /// Closed live activities hide in full-screen apps; without a notch the island can hide while
    /// nothing is live. Alerts always show.
    var hideOnClosed: Bool {
        if isAlerting || IslandCapture.isRecording { return false }
        if isFullScreen && settings.hideInFullScreen { return true }
        // Hidden until hover: nothing shows until the pointer opens it.
        if settings.opening == .hidden { return true }
        if IslandNotices.shared.current != nil { return false }
        return !hasNotch && settings.noNotch == .hidden && !isLive && !showsBatteryRest
    }

    // Computed property for effective notch height
    var effectiveClosedHeight: CGFloat {
        // A notched display keeps its notch-sized island even when hidden: the hardware is black there anyway.
        hideOnClosed && !hasNotch ? 0 : closedSize.height
    }

    /// The menu bar's height minus the island's, so hovering the menu bar beside a short pill still counts.
    var chinHeight: CGFloat {
        guard let screen, state == .closed else { return 0 }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let current = effectiveClosedHeight
        if current == 0 { return 0 }
        return max(0, menuBarHeight - current - capsuleTop)
    }

    func open() {
        if state == .closed {
            tab = tabToOpen
            showingGrid = opensOnGrid
        }
        peeking = false
        size = IslandSizing.openSize
        state = .open
    }

    /// Opens on one tab (the preview strip's icons).
    func open(on tab: IslandTab) {
        self.tab = tab
        settings.lastTab = tab
        showingGrid = false
        peeking = false
        size = IslandSizing.openSize
        state = .open
    }

    /// "When reopening" is All Tabs, and no live activity takes the island.
    private var opensOnGrid: Bool {
        guard settings.reopenTo == "grid" else { return false }
        return !(settings.opensActivity && liveTabs.contains { settings.visibleTabs.contains($0) })
    }

    /// A drag reached the closed notch: open on the Shelf (the tab, or Home when it has the Shelf and
    /// the Shelf tab is off).
    func openForDrop() {
        let shown = settings.visibleTabs
        tab = shown.contains(.shelf) || !(shown.contains(.home) && settings.homeItems.contains(.shelf)) ? .shelf : .home
        showingGrid = false
        size = IslandSizing.openSize
        state = .open
    }

    @ObservationIgnored private var dragWatch: Task<Void, Never>?

    /// A drag gives no hover events, so after one the island checks for the pointer itself (every
    /// quarter second, only until it closes) and closes once the drag is over and the pointer is out.
    func watchUntilPointerLeaves() {
        dragWatch?.cancel()
        dragWatch = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled, let self, self.state == .open {
                if !self.pinned, !self.menuOpen, !ScreenCapture.isHolding, !self.isPointerInside(), NSEvent.pressedMouseButtons == 0 {
                    withAnimation(IslandMotion.close) { self.close() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Something was dropped on the open island: show the Shelf if Home doesn't.
    func droppedOnShelf() {
        if tab != .shelf && !(tab == .home && settings.homeItems.contains(.shelf)) {
            tab = .shelf
            showingGrid = false
        }
    }

    /// Shows a tab (from the grid) and remembers it.
    func select(_ tab: IslandTab) {
        self.tab = tab
        settings.lastTab = tab
        showingGrid = false
    }

    /// The live one if "Open the visible activity" is on (music falls back to Home when Music is
    /// off), else the "When reopening" page, else the last one used, else the first.
    private var tabToOpen: IslandTab {
        let shown = settings.visibleTabs
        if settings.opensActivity {
            for live in liveTabs {
                if shown.contains(live) { return live }
                if live == .music, shown.contains(.home), settings.homeItems.contains(.music) { return .home }
            }
        }
        if let chosen = IslandTab(rawValue: settings.reopenTo), shown.contains(chosen) { return chosen }
        if shown.contains(settings.lastTab) { return settings.lastTab }
        return shown.first ?? .home
    }

    /// The pointer is over the open island (its menu just closed, for example).
    func isPointerInside(_ point: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let frame = screen?.frame else { return false }
        let x = frame.midX - size.width / 2
        return point.y >= frame.maxY - size.height && point.x >= x && point.x <= x + size.width
    }

    func close() {
        peeking = false
        closedSize = IslandSizing.closedSize(on: screen)
        size = closedSize
        state = .closed
        showingGrid = false
        pinned = false
    }
}
