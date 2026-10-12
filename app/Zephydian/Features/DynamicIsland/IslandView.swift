//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//
// Copied into Zephydian from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee). Zephydian changes: reads IslandModel/IslandSettings instead of boring.notch's
// view model and Defaults; the Liquid Glass look; Reduce Motion; click-only opening; the face,
// hello animation, battery, music and shelf branches are left for later stages (Zephydian
// content), and the volume/brightness HUD is left out (macOS keeps its own pop-up); the context menu opens Zephydian's settings; Vorssaint's opening modes (preview strip, hidden until hover); Keep Open and the header's menu stop
// the hover close.

import SwiftUI

struct IslandView: View {
    let model: IslandModel
    private var settings: IslandSettings { IslandSettings.shared }

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false
    /// A drag is over the closed notch (boring.notch's dragDetector).
    @State private var dragTargeting = false
    @Namespace private var albumArtNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a swipe travels before it opens or closes the island (boring.notch's default).
    private let gestureSensitivity: CGFloat = 200

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private var animationSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    }

    private var insets: (top: CGFloat, bottom: CGFloat) {
        model.state == .open ? IslandSizing.cornerRadiusInsets.opened : IslandSizing.cornerRadiusInsets.closed
    }

    private var currentShape: IslandSilhouetteShape {
        IslandSilhouetteShape(capsule: model.floatsAsCapsule, topCornerRadius: insets.top, bottomCornerRadius: insets.bottom)
    }

    private var glassOpen: Bool { settings.look == .glass && model.state == .open }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(SettingsStore.self) private var appSettings

    /// Vorssaint's translucent background: the Black look blurs what's behind the open island.
    private var translucentOpen: Bool {
        settings.look == .black && settings.translucent && model.state == .open && !reduceTransparency
    }

    /// Show over the menus off (Vorssaint's): the closed activity gives way when the menus beside the
    /// notch need its room. The activity's wing is measured while it shows.
    @State private var activityWing: CGFloat = 0
    private var blockedByMenus: Bool {
        guard !settings.coversMenus, model.state == .closed, activityWing > 0,
              let room = IslandMenuSpace.shared.room(on: model.screen) else { return false }
        return room < activityWing
    }

    /// The outline shows only while you use the island or something is live (B-41): hovering, open,
    /// or a live activity or alert beside the notch. At rest the island is just the notch.
    private var outlineShows: Bool {
        guard settings.outline else { return false }
        if model.state == .open || isHovering { return true }
        return model.isAlerting || IslandCapture.isRecording || (!model.hideOnClosed && model.isLive)
    }

    /// While the outline shows, a closed island on a notch grows by its width down and to each side,
    /// so the line isn't hidden under the real notch's edge (B-40, Vorssaint's outline room).
    private var outlineRoom: CGFloat {
        outlineShows && model.state == .closed && model.hasNotch && model.effectiveClosedHeight > 0 ? IslandSizing.outlineWidth : 0
    }

