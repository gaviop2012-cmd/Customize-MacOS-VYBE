import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DesktopEnvironment {
    static let shared = DesktopEnvironment()

    private var widgetPanels: [NSPanel] = []
    private var dockPanel: NSPanel?
    private var desktopAppPanels: [NSPanel] = []
    private var hudPanel: NSPanel?

    private init() {}

    func start() {
        VYBEBackgroundPresets.shared.apply(VYBEBackgroundPresets.shared.selectedName)
        showWidgets()
        showDesktopApplications()
        showDock()
        showHUD()
    }

    private func showHUD() {
        guard hudPanel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let panel = NSPanel(contentRect: NSRect(x: frame.midX - 150, y: frame.maxY - 105, width: 300, height: 78),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: VYBEHUDView())
        hudPanel = panel
        panel.orderFrontRegardless()
    }

    func refreshDesktopApplications() {
        desktopAppPanels.forEach { $0.close() }
        desktopAppPanels.removeAll()
        showDesktopApplications()
    }

    func refreshWidgets() {
        widgetPanels.forEach { $0.close() }
        widgetPanels.removeAll()
        showWidgets()
    }

    func showWidgets() {
        guard widgetPanels.isEmpty else { widgetPanels.forEach { $0.orderFrontRegardless() }; return }
        let selected = VYBEWidgetSelection.shared.selectedIDs.sorted()
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            let screenKey = Self.screenKey(screen)
            for (index, widgetID) in selected.enumerated() {
                let column = index % 3; let row = index / 3
                let size = NSSize(width: widgetID == "note" ? 250 : 220, height: widgetID == "calendar" ? 230 : (widgetID == "note" ? 185 : 132))
                let origin = NSPoint(x: frame.maxX - 250 - CGFloat(column) * 238, y: frame.maxY - 155 - CGFloat(row) * 150)
                let panelID = "widget-\(widgetID)-\(screenKey)"
                let panel = makeWidgetPanel(id: panelID, content: AnyView(WidgetCard(id: widgetID)), size: size, defaultOrigin: origin)
                widgetPanels.append(panel)
                panel.orderFrontRegardless()
            }
        }
    }

    func showDesktopApplications() {
        guard desktopAppPanels.isEmpty else {
            desktopAppPanels.forEach { $0.orderFrontRegardless() }
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let apps = DockApplications.shared.desktopApplications + DockApplications.shared.desktopFolders
        let columns = 2
        for (index, appURL) in apps.enumerated() {
            let column = index % columns
            let row = index / columns
            let origin = NSPoint(x: visible.minX + 26 + CGFloat(column) * 104,
                                 y: visible.maxY - 132 - CGFloat(row) * 112)
            let panel = makeWidgetPanel(
                id: "desktop-app-\(appURL.path.hashValue)",
                content: AnyView(VYBEDesktopAppIcon(url: appURL, isFolder: DockApplications.shared.desktopFolders.contains(appURL)) {
                    NSWorkspace.shared.open(appURL)
                }),
                size: NSSize(width: 88, height: 96),
                defaultOrigin: origin,
                level: desktopOverlayLevel
            )
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            desktopAppPanels.append(panel)
            panel.orderFrontRegardless()
        }
    }

    func showDock() {
        if let existing = dockPanel {
            existing.setFrame(dockFrame(for: existing.frame), display: true, animate: false)
            existing.orderFrontRegardless()
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = calculatedDockSize()
        let visible = screen.visibleFrame
        let defaultOrigin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 12)
        let saved = UserDefaults.standard.string(forKey: "VYBE.dockFrame.v2").flatMap { NSRectFromString($0).isEmpty ? nil : NSRectFromString($0) }
        let restoredOrigin = saved.map { NSPoint(x: $0.midX - size.width / 2, y: $0.minY) } ?? defaultOrigin
        let safeOrigin = Self.ensureOnScreen(rect: NSRect(origin: restoredOrigin, size: size), defaultOrigin: defaultOrigin).origin
        let panel = DesktopWidgetPanel(contentRect: NSRect(origin: safeOrigin, size: size),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("dock-v2")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = dockLevel
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = DraggableHostingView(rootView: AnyView(VYBEDockView()))
        panel.delegate = WindowFramePersistence.shared
        dockPanel = panel
        panel.orderFrontRegardless()
    }

    func toggleDockVisibility() {
        if let panel = dockPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showDock()
        }
    }

    func resizeDockToFitContents() {
        guard let panel = dockPanel else { return }
        let nextFrame = dockFrame(for: panel.frame)
        guard abs(panel.frame.width - nextFrame.width) > 0.5 else { return }
        panel.setFrame(nextFrame, display: true, animate: true)
    }

    private func calculatedDockSize() -> NSSize {
        let apps = DockApplications.shared.dockApplications
        let itemWidths = apps.reduce(CGFloat.zero) { partial, url in
            let title = url.deletingPathExtension().lastPathComponent
            let estimated = CGFloat(title.count) * 6.2 + 68
            return partial + min(max(estimated, 88), 176) + 7
        }
        // Two drag handles, add button, outer padding and inter-item spacing.
        let chrome: CGFloat = 18 + 18 + 38 + 8 * 5 + 16
        let width = min(max(154, itemWidths + chrome), 1100)
        return NSSize(width: width, height: 94)
    }

    private func dockFrame(for currentFrame: NSRect) -> NSRect {
        let size = calculatedDockSize()
        // Keep the Dock's horizontal centre and bottom edge fixed while resizing.
        return NSRect(x: currentFrame.midX - size.width / 2,
                      y: currentFrame.minY,
                      width: size.width,
                      height: size.height)
    }

    func showControlCentre() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "vybe-control-centre" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .vybeOpenControlCentre, object: nil)
        }
    }

    private var desktopOverlayLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    // Widgets sit on the desktop layer above Finder desktop icons and wallpaper,
    // ensuring mouse clicks are received directly by widgets instead of being consumed by Finder.
    private var widgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private var dockLevel: NSWindow.Level {
        .floating
    }

    // MARK: - Widget Panel Factory (Fixed Dragging)

    /// Creates a borderless panel configured for smooth, native AppKit window dragging.
    private func makeWidgetPanel(id: String, content: AnyView, size: NSSize, defaultOrigin: NSPoint,
                                  level: NSWindow.Level? = nil) -> NSPanel {
        let panelLevel = level ?? widgetLevel
        let saved = UserDefaults.standard.string(forKey: "VYBE.panel.\(id)").flatMap {
            NSRectFromString($0).isEmpty ? nil : NSRectFromString($0)
        }
        let safeOrigin = Self.ensureOnScreen(rect: NSRect(origin: saved?.origin ?? defaultOrigin, size: size), defaultOrigin: defaultOrigin).origin
        let panel = DesktopWidgetPanel(
            contentRect: NSRect(origin: safeOrigin, size: saved?.size ?? size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier(id)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = panelLevel
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.delegate = WindowFramePersistence.shared
        panel.contentView = DraggableHostingView(rootView: content)
        return panel
    }

    private static func ensureOnScreen(rect: NSRect, defaultOrigin: NSPoint) -> NSRect {
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(rect) {
                return rect
            }
        }
        return NSRect(origin: defaultOrigin, size: rect.size)
    }

    private static func screenKey(_ screen: NSScreen) -> String {
        String(screen.localizedName.filter { $0.isLetter || $0.isNumber })
    }
}

