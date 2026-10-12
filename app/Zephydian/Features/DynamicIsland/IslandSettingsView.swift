// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The Dynamic Island's Settings page, copied from Vorssaint's (UI/Settings/NotchSettings.swift and
// NotchSettingsTabRow.swift, commit 1d32501): a header with the title, a line about it and the
// switch; the tab row (Layout, Content, Activity, Behavior) with the button that opens the island;
// cards of rows, tiles and toggle cards. Zephydian changes: Zephydian's options and wording; the
// pages fill in stage by stage (22.12 b–h); the Layout tab opens with Vorssaint's layout editor; English only.

import ApplicationServices
import IOKit.ps
import SwiftUI

/// The island page's tabs (Vorssaint's NotchSettingsTab, without the companion).
enum IslandSettingsTab: CaseIterable {
    case layout, content, activity, behavior

    var title: String {
        switch self {
        case .layout: "Layout"
        case .content: "Content"
        case .activity: "Activity"
        case .behavior: "Behavior"
        }
    }
}

struct IslandSettingsView: View {
    @Bindable private var settings = IslandSettings.shared
    @State private var tab = IslandSettingsTab.layout
    private var features: Features { Features.shared }
    private static let featureID = "dynamic-island"

    private var enabled: Binding<Bool> {
        Binding(get: { features.isOn(Self.featureID) }, set: { features.set(Self.featureID, on: $0) })
    }

