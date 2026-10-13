// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Copied from Vorssaint's NotchSectionsView (UI/Notch/NotchSectionsView.swift, commit 1d32501).
// Zephydian changes: IslandTab instead of NotchModule; four columns, at most two rows (Zephydian
// has seven tabs), so the row paging, its dots, the search and the keyboard shortcuts were left
// out; English text; Zephydian's model instead of NotchService.

import SwiftUI

/// The grid of tabs, opened by the header's grid button. Clicking a tile shows that tab.
struct IslandGrid: View {
    let model: IslandModel
    @Environment(\.colorSchemeContrast) private var contrast
    private var settings: IslandSettings { IslandSettings.shared }

    static let columns = 4
    static let tileHeight: CGFloat = 64
    static let spacing: CGFloat = 8

    var body: some View {
        let tabs = settings.visibleTabs
        Group {
            if tabs.isEmpty {
                IslandEmptyView(symbol: "square.grid.2x2", message: "No tabs are switched on. Choose them in Settings.")
            } else {
                VStack(spacing: Self.spacing) {
                    ForEach(0..<Self.rows(tabs.count), id: \.self) { row in
                        HStack(spacing: Self.spacing) {
                            ForEach(0..<Self.columns, id: \.self) { column in
                                let index = row * Self.columns + column
                                if index < tabs.count {
                                    tile(tabs[index])
                                } else {
                                    Color.clear.frame(maxWidth: .infinity).frame(height: Self.tileHeight)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    static func rows(_ count: Int) -> Int { max(1, (count + columns - 1) / columns) }

    private func tile(_ tab: IslandTab) -> some View {
        let current = model.tab == tab
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { model.select(tab) } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tab.tint)
                    .frame(width: 25, height: 25)
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .background(.white.opacity(current ? 0.12 : 0.045), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(current ? 0.3 : contrast == .increased ? 0.4 : 0.04), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(7)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(IslandTileButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(current ? .isSelected : [])
        .help(tab.summary)
    }
}

/// Tiles brighten under the pointer and dip when pressed.
struct IslandTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandTileButton(configuration: configuration)
    }
}

private struct IslandTileButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .brightness(hovering ? 0.06 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// A symbol and a line, for a tab with nothing to show.
struct IslandEmptyView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
