//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//
// Copied into Zephdeck from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee). Zephdeck changes: grouped in an enum, takes the screen instead of a display
// UUID, the notch height always matches the real notch and a notchless display uses the menu bar's
// height (boring.notch's defaults; its custom heights were left out), dropped the music sizes; the open size follows the Size setting; Vorssaint's camera fit and capsule (silhouette, fit) for the closed size.

import AppKit

enum IslandSizing {
    static let shadowPadding: CGFloat = 20
    /// The open island's size, after the Size setting (Compact, Spacious, Custom).
    static var openSize: CGSize { IslandSettings.shared.openSize }
    /// The open island plus room on each side for its buttons (22.11), and below for the shadow.
    static var windowSize: CGSize { .init(width: openSize.width + 2 * sideRoom, height: openSize.height + shadowPadding) }
    /// Room on each side of the open island for a column of buttons (a bubble, its gap, a margin).
    static let sideRoom: CGFloat = 56
    static let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) =
        (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

    /// The notch's size on `screen`, or a notch-sized pill's on a display without one.
    static func closedSize(on screen: NSScreen?) -> CGSize {
        // Default notch size, to avoid using optionals
        var notchHeight: CGFloat = 32
        var notchWidth: CGFloat = 185

        if let screen {
            // Calculate and set the exact width of the notch
            if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
               let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
            {
                notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
            }

            if screen.safeAreaInsets.top > 0 {
                // This is a display WITH a notch
                notchHeight = screen.safeAreaInsets.top
            } else {
                // This is a display WITHOUT a notch: as tall as the menu bar
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
                if notchHeight <= 0 { notchHeight = 32 }
            }
        }

        let settings = IslandSettings.shared
        if hasNotch(screen) {
            // Vorssaint's camera fit: a correction to the size macOS reports.
            notchWidth += settings.cameraFit.width
            notchHeight += settings.cameraFit.height
        } else if settings.silhouette == .capsule {
            // Vorssaint's capsule: inside the menu bar, clear of its edges, then the fit.
            let fit = settings.capsuleFit
            notchWidth += fit.width
            notchHeight = max(14, notchHeight - 2 * capsuleMargin + fit.height)
        }
        return .init(width: notchWidth, height: notchHeight)
    }

    /// Vorssaint's outline width.
    static let outlineWidth: CGFloat = 2

    /// The gap above and below a capsule inside the menu bar.
    static let capsuleMargin: CGFloat = 2

    /// The closed island floats as a capsule (a display without a notch, the Capsule shape chosen).
    static func floatsAsCapsule(_ screen: NSScreen?) -> Bool {
        !hasNotch(screen) && IslandSettings.shared.silhouette == .capsule
    }

    /// How far the closed capsule sits below the top of the screen.
    static func capsuleTop(_ screen: NSScreen?) -> CGFloat {
        floatsAsCapsule(screen) ? capsuleMargin + IslandSettings.shared.capsuleFit.drop : 0
    }

    static func hasNotch(_ screen: NSScreen?) -> Bool {
        (screen?.safeAreaInsets.top ?? 0) > 0
    }
}
