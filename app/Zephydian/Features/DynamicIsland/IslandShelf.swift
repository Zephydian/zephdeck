// The island's Shelf. The layout follows boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee): ShelfView (components/Shelf/Views/ShelfView.swift, by Alexander) with FileShareView's
// AirDrop square beside a dashed drop zone whose tiles scroll sideways, and the drag-to-open of
// ContentView's dragDetector. Zephydian changes: the items are Zephydian's ShelfStore (shared with the
// floating Shelf and the panel's Shelf); each tile is a small AppKit view, so it takes the first click
// in the island (which never becomes key), opens on double-click, drags out (and leaves the Shelf once
// dropped elsewhere, the owner's choice) and has its right-click menu; Quick Look goes through
// `qlmanage`; Share lists macOS's sharing services; English text.

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// The island the page is in (the Shelf keeps the island open while it shares or shows a menu).
    @Entry var islandModel: IslandModel? = nil
}

// MARK: - Receiving

enum IslandShelfDrop {
    static let types: [UTType] = [.fileURL, .url, .plainText]

    /// Adds dropped files, links and text to the Shelf.
    static func receive(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in ShelfStore.shared.add(.file(url)) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in ShelfStore.shared.add(.link(url)) }
                }
            } else {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text, !text.isEmpty else { return }
                    Task { @MainActor in ShelfStore.shared.add(.text(text)) }
                }
            }
        }
        return !providers.isEmpty
    }
}

// MARK: - The Shelf tab

/// boring.notch's shelf: the AirDrop square, then the dashed drop zone with the items.
struct IslandShelfPage: View {
    @State private var targeted = false
    @State private var selected: UUID?
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        HStack(spacing: 12) {
            IslandAirDropZone(selected: selected)
                .aspectRatio(1, contentMode: .fit)
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(targeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                              style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))
                .overlay { content.padding() }
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }
                .onDrop(of: IslandShelfDrop.types, isTargeted: $targeted) { IslandShelfDrop.receive($0) }
        }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)
                Text("Drop files here")
                    .foregroundStyle(.gray)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.items) { item in
                        IslandShelfTile(item: item, selected: selected == item.id, size: 56) { selected = item.id }
                    }
                }
            }
            .padding(-8)
            .scrollIndicators(.never)
        }
    }
}

/// Home's Shelf: the newest items in a scrolling row, and a drop zone.
struct IslandShelfHome: View {
    @State private var targeted = false
    @State private var selected: UUID?
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        // Home draws the widget's outline; a drag over it lights it in the accent.
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(targeted ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if store.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").imageScale(.large).foregroundStyle(.gray)
                        Text("Drop files here").font(.system(size: 12, weight: .medium)).foregroundStyle(.gray)
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(store.items.reversed()) { item in
                                IslandShelfTile(item: item, selected: selected == item.id, size: 44) { selected = item.id }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .scrollIndicators(.never)
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: IslandShelfDrop.types, isTargeted: $targeted) { IslandShelfDrop.receive($0) }
    }
}

// MARK: - AirDrop

/// boring.notch's FileShareView: drop files to send them with AirDrop; a click sends the selected
/// item (or every file on the Shelf).
struct IslandAirDropZone: View {
    let selected: UUID?
    @State private var targeted = false
    @Environment(\.islandModel) private var model

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(targeted ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
            .overlay {
                VStack(spacing: 6) {
                    // macOS's own AirDrop icon.
                    if let icon = NSSharingService(named: .sendViaAirDrop)?.image {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 24)).foregroundStyle(.white.opacity(0.85))
                    }
                    Text("AirDrop")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { sendShelf() }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                IslandAirDrop.send(providers, model: model)
                return true
            }
            .help("Drop files here to send them with AirDrop")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AirDrop")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { sendShelf() }
    }

    private func sendShelf() {
        let items = ShelfStore.shared.items
        let chosen = items.filter { selected == nil || $0.id == selected }
        let urls: [URL] = chosen.compactMap {
            switch $0.content {
            case .file(let url), .link(let url): url
            case .text: nil
            }
        }
        IslandAirDrop.send(urls, model: model)
    }
}

/// Sends with AirDrop, keeping the island open while macOS's AirDrop window is up.
final class IslandAirDrop: NSObject, NSSharingServiceDelegate {
    private static var current: IslandAirDrop?
    private weak var model: IslandModel?

    /// Collects dropped file URLs from the item providers' background callbacks.
    private nonisolated final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    static func send(_ providers: [NSItemProvider], model: IslandModel?) {
        let collected = Collected()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.add(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { send(collected.all, model: model) }
        }
    }

    static func send(_ urls: [URL], model: IslandModel?) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        let sharer = IslandAirDrop()
        sharer.model = model
        current = sharer
        service.delegate = sharer
        model?.menuOpen = true
        service.perform(withItems: urls)
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        MainActor.assumeIsolated { finish() }
    }

    private func finish() {
        model?.menuOpen = false
        if let model, model.state == .open, !model.pinned, !model.isPointerInside() {
            withAnimation(IslandMotion.close) { model.close() }
        }
        Self.current = nil
    }
}

// MARK: - Tiles

