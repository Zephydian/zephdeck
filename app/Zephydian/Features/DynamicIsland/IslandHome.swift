import SwiftUI

/// One thing the Home tab can show. Raw values are saved; never rename them.
enum IslandHomeItem: String, CaseIterable, Identifiable {
    case music, calendar, timer, capture, shelf, camera

    var id: String { rawValue }

    /// Home holds up to three.
    static let maximum = 3
    /// boring.notch's home: the player and the calendar.
    static let defaultItems: [IslandHomeItem] = [.music, .calendar]

    var title: String {
        switch self {
        case .music: "Music player"
        case .calendar: "Calendar"
        case .timer: "Quick timer"
        case .capture: "Capture"
        case .shelf: "Shelf"
        case .camera: "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .timer: "timer"
        case .capture: "camera.viewfinder"
        case .shelf: "tray.full"
        case .camera: "web.camera"
        }
    }

    var tint: Color {
        switch self {
        case .music: .pink
        case .calendar: .red
        case .timer: .mint
        case .capture: .indigo
        case .shelf: .cyan
        case .camera: .teal
        }
    }
}

/// The Home tab: up to three items side by side, sharing the island's width. With two, the player
/// takes about 60%; with three, everything gets a third and the player its compact look.
struct IslandHomePage: View {
    var namespace: Namespace.ID?
    private var settings: IslandSettings { IslandSettings.shared }

    var body: some View {
        let items = Array(settings.homeItems.prefix(IslandHomeItem.maximum))
        if items.isEmpty {
            IslandEmptyView(symbol: "house", message: "Home is empty. Choose what it shows in Settings.")
        } else {
            GeometryReader { proxy in
                let spacing: CGFloat = items.count == 3 ? 10 : 15
                let available = proxy.size.width - spacing * CGFloat(items.count - 1)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        view(for: item, compact: items.count == 3)
                            .padding(8)
                            .frame(width: width(of: item, in: items, available: available), alignment: .top)
                            .frame(maxHeight: .infinity, alignment: .top)
                            // An outline per widget, so they're easy to tell apart (the owner's request).
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                    }
                }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        }
    }

    private func width(of item: IslandHomeItem, in items: [IslandHomeItem], available: CGFloat) -> CGFloat {
        guard items.count == 2, items.contains(.music) else { return available / CGFloat(items.count) }
        return item == .music ? available * 0.6 : available * 0.4
    }

    @ViewBuilder private func view(for item: IslandHomeItem, compact: Bool) -> some View {
        switch item {
        case .music:
            if compact { IslandCompactPlayer() } else { IslandMusicPlayer(namespace: namespace) }
        case .calendar: IslandCalendarView()
        case .timer: IslandTimerHome()
        case .capture: IslandCaptureHome()
        case .shelf: IslandShelfHome()
        case .camera: IslandCameraView()
        }
    }
}
