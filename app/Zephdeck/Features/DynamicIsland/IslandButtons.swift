// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The island's side buttons follow Vorssaint's quick access (UI/Notch/NotchQuickAccessView.swift and
// NotchQuickButton / NotchQuickAccessConfiguration in Services/Notch/NotchSupport.swift, commit
// 1d32501): round buttons that grow out of the open island's sides, up to three a side, joined to
// it by a drip, black or glass after the island's look. Zephdeck changes: a button runs anything a
// Radial Menu slice can (RadialItem, RadialActions) or an island action (a tab, the grid, Keep
// Open, Settings); none by default; the drip is a plain bar; the editor reuses the Radial Menu's
// Add menu and item editor; English text.

import AppKit
import SwiftUI

// MARK: - Model

/// What an island-only button does.
enum IslandButtonAction: Codable, Equatable, Hashable {
    case tab(IslandTab)
    case grid, keepOpen, settings

    var title: String {
        switch self {
        case .tab(let tab): tab.title
        case .grid: "All Tabs"
        case .keepOpen: "Keep Open"
        case .settings: "Island Settings"
        }
    }

    var symbol: String {
        switch self {
        case .tab(let tab): tab.symbol
        case .grid: "square.grid.2x2"
        case .keepOpen: "pin"
        case .settings: "gearshape"
        }
    }

    // Saved as text ("tab:music", "grid"…), so new actions never break old saves.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "grid": self = .grid
        case "keepOpen": self = .keepOpen
        case "settings": self = .settings
        default:
            guard raw.hasPrefix("tab:"), let tab = IslandTab(rawValue: String(raw.dropFirst(4))) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown island action"))
            }
            self = .tab(tab)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .tab(let tab): try container.encode("tab:" + tab.rawValue)
        case .grid: try container.encode("grid")
        case .keepOpen: try container.encode("keepOpen")
        case .settings: try container.encode("settings")
        }
    }
}

/// One button beside the island: a Radial Menu action or an island action, on the left or right.
struct IslandButton: Codable, Equatable, Identifiable {
    enum Side: String, Codable, CaseIterable { case left, right }

    var id = UUID()
    var side: Side
    /// What a Radial Menu slice would do (its name and icon too).
    var item: RadialItem?
    var island: IslandButtonAction?
    /// A name chosen in the layout editor (empty: its own).
    var label = ""

    static let maximumPerSide = 3

    init(id: UUID = UUID(), side: Side, item: RadialItem? = nil, island: IslandButtonAction? = nil, label: String = "") {
        self.id = id
        self.side = side
        self.item = item
        self.island = island
        self.label = label
    }

    private enum CodingKeys: String, CodingKey { case id, side, item, island, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        side = try c.decode(Side.self, forKey: .side)
        item = try c.decodeIfPresent(RadialItem.self, forKey: .item)
        island = try c.decodeIfPresent(IslandButtonAction.self, forKey: .island)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    /// The name and icon to show, or nil when it can't run now (an uninstalled utility…).
    var shown: (title: String, icon: RadialIcon)? {
        if let island { return (label.isEmpty ? island.title : label, .symbol(island.symbol)) }
        guard let item, let slice = RadialActions.slices([item]).first else { return nil }
        return (label.isEmpty ? slice.title : label, slice.icon)
    }

    /// Its name and icon for Settings, with why it can't run.
    var editorInfo: (title: String, detail: String, icon: RadialIcon, problem: String?) {
        if let island { return (label.isEmpty ? island.title : label, "Dynamic Island", .symbol(island.symbol), nil) }
        guard let item else { return ("Button", "", .symbol("questionmark"), "Not understood by this version") }
        let info = RadialActions.editorInfo(item)
        return (label.isEmpty ? info.slice.title : label, info.slice.detail, info.slice.icon, info.problem)
    }
}

/// Saved buttons that don't decode (from a newer version) are dropped one by one.
private struct LossyButton: Decodable {
    let value: IslandButton?
    init(from decoder: Decoder) throws { value = try? IslandButton(from: decoder) }
}

extension IslandSettings {
    static func loadButtons(_ defaults: UserDefaults) -> [IslandButton] {
        guard let data = defaults.data(forKey: "island.buttons"),
              let list = try? JSONDecoder().decode([LossyButton].self, from: data) else { return [] }
        return list.compactMap(\.value)
    }

    static func saveButtons(_ buttons: [IslandButton], _ defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(buttons), forKey: "island.buttons")
    }

    func buttons(on side: IslandButton.Side) -> [IslandButton] { buttons.filter { $0.side == side } }
}

// MARK: - Running

enum IslandButtons {
    /// Runs a button. Island actions act on the island; anything else closes it first and runs.
    static func run(_ button: IslandButton, model: IslandModel) {
        if let island = button.island {
            switch island {
            case .tab(let tab): model.select(tab)
            case .grid: model.showingGrid.toggle()
            case .keepOpen: model.pinned.toggle()
            case .settings:
                model.close()
                CommandBarHooks.openSettings(SettingsPage.island.rawValue)
            }
            return
        }
        guard let item = button.item else { return }
        withAnimation(IslandMotion.close) { model.close() }
        RadialActions.run(item)
    }
}

