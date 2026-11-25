import AppKit
import Foundation
import UserNotifications

// MARK: - Action Permission System

enum ActionPermission {
    case allowed       // Execute immediately
    case needsConfirm  // Show confirmation dialog first
    case denied        // Never allow

    static func forAction(_ action: DesktopAction) -> ActionPermission {
        switch action {
        case .openApplication, .openFolder, .openURL,
             .startTimer, .cancelTimer, .timerStatus,
             .setAlarm, .cancelAlarm, .listAlarms,
             .getTime, .getDate, .getBatteryStatus,
             .getDiskSpace, .getRunningApps,
             .showWidget, .hideWidget,
             .enableVideoWallpaper, .disableVideoWallpaper,
             .openVYBELibrary, .openControlCentre,
             .speak:
            return .allowed
        case .deleteFile, .moveFile:
            return .needsConfirm
        }
    }
}

// MARK: - Desktop Actions

enum DesktopAction {
    case openApplication(name: String)
    case openFolder(name: String)
    case openURL(url: String)
    case startTimer(seconds: Int, name: String?)
    case cancelTimer(name: String?)
    case timerStatus
    case setAlarm(hour: Int, minute: Int, name: String?, repeating: Bool)
    case cancelAlarm(name: String?)
    case listAlarms
    case getTime
    case getDate
    case getBatteryStatus
    case getDiskSpace
    case getRunningApps
    case showWidget(id: String)
    case hideWidget(id: String)
    case enableVideoWallpaper
    case disableVideoWallpaper
    case openVYBELibrary
    case openControlCentre
    case deleteFile(path: String)
    case moveFile(from: String, to: String)
    case speak(text: String)
}

// MARK: - Action Result

struct ActionResult {
    let success: Bool
    let message: String
    let data: [String: Any]?

    init(success: Bool, message: String, data: [String: Any]? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }

    static func ok(_ message: String, data: [String: Any]? = nil) -> ActionResult {
        ActionResult(success: true, message: message, data: data)
    }
    static func fail(_ message: String) -> ActionResult {
        ActionResult(success: false, message: message)
    }
}

// MARK: - Timer Manager

@MainActor
final class VYBETimerManager: ObservableObject {
    static let shared = VYBETimerManager()
    @Published var activeTimers: [VYBETimer] = []

    struct VYBETimer: Identifiable {
        let id = UUID()
        let name: String
        let duration: TimeInterval
        let endDate: Date
        var timer: Timer?
        var remaining: TimeInterval { max(0, endDate.timeIntervalSinceNow) }
        var isExpired: Bool { remaining <= 0 }
    }

    private init() {}

