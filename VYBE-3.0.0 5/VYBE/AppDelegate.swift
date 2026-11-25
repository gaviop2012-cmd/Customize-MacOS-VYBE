import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // VYBE is a background desktop environment, not a foreground Dock app.
        NSApp.setActivationPolicy(.accessory)

        // Only hide Finder desktop icons if explicitly requested by the user in settings
        if UserDefaults.standard.bool(forKey: "VYBE.hideFinderDesktop") {
            FinderDesktopVisibility.hide()
        } else {
            // Keep user's real desktop files and folders visible
            FinderDesktopVisibility.restore()
        }

        // Only auto-hide Apple Dock if explicitly requested by the user
        if UserDefaults.standard.bool(forKey: "VYBE.autoHideAppleDock") {
            try? AppleDockVisibility.setAutoHide(true)
        }

        HotKeyManager.shared.registerShortcuts()
        Task { @MainActor in
            await WallpaperEngine.shared.restoreSavedVideo()
            DesktopEnvironment.shared.start()
            VYBESpaceManager.shared.restoreActiveConfiguration()
            VYBEDisplayManager.shared.launchInstalledHostIfNeeded()
        }
        // SwiftUI creates the control window scene, but the desktop should be
        // the first thing the user sees. The window remains available on demand.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.windows.first(where: { !($0 is NSPanel) })?.close()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterShortcuts()
        WallpaperEngine.shared.stopWallpaper()
        FinderDesktopVisibility.restore()
    }
}