// MARK: - Window Frame Persistence (Debounced)

@MainActor
final class WindowFramePersistence: NSObject, NSWindowDelegate {
    static let shared = WindowFramePersistence()
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    func windowDidMove(_ notification: Notification) { debouncedSave(notification) }
    func windowDidResize(_ notification: Notification) { debouncedSave(notification) }

    /// Debounces position writes: only persists 300ms after the last move event.
    /// This eliminates the per-pixel UserDefaults writes that caused drag jitter.
    private func debouncedSave(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        pendingSaves[id]?.cancel()
        let frame = window.frame
        let work = DispatchWorkItem { [weak self] in
            let key = id == "dock-v2" ? "VYBE.dockFrame.v2" : "VYBE.panel.\(id)"
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: key)
            self?.pendingSaves[id] = nil
        }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: work)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let vybeOpenControlCentre = Notification.Name("VYBEOpenControlCentre")
}

// MARK: - Widget Selection

@MainActor
final class VYBEWidgetSelection: ObservableObject {
    static let shared = VYBEWidgetSelection()
    static let catalog: [(String, String, String)] = [
        ("clock", "Clock", "clock"), ("date", "Date & Day", "calendar"), ("note", "Quick Notes", "note.text"),
        ("calendar", "Monthly Calendar", "calendar.month"), ("timer", "Countdown Timer", "timer"), ("stopwatch", "Stopwatch", "stopwatch"),
        ("battery", "Battery", "battery.100"), ("system", "System Overview", "desktopcomputer"), ("storage", "Storage", "internaldrive"),
        ("network", "Network Status", "wifi"), ("worldclock", "World Clock (UTC)", "globe"), ("quote", "Daily Thought", "quote.opening"),
        ("calculator", "Calculator", "plus.forwardslash.minus"), ("countdown", "Year Progress", "chart.bar"), ("focus", "Focus Session", "brain.head.profile"),
        ("launchpad", "Quick Launch", "app"), ("music", "Media Shortcuts", "music.note"), ("timezone", "Time Zones", "clock.badge"),
        ("memory", "Memory Info", "memorychip"), ("disk", "Disk Space", "externaldrive"),
        ("downloads", "Downloads Folder", "arrow.down.circle"), ("documents", "Documents Folder", "doc.text"),
        ("screenshots", "Screenshots Folder", "camera.viewfinder"), ("trash", "Trash", "trash"),
        ("reminders", "Reminders", "checklist"), ("mail", "Mail", "envelope"), ("messages", "Messages", "message"),
        ("photos", "Photos", "photo"), ("maps", "Maps", "map"), ("settings", "System Settings", "gear"),
        ("terminal", "Terminal", "terminal"), ("safari", "Safari", "safari"), ("contacts", "Contacts", "person.crop.circle"),
        ("notesapp", "Apple Notes", "note.text"), ("facetime", "FaceTime", "video"), ("preview", "Preview", "doc.richtext"),
        ("activitymonitor", "Activity Monitor", "waveform.path.ecg"), ("diskutility", "Disk Utility", "externaldrive"),
        ("bluetooth", "Bluetooth Settings", "bluetooth"), ("wifi", "Wi-Fi Settings", "wifi"),
        ("spotify", "Spotify", "waveform"), ("whatsapp", "WhatsApp", "message.fill"),
        ("books", "Apple Books", "book.closed.fill"), ("weather", "Weather", "cloud.sun.fill"),
        ("clockapp", "Clock", "clock.fill")
    ]
    @Published private(set) var selectedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "VYBE.selectedWidgets") ?? ["clock", "note"])
    private init() {}
    func toggle(_ id: String) {
        var next = selectedIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setSelection(next)
        VYBESpaceManager.shared.saveCurrentConfiguration()
    }

    func setSelection(_ ids: Set<String>) {
        selectedIDs = ids
        UserDefaults.standard.set(Array(ids), forKey: "VYBE.selectedWidgets")
        DesktopEnvironment.shared.refreshWidgets()
    }
}

// MARK: - UTC Clock Helper

private func utcClockString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

// MARK: - Widget Card

private struct WidgetCard: View {
    let id: String
    @AppStorage("VYBE.desktopNote") private var note = "Your space. Your rhythm."
    @State private var calculatorInput = ""
    @State private var focusSeconds = 1500
    @State private var timerRunning = false
    private var title: String { VYBEWidgetSelection.catalog.first(where: { $0.0 == id })?.1 ?? "Widget" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                Spacer()
                Image(systemName: VYBEWidgetSelection.catalog.first(where: { $0.0 == id })?.2 ?? "square")
            }
            .foregroundStyle(.white.opacity(0.65))
            .padding(.vertical, 2)
            .background(WindowDragHandle())

