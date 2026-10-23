// The island's Capture: Zephdeck's Capture utility (pack `screenshot`, `ScreenCapture` and
// `ScreenRecorder`). The closed recording indicator follows the live activities copied from
// boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0); the tab and Home layouts are Zephdeck's.

import AppKit
import SwiftUI

/// Capture as the island sees it: the recording in progress, recent shots, and the actions.
enum IslandCapture {
    static let packID = "screenshot"

    private static var services: PackServices { PackServices.shared }
    private static var capture: ScreenCapture { services.capture }

    /// Reading these follows changes.
    static var isRecording: Bool {
        _ = services.revision
        return capture.recorder.isRecording
    }

    static var startedAt: Date? {
        _ = services.revision
        return capture.recorder.startedAt
    }

    /// The newest screenshots first (at most 12).
    static var recentShots: [ScreenCapture.Shot] {
        _ = services.revision
        return Array(capture.shots.reversed().prefix(12))
    }

    static var isInstalled: Bool { PackLibrary.shared.packs.contains { $0.id == packID } }

    // MARK: Actions (the island closes first, so it's out of the way)

    static func screenshot(_ mode: ScreenCapture.Mode, model: IslandModel?) {
        model?.close()
        capture.capture(packID: packID, mode: mode) { _, error in
            if let error, !error.isEmpty { CaptureToast.show(error, symbol: "exclamationmark.triangle.fill") }
        }
    }

    static func record(_ target: ScreenRecorder.Target, model: IslandModel?) {
        model?.close()
        capture.recorder.start(packID: packID, target: target)
    }

    static func stopRecording() { capture.recorder.stop() }

    static func copyText(model: IslandModel?) {
        model?.close()
        capture.copyText()
    }

    static func pickColor(model: IslandModel?) {
        model?.close()
        capture.pickColor()
    }

    /// A recent shot opens in the image editor (Markup), or its preview card without one.
    static func open(_ shot: ScreenCapture.Shot, model: IslandModel?) {
        model?.close()
        if let editor = services.imageEditor() {
            services.openInEditor(editor, shot.id)
        } else {
            capture.showPreview(shot.id, packID: packID)
        }
    }

    static func thumbnail(_ shot: ScreenCapture.Shot) -> NSImage? { capture.thumbnail(shot.id) }

    /// Record: Area, Window or Screen, chosen each time (the owner's choice).
    static func chooseRecording(model: IslandModel?) {
        let menu = NSMenu()
        let actions = IslandMenuActions()
        menu.addItem(actions.item("Record an Area") { record(.area, model: model) })
        menu.addItem(actions.item("Record a Window") { record(.window, model: model) })
        menu.addItem(actions.item("Record the Screen") { record(.screen, model: model) })
        model?.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(actions) {}
        model?.menuOpen = false
    }

    static func elapsed(since start: Date?, at date: Date) -> String {
        guard let start else { return "0:00" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                               : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Closed island

/// A recording: a pulsing red dot on the left of the notch, the time recorded on the right, both
/// hugging the notch and sized to the wider side (like the timer's).
struct IslandRecordingLiveActivity: View {
    let model: IslandModel
    @State private var leftWidth: CGFloat = 0
    @State private var rightWidth: CGFloat = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func width(closed: CGFloat) -> CGFloat { closed + 28 + 2 * 50 }
    private var side: CGFloat { max(leftWidth, rightWidth) + 8 }

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
                .opacity(pulse ? 0.35 : 1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leftWidth = $0 }
                .frame(width: side, alignment: .trailing)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                }

            Rectangle().fill(.black).frame(width: model.closedSize.width + 8)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(IslandCapture.elapsed(since: IslandCapture.startedAt, at: context.date))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.red)
                    .fixedSize()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rightWidth = $0 }
            .frame(width: side, alignment: .leading)
        }
        .frame(height: model.effectiveClosedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording the screen")
    }
}

// MARK: - The Capture tab and Home