    func startTimer(seconds: Int, name: String?) -> ActionResult {
        let timerName = name ?? "Timer \(activeTimers.count + 1)"
        let endDate = Date().addingTimeInterval(TimeInterval(seconds))
        var vybeTimer = VYBETimer(name: timerName, duration: TimeInterval(seconds), endDate: endDate)

        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timerFired(timerName)
            }
        }
        vybeTimer.timer = timer
        activeTimers.append(vybeTimer)

        let minutes = seconds / 60
        let secs = seconds % 60
        let timeStr = minutes > 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")\(secs > 0 ? " \(secs) seconds" : "")" : "\(secs) second\(secs == 1 ? "" : "s")"
        return .ok("Timer \"\(timerName)\" set for \(timeStr).")
    }

    func cancelTimer(name: String?) -> ActionResult {
        if let name {
            if let idx = activeTimers.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                activeTimers[idx].timer?.invalidate()
                activeTimers.remove(at: idx)
                return .ok("Timer \"\(name)\" cancelled.")
            }
            return .fail("No timer named \"\(name)\" found.")
        } else {
            if activeTimers.isEmpty { return .fail("No active timers to cancel.") }
            activeTimers.forEach { $0.timer?.invalidate() }
            let count = activeTimers.count
            activeTimers.removeAll()
            return .ok("Cancelled \(count) timer\(count == 1 ? "" : "s").")
        }
    }

    func getStatus() -> ActionResult {
        activeTimers.removeAll(where: { $0.isExpired })
        if activeTimers.isEmpty { return .ok("No active timers.") }
        let lines = activeTimers.map { timer in
            let r = Int(timer.remaining)
            return "• \(timer.name): \(r / 60)m \(r % 60)s remaining"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func timerFired(_ name: String) {
        activeTimers.removeAll(where: { $0.name == name })
        // Send notification
        let content = UNMutableNotificationContent()
        content.title = "VYBE Timer"
        content.body = "\"\(name)\" has finished!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        // Post for voice feedback
        NotificationCenter.default.post(name: .vybeTimerFired, object: nil, userInfo: ["name": name])
    }
}

// MARK: - Alarm Manager

@MainActor
final class VYBEAlarmManager: ObservableObject {
    static let shared = VYBEAlarmManager()
    @Published var alarms: [VYBEAlarm] = []

    struct VYBEAlarm: Identifiable, Codable {
        let id: UUID
        let name: String
        let hour: Int
        let minute: Int
        let repeating: Bool
        var enabled: Bool

        var nextFireDate: Date? {
            let cal = Calendar.current
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            guard let next = cal.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return nil }
            return next
        }

        var timeString: String {
            String(format: "%d:%02d %@", hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour), minute, hour >= 12 ? "PM" : "AM")
        }
    }

    private let storageKey = "VYBE.alarms"
    private var alarmTimers: [UUID: Timer] = [:]

    private init() { loadAlarms(); scheduleAll() }

    func setAlarm(hour: Int, minute: Int, name: String?, repeating: Bool) -> ActionResult {
        let alarmName = name ?? "Alarm at \(String(format: "%d:%02d", hour, minute))"
        let alarm = VYBEAlarm(id: UUID(), name: alarmName, hour: hour, minute: minute, repeating: repeating, enabled: true)
        alarms.append(alarm)
        saveAlarms()
        scheduleAlarm(alarm)
        return .ok("Alarm \"\(alarmName)\" set for \(alarm.timeString).\(repeating ? " It will repeat daily." : "")\n\nNote: This alarm works while VYBE is running. It cannot wake your Mac from sleep.")
    }

    func cancelAlarm(name: String?) -> ActionResult {
        if let name {
            if let idx = alarms.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                let alarm = alarms.remove(at: idx)
                alarmTimers[alarm.id]?.invalidate()
                alarmTimers[alarm.id] = nil
                saveAlarms()
                return .ok("Alarm \"\(name)\" cancelled.")
            }
            return .fail("No alarm named \"\(name)\" found.")
        } else {
            alarmTimers.values.forEach { $0.invalidate() }
            alarmTimers.removeAll()
            let count = alarms.count
            alarms.removeAll()
            saveAlarms()
            return .ok("Cancelled \(count) alarm\(count == 1 ? "" : "s").")
        }
    }

    func listAlarms() -> ActionResult {
        if alarms.isEmpty { return .ok("No alarms set.") }
        let lines = alarms.map { alarm in
            "• \(alarm.name) at \(alarm.timeString)\(alarm.repeating ? " (repeating)" : "")\(alarm.enabled ? "" : " [disabled]")"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    private func scheduleAlarm(_ alarm: VYBEAlarm) {
        guard let fireDate = alarm.nextFireDate else { return }
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.alarmFired(alarm) }
        }
        alarmTimers[alarm.id] = timer
    }

    private func scheduleAll() {
        alarmTimers.values.forEach { $0.invalidate() }
        alarmTimers.removeAll()
        for alarm in alarms where alarm.enabled { scheduleAlarm(alarm) }
    }

    private func alarmFired(_ alarm: VYBEAlarm) {
        let content = UNMutableNotificationContent()
        content.title = "VYBE Alarm"
        content.body = alarm.name
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        NotificationCenter.default.post(name: .vybeAlarmFired, object: nil, userInfo: ["name": alarm.name])

        if alarm.repeating {
            scheduleAlarm(alarm)
        } else {
            if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[idx].enabled = false
                saveAlarms()
            }
        }
    }

    private func saveAlarms() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadAlarms() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([VYBEAlarm].self, from: data) else { return }
        alarms = saved
    }
}

// MARK: - Application Launcher