            content
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(.ultraThinMaterial.opacity(0.78))
                WindowDragHandle()
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.13), lineWidth: 1))
    }
    @ViewBuilder private var content: some View {
        switch id {
        case "clock": TimelineView(.periodic(from: .now, by: 1)) { c in Text(c.date, format: .dateTime.hour().minute()).font(.system(size: 39, weight: .light, design: .rounded)).monospacedDigit() }
        case "date": TimelineView(.periodic(from: .now, by: 30)) { c in Text(c.date, format: .dateTime.weekday(.wide).month(.wide).day().year()).font(.system(size: 19, weight: .medium)); Text(c.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.white.opacity(0.65)) }
        case "note": TextEditor(text: $note).font(.system(size: 13)).scrollContentBackground(.hidden).foregroundStyle(.white).background(.clear)
        case "calendar": CalendarGridView()
        case "timer": CountdownWidget(initialSeconds: 300)
        case "stopwatch": StopwatchWidget()
        case "battery": BatteryWidgetContent()
        case "system": Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.system(size: 12)); Text("\(ProcessInfo.processInfo.processorCount) logical CPU cores").font(.caption)
        case "storage", "disk": StorageWidgetContent()
        case "network": Label("Network interfaces managed by macOS", systemImage: "network").font(.system(size: 12)); Text("Open System Settings → Network for connection details.").font(.caption).foregroundStyle(.white.opacity(0.6))
        case "worldclock", "timezone": TimelineView(.periodic(from: .now, by: 1)) { c in Text(utcClockString(c.date)).font(.system(size: 29, weight: .light, design: .rounded)); Text("UTC · Coordinated Universal Time").font(.caption) }
        case "quote": Text("\u{201C}Great things are done by a series of small things brought together.\u{201D}").font(.system(size: 14, weight: .medium, design: .serif)); Text("— Vincent van Gogh").font(.caption).foregroundStyle(.white.opacity(0.6))
        case "calculator": TextField("Type a calculation", text: $calculatorInput).textFieldStyle(.roundedBorder); Text("Basic arithmetic · use Spotlight for advanced calculations").font(.caption2).foregroundStyle(.white.opacity(0.55))
        case "countdown": TimelineView(.periodic(from: .now, by: 60)) { c in let day = Calendar.current.ordinality(of: .day, in: .year, for: c.date) ?? 1; Text("\(Int(Double(day) / 365.0 * 100))%").font(.system(size: 38, weight: .light)); ProgressView(value: Double(day), total: 365) }
        case "focus": CountdownWidget(initialSeconds: 1500)
        case "launchpad": Button("Open Applications") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications")) }.buttonStyle(.bordered)
        case "music": HStack { Button { NSWorkspace.shared.launchApplication("Music") } label: { Label("Open Music", systemImage: "music.note") }.buttonStyle(.bordered); Button { NSWorkspace.shared.launchApplication("Podcasts") } label: { Image(systemName: "podcasts") }.buttonStyle(.bordered) }
        case "memory": Text(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)).font(.system(size: 25, weight: .light)); Text("Installed physical memory").font(.caption)
        case "downloads": launchFolder("Downloads")
        case "documents": launchFolder("Documents")
        case "screenshots": launchFolder("Desktop")
        case "trash": Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }.buttonStyle(.bordered)
        case "reminders": launchApp("Reminders")
        case "mail": launchApp("Mail")
        case "messages": launchApp("Messages")
        case "photos": launchApp("Photos")
        case "maps": launchApp("Maps")
        case "settings": Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!) }.buttonStyle(.bordered)
        case "terminal": launchApp("Terminal")
        case "safari": launchApp("Safari")
        case "spotify": launchApp("Spotify")
        case "whatsapp": launchApp("WhatsApp")
        case "books": launchApp("Books")
        case "weather": launchApp("Weather")
        case "clockapp": launchApp("Clock")
        case "contacts": launchApp("Contacts")
        case "notesapp": launchApp("Notes")
        case "facetime": launchApp("FaceTime")
        case "preview": launchApp("Preview")
        case "activitymonitor": launchApp("Activity Monitor")
        case "diskutility": launchApp("Disk Utility")
        case "bluetooth": Button("Bluetooth Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }.buttonStyle(.bordered)
        case "wifi": Button("Wi-Fi Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!) }.buttonStyle(.bordered)
        default: Text("A lightweight desktop companion.").font(.caption)
        }
    }
    @ViewBuilder private func launchApp(_ name: String) -> some View {
        Button("Open \(name)") { if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(for: name)) { NSWorkspace.shared.open(app) } else { NSWorkspace.shared.launchApplication(name) } }.buttonStyle(.bordered)
    }
    private func bundleID(for name: String) -> String {
        let ids = ["Safari":"com.apple.Safari", "Mail":"com.apple.mail", "Messages":"com.apple.Messages", "Photos":"com.apple.Photos", "Maps":"com.apple.Maps", "Reminders":"com.apple.reminders", "Terminal":"com.apple.Terminal", "Contacts":"com.apple.AddressBook", "Notes":"com.apple.Notes", "FaceTime":"com.apple.FaceTime", "Preview":"com.apple.Preview", "Activity Monitor":"com.apple.ActivityMonitor", "Disk Utility":"com.apple.DiskUtility", "Spotify":"com.spotify.client", "WhatsApp":"net.whatsapp.WhatsApp", "Books":"com.apple.iBooks", "Weather":"com.apple.weather", "Clock":"com.apple.clock"]
        return ids[name] ?? ""
    }
    @ViewBuilder private func launchFolder(_ name: String) -> some View {
        Button("Open \(name)") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true)) }.buttonStyle(.bordered)
    }
}


private struct CountdownWidget: View {
    let initialSeconds: Int
    @State private var endDate: Date?
    @State private var pausedRemaining: Int?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, pausedRemaining ?? (endDate.map { Int($0.timeIntervalSince(context.date)) } ?? initialSeconds))
            VStack(alignment: .leading, spacing: 7) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                HStack {
                    Button(endDate == nil ? "Start" : "Pause") {
                        if let end = endDate { pausedRemaining = max(0, Int(end.timeIntervalSinceNow)); endDate = nil }
                        else { endDate = Date().addingTimeInterval(TimeInterval(pausedRemaining ?? initialSeconds)); pausedRemaining = nil }
                    }.buttonStyle(.bordered)
                    Button("Reset") { endDate = nil; pausedRemaining = nil }.buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct StopwatchWidget: View {
    @State private var startedAt: Date?
    @State private var accumulated: TimeInterval = 0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = accumulated + (startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
            VStack(alignment: .leading, spacing: 7) {
                Text(String(format: "%02d:%02d.%d", Int(elapsed) / 60, Int(elapsed) % 60, Int((elapsed * 10).truncatingRemainder(dividingBy: 10))))
                    .font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                HStack {
                    Button(startedAt == nil ? "Start" : "Pause") {
                        if let start = startedAt { accumulated += Date().timeIntervalSince(start); startedAt = nil }
                        else { startedAt = Date() }
                    }.buttonStyle(.bordered)
                    Button("Reset") { startedAt = nil; accumulated = 0 }.buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct CalendarGridView: View {
    var body: some View {
        let first = Calendar.current.component(.weekday, from: Calendar.current.date(from: Calendar.current.dateComponents([.year,.month], from: Date())) ?? Date()) - 1
        let count = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(0..<first, id: \.self) { _ in Text(" ") }
            ForEach(1...count, id: \.self) { day in
                Text("\(day)").font(.system(size: 10)).frame(maxWidth: .infinity).padding(2)
                    .background(day == Calendar.current.component(.day, from: Date()) ? Color.accentColor.opacity(0.65) : .clear, in: Circle())
            }
        }
    }
}

private struct BatteryWidgetContent: View {
    var body: some View {
        Text("Battery readings are provided by macOS when available.").font(.system(size: 12))
        Button("Open Battery Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }.buttonStyle(.bordered)
    }
}

private struct StorageWidgetContent: View {
    var body: some View {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        Text(ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " available").font(.system(size: 22, weight: .light))
        Text("On the startup volume").font(.caption).foregroundStyle(.white.opacity(0.6))
    }
}



// MARK: - Native Window Dragging & Hosting

/// Dedicated AppKit drag handle view that starts native window dragging
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

final class DragHandleNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    private var initialLocation: NSPoint = .zero
    private var initialOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let dragSelector = NSSelectorFromString("performWindowDragWithEvent:")
        if let window = self.window, window.responds(to: dragSelector) {
            window.perform(dragSelector, with: event)
            return
        }
        initialLocation = NSEvent.mouseLocation
        if let window = self.window {
            initialOrigin = window.frame.origin
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: initialOrigin.x + (current.x - initialLocation.x),
                                      y: initialOrigin.y + (current.y - initialLocation.y)))
    }
}

final class DraggableHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
    private var initialLocation: NSPoint = .zero
    private var initialOrigin: NSPoint = .zero
    private var isDraggingWindow = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(point), hit !== self && (hit is NSTextView || hit is NSTextField) {
            super.mouseDown(with: event)
            return
        }
        let dragSelector = NSSelectorFromString("performWindowDragWithEvent:")
        if let window, window.responds(to: dragSelector) {
            window.perform(dragSelector, with: event)
            return
        }
        initialLocation = NSEvent.mouseLocation
        if let window {
            initialOrigin = window.frame.origin
        }
        isDraggingWindow = true
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(point), hit !== self && (hit is NSTextView || hit is NSTextField) {
            super.mouseDragged(with: event)
            return
        }
        if isDraggingWindow, let window {
            let current = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: initialOrigin.x + (current.x - initialLocation.x),
                                          y: initialOrigin.y + (current.y - initialLocation.y)))
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingWindow = false
        super.mouseUp(with: event)
    }
}