/// One item: its thumbnail or icon and its name. Click selects, double-click opens, drag takes it
/// out (and off the Shelf once it lands), right-click shows the menu.
struct IslandShelfTile: View {
    let item: ShelfItem
    let selected: Bool
    let size: CGFloat
    let select: () -> Void
    @State private var thumbnail: NSImage?
    @Environment(\.islandModel) private var model

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image = thumbnail ?? item.icon {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.symbol)
                        .resizable().scaledToFit().padding(size * 0.2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: size, height: size)
            Text(item.title)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size + 16)
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { IslandShelfMouse(item: item, model: model, select: select) }
        .task(id: item.id) { thumbnail = await IslandShelfThumbnails.image(for: item, side: size) }
        .help(item.title)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to open, or drag it to where you want it")
        .accessibilityAction(named: "Open") { IslandShelfActions.open(item) }
        .accessibilityAction(named: "Remove from Shelf") { IslandShelfActions.remove(item) }
    }
}

enum IslandShelfActions {
    static func open(_ item: ShelfItem) {
        switch item.content {
        case .file(let url), .link(let url): NSWorkspace.shared.open(url)
        case .text(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        withAnimation(.smooth) { ShelfStore.shared.items.removeAll { $0.id == item.id } }
    }

    static func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .file(let url), .link(let url): pasteboard.writeObjects([url as NSURL])
        case .text(let text): pasteboard.setString(text, forType: .string)
        }
    }

    /// Quick Look through `qlmanage`, which shows its own preview window.
    static func quickLook(_ url: URL) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/qlmanage")
            process.arguments = ["-p", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    /// What's handed over when it's dragged out.
    static func writer(_ item: ShelfItem) -> NSPasteboardWriting {
        switch item.content {
        case .file(let url), .link(let url): url as NSURL
        case .text(let text): text as NSString
        }
    }
}

/// Thumbnails for files (Quick Look's), cached by path.
enum IslandShelfThumbnails {
    private static var cache: [URL: NSImage] = [:]

    static func image(for item: ShelfItem, side: CGFloat) async -> NSImage? {
        guard case .file(let url) = item.content else { return nil }
        if let cached = cache[url] { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = representation.nsImage
        cache[url] = image
        return image
    }
}

/// The AppKit part of a tile: it takes the first click, so the island (never key) reacts at once.
private struct IslandShelfMouse: NSViewRepresentable {
    let item: ShelfItem
    let model: IslandModel?
    let select: () -> Void

    func makeNSView(context: Context) -> IslandShelfMouseView {
        IslandShelfMouseView()
    }

    func updateNSView(_ view: IslandShelfMouseView, context: Context) {
        view.item = item
        view.model = model
        view.select = select
    }
}

final class IslandShelfMouseView: NSView, NSDraggingSource {
    var item: ShelfItem?
    weak var model: IslandModel?
    var select: () -> Void = {}
    private var downEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        select()
        if event.clickCount == 2, let item { IslandShelfActions.open(item) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item, let down = downEvent else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        downEvent = nil
        let dragItem = NSDraggingItem(pasteboardWriter: IslandShelfActions.writer(item))
        let image = item.icon ?? NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) ?? NSImage()
        dragItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        downEvent = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let item else { return }
        select()
        let menu = NSMenu()
        let actions = IslandMenuActions()
        menu.addItem(actions.item("Open") { IslandShelfActions.open(item) })
        if case .file(let url) = item.content {
            menu.addItem(actions.item("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            menu.addItem(actions.item("Quick Look") { IslandShelfActions.quickLook(url) })
        }
        let shareItems: [Any] = {
            switch item.content {
            case .file(let url), .link(let url): [url]
            case .text(let text): [text]
            }
        }()
        // Apple's own Share menu item (with every sharing service).
        menu.addItem(NSSharingServicePicker(items: shareItems).standardShareMenuItem)
        menu.addItem(actions.item("Copy") { IslandShelfActions.copy(item) })
        menu.addItem(.separator())
        menu.addItem(actions.item("Remove from Shelf") { IslandShelfActions.remove(item) })
        model?.menuOpen = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        withExtendedLifetime(actions) {}
        model?.menuOpen = false
        if let model, model.state == .open, !model.pinned, !model.isPointerInside() {
            withAnimation(IslandMotion.close) { model.close() }
        }
    }

    // MARK: Dragging out

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Never .move: Finder would move the original file out of its folder.
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    /// Dropped somewhere: it leaves the Shelf (the owner's choice).
    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        MainActor.assumeIsolated {
            if let item { IslandShelfActions.remove(item) }
        }
    }
}

// MARK: - Drag detector

/// boring.notch's DragDetector (observers/DragDetector.swift, by Alexander): mouse down, dragged and
/// up are watched (only those; plain pointer movement isn't), and when real content starts being
/// dragged (the drag pasteboard changed and holds a file, link or text) the island opens on its
/// Shelf. Zephydian changes: it fires once per drag, when the drag starts (the owner's choice), not
/// when it reaches a region; it runs only while the island shows a Shelf.
final class IslandDragDetector {
    var onContentDragStarted: () -> Void = {}

    private var monitors: [Any] = []
    private var pasteboardChangeCount = -1
    private var isDragging = false
    private var isContentDragging = false
    private let dragPasteboard = NSPasteboard(name: .drag)

    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [.fileURL, NSPasteboard.PasteboardType(UTType.url.identifier), .string]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pasteboardChangeCount = self.dragPasteboard.changeCount
                self.isDragging = true
                self.isContentDragging = false
            }
        }) { monitors.append(down) }
        if let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDragging, !self.isContentDragging else { return }
                if self.dragPasteboard.changeCount != self.pasteboardChangeCount && self.hasValidDragContent() {
                    self.isContentDragging = true
                    self.onContentDragStarted()
                }
            }
        }) { monitors.append(dragged) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isDragging = false
                self?.isContentDragging = false
                self?.pasteboardChangeCount = -1
            }
        }) { monitors.append(up) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        isDragging = false
        isContentDragging = false
    }
}