@MainActor
struct ApplicationLauncher {
    // Known bundle identifiers for common apps
    private static let knownBundleIDs: [String: String] = [
        "safari": "com.apple.Safari",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "photos": "com.apple.Photos",
        "maps": "com.apple.Maps",
        "reminders": "com.apple.reminders",
        "notes": "com.apple.Notes",
        "terminal": "com.apple.Terminal",
        "contacts": "com.apple.AddressBook",
        "facetime": "com.apple.FaceTime",
        "preview": "com.apple.Preview",
        "calendar": "com.apple.iCal",
        "music": "com.apple.Music",
        "podcasts": "com.apple.podcasts",
        "books": "com.apple.iBooks",
        "weather": "com.apple.weather",
        "clock": "com.apple.clock",
        "xcode": "com.apple.dt.Xcode",
        "finder": "com.apple.finder",
        "system settings": "com.apple.systempreferences",
        "system preferences": "com.apple.systempreferences",
        "activity monitor": "com.apple.ActivityMonitor",
        "disk utility": "com.apple.DiskUtility",
        "spotify": "com.spotify.client",
        "whatsapp": "net.whatsapp.WhatsApp",
        "google chrome": "com.google.Chrome",
        "chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "slack": "com.tinyspeck.slackmacgap",
        "discord": "com.hnc.Discord",
        "zoom": "us.zoom.xos",
        "vscode": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2",
        "telegram": "ru.keepcoder.Telegram",
    ]

    static func openApplication(name: String) -> ActionResult {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try known bundle ID
        if let bundleID = knownBundleIDs[lowered],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
            return .ok("Opened \(name).")
        }

        // 2. Try system application paths
        let searchPaths = [
            "/System/Applications/\(name).app",
            "/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/Applications/Utilities/\(name).app",
        ]
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(url)
                return .ok("Opened \(name).")
            }
        }

        // 3. Try launchApplication (older API, broad search)
        if NSWorkspace.shared.launchApplication(name) {
            return .ok("Opened \(name).")
        }

        // 4. Try case-insensitive search in /Applications
        if let found = findApplicationCaseInsensitive(name) {
            NSWorkspace.shared.open(found)
            return .ok("Opened \(name).")
        }

        return .fail("I couldn't find an application called \"\(name)\" on your Mac. Please check the name and try again.")
    }

    private static func findApplicationCaseInsensitive(_ name: String) -> URL? {
        let directories = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        let lowered = name.lowercased()
        for dir in directories {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents {
                if item.lowercased().replacingOccurrences(of: ".app", with: "") == lowered {
                    return URL(fileURLWithPath: dir).appendingPathComponent(item)
                }
            }
        }
        return nil
    }
}

// MARK: - Finder Controller

@MainActor
struct FinderController {
    private static let knownFolders: [String: String] = [
        "downloads": "Downloads",
        "documents": "Documents",
        "desktop": "Desktop",
        "pictures": "Pictures",
        "movies": "Movies",
        "music": "Music",
        "home": "",
        "applications": "/Applications",
    ]

    static func openFolder(name: String) -> ActionResult {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let known = knownFolders[lowered] {
            let url: URL
            if known.hasPrefix("/") {
                url = URL(fileURLWithPath: known)
            } else if known.isEmpty {
                url = FileManager.default.homeDirectoryForCurrentUser
            } else {
                url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(known)
            }
            NSWorkspace.shared.open(url)
            return .ok("Opened \(name) folder.")
        }

        // Try as absolute path
        let path = (name as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return .ok("Opened \(path).")
        }

        // Try in home directory
        let homePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: homePath.path) {
            NSWorkspace.shared.open(homePath)
            return .ok("Opened \(name).")
        }

        return .fail("I couldn't find a folder called \"\(name)\". Try giving me the full path.")
    }
}

// MARK: - System Information

@MainActor
struct SystemInformation {
    static func getTime() -> ActionResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return .ok("The current time is \(formatter.string(from: Date())).")
    }

    static func getDate() -> ActionResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        return .ok("Today is \(formatter.string(from: Date())), \(time.string(from: Date())).")
    }

    static func getBatteryStatus() -> ActionResult {
        // Read battery info from IOKit via system_profiler
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                return .ok(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {}
        return .ok("Battery information is not available on this Mac.")
    }

    static func getDiskSpace() -> ActionResult {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return .ok("\(freeStr) available out of \(totalStr) total on the startup volume.")
        } catch {
            return .fail("Could not read disk space: \(error.localizedDescription)")
        }
    }

    static func getRunningApps() -> ActionResult {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
        if apps.isEmpty { return .ok("No visible applications are running.") }
        return .ok("Running applications:\n" + apps.map { "• \($0)" }.joined(separator: "\n"))
    }
}

// MARK: - Desktop Action Executor

@MainActor
final class DesktopActionExecutor {
    static let shared = DesktopActionExecutor()
    private init() {}