// MARK: - Desktop Widget Panel

final class DesktopWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isMovable: Bool {
        get { true }
        set {}
    }
}

// MARK: - Native Application Icons

private final class VYBEIconCache {
    static let shared = VYBEIconCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct VYBEApplicationIcon: View {
    let url: URL
    var isFolder: Bool = false

    var body: some View {
        let icon = VYBEIconCache.shared.image(for: url)
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(isFolder ? 2 : 0)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

private struct VYBEDesktopAppIcon: View {
    let url: URL
    var isFolder: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                VYBEApplicationIcon(url: url, isFolder: isFolder)
                    .frame(width: 54, height: 54)
                Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 10, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(.ultraThinMaterial.opacity(0.28))
                    WindowDragHandle()
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Remove from VYBE Desktop", role: .destructive) { if isFolder { DockApplications.shared.removeDesktopFolder(url) } else { DockApplications.shared.removeDesktopApplication(url) }; DesktopEnvironment.shared.refreshDesktopApplications() } }
    }
}

// MARK: - Dock View

private struct VYBEDockView: View {
    @ObservedObject private var applications = DockApplications.shared
    var body: some View {
        HStack(spacing: 8) {
            // Leading drag handle
            WindowDragHandle()
                .frame(width: 18, height: 44)
                .overlay(
                    VStack(spacing: 3) {
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                    }
                )
                .help("Drag to reposition VYBE Dock")

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 7) {
                ForEach(applications.dockApplications, id: \.path) { url in
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 8) {
                            VYBEApplicationIcon(url: url, isFolder: false).frame(width: 36, height: 36)
                            Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 10)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .draggable(url.path)
                    .dropDestination(for: String.self) { paths, _ in
                        guard let source = paths.first else { return false }
                        applications.moveDockApplication(sourcePath: source, before: url)
                        return true
                    }
                    .contextMenu { Button("Remove from VYBE Dock", role: .destructive) { applications.removeDockApplication(url) } }
                }
                Button { applications.addApplication(to: .dock) } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 38, height: 38).background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).help("Choose apps for VYBE Dock")
              }
            }

            // Trailing drag handle
            WindowDragHandle()
                .frame(width: 18, height: 44)
                .overlay(
                    VStack(spacing: 3) {
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                    }
                )
                .help("Drag to reposition VYBE Dock")
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.055, green: 0.065, blue: 0.09).opacity(0.94))
                WindowDragHandle()
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.19), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }
}

// MARK: - Dock Applications

@MainActor
final class DockApplications: ObservableObject {
    static let shared = DockApplications()
    @Published private(set) var dockApplications: [URL] = []
    @Published private(set) var desktopApplications: [URL] = []
    @Published private(set) var desktopFolders: [URL] = []
    private let dockKey = "VYBE.dockApplicationPaths.v2"
    private let desktopKey = "VYBE.desktopApplicationPaths.v1"
    private let foldersKey = "VYBE.desktopFolderPaths.v1"

    enum Destination: Equatable { case dock, desktop }

