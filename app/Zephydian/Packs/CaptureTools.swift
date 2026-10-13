import AppKit
import SwiftUI
import Vision

// MARK: - Text and QR codes from the screen

/// Reads text (and QR codes) in a picture with Apple's Vision framework, entirely on this Mac.
nonisolated enum ScreenText {
    struct Found: Sendable {
        var text: String
        /// The link or text in a QR code (or other barcode), if there was one.
        var code: String?
    }

    static func read(_ image: CGImage) async -> Found {
        await Task.detached(priority: .userInitiated) { () -> Found in
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            let codes = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([text, codes])
            // Lines top to bottom, as they appear.
            let lines = (text.results ?? [])
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }
            let code = (codes.results ?? []).compactMap(\.payloadStringValue).first
            return Found(text: lines.joined(separator: "\n"), code: code)
        }.value
    }
}

// MARK: - A short note on screen

/// "Copied 12 lines": a small glass note near the bottom of the screen for a moment.
@MainActor
enum CaptureToast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ text: String, symbol: String = "checkmark.circle.fill", detail: String? = nil) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        let settings = Features.shared.appSettings ?? SettingsStore()
        let view = HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(settings.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: detail == nil ? 44 : 52)
        .glassSurface(in: Capsule(), fallback: .regularMaterial)
        .environment(settings)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let new = NSPanel(contentRect: NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 90,
                                              width: size.width, height: size.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ScreenCapture.markAsTool(new)
        new.level = .statusBar
        new.isOpaque = false
        new.backgroundColor = .clear
        new.ignoresMouseEvents = true
        new.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        new.appearance = settings.appearance.nsAppearance
        new.contentView = hosting
        new.orderFrontRegardless()
        panel = new
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            panel = nil
        }
    }
}

// MARK: - Pinned screenshots

/// A screenshot floating above everything while you work: drag it to move, pinch or drag its corner
/// grip to resize, double-click (or its ×) to close, ⌘C copies it.
@MainActor
final class PinnedShots {
    private var windows: [NSPanel] = []

    func pin(_ image: CGImage, near point: NSPoint) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let limit = screen.visibleFrame.size
        let fit = min(1, limit.width * 0.6 / size.width, limit.height * 0.6 / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        let panel = PinPanel(contentRect: NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                                                 width: size.width, height: size.height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = size
        panel.isReleasedWhenClosed = false
        panel.image = image
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            self?.windows.removeAll { $0 === panel }
        }
        // Its × uses the glass button style, which reads the app's settings (B-48: without them the
        // pin crashed the moment it appeared).
        let settings = Features.shared.appSettings ?? SettingsStore()
        panel.contentView = NSHostingView(rootView: PinView(image: NSImage(cgImage: image, size: size), close: { [weak panel] in panel?.onClose() })
            .environment(settings)
            .tint(settings.accentColor))
        panel.orderFrontRegardless()
        windows.append(panel)
    }

    private final class PinPanel: NSPanel {
        var image: CGImage?
        var onClose: () -> Void = {}
        override var canBecomeKey: Bool { true }

        /// Pinch resizes around the pointer, in proportion to the pinch (B-51); scrolling no longer
        /// resizes, so it can't happen by accident.
        override func magnify(with event: NSEvent) {
            resize(by: 1 + event.magnification, around: NSEvent.mouseLocation)
        }

        func resize(by factor: CGFloat, around point: NSPoint) {
            var frame = self.frame
            let aspect = frame.width / max(1, frame.height)
            let newWidth = min(max(frame.width * factor, PinnedShots.minimumWidth), 4000)
            let newHeight = newWidth / aspect
            // Keep the point under the pointer where it is.
            let fx = (point.x - frame.minX) / max(1, frame.width), fy = (point.y - frame.minY) / max(1, frame.height)
            frame.origin.x = point.x - newWidth * min(max(fx, 0), 1)
            frame.origin.y = point.y - newHeight * min(max(fy, 0), 1)
            frame.size = NSSize(width: newWidth, height: newHeight)
            setFrame(frame, display: true)
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", let image {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
                CaptureToast.show("Copied")
            } else if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") {
                onClose()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    static let minimumWidth: CGFloat = 80

    private struct PinView: View {
        let image: NSImage
        let close: () -> Void
        @State private var hovering = false
        @Environment(SettingsStore.self) private var settings

        var body: some View {
            Image(nsImage: image)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                // Anywhere on the picture drags it; a double-click closes it (B-50: the picture took the
                // mouse-down, so the window never moved).
                .overlay { PinDragArea(close: close) }
                // An outline in the accent color (B-50, the owner's choice).
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(settings.accentColor.opacity(0.9), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if hovering {
                        Button(action: close) { Image(systemName: "xmark") }
                            .glassIconButtonStyle()
                            .padding(6)
                            .help("Close (or double-click)")
                            .accessibilityLabel("Close the pinned screenshot")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Drag the corner to resize, keeping the picture's shape (B-51).
                    if hovering {
                        PinResizeGrip()
                            .frame(width: 22, height: 22)
                            .overlay {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .allowsHitTesting(false)
                            }
                            .background(Circle().fill(settings.accentColor))
                            .padding(5)
                            .help("Drag to resize")
                            .accessibilityLabel("Resize")
                    }
                }
                .padding(1)
                .onHover { hovering = $0 }
                .accessibilityLabel("Pinned screenshot")
        }
    }

    /// Moves the pin with the mouse (a window that never activates the app can't use the usual
    /// background drag through SwiftUI), and closes it on a double-click.
    private struct PinDragArea: NSViewRepresentable {
        let close: () -> Void
        func makeNSView(context: Context) -> DragView { DragView() }
        func updateNSView(_ view: DragView, context: Context) { view.close = close }

        final class DragView: NSView {
            var close: () -> Void = {}
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) {
                if event.clickCount == 2 { close(); return }
                window?.performDrag(with: event)
            }
        }
    }

    /// The corner grip: dragging it resizes the pin from its top-left corner, keeping its shape.
    private struct PinResizeGrip: NSViewRepresentable {
        func makeNSView(context: Context) -> GripView { GripView() }
        func updateNSView(_ view: GripView, context: Context) {}

        final class GripView: NSView {
            private var start: (frame: NSRect, mouse: NSPoint)?
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
            override func mouseDown(with event: NSEvent) {
                guard let window else { return }
                start = (window.frame, NSEvent.mouseLocation)
            }
            override func mouseDragged(with event: NSEvent) {
                guard let window, let start else { return }
                let mouse = NSEvent.mouseLocation
                let aspect = start.frame.width / max(1, start.frame.height)
                // Right and down both grow it; whichever moved more decides.
                let dx = mouse.x - start.mouse.x, dy = start.mouse.y - mouse.y
                let grow = abs(dx) >= abs(dy * aspect) ? dx : dy * aspect
                let width = min(max(start.frame.width + grow, PinnedShots.minimumWidth), 4000)
                let height = width / aspect
                window.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
            }
            override func mouseUp(with event: NSEvent) { start = nil }
        }
    }
}
