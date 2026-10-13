import AppKit
import SwiftUI

/// macOS's own dark blur of what's behind the window (Vorssaint's translucent background), always
/// drawn active since the island's window never becomes key. Masked to the island's shape by its own
/// layer, since SwiftUI's clip doesn't always reach AppKit views.
struct IslandBehindBlur<S: Shape>: NSViewRepresentable {
    let shape: S

    func makeNSView(context: Context) -> BlurView {
        let view = BlurView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.makeMask = { rect in shape.path(in: rect).cgPath }
        return view
    }

    func updateNSView(_ view: BlurView, context: Context) {
        view.makeMask = { rect in shape.path(in: rect).cgPath }
        view.needsLayout = true
    }

    final class BlurView: NSVisualEffectView {
        var makeMask: (CGRect) -> CGPath = { CGPath(rect: $0, transform: nil) }
        private let maskLayer = CAShapeLayer()

        override func layout() {
            super.layout()
            wantsLayer = true
            // SwiftUI's shapes are drawn top-down; AppKit layers here are bottom-up.
            var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
            maskLayer.path = isFlipped ? makeMask(bounds) : makeMask(bounds).copy(using: &flip)
            layer?.mask = maskLayer
        }
    }
}