    private init() {
        let defaults = ["/System/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Calendar.app"]
        dockApplications = (UserDefaults.standard.stringArray(forKey: dockKey) ?? defaults).map { URL(fileURLWithPath: $0).standardizedFileURL }.filter { FileManager.default.fileExists(atPath: $0.path) }
        desktopApplications = (UserDefaults.standard.stringArray(forKey: desktopKey) ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL }.filter { FileManager.default.fileExists(atPath: $0.path) }
        desktopFolders = (UserDefaults.standard.stringArray(forKey: foldersKey) ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addApplication(to destination: Destination) {
        let picker = NSOpenPanel()
        picker.title = destination == .dock ? "Choose apps for VYBE Dock" : "Choose apps to show on VYBE Desktop"
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        for url in picker.urls {
            let standardized = url.standardizedFileURL
            switch destination {
            case .dock: if !dockApplications.contains(standardized) { dockApplications.append(standardized) }
            case .desktop: if !desktopApplications.contains(standardized) { desktopApplications.append(standardized) }
            }
        }
        persist()
        if destination == .desktop { DesktopEnvironment.shared.refreshDesktopApplications() }
    }

    func removeDockApplication(_ url: URL) { dockApplications.removeAll { $0 == url }; persist() }
    func moveDockApplication(sourcePath: String, before target: URL) {
        guard let sourceIndex = dockApplications.firstIndex(where: { $0.path == sourcePath }),
              dockApplications.contains(target), dockApplications[sourceIndex] != target else { return }
        let item = dockApplications.remove(at: sourceIndex)
        let targetIndex = dockApplications.firstIndex(of: target) ?? dockApplications.count
        dockApplications.insert(item, at: targetIndex)
        persist()
    }
    func addFolderToDesktop() {
        let picker = NSOpenPanel(); picker.title = "Choose folders for VYBE Desktop"; picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        for url in picker.urls.map(\.standardizedFileURL) where !desktopFolders.contains(url) { desktopFolders.append(url) }
        persist(); DesktopEnvironment.shared.refreshDesktopApplications()
    }
    func removeDesktopFolder(_ url: URL) { desktopFolders.removeAll { $0 == url }; persist() }
    func removeDesktopApplication(_ url: URL) { desktopApplications.removeAll { $0 == url }; persist() }
    private func persist() {
        UserDefaults.standard.set(dockApplications.map(\.path), forKey: dockKey)
        UserDefaults.standard.set(desktopApplications.map(\.path), forKey: desktopKey)
        UserDefaults.standard.set(desktopFolders.map(\.path), forKey: foldersKey)
        DesktopEnvironment.shared.resizeDockToFitContents()
    }
}

// MARK: - Background Presets

@MainActor
final class VYBEBackgroundPresets: ObservableObject {
    static let shared = VYBEBackgroundPresets()
    @Published private(set) var selectedName = UserDefaults.standard.string(forKey: "VYBE.backgroundPreset") ?? "Blue Hour"

    // Keep the original names so existing Spaces and saved preferences continue to work.
    let names = [
        "Midnight", "Arctic", "Violet Haze", "Deep Ocean", "Emerald", "Solaris", "Carbon", "Aurora", "Dusk", "Monochrome",
        "Blue Hour", "Velvet Dunes", "Solstice", "Lunar Tide", "Sacred Geometry", "Botanical Pulse", "Afterglow", "Quiet Earth", "Electric Bloom", "Monolith",
        "Mythic Forest", "Neon Rain", "Sakura District", "Abyssal Bloom", "Astral Cathedral"
    ]

    private let palettes: [[NSColor]] = [
        [NSColor(calibratedRed: 0.015, green: 0.025, blue: 0.075, alpha: 1), NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.40, alpha: 1)],
        [NSColor(calibratedRed: 0.05, green: 0.17, blue: 0.25, alpha: 1), NSColor(calibratedRed: 0.36, green: 0.65, blue: 0.72, alpha: 1)],
        [NSColor(calibratedRed: 0.09, green: 0.035, blue: 0.18, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.58, alpha: 1)],
        [NSColor(calibratedRed: 0.005, green: 0.08, blue: 0.17, alpha: 1), NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.55, alpha: 1)],
        [NSColor(calibratedRed: 0.015, green: 0.10, blue: 0.075, alpha: 1), NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.30, alpha: 1)],
        [NSColor(calibratedRed: 0.22, green: 0.055, blue: 0.015, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.34, blue: 0.10, alpha: 1)],
        [NSColor(calibratedRed: 0.025, green: 0.03, blue: 0.04, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.25, alpha: 1)],
        [NSColor(calibratedRed: 0.015, green: 0.10, blue: 0.15, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.48, alpha: 1)],
        [NSColor(calibratedRed: 0.12, green: 0.045, blue: 0.12, alpha: 1), NSColor(calibratedRed: 0.50, green: 0.18, blue: 0.24, alpha: 1)],
        [NSColor(calibratedWhite: 0.025, alpha: 1), NSColor(calibratedWhite: 0.34, alpha: 1)],
        [NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.16, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.62, alpha: 1)],
        [NSColor(calibratedRed: 0.12, green: 0.035, blue: 0.12, alpha: 1), NSColor(calibratedRed: 0.67, green: 0.30, blue: 0.28, alpha: 1)],
        [NSColor(calibratedRed: 0.10, green: 0.045, blue: 0.025, alpha: 1), NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.18, alpha: 1)],
        [NSColor(calibratedRed: 0.015, green: 0.045, blue: 0.12, alpha: 1), NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.56, alpha: 1)],
        [NSColor(calibratedRed: 0.025, green: 0.015, blue: 0.10, alpha: 1), NSColor(calibratedRed: 0.35, green: 0.16, blue: 0.50, alpha: 1)],
        [NSColor(calibratedRed: 0.015, green: 0.10, blue: 0.08, alpha: 1), NSColor(calibratedRed: 0.30, green: 0.48, blue: 0.31, alpha: 1)],
        [NSColor(calibratedRed: 0.16, green: 0.035, blue: 0.08, alpha: 1), NSColor(calibratedRed: 0.86, green: 0.34, blue: 0.22, alpha: 1)],
        [NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.065, alpha: 1), NSColor(calibratedRed: 0.39, green: 0.36, blue: 0.26, alpha: 1)],
        [NSColor(calibratedRed: 0.045, green: 0.015, blue: 0.13, alpha: 1), NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.78, alpha: 1)],
        [NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.075, alpha: 1), NSColor(calibratedRed: 0.28, green: 0.39, blue: 0.48, alpha: 1)],
        [NSColor(calibratedRed: 0.008, green: 0.055, blue: 0.052, alpha: 1), NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.23, alpha: 1)],
        [NSColor(calibratedRed: 0.012, green: 0.018, blue: 0.075, alpha: 1), NSColor(calibratedRed: 0.22, green: 0.055, blue: 0.36, alpha: 1)],
        [NSColor(calibratedRed: 0.12, green: 0.035, blue: 0.12, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.28, blue: 0.43, alpha: 1)],
        [NSColor(calibratedRed: 0.002, green: 0.035, blue: 0.09, alpha: 1), NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.43, alpha: 1)],
        [NSColor(calibratedRed: 0.018, green: 0.012, blue: 0.07, alpha: 1), NSColor(calibratedRed: 0.27, green: 0.20, blue: 0.48, alpha: 1)]
    ]

    func apply(_ name: String) {
        guard let index = names.firstIndex(of: name) else { return }
        let url = presetURL(for: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            createImage(at: url, name: name, palette: palettes[index])
        }
        for screen in NSScreen.screens {
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue]) }
            catch { continue }
        }
        selectedName = name
        UserDefaults.standard.set(name, forKey: "VYBE.backgroundPreset")
    }

    private func presetURL(for name: String) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VYBE/Backgrounds/Artwork-v3", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-") + ".png")
    }

    private func createImage(at url: URL, name: String, palette: [NSColor]) {
        let size = NSSize(width: 2560, height: 1600)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: palette)?.draw(in: rect, angle: 32)
        let w = size.width, h = size.height
        let accent = palette.last ?? .cyan
        let pale = NSColor(calibratedWhite: 1, alpha: 0.78)

        func fillShape(_ points: [(CGFloat, CGFloat)], color: NSColor) {
            let path = NSBezierPath()
            guard let first = points.first else { return }
            path.move(to: NSPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
            path.close()
            color.setFill(); path.fill()
        }
        func strokeCurve(_ y: CGFloat, amplitude: CGFloat, phase: CGFloat, alpha: CGFloat, width: CGFloat = 2) {
            let path = NSBezierPath(); path.lineWidth = width
            path.move(to: NSPoint(x: 0, y: y + sin(phase) * amplitude))
            path.curve(to: NSPoint(x: w, y: y + sin(phase + 2.1) * amplitude),
                       controlPoint1: NSPoint(x: w * 0.28, y: y + sin(phase + 1.1) * amplitude * 1.7),
                       controlPoint2: NSPoint(x: w * 0.72, y: y + sin(phase + 1.7) * amplitude * 1.5))
            NSColor.white.withAlphaComponent(alpha).setStroke(); path.stroke()
        }
        func drawOrb(_ center: NSPoint, radius: CGFloat, color: NSColor) {
            let halo = NSGradient(colors: [color.withAlphaComponent(0.30), color.withAlphaComponent(0.08), color.withAlphaComponent(0)])
            halo?.draw(in: NSRect(x: center.x - radius * 1.8, y: center.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6), relativeCenterPosition: NSPoint(x: 0.5, y: 0.5))
            color.withAlphaComponent(0.88).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        }

        switch name {
        case "Blue Hour":
            drawOrb(NSPoint(x: w * 0.73, y: h * 0.64), radius: 230, color: NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.94, alpha: 1))
            fillShape([(0,0),(0,h*0.32),(w*0.18,h*0.47),(w*0.38,h*0.29),(w*0.57,h*0.43),(w*0.78,h*0.24),(w,h*0.38),(w,0)], color: palette[0].withAlphaComponent(0.72))
            fillShape([(0,0),(0,h*0.18),(w*0.24,h*0.29),(w*0.43,h*0.13),(w*0.66,h*0.25),(w*0.84,h*0.12),(w, h*0.20),(w,0)], color: accent.withAlphaComponent(0.42))
            for i in 0..<90 { let x = CGFloat((i * 173) % 2510), y = CGFloat((i * 97) % 850) + h * 0.43; NSColor.white.withAlphaComponent(0.22).setFill(); NSBezierPath(ovalIn: NSRect(x:x,y:y,width:2.4,height:2.4)).fill() }
        case "Velvet Dunes", "Quiet Earth":
            for i in 0..<7 {
                let y = CGFloat(i) * h * 0.105 + h * 0.06
                let path = NSBezierPath(); path.move(to: NSPoint(x: -100, y: y))
                path.curve(to: NSPoint(x: w + 100, y: y + CGFloat((i % 2 == 0) ? 170 : -120)), controlPoint1: NSPoint(x:w*0.24,y:y+260), controlPoint2:NSPoint(x:w*0.66,y:y-190))
                path.line(to: NSPoint(x:w+100,y:-20)); path.line(to:NSPoint(x:-100,y:-20)); path.close()
                palette[i % palette.count].withAlphaComponent(0.16 + CGFloat(i) * 0.045).setFill(); path.fill()
                strokeCurve(y + 75, amplitude: 36, phase: CGFloat(i) * 0.6, alpha: 0.12, width: 1.4)
            }
            drawOrb(NSPoint(x:w*0.72,y:h*0.73), radius:150, color:accent.withAlphaComponent(0.72))
        case "Solstice", "Afterglow":
            drawOrb(NSPoint(x:w*0.50,y:h*0.60), radius:250, color:NSColor(calibratedRed:1,green:0.72,blue:0.42,alpha:1))
            for i in 0..<8 { let y = h*0.42 - CGFloat(i)*48; let path=NSBezierPath(roundedRect:NSRect(x:-40,y:y,width:w+80,height:CGFloat(18+i%3*5)),xRadius:12,yRadius:12); palette[i%palette.count].withAlphaComponent(0.24).setFill(); path.fill() }
            for i in 0..<5 { strokeCurve(h*0.24+CGFloat(i)*42,amplitude:28,phase:CGFloat(i)*0.5,alpha:0.28,width:2) }
        case "Lunar Tide":
            drawOrb(NSPoint(x:w*0.72,y:h*0.70), radius:205, color:NSColor(calibratedRed:0.78,green:0.82,blue:0.92,alpha:1))
            for i in 0..<12 { strokeCurve(h*0.38-CGFloat(i)*39,amplitude:42,phase:CGFloat(i)*0.42,alpha:0.12+CGFloat(i)*0.012,width:2.2) }
            fillShape([(0,0),(0,h*0.22),(w*0.22,h*0.28),(w*0.46,h*0.17),(w*0.72,h*0.26),(w,h*0.14),(w,0)],color:palette[0].withAlphaComponent(0.52))
        case "Sacred Geometry":
            for row in 0..<8 { for col in 0..<13 {
                let x=CGFloat(col)*230 + CGFloat(row%2)*115, y=CGFloat(row)*210 + 100
                let r:CGFloat=78; let path=NSBezierPath(); for side in 0..<6 { let a=CGFloat(side)*CGFloat.pi/3; let pt=NSPoint(x:x+cos(a)*r,y:y+sin(a)*r); if side==0 { path.move(to:pt) } else { path.line(to:pt) } }; path.close(); path.lineWidth=2
                accent.withAlphaComponent(0.17).setStroke(); path.stroke()
                NSBezierPath(ovalIn:NSRect(x:x-24,y:y-24,width:48,height:48)).stroke()
            } }
            let center=NSBezierPath(ovalIn:NSRect(x:w*0.37,y:h*0.22,width:650,height:650)); center.lineWidth=3; pale.withAlphaComponent(0.18).setStroke(); center.stroke()
        case "Botanical Pulse":
            for i in 0..<9 {
                let x=w*0.12+CGFloat(i)*w*0.105
                let path=NSBezierPath(); path.move(to:NSPoint(x:x,y:-30)); path.curve(to:NSPoint(x:x+CGFloat(i%2==0 ? 220 : -180),y:h+40),controlPoint1:NSPoint(x:x+180,y:h*0.30),controlPoint2:NSPoint(x:x-150,y:h*0.72)); path.lineWidth=4; accent.withAlphaComponent(0.32).setStroke(); path.stroke()
                for leaf in 0..<5 { let ly=CGFloat(leaf)*270+100; let side:CGFloat=leaf%2==0 ? 1 : -1; let leafPath=NSBezierPath(); leafPath.move(to:NSPoint(x:x+side*20,y:ly)); leafPath.curve(to:NSPoint(x:x+side*170,y:ly+95),controlPoint1:NSPoint(x:x+side*35,y:ly+145),controlPoint2:NSPoint(x:x+side*145,y:ly+180)); leafPath.curve(to:NSPoint(x:x+side*20,y:ly),controlPoint1:NSPoint(x:x+side*160,y:ly+5),controlPoint2:NSPoint(x:x+side*70,y:ly-55)); leafPath.lineWidth=2; pale.withAlphaComponent(0.24).setStroke(); leafPath.stroke() }
            }
        case "Electric Bloom":
            let c=NSPoint(x:w*0.50,y:h*0.50)
            for i in 0..<18 { let a=CGFloat(i)*CGFloat.pi/9; let path=NSBezierPath(); path.move(to:c); path.curve(to:NSPoint(x:c.x+cos(a)*760,y:c.y+sin(a)*620),controlPoint1:NSPoint(x:c.x+cos(a+0.55)*260,y:c.y+sin(a+0.55)*260),controlPoint2:NSPoint(x:c.x+cos(a-0.55)*550,y:c.y+sin(a-0.55)*470)); path.curve(to:c,controlPoint1:NSPoint(x:c.x+cos(a+0.9)*530,y:c.y+sin(a+0.9)*430),controlPoint2:NSPoint(x:c.x+cos(a-0.9)*260,y:c.y+sin(a-0.9)*260)); path.lineWidth=2; palette[i%palette.count].withAlphaComponent(0.22).setStroke(); path.stroke() }
            drawOrb(c,radius:82,color:accent)
        case "Monolith":
            for i in 0..<7 { let x=CGFloat(i)*390+120; let width:CGFloat=245; let height=CGFloat(700+(i%3)*190); let arch=NSBezierPath(roundedRect:NSRect(x:x,y:h*0.16,width:width,height:height),xRadius:width/2,yRadius:width/2); arch.lineWidth=3; palette[i%palette.count].withAlphaComponent(0.28).setStroke(); arch.stroke(); let inner=NSBezierPath(roundedRect:NSRect(x:x+28,y:h*0.16+28,width:width-56,height:height-56),xRadius:(width-56)/2,yRadius:(width-56)/2); inner.lineWidth=1.5; pale.withAlphaComponent(0.16).setStroke(); inner.stroke() }
        case "Mythic Forest":
            // Deep, layered forest with a luminous canopy, winding river and firefly field.
            drawOrb(NSPoint(x: w * 0.52, y: h * 0.76), radius: 340, color: NSColor(calibratedRed: 0.42, green: 0.82, blue: 0.55, alpha: 1))
            for layer in 0..<5 {
                let baseY = CGFloat(layer) * 145 + 80
                let path = NSBezierPath(); path.move(to: NSPoint(x: -40, y: 0))
                path.line(to: NSPoint(x: -40, y: baseY + 280))
                for step in 0..<16 {
                    let x = CGFloat(step) * w / 15
                    let y = baseY + CGFloat((step * 97 + layer * 61) % 240)
                    path.line(to: NSPoint(x: x, y: y))
                }
                path.line(to: NSPoint(x: w + 40, y: 0)); path.close()
                [NSColor(calibratedRed: 0.012, green: 0.055, blue: 0.045, alpha: 1), NSColor(calibratedRed: 0.018, green: 0.09, blue: 0.06, alpha: 1), NSColor(calibratedRed: 0.025, green: 0.14, blue: 0.08, alpha: 1)][layer % 3].withAlphaComponent(0.92).setFill(); path.fill()
            }
            for tree in 0..<17 {
                let x = CGFloat(tree) * 165 - 35
                let height = CGFloat(480 + (tree * 83) % 520)
                let trunk = NSBezierPath(); trunk.move(to: NSPoint(x: x, y: 0)); trunk.curve(to: NSPoint(x: x + CGFloat((tree % 3) - 1) * 65, y: height), controlPoint1: NSPoint(x: x - 35, y: height * 0.35), controlPoint2: NSPoint(x: x + 30, y: height * 0.72)); trunk.lineWidth = CGFloat(18 + tree % 4 * 7); NSColor(calibratedRed: 0.018, green: 0.045, blue: 0.035, alpha: 1).setStroke(); trunk.stroke()
                for branch in 0..<5 {
                    let bx = x + CGFloat(branch - 2) * 38
                    let leaf = NSBezierPath(ovalIn: NSRect(x: bx - 105, y: height * 0.52 + CGFloat(branch) * 65, width: 210, height: 118))
                    NSColor(calibratedRed: 0.06 + CGFloat(branch) * 0.012, green: 0.25 + CGFloat(branch) * 0.025, blue: 0.13, alpha: 0.76).setFill(); leaf.fill()
                }
            }
            for i in 0..<140 { let x = CGFloat((i * 173) % 2530), y = CGFloat((i * 113) % 1510); drawOrb(NSPoint(x: x, y: y), radius: CGFloat(i % 3 + 2), color: NSColor(calibratedRed: 0.45, green: 0.95, blue: 0.56, alpha: 0.8)) }
        case "Neon Rain":
            // Dense night skyline, wet streets, lit windows and rain streaks.
            drawOrb(NSPoint(x: w * 0.78, y: h * 0.82), radius: 240, color: NSColor(calibratedRed: 0.38, green: 0.12, blue: 0.82, alpha: 1))
            for building in 0..<22 {
                let x = CGFloat(building) * 122 - 12
                let bw = CGFloat(78 + (building * 29) % 52)
                let bh = CGFloat(280 + (building * 137) % 900)
                let rect = NSRect(x: x, y: 0, width: bw, height: bh)
                NSColor(calibratedRed: 0.012, green: 0.018, blue: 0.055, alpha: 0.98).setFill(); NSBezierPath(rect: rect).fill()
                for row in 0..<Int(bh / 42) { for col in 0..<3 where (row + col + building) % 3 != 0 {
                    let window = NSRect(x: x + 12 + CGFloat(col) * 20, y: CGFloat(row) * 42 + 22, width: 8, height: 15)
                    NSColor(calibratedRed: 0.15, green: 0.75, blue: 0.92, alpha: 0.28 + CGFloat((row + building) % 4) * 0.1).setFill(); NSBezierPath(rect: window).fill()
                } }
            }
            for sign in 0..<8 { let x = CGFloat(sign) * 330 + 60; let box = NSBezierPath(roundedRect: NSRect(x: x, y: CGFloat(280 + sign % 3 * 130), width: 180, height: 62), xRadius: 12, yRadius: 12); box.lineWidth = 5; [NSColor.cyan, NSColor.magenta, NSColor.systemPink, NSColor.systemTeal][sign % 4].withAlphaComponent(0.75).setStroke(); box.stroke() }
            for rain in 0..<650 { let x = CGFloat((rain * 47) % 2560), y = CGFloat((rain * 79) % 1600); let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: y)); line.line(to: NSPoint(x: x - 18, y: y - 72)); line.lineWidth = 1; NSColor.cyan.withAlphaComponent(0.13).setStroke(); line.stroke() }
            for streak in 0..<16 { strokeCurve(CGFloat(streak) * 34 + 30, amplitude: 12, phase: CGFloat(streak) * 0.42, alpha: 0.13, width: 5) }
        case "Sakura District":
            // Layered Japanese-inspired rooftops, a giant flowering tree and drifting petals.
            drawOrb(NSPoint(x: w * 0.78, y: h * 0.75), radius: 250, color: NSColor(calibratedRed: 1, green: 0.58, blue: 0.68, alpha: 1))
            for roof in 0..<7 {
                let y = CGFloat(roof) * 115 + 80
                let x = CGFloat((roof * 307) % 1900)
                let path = NSBezierPath(); path.move(to: NSPoint(x: x - 180, y: y)); path.line(to: NSPoint(x: x + 150, y: y + 120)); path.line(to: NSPoint(x: x + 470, y: y)); path.lineWidth = 24; NSColor(calibratedRed: 0.035, green: 0.025, blue: 0.075, alpha: 0.95).setStroke(); path.stroke()
                let building = NSBezierPath(rect: NSRect(x: x - 95, y: 0, width: 500, height: y)); NSColor(calibratedRed: 0.06, green: 0.035, blue: 0.085, alpha: 0.7).setFill(); building.fill()
            }
            let branch = NSBezierPath(); branch.move(to: NSPoint(x: w * 0.13, y: 0)); branch.curve(to: NSPoint(x: w * 0.72, y: h * 0.94), controlPoint1: NSPoint(x: w * 0.18, y: h * 0.5), controlPoint2: NSPoint(x: w * 0.48, y: h * 0.68)); branch.lineWidth = 42; NSColor(calibratedRed: 0.12, green: 0.055, blue: 0.075, alpha: 1).setStroke(); branch.stroke()
            for petal in 0..<190 { let x = CGFloat((petal * 127) % 2500), y = CGFloat((petal * 211) % 1500); let oval = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: CGFloat(7 + petal % 8), height: CGFloat(13 + petal % 11))); NSColor(calibratedRed: 1, green: 0.45 + CGFloat(petal % 4) * 0.08, blue: 0.66, alpha: 0.58).setFill(); oval.fill() }
        case "Abyssal Bloom":
            // Bioluminescent undersea scene with coral gardens, schools of fish and drifting particles.
            for coral in 0..<34 {
                let x = CGFloat(coral) * 78 - 25
                let height = CGFloat(150 + (coral * 97) % 530)
                let path = NSBezierPath(); path.move(to: NSPoint(x: x, y: 0)); path.curve(to: NSPoint(x: x + CGFloat(coral % 5 - 2) * 90, y: height), controlPoint1: NSPoint(x: x - 35, y: height * 0.35), controlPoint2: NSPoint(x: x + 60, y: height * 0.72)); path.lineWidth = CGFloat(8 + coral % 6 * 3); [NSColor.systemTeal, NSColor.cyan, NSColor.systemPurple, NSColor.systemPink][coral % 4].withAlphaComponent(0.42).setStroke(); path.stroke()
                for branch in 0..<3 { drawOrb(NSPoint(x: x + CGFloat(branch - 1) * 30, y: height * (0.55 + CGFloat(branch) * 0.12)), radius: CGFloat(13 + branch * 4), color: NSColor(calibratedRed: 0.12, green: 0.86, blue: 0.78, alpha: 0.8)) }
            }
            for fish in 0..<18 { let x = CGFloat((fish * 149) % 2380), y = CGFloat(400 + (fish * 83) % 1000); let body = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: CGFloat(55 + fish % 4 * 12), height: CGFloat(24 + fish % 3 * 7))); NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.78, alpha: 0.35).setFill(); body.fill(); let tail = NSBezierPath(); tail.move(to: NSPoint(x: x, y: y + 12)); tail.line(to: NSPoint(x: x - 24, y: y + 30)); tail.line(to: NSPoint(x: x - 24, y: y - 6)); tail.close(); NSColor.cyan.withAlphaComponent(0.35).setFill(); tail.fill() }
            for i in 0..<260 { let x = CGFloat((i * 73) % 2520), y = CGFloat((i * 109) % 1570); drawOrb(NSPoint(x: x, y: y), radius: CGFloat(i % 4 + 1), color: NSColor.cyan.withAlphaComponent(0.52)) }
        case "Astral Cathedral":
            // Monumental layered arches, stained-glass geometry and a star-filled vault.
            for archIndex in 0..<9 {
                let width = CGFloat(240 + archIndex * 210)
                let height = CGFloat(520 + archIndex * 120)
                let rect = NSRect(x: w * 0.5 - width / 2, y: h * 0.08, width: width, height: height)
                let arch = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2); arch.lineWidth = CGFloat(5 - archIndex % 3)
                [NSColor.systemIndigo, NSColor.systemPurple, NSColor.cyan, NSColor.systemPink][archIndex % 4].withAlphaComponent(0.22).setStroke(); arch.stroke()
            }
            for panel in 0..<12 { let x = CGFloat(panel) * 220 + 40; let glass = NSBezierPath(); glass.move(to: NSPoint(x: x, y: 0)); glass.line(to: NSPoint(x: x + 110, y: h * 0.55)); glass.line(to: NSPoint(x: x + 220, y: 0)); glass.close(); [NSColor.systemPurple, NSColor.cyan, NSColor.systemPink][panel % 3].withAlphaComponent(0.12).setFill(); glass.fill() }
            for star in 0..<180 { let x = CGFloat((star * 97) % 2540), y = CGFloat((star * 151) % 1550); drawOrb(NSPoint(x: x, y: y), radius: CGFloat(star % 3 + 1), color: NSColor.white.withAlphaComponent(0.72)) }
        default:
            // Legacy presets also receive layered contour artwork rather than a flat gradient.
            for i in 0..<18 { strokeCurve(CGFloat(i)*92-80,amplitude:80,phase:CGFloat(i)*0.31,alpha:0.10,width:2) }
            drawOrb(NSPoint(x:w*0.72,y:h*0.66),radius:230,color:accent.withAlphaComponent(0.72))
            for i in 0..<12 { let r=CGFloat(i)*110+170; let ring=NSBezierPath(ovalIn:NSRect(x:w*0.72-r,y:h*0.66-r,width:r*2,height:r*2)); ring.lineWidth=1.4; pale.withAlphaComponent(0.08).setStroke(); ring.stroke() }
        }

        // Fine, deterministic grain gives the generated artwork a tactile print finish.
        for i in 0..<1800 {
            let x = CGFloat((i * 811) % 2557), y = CGFloat((i * 613) % 1597)
            NSColor.white.withAlphaComponent(i % 3 == 0 ? 0.035 : 0.012).setFill()
            NSBezierPath(ovalIn: NSRect(x:x,y:y,width:1.5,height:1.5)).fill()
        }

        image.unlockFocus()
        if let data = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: url, options: .atomic)
        }
    }
}
