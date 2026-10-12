// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The hover preview follows Vorssaint's peek (UI/Notch/NotchView.swift and NotchGeometry.peek in
// Services/Notch/NotchSupport.swift, commit 1d32501): a short strip under the notch with the
// navigation and an Open chevron; a click opens the whole island. Zephydian changes: the navigation
// is a row of the shown tabs' icons, each opening the island on its tab; English text.

import SwiftUI

/// The preview strip: the shown tabs and Open, below the notch.
struct IslandPeekStrip: View {
    let model: IslandModel
    private var settings: IslandSettings { IslandSettings.shared }

    /// Vorssaint's size: at least 340 pt, and 110 more than the notch; a row of 44 under it.
    static func width(closed: CGFloat) -> CGFloat { max(340, closed + 110) }
    static let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.effectiveClosedHeight)
            HStack(spacing: 4) {
                ForEach(settings.visibleTabs.prefix(8)) { tab in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { model.open(on: tab) }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(IslandTileButtonStyle())
                    .help(tab.title)
                    .accessibilityLabel("Open \(tab.title)")
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { model.open() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(IslandTileButtonStyle())
                .help("Open")
                .accessibilityLabel("Open")
            }
            .frame(height: Self.rowHeight)
        }
        .frame(width: Self.width(closed: model.closedSize.width) - 2 * IslandSizing.cornerRadiusInsets.closed.bottom)
    }
}
