// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Copied from Vorssaint's island layout editor (UI/Settings/NotchLayoutEditor.swift, commit 1d32501):
// the island drawn at half its real size on a rounded canvas, its buttons beside it, a dashed + in
// the next free slot, dragging a button to the other side (drop zones light up), a click opening
// its editor (name, side, order, what it does, remove), and a click on the island going to the
// Content tab. Zephydian changes: left and right only (no bottom row); Zephydian's buttons
// (IslandButton) and Add menu (the Radial Menu's, plus island actions); the Radial Menu's item
// editor for changing what a button does; the island preview is Zephydian's (IslandPreviewBody);
// sizes in Zephydian's wide shape (IslandSettings.Size); English text.

import SwiftUI

struct IslandLayoutEditor: View {
    var editContents: () -> Void
    @Bindable private var settings = IslandSettings.shared
    @State private var editingID: UUID?
    @State private var draggingID: UUID?
    @State private var translation = CGSize.zero
    @State private var dragLocation: CGPoint?
    @State private var changing: IslandLayoutEdit?
    @State private var shortcutNames: [String] = []
    @State private var resizeStart: CGSize?
    @Environment(SettingsStore.self) private var appSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let previewScale: CGFloat = 0.5
    /// Room for the tallest custom island and the grip below it.
    private static var canvasHeight: CGFloat { IslandSettings.Size.heightRange.upperBound * previewScale + 20 + 34 }
    private static let bubble: CGFloat = 30

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let scale = scale(in: proxy.size)
                let frame = islandFrame(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22).fill(.quaternary.opacity(0.35))
                    if draggingID != nil {
                        ForEach(IslandButton.Side.allCases, id: \.self) { side in
                            let target = dropFrame(side, island: frame)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(appSettings.accentColor.opacity(target.contains(dragLocation ?? .zero) ? 0.15 : 0.04))
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(appSettings.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                                .frame(width: target.width, height: target.height)
                                .position(x: target.midX, y: target.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    // Laid out at the island's real size and scaled down, so it keeps its proportions.
                    Button(action: editContents) {
                        IslandPreviewBody(tab: settings.visibleTabs.first ?? .home)
                            .scaleEffect(scale)
                            .frame(width: frame.width, height: frame.height)
                    }
                    .buttonStyle(.plain)
                    .help("Content")
                    .accessibilityLabel("Content")
                    .position(x: frame.midX, y: frame.midY)
                    grip(scale: scale, island: frame)
                    ForEach(IslandButton.Side.allCases, id: \.self) { side in
                        let items = settings.buttons(on: side)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, button in
                            bubble(button)
                                .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("island.editor"))
                                    .onChanged { value in
                                        editingID = nil
                                        draggingID = button.id
                                        translation = value.translation
                                        dragLocation = value.location
                                    }
                                    .onEnded { value in
                                        move(button, at: value.location, island: frame)
                                        draggingID = nil; translation = .zero; dragLocation = nil
                                    })
                                .offset(draggingID == button.id ? translation : .zero)
                                .position(point(index, side: side, island: frame))
                                .zIndex(draggingID == button.id ? 3 : 1)
                        }
                        if items.count < IslandButton.maximumPerSide {
                            addButton(side)
                                .position(point(items.count, side: side, island: frame))
                        }
                    }
                }
                .coordinateSpace(name: "island.editor")
            }
            .frame(height: Self.canvasHeight)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: settings.buttons)
            Text("Click + to add a button. Drag buttons around the island. Click a button to edit it.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadShortcutNames)
        .sheet(item: $changing) { target in
            RadialItemEditor(item: target.item, isNew: target.isNew, shortcutNames: shortcutNames) { saved in
                if let index = settings.buttons.firstIndex(where: { $0.id == target.buttonID }) {
                    settings.buttons[index].item = saved
                    settings.buttons[index].island = nil
                } else if settings.buttons(on: target.side).count < IslandButton.maximumPerSide {
                    settings.buttons.append(IslandButton(id: target.buttonID, side: target.side, item: saved))
                }
            }
        }
    }

    /// Vorssaint's grip on the island's corner: dragging it picks Custom and sets the size.
    private func grip(scale: CGFloat, island: CGRect) -> some View {
        typealias Size = IslandSettings.Size
        return Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(appSettings.accentColor)
            .frame(width: 24, height: 24)
            .background(.background, in: Circle())
            .overlay { Circle().strokeBorder(appSettings.accentColor.opacity(0.65), lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("island.editor")).onChanged { value in
                if resizeStart == nil { resizeStart = IslandSizing.openSize }
                guard let start = resizeStart else { return }
                // The island grows from its centre, so a corner moves half as far as its width.
                let width = Size.clamped(Double(start.width + 2 * value.translation.width / scale), to: Size.widthRange, fallback: Size.defaultWidth)
                let height = Size.clamped(Double(start.height + value.translation.height / scale), to: Size.heightRange, fallback: Size.defaultHeight)
                settings.customWidth = (width / 10).rounded() * 10
                settings.customHeight = (height / 10).rounded() * 10
                if settings.size != .custom { settings.size = .custom }
            }.onEnded { _ in resizeStart = nil })
            // Below the third right slot when the island is short.
            .position(x: island.maxX - 3, y: max(island.maxY - 3, island.minY + 30 + 2 * 40 + 29))
            .help("Drag to resize")
            .accessibilityLabel("Size")
            .zIndex(2)
    }

    // MARK: Geometry (Vorssaint's)

    /// A narrow window shrinks the whole island rather than only its width.
    private func scale(in canvas: CGSize) -> CGFloat {
        min(Self.previewScale, max(0.2, (canvas.width - 112) / IslandSizing.openSize.width))
    }

    private func islandFrame(in canvas: CGSize) -> CGRect {
        let scale = scale(in: canvas)
        let w = IslandSizing.openSize.width * scale
        let h = IslandSizing.openSize.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: 20, width: w, height: h)
    }

    /// Buttons float clear of the silhouette, as the real ones do.
    private func point(_ index: Int, side: IslandButton.Side, island: CGRect) -> CGPoint {
        let x = side == .left ? island.minX - 18 : island.maxX + 18
        return CGPoint(x: x, y: island.minY + 30 + CGFloat(index) * 40)
    }

    private func dropFrame(_ side: IslandButton.Side, island: CGRect) -> CGRect {
        side == .left ? CGRect(x: island.minX - 48, y: island.minY, width: 62, height: island.height)
                      : CGRect(x: island.maxX - 14, y: island.minY, width: 62, height: island.height)
    }

    /// Dropped on a side: it goes there, before the first button below where it was let go.
    private func move(_ button: IslandButton, at point: CGPoint, island: CGRect) {
        guard let side = IslandButton.Side.allCases.first(where: { dropFrame($0, island: island).contains(point) }) else { return }
        let siblings = settings.buttons(on: side).filter { $0.id != button.id }
        guard side == button.side || siblings.count < IslandButton.maximumPerSide else { return }
        let target = siblings.enumerated().first { index, _ in
            self.point(index, side: side, island: island).y > point.y
        }?.element.id
        var buttons = settings.buttons
        guard let from = buttons.firstIndex(where: { $0.id == button.id }) else { return }
        var moved = buttons.remove(at: from)
        moved.side = side
        if let target, let to = buttons.firstIndex(where: { $0.id == target }) {
            buttons.insert(moved, at: to)
        } else {
            buttons.append(moved)
        }
        settings.buttons = buttons
    }

    private func reorder(_ id: UUID, by offset: Int) {
        guard let item = settings.buttons.first(where: { $0.id == id }) else { return }
        let items = settings.buttons(on: item.side)
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset),
              let from = settings.buttons.firstIndex(where: { $0.id == id }),
              let to = settings.buttons.firstIndex(where: { $0.id == items[index + offset].id }) else { return }
        settings.buttons.swapAt(from, to)
    }

    private func setSide(_ id: UUID, _ side: IslandButton.Side) {
        guard let index = settings.buttons.firstIndex(where: { $0.id == id }), settings.buttons[index].side != side,
              settings.buttons(on: side).count < IslandButton.maximumPerSide else { return }
        var moved = settings.buttons.remove(at: index)
        moved.side = side
        settings.buttons.append(moved)
    }

    // MARK: Bubbles

    private func bubble(_ button: IslandButton) -> some View {
        let info = button.editorInfo
        return Button { editingID = button.id } label: {
            iconView(info.icon)
                .frame(width: Self.bubble, height: Self.bubble)
                .background(.black, in: Circle())
                .overlay { Circle().strokeBorder(editingID == button.id ? appSettings.accentColor : .white.opacity(0.2), lineWidth: 1.5) }
                .opacity(info.problem == nil ? 1 : 0.45)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .help(info.problem.map { "\(info.title): \($0)" } ?? info.title)
        .accessibilityLabel("Edit button, \(info.title)")
        .popover(isPresented: Binding(get: { editingID == button.id }, set: { if !$0 { editingID = nil } }),
                 arrowEdge: button.side == .left ? .trailing : .leading) {
            editor(button)
        }
    }

    @ViewBuilder private func iconView(_ icon: RadialIcon) -> some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image).resizable().scaledToFit().padding(6)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
    }

    /// The button's editor: its name, its side and order, what it does, and Remove.
    private func editor(_ button: IslandButton) -> some View {
        let info = button.editorInfo
        let index = settings.buttons.firstIndex { $0.id == button.id }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Edit button").font(.headline)
            TextField("Name", text: Binding(
                get: { index.map { settings.buttons[$0].label } ?? "" },
                set: { value in if let index { settings.buttons[index].label = value } }),
                      prompt: Text(button.item.map { RadialActions.editorInfo($0).slice.title } ?? button.island?.title ?? ""))
            Picker("Position", selection: Binding(
                get: { settings.buttons.first { $0.id == button.id }?.side ?? button.side },
                set: { setSide(button.id, $0) })) {
                Text("Left").tag(IslandButton.Side.left)
                    .disabled(button.side != .left && settings.buttons(on: .left).count >= IslandButton.maximumPerSide)
                Text("Right").tag(IslandButton.Side.right)
                    .disabled(button.side != .right && settings.buttons(on: .right).count >= IslandButton.maximumPerSide)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Move Up") { reorder(button.id, by: -1) }
                Button("Move Down") { reorder(button.id, by: 1) }
            }
            .controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                Text("Does").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(info.problem ?? info.detail).font(.callout).lineLimit(1)
                        .foregroundStyle(info.problem == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
                    Spacer()
                    if let item = button.item {
                        Button("Edit…") {
                            editingID = nil
                            changing = IslandLayoutEdit(buttonID: button.id, side: button.side, item: item, isNew: false)
                        }
                    }
                    actionMenu(title: "Change", side: button.side) { replacement in
                        guard let index = settings.buttons.firstIndex(where: { $0.id == button.id }) else { return }
                        settings.buttons[index].item = replacement.item
                        settings.buttons[index].island = replacement.island
                    }
                }
                .controlSize(.small)
            }
            Button("Remove button", role: .destructive) {
                editingID = nil
                settings.buttons.removeAll { $0.id == button.id }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: Adding

    private func addButton(_ side: IslandButton.Side) -> some View {
        actionMenu(title: nil, side: side) { new in
            guard settings.buttons(on: side).count < IslandButton.maximumPerSide else { return }
            settings.buttons.append(IslandButton(side: side, item: new.item, island: new.island))
        }
        .help("Add button")
        .accessibilityLabel("Add button, \(side == .left ? "left" : "right")")
    }

    /// The Add menu: island actions, then everything a Radial Menu slice can do. `title` nil draws
    /// Vorssaint's dashed + circle.
    private func actionMenu(title: String?, side: IslandButton.Side, choose: @escaping (IslandButton) -> Void) -> some View {
        Menu {
            Menu("Dynamic Island") {
                ForEach(settings.visibleTabs) { tab in
                    Button("\(tab.title) Tab") { choose(IslandButton(side: side, island: .tab(tab))) }
                }
                Divider()
                Button("All Tabs") { choose(IslandButton(side: side, island: .grid)) }
                Button("Keep Open") { choose(IslandButton(side: side, island: .keepOpen)) }
                Button("Island Settings") { choose(IslandButton(side: side, island: .settings)) }
            }
            Divider()
            RadialAddMenuItems(
                shortcutNames: shortcutNames,
                add: { choose(IslandButton(side: side, item: $0)) },
                startNew: { item in
                    editingID = nil
                    changing = IslandLayoutEdit(buttonID: UUID(), side: side, item: item, isNew: true)
                },
                pick: { apps in
                    guard let path = RadialItemEditor.choosePath(apps: apps) else { return }
                    choose(IslandButton(side: side, item: RadialItem(kind: apps ? .app : .file, payload: path)))
                })
        } label: {
            if let title {
                Text(title)
            } else {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appSettings.accentColor)
                    .frame(width: Self.bubble, height: Self.bubble)
                    .background(.background, in: Circle())
                    .overlay { Circle().strokeBorder(appSettings.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
        }
        .menuStyle(.button)
        .menuIndicator(title == nil ? .hidden : .visible)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func loadShortcutNames() {
        guard shortcutNames.isEmpty else { return }
        Task { shortcutNames = await RadialItemEditor.shortcutNames() }
    }
}

/// A button whose action is being set in the Radial Menu's item editor (or a new one waiting for it).
private struct IslandLayoutEdit: Identifiable {
    let id = UUID()
    let buttonID: UUID
    let side: IslandButton.Side
    let item: RadialItem
    let isNew: Bool
}