    func execute(_ action: DesktopAction) async -> ActionResult {
        let permission = ActionPermission.forAction(action)
        if permission == .denied {
            return .fail("This action is not permitted.")
        }
        if permission == .needsConfirm {
            let confirmed = await requestConfirmation(for: action)
            if !confirmed { return .fail("Action cancelled by user.") }
        }

        switch action {
        case .openApplication(let name):
            return ApplicationLauncher.openApplication(name: name)
        case .openFolder(let name):
            return FinderController.openFolder(name: name)
        case .openURL(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return .ok("Opened \(urlString).")
            }
            return .fail("Invalid URL: \(urlString)")
        case .startTimer(let seconds, let name):
            return VYBETimerManager.shared.startTimer(seconds: seconds, name: name)
        case .cancelTimer(let name):
            return VYBETimerManager.shared.cancelTimer(name: name)
        case .timerStatus:
            return VYBETimerManager.shared.getStatus()
        case .setAlarm(let hour, let minute, let name, let repeating):
            return VYBEAlarmManager.shared.setAlarm(hour: hour, minute: minute, name: name, repeating: repeating)
        case .cancelAlarm(let name):
            return VYBEAlarmManager.shared.cancelAlarm(name: name)
        case .listAlarms:
            return VYBEAlarmManager.shared.listAlarms()
        case .getTime:
            return SystemInformation.getTime()
        case .getDate:
            return SystemInformation.getDate()
        case .getBatteryStatus:
            return SystemInformation.getBatteryStatus()
        case .getDiskSpace:
            return SystemInformation.getDiskSpace()
        case .getRunningApps:
            return SystemInformation.getRunningApps()
        case .showWidget(let id):
            VYBEWidgetSelection.shared.toggle(id)
            return .ok("Widget \"\(id)\" toggled.")
        case .hideWidget(let id):
            if VYBEWidgetSelection.shared.selectedIDs.contains(id) {
                VYBEWidgetSelection.shared.toggle(id)
            }
            return .ok("Widget \"\(id)\" hidden.")
        case .enableVideoWallpaper:
            WallpaperEngine.shared.setVideoBackgroundEnabled(true)
            return .ok("Video wallpaper enabled.")
        case .disableVideoWallpaper:
            WallpaperEngine.shared.setVideoBackgroundEnabled(false)
            return .ok("Video wallpaper disabled. Your static background is now showing.")
        case .openVYBELibrary:
            DesktopEnvironment.shared.showControlCentre()
            return .ok("Opened the VYBE Control Centre.")
        case .openControlCentre:
            DesktopEnvironment.shared.showControlCentre()
            return .ok("Opened the VYBE Control Centre.")
        case .deleteFile, .moveFile:
            return .fail("File operations are restricted for safety. Please use Finder directly.")
        case .speak(let text):
            return .ok(text)
        }
    }

