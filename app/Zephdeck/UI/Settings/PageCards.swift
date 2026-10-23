// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Copied from Vorssaint (UI/Settings/SettingsCard.swift and UI/Settings/NotchEditorItem.swift, commit
// 1d32501): SettingsCard, SettingsRow, SettingsChoiceRow, SettingsMenuRow, TrailingSwitchToggleStyle,
// NotchEditorItem, and the page's choice tile (NotchSettings.choice). Zephdeck changes: renamed
// (Page…) beside Zephdeck's own SettingsRow; the accent is Zephdeck's; no menu-bar glyph tile.

import SwiftUI

/// A rounded card holding a group of rows, with an optional title.
struct PageCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Where a row's text column starts, so follow-up controls can line up with it.
let pageRowTextInset: CGFloat = 26 + 12

/// Icon, title, one line of explanation and the control on the right.
struct PageRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let caption: String?
    let accessory: Accessory
    @Environment(SettingsStore.self) private var settings

    init(symbol: String, title: String, caption: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settings.accentColor)
                .frame(width: 26, height: 26)
                .background(settings.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

/// An option with its icon, one line and a switch.
struct PageSwitchRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        PageRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// A row that picks one of a few options: segments beside the title while the row fits on one
/// line, under the title otherwise, and a menu there when the segments don't fit either.
struct PageChoiceRow<Value: Hashable, Options: View>: View {
    let symbol: String
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            PageRow(symbol: symbol, title: title) {
                picker.pickerStyle(.segmented).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                PageRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
                .padding(.leading, pageRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options }.labelsHidden()
    }
}

/// A row whose choice is a menu: beside the title while the row fits on one line, under it otherwise.
struct PageMenuRow<Value: Hashable, Options: View>: View {
    let symbol: String
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            PageRow(symbol: symbol, title: title) { menu }
            VStack(alignment: .leading, spacing: 8) {
                PageRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    menu.padding(.leading, pageRowTextInset)
                    menu
                }
            }
        }
    }

    private var menu: some View {
        Picker(title, selection: $selection) { options }.pickerStyle(.menu).labelsHidden().fixedSize()
    }
}

/// A switch pushed to the trailing edge with its label at the leading one.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A big tile to pick one option from a few (an icon over its name).
struct PageChoiceTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 68).padding(8)
            .foregroundStyle(selected ? settings.accentColor : .primary)
            .background(selected ? settings.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? settings.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card that switches something on or off (Vorssaint's NotchEditorItem): icon, name, and a tick
/// in the corner; a reason underneath when it can't be used.
struct PageToggleCard: View {
    let symbol: String
    let title: String
    @Binding var included: Bool
    var available = true
    var unavailableReason: String? = nil
    var unavailableAction: (() -> Void)? = nil
    /// Keeps a card as tall as a neighbour that explains why it is off.
    var reservesReason = false
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if available { included.toggle() } else { unavailableAction?() }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(included && available ? settings.accentColor : .secondary)
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                        .multilineTextAlignment(.center).frame(height: 28)
                    if unavailableReason != nil || reservesReason {
                        Text(unavailableReason ?? " ").font(.caption2)
                            .foregroundStyle(unavailableAction == nil ? Color.secondary : settings.accentColor)
                            .multilineTextAlignment(.center).lineLimit(3, reservesSpace: true)
                            .accessibilityHidden(unavailableReason == nil)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 76).padding(10)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(!available && unavailableAction == nil)
            Image(systemName: !available ? (unavailableAction == nil ? "minus.circle" : "arrow.up.right.circle")
                  : included ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 15)).foregroundStyle(included && available ? settings.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .help(unavailableReason ?? title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(included && available ? .isSelected : [])
    }
}
