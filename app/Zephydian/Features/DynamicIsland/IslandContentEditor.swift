// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Adapted from Vorssaint's island content editor (UI/Settings/NotchContentEditor.swift and
// NotchSettings.swift, commit 1d32501): NotchSectionListRow, NotchSectionHeader, NotchSectionTile
// and NotchIslandPreview. Zephydian changes: IslandTab instead of NotchModule; rows drag with
// Zephydian's `.reorderable`; the preview draws the island's own pages over a strip of menu bar at
// a scale that fits the column; the wide/narrow layouts use ViewThatFits; English text.

import SwiftUI

/// Settings → Dynamic Island → Content: every tab in the island's order, with a checkbox to show
/// it, and the chosen tab's description, preview and options.
struct IslandContentEditor: View {
    @Bindable private var settings = IslandSettings.shared
    @State private var selected: IslandTab = IslandSettings.shared.visibleTabs.first ?? .home
    @State private var dragging: IslandTab?

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    list.frame(width: 190)
                    VStack(alignment: .leading, spacing: 14) {
                        detail
                        IslandPreview(tab: selected, hidden: !settings.shownTabs.contains(selected))
                            .frame(minWidth: 320)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        list.frame(width: 170)
                        detail
                    }
                    IslandPreview(tab: selected, hidden: !settings.shownTabs.contains(selected))
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Drag tabs to change their order in the island's grid. The island opens to what's live (a recording, a timer, music), otherwise to the tab you used last.")
        }
    }

    /// Every tab in the island's order, each with the box that shows it.
    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tabs").font(.headline).padding(.horizontal, 6).padding(.bottom, 4)
            ForEach(settings.tabOrder) { tab in
                IslandTabRow(tab: tab, included: binding(tab), selected: selected == tab, dragging: dragging == tab) {
                    selected = tab
                }
                .reorderable(tab, dragging: $dragging) { dragged, target in settings.tabOrder.move(dragged, onto: target) }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandTabHeader(tab: selected, shown: settings.shownTabs.contains(selected))
            // Each stage adds its tab's options here.
            switch selected {
            case .home:
                IslandHomeItemsEditor()
                Toggle("Follow every player", isOn: $settings.otherPlayers)
                    .toggleStyle(.switch)
            case .shelf:
                Text("Starting to drag a file, link or text opens the island on its Shelf. While the island shows a Shelf (this tab, or Home's Shelf), Zephydian's floating Shelf steps aside: its shortcut and menu bar item open the island's Shelf too.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .calendar:
                IslandCalendarOptions()
            case .music:
                Toggle("Follow every player", isOn: $settings.otherPlayers)
                    .toggleStyle(.switch)
                Text("Music apps only when off. On, browsers, videos and podcasts show too.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                Text("No options yet.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ tab: IslandTab) -> Binding<Bool> {
        Binding(
            get: { settings.shownTabs.contains(tab) },
            set: { on in if on { settings.shownTabs.insert(tab) } else { settings.shownTabs.remove(tab) } }
        )
    }
}

/// One row of the editor's list: a box that shows the tab in the island, its icon and its name.
/// A box rather than a switch leaves the name its whole line in a narrow window.
private struct IslandTabRow: View {
    let tab: IslandTab
    @Binding var included: Bool
    let selected: Bool
    let dragging: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(tab.title, isOn: $included)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Button(action: select) {
                HStack(spacing: 8) {
                    IslandTabTile(tab: tab, shown: included, side: 22)
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.summary)
            .accessibilityLabel(tab.title)
            .accessibilityValue(tab.summary)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(selected ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(dragging ? 0.45 : 1)
    }
}

/// What the chosen tab is: its icon, name and one line on what it shows.
private struct IslandTabHeader: View {
    let tab: IslandTab
    let shown: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IslandTabTile(tab: tab, shown: shown, side: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title).font(.title3.weight(.semibold))
                Text(tab.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tab's icon on its own color; grey while the tab is hidden.
struct IslandTabTile: View {
    let tab: IslandTab
    let shown: Bool
    let side: CGFloat

    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: side * 0.46, weight: .semibold))
            .foregroundStyle(shown ? Color.white : Color.secondary)
            .frame(width: side, height: side)
            .background(shown ? tab.settingsTint : Color.secondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The open island showing one tab, hanging from a strip of menu bar: the island's own page at its
/// real size, scaled to the column, so every option changes the preview the way it changes the island.
struct IslandPreview: View {
    let tab: IslandTab
    /// The tab is switched off.
    var hidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var settings: IslandSettings { IslandSettings.shared }

    private static let menuBarHeight: CGFloat = 24
    private static let captionHeight: CGFloat = 26
    private static let margin: CGFloat = 12
    private static var islandSize: CGSize { IslandSizing.openSize }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, (proxy.size.width - Self.margin * 2) / Self.islandSize.width)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(height: Self.menuBarHeight * scale)
                island
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: Self.islandSize.width * scale, height: Self.islandSize.height * scale, alignment: .top)
                    .opacity(hidden ? 0.4 : 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .aspectRatio(Self.islandSize.width / (Self.islandSize.height + Self.captionHeight * 1.6), contentMode: .fit)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Label(hidden ? "Hidden in the island" : "Preview", systemImage: hidden ? "eye.slash" : "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tab)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue(tab.title + (hidden ? ", hidden in the island" : ""))
    }

    private var island: some View { IslandPreviewBody(tab: tab) }
}

/// The open island showing one tab, at its real size, drawn still (Settings' previews).
struct IslandPreviewBody: View {
    let tab: IslandTab
    private var settings: IslandSettings { IslandSettings.shared }
    private static var islandSize: CGSize { IslandSizing.openSize }

    var body: some View {
        let insets = IslandSizing.cornerRadiusInsets.opened
        let shape = IslandShape(topCornerRadius: insets.top, bottomCornerRadius: insets.bottom)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Tokens.iconButtonSize, height: Tokens.iconButtonSize)
                    .background(.white.opacity(0.1), in: Circle())
                Text(tab.title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .frame(height: 32)
            IslandPage(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .padding(.horizontal, insets.top + 12)
        .padding(.bottom, 12)
        .frame(width: Self.islandSize.width, height: Self.islandSize.height, alignment: .top)
        .background {
            if settings.look == .glass {
                shape.fill(Material.regular)
            } else {
                shape.fill(.black)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.islandPreview, true)
        .allowsHitTesting(false)
    }
}

/// Home's items: up to three, in order, dragged to reorder.
private struct IslandHomeItemsEditor: View {
    @Bindable private var settings = IslandSettings.shared
    @State private var dragging: IslandHomeItem?

    /// The chosen items first (in Home's order), then the rest.
    private var ordered: [IslandHomeItem] {
        settings.homeItems + IslandHomeItem.allCases.filter { !settings.homeItems.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home shows").font(.subheadline.weight(.medium))
            ForEach(ordered) { item in
                let on = settings.homeItems.contains(item)
                let full = settings.homeItems.count >= IslandHomeItem.maximum
                HStack(spacing: 8) {
                    Toggle(item.title, isOn: Binding(
                        get: { on },
                        set: { value in
                            if value, !full { settings.homeItems.append(item) }
                            if !value { settings.homeItems.removeAll { $0 == item } }
                        }))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .disabled(!on && full)
                    Image(systemName: item.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .frame(width: 20, height: 20)
                        .background(on ? item.tint : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(item.title)
                        .foregroundStyle(!on && full ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .opacity(dragging == item ? 0.45 : 1)
                .modifier(HomeReorder(item: item, enabled: on, dragging: $dragging))
            }
            Text("Up to three. Drag the ticked ones to change their order.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Only ticked items drag, and only among themselves.
private struct HomeReorder: ViewModifier {
    let item: IslandHomeItem
    let enabled: Bool
    @Binding var dragging: IslandHomeItem?

    func body(content: Content) -> some View {
        if enabled {
            content.reorderable(item, dragging: $dragging) { dragged, target in
                IslandSettings.shared.homeItems.move(dragged, onto: target)
            }
        } else {
            content
        }
    }
}

/// The Calendar tab's options: reminders, all-day events, the next event, and which calendars show.
private struct IslandCalendarOptions: View {
    @Bindable private var settings = IslandSettings.shared
    private var calendar: IslandCalendar { IslandCalendar.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show reminders due that day", isOn: $settings.calendarReminders)
            Toggle("Hide all-day events", isOn: $settings.calendarHideAllDay)
            Toggle("Next event in the closed island", isOn: $settings.calendarNextEvent)
            Text("10 minutes before an event, the closed island shows its title and the time left.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if calendar.hasAccess {
                Text("Calendars").font(.subheadline.weight(.medium)).padding(.top, 4)
                ForEach(groups, id: \.account) { group in
                    Text(group.account).font(.caption).foregroundStyle(.secondary)
                    ForEach(group.calendars) { item in
                        Toggle(isOn: Binding(
                            get: { !settings.calendarHidden.contains(item.id) },
                            set: { on in
                                if on { settings.calendarHidden.removeAll { $0 == item.id } }
                                else { settings.calendarHidden.append(item.id) }
                            })) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(item.color)).frame(width: 8, height: 8)
                                Text(item.title)
                                if item.isReminder { Text("Reminders").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            } else {
                Text("Allow Calendar access from the island's Calendar tab to choose calendars.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    private var groups: [(account: String, calendars: [IslandCalendarModel])] {
        Dictionary(grouping: calendar.calendars, by: \.account)
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.0 < $1.0 }
    }
}