    private func requestConfirmation(for action: DesktopAction) async -> Bool {
        let description: String
        switch action {
        case .deleteFile(let path): description = "Delete file: \(path)"
        case .moveFile(let from, let to): description = "Move \(from) to \(to)"
        default: description = "Perform action"
        }

        let alert = NSAlert()
        alert.messageText = "Confirm Action"
        alert.informativeText = "VYBE AI wants to: \(description)\n\nDo you want to allow this?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Intent Parser (for models without tool calling)

@MainActor
struct IntentParser {

    /// Tool definitions for OpenRouter function calling
    static let toolDefinitions: [[String: Any]] = [
        makeTool("open_application", "Open a macOS application by name", [
            "name": ["type": "string", "description": "The application name, e.g. Safari, Spotify, Xcode"]
        ], required: ["name"]),
        makeTool("open_folder", "Open a folder in Finder", [
            "name": ["type": "string", "description": "Folder name like Downloads, Documents, Desktop, or a path"]
        ], required: ["name"]),
        makeTool("start_timer", "Start a countdown timer", [
            "seconds": ["type": "integer", "description": "Duration in seconds"],
            "name": ["type": "string", "description": "Optional name for the timer"]
        ], required: ["seconds"]),
        makeTool("cancel_timer", "Cancel an active timer", [
            "name": ["type": "string", "description": "Timer name to cancel, or omit to cancel all"]
        ], required: []),
        makeTool("timer_status", "Check remaining time on active timers", [:], required: []),
        makeTool("set_alarm", "Set an alarm for a specific time", [
            "hour": ["type": "integer", "description": "Hour in 24-hour format (0-23)"],
            "minute": ["type": "integer", "description": "Minute (0-59)"],
            "name": ["type": "string", "description": "Optional alarm name"],
            "repeating": ["type": "boolean", "description": "Whether the alarm repeats daily"]
        ], required: ["hour", "minute"]),
        makeTool("cancel_alarm", "Cancel an alarm", [
            "name": ["type": "string", "description": "Alarm name to cancel, or omit to cancel all"]
        ], required: []),
        makeTool("list_alarms", "List all set alarms", [:], required: []),
        makeTool("get_time", "Get the current time", [:], required: []),
        makeTool("get_date", "Get the current date and time", [:], required: []),
        makeTool("get_battery_status", "Get battery information", [:], required: []),
        makeTool("get_disk_space", "Get available disk space", [:], required: []),
        makeTool("get_running_apps", "List currently running applications", [:], required: []),
        makeTool("enable_video_wallpaper", "Turn on the video wallpaper", [:], required: []),
        makeTool("disable_video_wallpaper", "Turn off the video wallpaper and show static background", [:], required: []),
        makeTool("open_control_centre", "Open the VYBE Control Centre window", [:], required: []),
    ]

    private static func makeTool(_ name: String, _ desc: String, _ props: [String: [String: Any]], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": desc,
                "parameters": [
                    "type": "object",
                    "properties": props,
                    "required": required
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    /// Parse a tool call from OpenRouter response into a DesktopAction
    static func parseToolCall(_ call: ToolCall) -> DesktopAction? {
        guard let function = call.function else { return nil }
        let args = (try? JSONSerialization.jsonObject(with: Data(function.arguments.utf8))) as? [String: Any] ?? [:]

        switch function.name {
        case "open_application":
            guard let name = args["name"] as? String else { return nil }
            return .openApplication(name: name)
        case "open_folder":
            guard let name = args["name"] as? String else { return nil }
            return .openFolder(name: name)
        case "start_timer":
            guard let seconds = args["seconds"] as? Int else { return nil }
            return .startTimer(seconds: seconds, name: args["name"] as? String)
        case "cancel_timer":
            return .cancelTimer(name: args["name"] as? String)
        case "timer_status":
            return .timerStatus
        case "set_alarm":
            guard let hour = args["hour"] as? Int, let minute = args["minute"] as? Int else { return nil }
            return .setAlarm(hour: hour, minute: minute, name: args["name"] as? String, repeating: args["repeating"] as? Bool ?? false)
        case "cancel_alarm":
            return .cancelAlarm(name: args["name"] as? String)
        case "list_alarms":
            return .listAlarms
        case "get_time":
            return .getTime
        case "get_date":
            return .getDate
        case "get_battery_status":
            return .getBatteryStatus
        case "get_disk_space":
            return .getDiskSpace
        case "get_running_apps":
            return .getRunningApps
        case "enable_video_wallpaper":
            return .enableVideoWallpaper
        case "disable_video_wallpaper":
            return .disableVideoWallpaper
        case "open_control_centre":
            return .openControlCentre
        default:
            return nil
        }
    }

    /// Parse intent from plain text (handles local desktop actions with zero network/rate limits)
    static func parseFromText(_ text: String) -> DesktopAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Strip polite prefixes like "please", "can you", "could you"
        var clean = lower
        let prefixesToStrip = ["please ", "can you ", "could you ", "would you ", "hey vybe ", "vybe "]
        for p in prefixesToStrip {
            if clean.hasPrefix(p) { clean = String(clean.dropFirst(p.count)) }
        }

        // 1. Time queries
        if clean == "time" || clean == "what time is it" || clean == "what's the time" ||
           clean == "what time is it?" || clean == "what's the time?" ||
           clean.contains("what time") || clean.contains("current time") || clean.contains("tell me the time") {
            return .getTime
        }

        // 2. Date queries
        if clean == "date" || clean == "what date is it" || clean == "what's the date" ||
           clean == "what day is today" || clean == "what day is it" ||
           clean.contains("today's date") || clean.contains("what is today's date") {
            return .getDate
        }

        // 3. Battery status
        if clean.contains("battery") {
            return .getBatteryStatus
        }

        // 4. Disk space / storage
        if clean.contains("disk space") || clean.contains("storage") || clean.contains("free space") {
            return .getDiskSpace
        }

        // 5. Running applications
        if clean.contains("running app") || clean == "what apps are running" {
            return .getRunningApps
        }

        // 6. Wallpaper controls
        if clean.contains("video wallpaper") || clean.contains("video background") {
            if clean.contains("enable") || clean.contains("turn on") || clean.contains("start") || clean.contains("on") || clean.contains("play") {
                return .enableVideoWallpaper
            }
            if clean.contains("disable") || clean.contains("turn off") || clean.contains("stop") || clean.contains("off") {
                return .disableVideoWallpaper
            }
        }
        if clean.contains("static wallpaper") || clean.contains("static background") || clean.contains("default background") {
            return .disableVideoWallpaper
        }

        // 7. VYBE Control Centre
        if clean.contains("control centre") || clean.contains("control center") || clean == "open settings" {
            return .openControlCentre
        }

        // 8. Timers
        if clean.contains("timer") {
            if clean.contains("cancel") || clean.contains("stop") || clean.contains("delete") || clean.contains("clear") {
                return .cancelTimer(name: nil)
            }
            if clean.contains("status") || clean.contains("how much") || clean.contains("how long") || clean.contains("left") || clean.contains("remaining") {
                return .timerStatus
            }
            if let seconds = extractSeconds(from: clean) {
                return .startTimer(seconds: seconds, name: nil)
            }
        }

        // 9. Alarms
        if clean.contains("alarm") {
            if clean.contains("cancel") || clean.contains("stop") || clean.contains("delete") {
                return .cancelAlarm(name: nil)
            }
            if clean.contains("list") || clean.contains("show") || clean.contains("what") {
                return .listAlarms
            }
            if let (hour, minute) = extractAlarmTime(from: clean) {
                return .setAlarm(hour: hour, minute: minute, name: nil, repeating: clean.contains("daily") || clean.contains("every day") || clean.contains("repeating"))
            }
        }

        // 10. Open Folders or Applications
        // Supports: "open safari", "launch spotify", "start xcode", "open app safari", "open my downloads"
        var targetToOpen: String? = nil
        let openTriggers = ["open app ", "open the app ", "open folder ", "open the folder ", "open my ", "open ", "launch ", "start "]
        for trigger in openTriggers {
            if clean.hasPrefix(trigger) {
                targetToOpen = String(clean.dropFirst(trigger.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if let target = targetToOpen, !target.isEmpty {
            let folderKeywords = ["downloads", "documents", "desktop", "pictures", "movies", "music", "home", "applications"]
            let cleanFolder = target.replacingOccurrences(of: " folder", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if folderKeywords.contains(cleanFolder) || target.contains("folder") {
                return .openFolder(name: cleanFolder)
            }
            let cleanApp = target.replacingOccurrences(of: " app", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .openApplication(name: cleanApp)
        }

        return nil
    }

    private static func extractAlarmTime(from text: String) -> (Int, Int)? {
        // e.g. "7 am", "7:30 pm", "19:00", "at 6:45"
        let pattern = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        
        guard let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else { return nil }

        var minute = 0
        if match.range(at: 2).location != NSNotFound,
           let minRange = Range(match.range(at: 2), in: text),
           let m = Int(text[minRange]) {
            minute = m
        }

        if match.range(at: 3).location != NSNotFound,
           let ampmRange = Range(match.range(at: 3), in: text) {
            let ampm = text[ampmRange].lowercased()
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        }

        return (hour, minute)
    }

    private static func extractSeconds(from text: String) -> Int? {
        let patterns: [(String, Int)] = [
            ("(\\d+)\\s*hour", 3600),
            ("(\\d+)\\s*min", 60),
            ("(\\d+)\\s*sec", 1),
        ]
        var total = 0
        for (pattern, multiplier) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let value = Int(text[range]) {
                total += value * multiplier
            }
        }
        // Plain number like "set a timer for 5"
        if total == 0 {
            if let regex = try? NSRegularExpression(pattern: "(\\d+)", options: []),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let value = Int(text[range]) {
                // If it looks like minutes (most natural), use minutes
                if text.lowercased().contains("timer") { total = value * 60 }
                else { total = value }
            }
        }
        return total > 0 ? total : nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let vybeTimerFired = Notification.Name("VYBETimerFired")
    static let vybeAlarmFired = Notification.Name("VYBEAlarmFired")
}