// MARK: - The bubbles

/// The buttons beside the open island. Each grows out of the island's edge (a spring, one after
/// the other), joined to it by a bar in the Black look; in the Liquid Glass look they're glass.
struct IslandSideButtons: View {
    let model: IslandModel
    private var settings: IslandSettings { IslandSettings.shared }

    static let diameter: CGFloat = 34
    static let spacing: CGFloat = 8
    /// Between the island's side and a bubble.
    static let gap: CGFloat = 10
    /// Room the window keeps on each side of the open island for a column of buttons.
    static var sideRoom: CGFloat { IslandSizing.sideRoom }

    var body: some View {
        let width = IslandSizing.windowSize.width
        let top = max(28, model.closedSize.height) + 8
        // The island's straight sides, inside its flared top corners.
        let leftEdge = Self.sideRoom + IslandButtons.edgeInset
        let rightEdge = width - Self.sideRoom - IslandButtons.edgeInset
        ZStack(alignment: .topLeading) {
            ForEach(Array(entries(.left).enumerated()), id: \.element.button.id) { index, entry in
                IslandSideBubble(model: model, button: entry.button, title: entry.title, icon: entry.icon,
                                 side: .left, order: index, look: settings.look)
                    .offset(x: leftEdge - Self.gap - Self.diameter, y: top + CGFloat(index) * (Self.diameter + Self.spacing))
            }
            ForEach(Array(entries(.right).enumerated()), id: \.element.button.id) { index, entry in
                IslandSideBubble(model: model, button: entry.button, title: entry.title, icon: entry.icon,
                                 side: .right, order: index, look: settings.look)
                    .offset(x: rightEdge - 2, y: top + CGFloat(index) * (Self.diameter + Self.spacing))
            }
        }
        .frame(width: width, height: IslandSizing.openSize.height, alignment: .topLeading)
    }

    private func entries(_ side: IslandButton.Side) -> [(button: IslandButton, title: String, icon: RadialIcon)] {
        Array(settings.buttons(on: side)
            .compactMap { button in button.shown.map { (button: button, title: $0.title, icon: $0.icon) } }
            .prefix(IslandButton.maximumPerSide))
    }
}

extension IslandButtons {
    /// How far the island's straight side sits inside its frame (the open top corner's flare).
    static var edgeInset: CGFloat { IslandSizing.cornerRadiusInsets.opened.top }
}

/// One bubble, with its drip toward the island.
private struct IslandSideBubble: View {
    let model: IslandModel
    let button: IslandButton
    let title: String
    let icon: RadialIcon
    let side: IslandButton.Side
    let order: Int
    let look: IslandSettings.Look
    /// Out while the island is open; growing out and tucking back on the island's own spring.
    private var shown: Bool { model.state == .open }

    private let d = IslandSideButtons.diameter

    var body: some View {
        HStack(spacing: 0) {
            if side == .right { drip }
            bubble
            if side == .left { drip }
        }
        .frame(height: d)
        // Hovering a bubble counts as hovering the island, so it stays open.
        .onHover { hovering in
            model.overSideButtons = hovering
            if !hovering { model.closeIfPointerLeft() }
        }
        .animation(shown ? IslandMotion.sideButton(order) : IslandMotion.close, value: shown)
    }

    /// A short bar joining the bubble to the island's side (Black look only; glass stands alone).
    private var drip: some View {
        Rectangle()
            .fill(look == .black ? Color.black : Color.black.opacity(0.01))
            .frame(width: IslandSideButtons.gap + 2, height: d * 0.42)
            .scaleEffect(x: shown ? 1 : 0, anchor: side == .left ? .trailing : .leading)
            .opacity(shown ? 1 : 0)
    }

    private var bubble: some View {
        Button { IslandButtons.run(button, model: model) } label: {
            iconView
                .frame(width: d, height: d)
                .background { background }
                .contentShape(Circle())
        }
        .buttonStyle(IslandTileButtonStyle())
        .scaleEffect(shown ? 1 : 0.4)
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : (side == .left ? d * 0.6 : -d * 0.6))
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var background: some View {
        if look == .glass {
            ZStack {
                Circle().fill(Color.black.opacity(0.01))   // clicks stop here (B-33)
                Circle().fill(.clear).glassSurface(in: Circle(), interactive: true, fallback: Material.regular)
            }
        } else {
            Circle().fill(.black)
        }
    }

    @ViewBuilder private var iconView: some View {
        let pinned = button.island == .keepOpen && model.pinned
        switch icon {
        case .image(let image):
            Image(nsImage: image).resizable().scaledToFit().padding(7)
        case .symbol(let name):
            Image(systemName: pinned ? "pin.fill" : name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
