// The header follows Vorssaint's island header (UI/Notch/NotchView.swift, commit 1d32501; GPL-3.0-or-later,
// Copyright (C) 2026 Vorssaint): the tab's name with a grid button on the left, the camera in the
// middle, and actions that wait for the pointer on the right. The black block over the notch is
// boring.notch's (BoringHeader.swift, GPL-3.0, commit e2654ee; created by Harsh Vardhan Goswami).
// Zephydian changes: Zephydian's glass icon buttons, a native menu (Keep Open, the Zephydian panel,
// Settings) instead of Vorssaint's overflow menu, English text.

import AppKit
import SwiftUI

/// The open island's top row.
struct IslandHeader: View {
    let model: IslandModel
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.showingGrid {
                    Button("Back", systemImage: "chevron.left") { setGrid(false) }
                        .labelStyle(.iconOnly)
                        .glassIconButtonStyle()
                        .help("Back to \(model.tab.title)")
                    Text("Tabs")
                } else {
                    Button("All Tabs", systemImage: "square.grid.2x2") { setGrid(true) }
                        .labelStyle(.iconOnly)
                        .glassIconButtonStyle()
                        .help("All tabs")
                    Text(model.tab.title)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.hasNotch {
                Rectangle()
                    .fill(.black)
                    .frame(width: model.closedSize.width)
                    .mask { IslandShape() }
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if IslandSettings.shared.batteryInHeader && IslandBattery.shared.hasBattery {
                    IslandBatteryButton(model: model)
                }
                // Settings, right beside the … menu (the owner's request), shown with it.
                Button("Dynamic Island Settings", systemImage: "gearshape") {
                    model.close()
                    CommandBarHooks.openSettings(SettingsPage.island.rawValue)
                }
                .labelStyle(.iconOnly)
                .glassIconButtonStyle()
                .help("Dynamic Island Settings")
                .opacity(hovered || model.pinned || model.menuOpen ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
                Button(model.pinned ? "Kept Open" : "More", systemImage: model.pinned ? "pin.fill" : "ellipsis") { showMenu() }
                    .labelStyle(.iconOnly)
                    .glassIconButtonStyle()
                    .help("More")
                    // Out of sight until the pointer reaches the row, so the header reads as a title.
                    .opacity(hovered || model.pinned || model.menuOpen ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onDisappear { hovered = false }
    }

    private func setGrid(_ on: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { model.showingGrid = on }
    }

    /// Keep Open, the Zephydian panel and Settings, in a native menu at the pointer.
    private func showMenu() {
        let menu = NSMenu()
        let actions = IslandMenuActions()
        let keep = actions.item("Keep Open") { model.pinned.toggle() }
        keep.state = model.pinned ? .on : .off
        menu.addItem(keep)
        menu.addItem(actions.item("Open Zephydian Panel") {
            model.close()
            RadialActions.showPanel()
        })
        menu.addItem(.separator())
        menu.addItem(actions.item("Dynamic Island Settings…") {
            model.close()
            CommandBarHooks.openSettings(SettingsPage.island.rawValue)
        })
        model.menuOpen = true
        // Returns once the menu closes.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(actions) {}
        model.menuOpen = false
        // The pointer may have left the island for the menu.
        if model.state == .open, !model.pinned, !model.isPointerInside() {
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { model.close() }
        }
    }
}

/// Runs the island menu's closures (NSMenu items need an Objective-C target).
final class IslandMenuActions: NSObject {
    private var handlers: [() -> Void] = []

    func item(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self
        item.tag = handlers.count
        handlers.append(handler)
        return item
    }

    @objc private func run(_ sender: NSMenuItem) {
        handlers[sender.tag]()
    }
}