/// One capture action: an icon and a word on a soft capsule.
struct IslandCaptureButton: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: compact ? 15 : 17, weight: .medium)).foregroundStyle(tint)
                if !compact {
                    Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.75)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 34 : 46)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(IslandTileButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The Capture tab: six actions and the recent screenshots; while recording, the time and Stop.
struct IslandCapturePage: View {
    @Environment(\.islandModel) private var model

    var body: some View {
        if !IslandCapture.isInstalled {
            IslandUtilityInstall(symbol: "camera.viewfinder", message: "Capture comes from the Capture utility.", name: "Capture")
        } else if IslandCapture.isRecording {
            IslandRecordingControls(large: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    IslandCaptureButton(title: "Area", symbol: "rectangle.dashed") { IslandCapture.screenshot(.area, model: model) }
                    IslandCaptureButton(title: "Window", symbol: "macwindow") { IslandCapture.screenshot(.window, model: model) }
                    IslandCaptureButton(title: "Screen", symbol: "display") { IslandCapture.screenshot(.screen, model: model) }
                    IslandCaptureButton(title: "Record", symbol: "record.circle", tint: .red) { IslandCapture.chooseRecording(model: model) }
                    IslandCaptureButton(title: "Text", symbol: "text.viewfinder") { IslandCapture.copyText(model: model) }
                    IslandCaptureButton(title: "Color", symbol: "eyedropper") { IslandCapture.pickColor(model: model) }
                }
                let shots = IslandCapture.recentShots
                if shots.isEmpty {
                    Text("Your screenshots show here.")
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(shots, id: \.id) { IslandShotTile(shot: $0) }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// The time recorded and a Stop button.
struct IslandRecordingControls: View {
    let large: Bool

    var body: some View {
        VStack(spacing: large ? 10 : 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: large ? 10 : 8, height: large ? 10 : 8)
                    Text(IslandCapture.elapsed(since: IslandCapture.startedAt, at: context.date))
                        .font(.system(size: large ? 30 : 22, weight: .light).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            Button { IslandCapture.stopRecording() } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .font(.system(size: large ? 13 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, large ? 16 : 10)
                    .frame(height: large ? 30 : 24)
                    .background(Color.red, in: Capsule())
            }
            .buttonStyle(IslandTileButtonStyle())
            .accessibilityLabel("Stop recording")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A recent screenshot: click opens it in Markup, drag it out to use it anywhere.
struct IslandShotTile: View {
    let shot: ScreenCapture.Shot
    @Environment(\.islandModel) private var model

    var body: some View {
        Group {
            if let image = IslandCapture.thumbnail(shot) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 78, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .overlay {
            IslandClickDrag(
                click: { IslandCapture.open(shot, model: model) },
                writer: { NSImage(cgImage: shot.image, size: .zero) },
                image: { IslandCapture.thumbnail(shot) })
        }
        .help("Click to edit in Markup, or drag it to where you want it")
        .accessibilityElement()
        .accessibilityLabel("Screenshot, \(shot.date.formatted(date: .omitted, time: .shortened))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { IslandCapture.open(shot, model: model) }
    }
}

/// Home's Capture: Area, Window, Screen and Record as a 2×2 grid; while recording, the time and Stop.
struct IslandCaptureHome: View {
    @Environment(\.islandModel) private var model

    var body: some View {
        if !IslandCapture.isInstalled {
            IslandUtilityInstall(symbol: "camera.viewfinder", message: "From the Capture utility.", name: "Capture")
        } else if IslandCapture.isRecording {
            IslandRecordingControls(large: false)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                IslandCaptureButton(title: "Area", symbol: "rectangle.dashed", compact: true) { IslandCapture.screenshot(.area, model: model) }
                IslandCaptureButton(title: "Window", symbol: "macwindow", compact: true) { IslandCapture.screenshot(.window, model: model) }
                IslandCaptureButton(title: "Screen", symbol: "display", compact: true) { IslandCapture.screenshot(.screen, model: model) }
                IslandCaptureButton(title: "Record", symbol: "record.circle", tint: .red, compact: true) { IslandCapture.chooseRecording(model: model) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Without a utility the island needs: a link that opens the Library on Utilities.
struct IslandUtilityInstall: View {
    let symbol: String
    let message: String
    let name: String
    @Environment(\.islandModel) private var model
    @Environment(SettingsStore.self) private var appSettings

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(appSettings.accentColor)
            Text(message)
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
            Button("Get the \(name) Utility") {
                model?.close()
                IslandHooks.openUtilitiesLibrary()
            }
            .buttonStyle(IslandLinkButtonStyle())
            .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A click and a drag for any island item, in AppKit so it takes the first click (the island never
/// becomes key).
struct IslandClickDrag: NSViewRepresentable {
    let click: () -> Void
    let writer: () -> NSPasteboardWriting?
    let image: () -> NSImage?

    func makeNSView(context: Context) -> IslandClickDragView { IslandClickDragView() }

    func updateNSView(_ view: IslandClickDragView, context: Context) {
        view.click = click
        view.writer = writer
        view.image = image
    }
}

final class IslandClickDragView: NSView, NSDraggingSource {
    var click: () -> Void = {}
    var writer: () -> NSPasteboardWriting? = { nil }
    var image: () -> NSImage? = { nil }
    private var down: NSEvent?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        down = event
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = down, !dragged, let item = writer() else { return }
        let a = start.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
        dragged = true
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: image() ?? NSImage())
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { click() }
        down = nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : []
    }
}
