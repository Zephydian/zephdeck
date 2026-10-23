import SwiftUI

@main
struct ZephdeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Zephdeck has no regular windows: everything lives in the floating panel,
        // which AppDelegate creates. SwiftUI requires at least one scene, so this is empty.
        Settings { EmptyView() }
            .commands {
                // The menu bar only shows while a utility's window is open (Zephdeck is then in the
                // Dock). Settings… opens Zephdeck's own Settings window instead of an empty one.
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.openSettings() }
                        .keyboardShortcut(",")
                }
                CommandGroup(replacing: .newItem) {}
            }
    }
}
