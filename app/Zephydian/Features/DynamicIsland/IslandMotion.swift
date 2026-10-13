// The island's one motion spec (the owner signed off on these values in a side-by-side mockup,
// 2026-10-12). Restrained on purpose: a small bounce opening, none closing; the shape leads and the
// content follows. Values follow Apple's spring guidance (WWDC23 "Animate with springs") and
// Vorssaint's staging, toned down.

import AppKit
import SwiftUI

enum IslandMotion {
    // MARK: Values

    // Tuned with the owner 2026-10-12: bounce 0.15 → 0.10 ("smoother"), then closing made the mirror
    // of opening (same spring; the content leaves the way it came).
    static let openDuration = 0.40
    static let openBounce = 0.10
    /// Closing mirrors opening (the owner, 2026-10-12: "the same opposite animation as the open").
    static let closeDuration = 0.40
    /// The content follows the shape by this much, then fades in.
    /// (0.04 and 0.18 since B-42: the mockup's 0.12 and 0.25 felt late in the app.)
    static let contentDelay = 0.04
    static let contentFadeIn = 0.18
    static let contentBlur: CGFloat = 8
    static let contentStartScale: CGFloat = 0.92
    /// The content leaves before the shape shrinks.
    static let contentFadeOut = 0.18

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Animations

    /// Opening (also alerts arriving, the preview strip). With a 0.10 bounce the overshoot stays around
    /// 1 pt across the island's width, well inside the 5 pt cap of the mockup.
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: openDuration, bounce: openBounce)
    }

    /// Closing: the opening spring, run the other way.
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: closeDuration, bounce: openBounce)
    }

    static func to(open opening: Bool) -> Animation { opening ? open : close }

    /// Small changes under the pointer: hover, the outline's room, a swipe settling back.
    static var hover: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0)
    }

    /// A side button riding the same curve as the island, a beat behind the content.
    static func sideButton(_ order: Int) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15)
            : .spring(duration: openDuration, bounce: openBounce).delay(contentDelay + 0.04 * Double(order))
    }

    // MARK: Transitions

    /// The open island's content (its header and page): in a beat after the shape, coming into focus
    /// and growing slightly from the top; out quickly, softening, before the shape shrinks.
    static var content: AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .modifier(active: IslandContentEffect(shown: 0, blur: contentBlur, scale: contentStartScale),
                                 identity: IslandContentEffect(shown: 1, blur: contentBlur, scale: contentStartScale))
                .animation(.easeOut(duration: contentFadeIn).delay(contentDelay)),
            // The opening in reverse: softening and shrinking toward the top as it fades.
            removal: .modifier(active: IslandContentEffect(shown: 0, blur: contentBlur, scale: contentStartScale),
                               identity: IslandContentEffect(shown: 1, blur: contentBlur, scale: contentStartScale))
                .animation(.easeIn(duration: contentFadeIn)))
    }

    /// What the closed island shows beside the notch: leaves as fast as open content, and comes back
    /// once the shape has mostly closed.
    static var activity: AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(closeDuration * 0.4)),
            removal: .opacity.animation(.easeIn(duration: contentFadeOut)))
    }
}

/// Fades, focuses and scales a view from the top as `shown` goes from 0 to 1.
struct IslandContentEffect: ViewModifier, Animatable {
    var shown: Double
    let blur: CGFloat
    let scale: CGFloat

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .opacity(shown)
            .blur(radius: blur * (1 - shown))
            .scaleEffect(scale + (1 - scale) * shown, anchor: .top)
    }
}
