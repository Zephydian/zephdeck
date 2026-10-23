import SwiftUI

extension EnvironmentValues {
    /// Drawn as a still in Settings' preview: nothing live may start (no camera, no keyboard focus).
    @Entry var islandPreview = false
}

/// The open island under its header: the chosen tab, or the grid of tabs.
struct IslandBody: View {
    let model: IslandModel
    var namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if model.showingGrid {
                IslandGrid(model: model)
                    .transition(.opacity)
            } else {
                IslandPage(tab: model.tab, namespace: namespace)
                    .id(model.tab)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandModel, model)
        // A drop anywhere else on the open island goes on the Shelf too, and shows it.
        .onDrop(of: IslandShelfDrop.types, isTargeted: nil) { providers in
            model.droppedOnShelf()
            return IslandShelfDrop.receive(providers)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.showingGrid)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.tab)
    }
}

/// One tab's page.
struct IslandPage: View {
    let tab: IslandTab
    var namespace: Namespace.ID?

    var body: some View {
        switch tab {
        case .home: IslandHomePage(namespace: namespace)
        case .music: IslandMusicPlayer(namespace: namespace)
        case .calendar: IslandCalendarView()
        case .shelf: IslandShelfPage()
        case .timers: IslandTimersPage()
        case .capture: IslandCapturePage()
        case .camera: IslandCameraPage()
        }
    }
}
