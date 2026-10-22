// The island's camera. The click-to-start "Mirror" placeholder and stopping on disappear follow
// boring.notch's CameraPreviewView (components/Webcam/WebcamView.swift, GPL-3.0, commit e2654ee;
// created by Harsh Vardhan Goswami) and WebcamManager. Zephdeck changes: one AVCaptureSession on its
// own queue, the shape and mirroring of Zephdeck's Camera Mirror (`CameraMirrorSettings`), a button
// to open Camera Mirror's floating window, English text.

@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// The camera while the island shows it (the camera light is on only then).
@Observable
final class IslandCameraSession {
    static let shared = IslandCameraSession()

    private(set) var isRunning = false
    private(set) var access = AVCaptureDevice.authorizationStatus(for: .video)
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.zephydian.zephdeck.island-camera")
    @ObservationIgnored private var configured = false
    /// One preview, made once and reused (B-35: a new preview per start stayed blank after a stop;
    /// boring.notch keeps its preview layer too).
    @ObservationIgnored lazy var previewView: IslandCameraPreviewView = {
        let view = IslandCameraPreviewView()
        view.preview.session = session
        return view
    }()

    var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// Click to start (the owner's choice): asks for the camera the first time.
    func start() {
        access = AVCaptureDevice.authorizationStatus(for: .video)
        switch access {
        case .authorized:
            run()
        case .notDetermined:
            // Called on AVFoundation's queue: not main-actor isolated (B-29).
            AVCaptureDevice.requestAccess(for: .video) { @Sendable granted in
                Task { @MainActor in
                    self.access = AVCaptureDevice.authorizationStatus(for: .video)
                    Permissions.shared.refresh()
                    if granted { self.run() }
                }
            }
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = self.session
        queue.async { session.stopRunning() }
    }

    private func run() {
        guard !isRunning, let device = AVCaptureDevice.default(for: .video) else { return }
        if !configured {
            configured = true
            session.beginConfiguration()
            session.sessionPreset = .high
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
        isRunning = true
        let session = self.session
        queue.async { session.startRunning() }
    }
}

/// The camera, or boring.notch's "Mirror" placeholder to click.
struct IslandCameraView: View {
    @Environment(\.islandPreview) private var preview
    private var camera: IslandCameraSession { IslandCameraSession.shared }
    private var settings: CameraMirrorSettings { CameraMirrorSettings.shared }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let shape = settings.shape == .circle
                ? AnyShape(Circle())
                : AnyShape(RoundedRectangle(cornerRadius: min(18, side * 0.16), style: .continuous))
            ZStack {
                // Always in place (boring.notch's way), shown only while the camera runs.
                if !preview {
                    IslandCameraLayer(mirrored: settings.mirrored,
                                      circle: settings.shape == .circle, radius: min(18, side * 0.16))
                        .clipShape(shape)
                        .opacity(camera.isRunning ? 1 : 0)
                }
                if !camera.isRunning || preview {
                    shape
                        .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                        .overlay(shape.stroke(.white.opacity(0.06), lineWidth: 1).padding(0.5))
                    VStack(spacing: 6) {
                        Image(systemName: denied ? "exclamationmark.triangle" : "web.camera")
                            .font(.system(size: side / 4))
                            .foregroundStyle(.gray)
                        Text(placeholder)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(width: side, height: settings.shape == .circle ? side : side * 0.75)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(shape)
            .onTapGesture {
                guard !preview else { return }
                if camera.isRunning { camera.stop() } else { camera.start() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(camera.isRunning ? "Camera, on. Click to turn it off." : "Camera mirror. Click to turn it on.")
            .accessibilityAddTraits(.isButton)
        }
        // Off whenever it leaves the screen: the island closing, another tab, Home rearranged.
        .onDisappear { camera.stop() }
    }

    private var denied: Bool { camera.access == .denied || camera.access == .restricted }

    private var placeholder: String {
        if !camera.hasCamera { return "No camera" }
        if denied { return "Camera access is off.\nClick for Privacy settings." }
        return "Mirror"
    }
}

/// The Camera tab: the camera centred, and a button that opens Camera Mirror's floating window.
struct IslandCameraPage: View {
    @Environment(\.islandModel) private var model

    var body: some View {
        HStack(spacing: 14) {
            IslandCameraView()
                .frame(maxWidth: 220)
            if CameraMirrorEngine.current != nil {
                Button {
                    IslandCameraSession.shared.stop()
                    model?.close()
                    CameraMirrorEngine.current?.toggle()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(IslandTileButtonStyle())
                .help("Keep it in Camera Mirror's floating window")
                .accessibilityLabel("Open Camera Mirror's floating window")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// AVFoundation's live preview, mirrored like Camera Mirror. The preview layer is the view's own
/// backing layer, so it always has the view's size (B-35: a sublayer added at zero size stayed at zero).
private struct IslandCameraLayer: NSViewRepresentable {
    let mirrored: Bool
    let circle: Bool
    let radius: CGFloat

    /// The session's one preview, moved here if another place showed it before.
    func makeNSView(context: Context) -> IslandCameraPreviewView {
        let view = IslandCameraSession.shared.previewView
        view.removeFromSuperview()
        update(view)
        return view
    }

    func updateNSView(_ view: IslandCameraPreviewView, context: Context) {
        update(view)
    }

    private func update(_ view: IslandCameraPreviewView) {
        view.circle = circle
        view.radius = radius
        view.needsLayout = true
        apply(view.preview)
    }

    private func apply(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}

final class IslandCameraPreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    /// The layer is rounded itself, like Camera Mirror's (SwiftUI's clip doesn't always reach AppKit views).
    var circle = true
    var radius: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.videoGravity = .resizeAspectFill
        preview.masksToBounds = true
        layer = preview
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to the SwiftUI view around it (a click turns the camera off).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        preview.frame = bounds
        preview.cornerRadius = circle ? min(bounds.width, bounds.height) / 2 : radius
    }
}