    /// Vorssaint's outline: 2 pt, in the accent color (the owner's choice), orange while a timer shows
    /// in the closed island; stronger with Increase Contrast.
    @ViewBuilder private var outline: some View {
        if outlineShows {
            let timer = model.state == .closed && !model.hideOnClosed && IslandTimers.shared.soonest != nil
            let color = contrast == .increased ? Color.white : (timer ? Color.orange : appSettings.accentColor)
            currentShape
                .stroke(color.opacity(contrast == .increased ? 0.85 : 0.65), lineWidth: 2 * IslandSizing.outlineWidth)
                .clipShape(currentShape)
                // A notch hangs from the screen's edge, so its outline leaves the top open; a capsule's goes round.
                .mask(alignment: .bottom) {
                    Rectangle().padding(.top, model.floatsAsCapsule ? 0 : IslandSizing.outlineWidth)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // The open island keeps its own width; the window is wider, for the side buttons.
                let mainLayout = layout
                    .frame(width: model.state == .open ? IslandSizing.openSize.width - 2 * (IslandSizing.cornerRadiusInsets.opened.top + 12) : nil,
                           alignment: .top)
                    .padding(
                        .horizontal,
                        model.state == .open ? IslandSizing.cornerRadiusInsets.opened.top : IslandSizing.cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], model.state == .open ? 12 : 0)
                    .padding([.horizontal, .bottom], outlineRoom)
                    .animation(animationSpring, value: outlineRoom)
                    .background { background }
                    .clipShape(currentShape)
                    .overlay { outline }
                    .overlay(alignment: .top) {
                        // Covers the hairline gap between the island and the top of the screen.
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, insets.top)
                    }
                    .shadow(
                        color: ((model.state == .open || isHovering) && settings.shadow) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .padding(
                        .bottom,
                        model.effectiveClosedHeight == 0 ? 10 : 0
                    )
                    // A capsule floats below the top of the screen (Vorssaint's silhouette).
                    .padding(.top, model.capsuleTop)

                mainLayout
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        // The activity's wing beside the notch, kept while it gives way.
                        guard model.state == .closed, !blockedByMenus, !model.peeking else { return }
                        // How far the island reaches past the notch on each side.
                        let wing = (width - model.closedSize.width) / 2
                        if wing > IslandSizing.cornerRadiusInsets.closed.bottom + 4 { activityWing = wing }
                    }
                    .frame(height: model.state == .open ? model.size.height : nil)
                    .scaleEffect(hoverBulge, anchor: .top)
                    .animation(openCloseAnimation, value: model.state)
                    .animation(.smooth, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .islandPanGesture(direction: .down) { translation, phase in
                        handleDownGesture(translation: translation, phase: phase)
                    }
                    .islandPanGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
                    .onChange(of: model.state) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Dynamic Island Settings…") {
                            CommandBarHooks.openSettings(SettingsPage.island.rawValue)
                        }
                    }
                if model.chinHeight > 0 {
                    // The rest of the menu bar's height under a short pill still counts as the island.
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: chinWidth, height: model.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            // Buttons beside the open island (22.11, after Vorssaint's).
            if model.state == .open && !settings.buttons.isEmpty {
                IslandSideButtons(model: model)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: IslandSizing.windowSize.width, maxHeight: IslandSizing.windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .animation(.smooth, value: model.hideOnClosed)
        .background(dragDetector)
        .onChange(of: dragTargeting) { _, targeted in
            guard targeted, model.state == .closed else { return }
            withAnimation(animationSpring) { model.openForDrop() }
            if settings.haptics { haptics.toggle() }
            model.watchUntilPointerLeaves()
        }
    }

    /// The closed island's width, wider while a live activity shows beside the notch.
    private var chinWidth: CGFloat {
        var width = model.closedSize.width
        if model.state == .closed && (IslandBattery.shared.alert != nil || IslandTimers.shared.doneAlert != nil) {
            width = IslandBatteryAlert.width
        } else if model.state == .closed && !model.hideOnClosed && IslandNotices.shared.current != nil {
            width = IslandTimerLiveActivity.width(closed: model.closedSize.width)
        } else if model.state == .closed && IslandCapture.isRecording {
            width = IslandRecordingLiveActivity.width(closed: model.closedSize.width)
        } else if model.state == .closed && (model.hideOnClosed || blockedByMenus) {
            // Just the notch.
        } else if model.state == .closed && IslandTimers.shared.isLive {
            width = IslandTimerLiveActivity.width(closed: model.closedSize.width)
        } else if model.state == .closed && IslandCalendar.shared.upcoming != nil {
            width = IslandCalendarLiveActivity.width(closed: model.closedSize.width)
        } else if model.state == .closed && model.showsMusicClosed {
            width += IslandMusicLiveActivity.extraWidth(height: model.effectiveClosedHeight)
        } else if model.state == .closed && model.showsBatteryRest {
            width += 2 * IslandBatteryRest.wing
        }
        return width
    }

    /// boring.notch's dragDetector: while closed, the island takes macOS's drag and drop (no mouse
    /// watching), and a drag arriving opens it on the Shelf.
    @ViewBuilder private var dragDetector: some View {
        if model.state == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: IslandShelfDrop.types, isTargeted: $dragTargeting) { providers in
                    IslandShelfDrop.receive(providers)
                }
        }
    }

    private var openCloseAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
        return model.state == .open ? openAnimation : closeAnimation
    }

    /// Click-only opening: the closed island swells a little under the pointer instead of opening.
    private var hoverBulge: CGFloat {
        guard !reduceMotion, settings.opening == .click, model.state == .closed, isHovering else { return 1 }
        return 1.04
    }

    /// Solid black, or Liquid Glass while open with the Liquid Glass look (black while closed, so it
    /// blends with the notch).
    @ViewBuilder private var background: some View {
        if glassOpen {
            ZStack {
                // B-33: glass leaves the window's own pixels clear, and macOS sends clicks through clear
                // pixels to the window behind. An invisible 1% fill makes the whole island catch them
                // (boring.notch does the same for its notch's hover area).
                currentShape.fill(Color.black.opacity(0.01))
                Color.clear.glassSurface(in: currentShape, fallback: Material.regular)
            }
            .transition(.opacity)
        } else if translucentOpen {
            ZStack {
                currentShape.fill(Color.black.opacity(0.01))   // clicks stop here (B-33)
                IslandBehindBlur(shape: currentShape)
                // Black over the camera strip, so the open island still meets the notch as black, then a
                // dark tint over the blur (Vorssaint's NotchTranslucentTint, simplified).
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: min(0.9, model.closedSize.height / max(1, model.size.height))),
                    .init(color: .black.opacity(contrast == .increased ? 0.75 : 0.45), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .transition(.opacity)
        } else {
            Color.black
                .transition(.opacity)
        }
    }

    @ViewBuilder private var layout: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if model.state == .closed, model.peeking, IslandBattery.shared.alert == nil, IslandTimers.shared.doneAlert == nil {
                    // Preview on hover (Vorssaint's peek): the tabs and Open, under the notch.
                    IslandPeekStrip(model: model)
                        .transition(.opacity)
                } else if model.state == .closed, let alert = IslandBattery.shared.alert {
                    // boring.notch's battery expanding view: over everything for 3 s (22-D7).
                    IslandBatteryAlert(model: model, text: alert.text)
                        .transition(.opacity)
                } else if model.state == .closed, let done = IslandTimers.shared.doneAlert {
                    IslandTimerDoneAlert(model: model, text: done)
                        .transition(.opacity)
                } else if model.state == .closed, !model.hideOnClosed, let notice = IslandNotices.shared.current {
                    // Vorssaint's indicators: a moment's notice beside the notch.
                    IslandNoticeView(model: model, notice: notice)
                        .id(notice.id)
                        .transition(.opacity)
                } else if model.state == .closed, IslandCapture.isRecording {
                    // A recording comes first, even in full-screen apps (you need to know it's on).
                    IslandRecordingLiveActivity(model: model)
                        .transition(.opacity)
                } else if model.state == .closed, !model.hideOnClosed, !blockedByMenus, let timer = IslandTimers.shared.soonest {
                    // A timer comes before the calendar and music (22-D7).
                    IslandTimerLiveActivity(model: model, timer: timer)
                        .transition(.opacity)
                } else if model.state == .closed, !model.hideOnClosed, !blockedByMenus, let event = IslandCalendar.shared.upcoming {
                    // An event in the next 10 minutes comes before music (22-D20).
                    IslandCalendarLiveActivity(model: model, event: event)
                        .transition(.opacity)
                } else if model.state == .closed && model.showsMusicClosed && !model.hideOnClosed && !blockedByMenus {
                    IslandMusicLiveActivity(model: model, namespace: albumArtNamespace)
                        .frame(alignment: .center)
                } else if model.state == .closed && model.showsBatteryRest && !model.hideOnClosed && !blockedByMenus {
                    // At rest with Battery (Vorssaint's resting choice).
                    IslandBatteryRest(model: model)
                        .transition(.opacity)
                } else if model.state == .open {
                    IslandHeader(model: model)
                        .frame(height: max(24, model.effectiveClosedHeight))
                        .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                } else {
                    Rectangle().fill(.clear).frame(width: model.closedSize.width - 20, height: model.effectiveClosedHeight)
                }

            }
            .zIndex(2)
            if model.state == .open {
                IslandBody(model: model, namespace: albumArtNamespace)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35))
                    )
                    .zIndex(1)
                    .allowsHitTesting(model.state == .open)
                    .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            model.open()
        }
    }

    private func doClose() {
        withAnimation(animationSpring) {
            model.close()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            if model.state == .closed && settings.haptics {
                haptics.toggle()
            }

            guard model.state == .closed, settings.opening.usesHover, !model.peeking else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(settings.hoverDelay))
                guard !Task.isCancelled else { return }

                guard model.state == .closed, isHovering else { return }
                if settings.opening == .preview {
                    withAnimation(animationSpring) { model.peek() }
                } else {
                    doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                withAnimation(animationSpring) {
                    isHovering = false
                    model.endPeek()
                }

                // A capture under way keeps it open, so it can be in the picture (B-39).
                if model.state == .open && !model.pinned && !model.menuOpen && !model.overSideButtons && !ScreenCapture.isHolding {
                    doClose()
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard settings.gestures, model.state == .closed, !IslandGestureGuard.overScrollingContent else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / gestureSensitivity) * 20
        }

        if translation > gestureSensitivity {
            if settings.haptics {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard settings.gestures, model.state == .open, !IslandGestureGuard.overScrollingContent else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / gestureSensitivity) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > gestureSensitivity {
            withAnimation(animationSpring) {
                isHovering = false
            }
            gestureProgress = .zero
            doClose()

            if settings.haptics {
                haptics.toggle()
            }
        }
    }
}

/// Content that scrolls (the calendar's events) sets this while the pointer is over it, so the
/// island's swipe gestures don't close it while scrolling (boring.notch's isHoveringCalendar).
enum IslandGestureGuard {
    static var overScrollingContent = false
}
