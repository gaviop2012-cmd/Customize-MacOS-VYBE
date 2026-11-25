import Foundation

/// Changes only the user's Dock auto-hide preference; it never edits or replaces
/// the Dock application or any protected macOS component.
enum AppleDockVisibility {
    static func setAutoHide(_ enabled: Bool) throws {
        let defaults = Process()
        defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaults.arguments = ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"]
        try defaults.run()
        defaults.waitUntilExit()
        guard defaults.terminationStatus == 0 else {
            throw NSError(domain: "VYBE.Dock", code: Int(defaults.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "macOS did not accept the Dock preference."])
        }

        let restartDock = Process()
        restartDock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restartDock.arguments = ["Dock"]
        try restartDock.run()
        restartDock.waitUntilExit()
    }
}