    /// The page takes its width from the column (a GeometryReader never asks for more), so it can't
    /// grow wider than its column, spread under the sidebar or widen the window (B-36; Vorssaint's
    /// pages are laid out the same way).
    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - 44)
            VStack(alignment: .leading, spacing: 20) {
                header.frame(width: width, alignment: .leading)
                tabRow.frame(width: width, alignment: .leading)
                ScrollView {
                    Group {
                        switch tab {
                        case .layout: layoutPage
                        case .content: IslandContentEditor()
                        case .activity: activityPage
                        case .behavior: behaviorPage
                        }
                    }
                    .frame(width: width, alignment: .topLeading)
                    .padding(.bottom, 22)
                }
                .id(tab)
            }
            .padding(.horizontal, 22).padding(.top, 22)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dynamic Island").font(.title2.bold())
                Text("Your music, timers, calendar and everyday tools, together at the top of your screen. Optional: turn it off to keep using the panel.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("Enable Dynamic Island", isOn: enabled).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("Enable Dynamic Island")
        }
    }

    /// The page's tabs, with the button that opens the island; the segments become a menu when
    /// they don't fit beside it (Vorssaint's NotchSettingsTabRow).
    private var tabRow: some View {
        HStack {
            ViewThatFits(in: .horizontal) {
                tabPicker.pickerStyle(.segmented)
                tabPicker.pickerStyle(.menu)
            }
            Button { IslandEngine.current?.toggle() } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered)
                .disabled(!features.running.contains(Self.featureID))
                .help("Open Dynamic Island")
                .accessibilityLabel("Open Dynamic Island")
        }
    }

    private var tabPicker: some View {
        Picker("Dynamic Island", selection: $tab) {
            ForEach(IslandSettingsTab.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
    }

    // MARK: Layout

    private var layoutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            IslandLayoutEditor { tab = .content }
            PageCard(title: "Size") {
                HStack(spacing: 10) {
                    PageChoiceTile(title: "Compact", symbol: "rectangle.compress.vertical", selected: settings.size == .compact) { settings.size = .compact }
                    PageChoiceTile(title: "Spacious", symbol: "rectangle.expand.vertical", selected: settings.size == .spacious) { settings.size = .spacious }
                    PageChoiceTile(title: "Custom", symbol: "arrow.up.left.and.arrow.down.right", selected: settings.size == .custom) { settings.size = .custom }
                }
                if settings.size == .custom {
                    // One grid starts both sliders at the same edge.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        dimensionSlider("Width", value: $settings.customWidth, range: IslandSettings.Size.widthRange, fallback: IslandSettings.Size.defaultWidth)
                        dimensionSlider("Height", value: $settings.customHeight, range: IslandSettings.Size.heightRange, fallback: IslandSettings.Size.defaultHeight)
                    }
                    Text("You can also drag the grip on the island's corner above.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            PageCard(title: "Look") {
                HStack(spacing: 10) {
                    PageChoiceTile(title: "Black", symbol: "capsule.fill", selected: settings.look == .black) { settings.look = .black }
                    PageChoiceTile(title: "Liquid Glass", symbol: "drop.halffull", selected: settings.look == .glass) { settings.look = .glass }
                }
                Text(settings.look == .black
                     ? "Solid black, so it looks like the notch is growing."
                     : "Black while closed so it blends with the notch, Liquid Glass once it opens.")
                    .font(.caption).foregroundStyle(.secondary)
                // Liquid Glass is see-through already, so the switch reads on and changes nothing then
                // (Vorssaint's way).
                PageSwitchRow(symbol: "circle.lefthalf.filled", title: "Translucent background",
                              caption: settings.look == .glass
                                ? "Liquid Glass is on, so the island uses it instead."
                                : "When open, the island blurs what is behind it with macOS's own material.",
                              isOn: settings.look == .glass ? .constant(true) : $settings.translucent)
                    .disabled(settings.look == .glass)
                PageSwitchRow(symbol: "shadow", title: "Shadow under the open island", isOn: $settings.shadow)
            }
            PageCard {
                PageSwitchRow(symbol: "capsule", title: "Show outline",
                              caption: "A thin line in your accent color around the island.", isOn: $settings.outline)
            }
            // Only a real notch has an edge to match.
            if NSScreen.screens.contains(where: { IslandSizing.hasNotch($0) }) {
                PageCard(title: "Notch fit") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        // Whole points keep the island centred on the camera's pixels.
                        fitSlider("Width", card: "Notch fit", value: $settings.cameraFitWidth,
                                  range: IslandSettings.Fit.cameraWidth, step: 1)
                        fitSlider("Height", card: "Notch fit", value: $settings.cameraFitHeight,
                                  range: IslandSettings.Fit.cameraHeight, step: 0.5)
                    }
                    Text("If an edge of the notch shows around the island, adjust these values until it disappears.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PageCard(title: "Displays without a notch") {
                HStack(spacing: 10) {
                    PageChoiceTile(title: "Capsule", symbol: "capsule", selected: settings.silhouette == .capsule) { settings.silhouette = .capsule }
                    PageChoiceTile(title: "Notch", symbol: "rectangle.topthird.inset.filled", selected: settings.silhouette == .notch) { settings.silhouette = .notch }
                }
                PageChoiceRow(symbol: "eye", title: "While nothing is live", selection: $settings.noNotch) {
                    Text("Always shown").tag(IslandSettings.NoNotch.pill)
                    Text("Hidden").tag(IslandSettings.NoNotch.hidden)
                }
                Text("Without a notch the island sits at the top centre of the display; hovering there opens it either way. Behavior → Display picks the display.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if settings.silhouette == .capsule {
                PageCard(title: "Capsule fit") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        // Even widths keep the capsule centred on whole points.
                        fitSlider("Width", card: "Capsule fit", value: $settings.capsuleFitWidth,
                                  range: IslandSettings.Fit.capsuleWidth, step: 2)
                        fitSlider("Height", card: "Capsule fit", value: $settings.capsuleFitHeight,
                                  range: IslandSettings.Fit.capsuleHeight, step: 1)
                        fitSlider("Distance from top", card: "Capsule fit", value: $settings.capsuleFitDrop,
                                  range: IslandSettings.Fit.capsuleDrop, step: 1)
                    }
                    Text("Resizes the capsule and lowers it from the top of the screen on displays without a notch.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Activity

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageCard(title: "At rest") {
                HStack(spacing: 10) {
                    PageChoiceTile(title: "Nothing", symbol: "minus", selected: settings.restWith == .nothing) { settings.restWith = .nothing }
                    if Self.hasBattery() {
                        PageChoiceTile(title: "Battery", symbol: "battery.75percent", selected: settings.restWith == .battery) { settings.restWith = .battery }
                    }
                    PageChoiceTile(title: "Music", symbol: "music.note", selected: settings.restWith == .music) { settings.restWith = .music }
                }
                Text(restCaption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PageSwitchRow(symbol: "menubar.rectangle", title: "Show over the menus",
                              caption: "Keeps the timer, music and other activity on screen when the menu bar has no room, covering the menus beside the notch."
                                + (settings.coversMenus || AXIsProcessTrusted() ? "" : " Without Accessibility only the menu bar icons are checked."),
                              isOn: $settings.coversMenus)
            }
            PageCard(title: "Indicators") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    if Self.hasBattery() {
                        PageToggleCard(symbol: "powerplug", title: "Plugged in and unplugged", included: $settings.batteryPlugAlert)
                        PageToggleCard(symbol: "battery.100", title: "Fully charged", included: $settings.batteryFullAlert)
                        PageToggleCard(symbol: "battery.25", title: "Low battery", included: $settings.batteryLowAlert)
                        PageToggleCard(symbol: "leaf", title: "Low Power Mode", included: $settings.batteryLowPowerAlert)
                    }
                    PageToggleCard(symbol: "camera.viewfinder", title: "Captures", included: $settings.noticeCaptures)
                    PageToggleCard(symbol: "music.note", title: "New song", included: $settings.noticeSong)
                    PageToggleCard(symbol: "mic", title: "Microphone", included: $settings.noticeMic,
                                   available: Features.shared.isOn("quick-toggles"),
                                   unavailableReason: Features.shared.isOn("quick-toggles") ? nil : "Turn on Quick Toggles",
                                   unavailableAction: { CommandBarHooks.openSettings("feature:quick-toggles") })
                    PageToggleCard(symbol: "doc.on.clipboard", title: "Clipboard", included: $settings.noticeClipboard)
                }
                Text("Each shows beside the notch for a moment. Battery alerts widen the island for 3 seconds, even over full-screen apps; low battery alerts at 20% and again at 10%. Captures come from Capture, Microphone from its mute shortcut, Clipboard while Clipboard history records.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Self.hasBattery() {
                PageCard(title: "Battery") {
                    PageSwitchRow(symbol: "battery.75percent", title: "Battery in the open island's header",
                                  caption: "Click it for its health and charging details.", isOn: $settings.batteryInHeader)
                }
            }
        }
    }

    private var restCaption: String {
        switch settings.restWith {
        case .nothing: "Just the notch. Music shows inside the open island."
        case .battery: "The battery's icon and percentage beside the notch all the time."
        case .music: "The cover and bars beside the notch while something plays."
        }
    }

    // MARK: Behavior

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageCard(title: "Opening") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(IslandSettings.Opening.allCases) { mode in
                        PageChoiceTile(title: mode.title, symbol: mode.symbol, selected: settings.opening == mode) { settings.opening = mode }
                    }
                }
                Text(openingCaption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.opening.usesHover { hoverDelayControl }
                PageSwitchRow(symbol: "hand.draw", title: "Gestures",
                              caption: settings.gestures ? "Swipe down on the island to open it, up to close it." : nil,
                              isOn: $settings.gestures)
                PageSwitchRow(symbol: "waveform.path", title: "Haptic feedback", isOn: $settings.haptics)
                PageMenuRow(symbol: "arrow.uturn.backward", title: "When reopening", selection: $settings.reopenTo) {
                    Text("Last page").tag("")
                    Text("All Tabs").tag("grid")
                    ForEach(settings.visibleTabs) { tab in Text(tab.title).tag(tab.rawValue) }
                    // A tab chosen before it was hidden stays listed, greyed, until another is picked.
                    if let saved = IslandTab(rawValue: settings.reopenTo), !settings.visibleTabs.contains(saved) {
                        Text(saved.title).tag(saved.rawValue).disabled(true)
                    }
                }
                PageSwitchRow(symbol: "livephoto", title: "Open the visible activity",
                              caption: "When the closed island shows music, a timer or another activity, it opens on that page instead.",
                              isOn: $settings.opensActivity)
            }
            PageCard(title: "Display") {
                PageSwitchRow(symbol: "arrow.up.left.and.arrow.down.right", title: "Hide in full screen",
                              caption: "Music, timers and events beside the notch hide while a full-screen app is in front. Alerts and recordings still show.",
                              isOn: $settings.hideInFullScreen)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(IslandSettings.Display.allCases) { display in
                        PageChoiceTile(title: display.title, symbol: display.symbol, selected: settings.display == display) { settings.display = display }
                    }
                }
                Text(displayCaption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PageCard(title: "Privacy") {
                PageSwitchRow(symbol: "camera.viewfinder", title: "Show in screenshots and videos",
                              caption: "Off, the island stays out of every screenshot, recording and screen share, including Zephydian's Capture.",
                              isOn: $settings.showInCaptures)
            }
        }
    }

    private var displayCaption: String {
        switch settings.display {
        case .automatic: "The display with a notch (the built-in one first), or the main display."
        case .builtIn: "Your Mac's own display. With the lid closed the island hides."
        case .main: "The display with the menu bar."
        case .pointer: "The island moves to the display the pointer is on once it's closed."
        case .all: "An island on every display, each opening on its own."
        }
    }

    private var openingCaption: String {
        switch settings.opening {
        case .click: "Click the island to open it. Hovering makes it swell a little."
        case .preview: "Hovering shows a strip of your tabs under the notch; click it or a tab to open the island."
        case .hover: "Hovering opens the whole island."
        case .hidden: "The closed island and its activities stay hidden (alerts and recordings still show); hovering the notch opens it."
        }
    }

    /// Vorssaint's size slider: its name, the slider and the value, in a grid row.
    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double) -> some View {
        let bounded = Binding(get: { IslandSettings.Size.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = IslandSettings.Size.clamped($0, to: range, fallback: fallback) })
        return GridRow {
            // The slider carries the name for VoiceOver.
            Text(title).fixedSize().accessibilityHidden(true)
            Slider(value: bounded, in: range, step: 10) { Text(title) }.labelsHidden()
            Text(Int(bounded.wrappedValue), format: .number)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }

    /// Vorssaint's fit slider: a correction around zero, signed so the untouched value reads as none.
    private func fitSlider(_ title: String, card: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        let bounded = Binding(get: { IslandSettings.Size.clamped(value.wrappedValue, to: range, fallback: 0) },
                              set: { value.wrappedValue = IslandSettings.Size.clamped($0, to: range, fallback: 0) })
        let formatted = bounded.wrappedValue.formatted(.number.sign(strategy: .always(includingZero: false)).precision(.fractionLength(0...1)))
        return GridRow {
            Text(title).fixedSize().accessibilityHidden(true)
            // Other cards have sliders with the same names.
            Slider(value: bounded, in: range, step: step) { Text("\(card), \(title)") }.labelsHidden()
                .accessibilityValue(formatted)
            Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }

    /// Vorssaint's activation time: a slider with its value.
    private var hoverDelayControl: some View {
        let formatted = String(format: "%.2f s", settings.hoverDelay)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Activation time")
                Spacer()
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $settings.hoverDelay, in: 0.1...1.0, step: 0.05) { Text("Activation time") }
                .labelsHidden().accessibilityValue(formatted)
            Text("Keep the pointer over the island for this long to open it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Whether this Mac has a battery (the page shows even while the island is off).
    static func hasBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains {
            (IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}
