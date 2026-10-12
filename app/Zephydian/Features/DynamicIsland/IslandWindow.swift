//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//
// Copied into Zephydian from boring.notch (github.com/TheBoredTeam/boring.notch, GPL-3.0,
// commit e2654ee). Zephydian changes: renamed; the window is always dark. boring.notch's private CGS
// space was left out (B-33).

import AppKit

final class IslandWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
