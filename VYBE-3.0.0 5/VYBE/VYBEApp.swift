import SwiftUI

@main
struct VYBEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = WallpaperEngine.shared

    var body: some Scene {
        WindowGroup("VYBE Control Centre", id: "control") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 680, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("VYBE", systemImage: "sparkles.rectangle.stack") {
            MenuBarPanel()
                .environmentObject(engine)
        }
        .menuBarExtraStyle(.window)
    }
}
