import Foundation

/// Hides Finder-managed Desktop icons while VYBE is running, without moving,
/// deleting, renaming, or changing any files. The user's previous setting is
/// restored when VYBE quits. A persisted marker also lets the next launch
/// recover the original preference if VYBE was force-quit or crashed.
enum FinderDesktopVisibility {
    private static let markerKey = "VYBE.finderDesktopOriginalVisibility.saved"
    private static let originalValueKey = "VYBE.finderDesktopOriginalVisibility"

    static func hide() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: markerKey) == nil {
            defaults.set(readCurrentVisibility(), forKey: originalValueKey)
            defaults.set(true, forKey: markerKey)
        }
        writeVisibility(false)
    }

    static func restore() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: originalValueKey) as? Bool ?? true
        writeVisibility(original)
        // Also ensure CreateDesktop is explicitly true if original was true
        if original {
            writeVisibility(true)
        }
        defaults.removeObject(forKey: markerKey)
        defaults.removeObject(forKey: originalValueKey)
    }

    static func show() {
        writeVisibility(true)
        UserDefaults.standard.set(false, forKey: "VYBE.hideFinderDesktop")
    }

    static func setHidden(_ hidden: Bool) {
        if hidden {
            hide()
            UserDefaults.standard.set(true, forKey: "VYBE.hideFinderDesktop")
        } else {
            show()
        }
    }

    private static func readCurrentVisibility() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return true // Finder's default when the preference has never been set.
            }
            return value != "0" && value != "false"
        } catch {
            return true
        }
    }

    private static func writeVisibility(_ visible: Bool) {
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"]
        do {
            try write.run()
            write.waitUntilExit()
            guard write.terminationStatus == 0 else { return }

            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            restart.arguments = ["Finder"]
            try restart.run()
            restart.waitUntilExit()
        } catch {
            // Keep VYBE launch/termination safe if macOS refuses the preference change.
        }
    }
}
