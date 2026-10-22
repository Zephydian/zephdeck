// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The symbols and colors follow Vorssaint's NotchModule (Services/Notch/NotchSupport.swift and
// UI/Settings/NotchContentEditor.swift, commit 1d32501). Zephdeck changes: Zephdeck's own tabs
// (Home, Music, Calendar, Shelf, Timers, Capture, Camera), their names and summaries in English.

import SwiftUI

/// One page of the open island. Raw values are saved; never rename them.
enum IslandTab: String, CaseIterable, Identifiable {
    case home, music, calendar, shelf, timers, capture, camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .timers: "Timers"
        case .capture: "Capture"
        case .camera: "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .timers: "timer"
        case .capture: "camera.viewfinder"
        case .camera: "web.camera"
        }
    }

    /// One line on what the tab shows (the editor's description and tooltips).
    var summary: String {
        switch self {
        case .home: "What's playing and today's calendar, side by side."
        case .music: "The artwork, a scrubber and the playback controls."
        case .calendar: "Today's events and the days around it."
        case .shelf: "Files, links and text you parked on the Shelf. Drop more on the notch."
        case .timers: "Your running timers, with pause and stop, and new ones."
        case .capture: "Take a screenshot or a recording, and stop a recording."
        case .camera: "A mirror of your camera, to check how you look."
        }
    }

    /// The symbol's color on the island's grid.
    var tint: Color {
        switch self {
        case .music: .pink
        case .calendar: .red
        case .timers: .orange
        default: .white.opacity(0.85)
        }
    }

    /// A color per tab in Settings, like the icons of System Settings, so the list can be scanned by eye.
    var settingsTint: Color {
        switch self {
        case .home: .blue
        case .music: .pink
        case .calendar: .red
        case .shelf: .cyan
        case .timers: .mint
        case .capture: .indigo
        case .camera: .teal
        }
    }

    /// On by default (22-D3).
    static let defaultShown: Set<IslandTab> = [.home, .shelf, .timers]
}
