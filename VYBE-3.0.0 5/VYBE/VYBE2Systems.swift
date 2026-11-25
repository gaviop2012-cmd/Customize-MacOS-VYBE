import AppKit
import CoreGraphics
import SwiftUI
import Speech
import AVFoundation
import ApplicationServices
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import ImageIO
import PDFKit

// MARK: - VYBE Spaces

struct VYBESpace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var accent: String
    var widgetIDs: [String]
    var wallpaperPreset: String

    static let defaults: [VYBESpace] = [
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, name: "COMMAND", symbol: "terminal.fill", accent: "cyan", widgetIDs: ["clock", "system", "network", "memory", "terminal"], wallpaperPreset: "Blue Hour"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, name: "FOCUS", symbol: "scope", accent: "blue", widgetIDs: ["clock", "note", "timer", "focus"], wallpaperPreset: "Monolith"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, name: "PLAY", symbol: "waveform", accent: "violet", widgetIDs: ["clock", "music", "weather"], wallpaperPreset: "Electric Bloom"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!, name: "CREATE", symbol: "scribble.variable", accent: "cyan", widgetIDs: ["clock", "note", "calendar"], wallpaperPreset: "Botanical Pulse"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!, name: "PERSONAL", symbol: "sparkles", accent: "violet", widgetIDs: ["clock", "calendar", "weather", "messages"], wallpaperPreset: "Velvet Dunes")
    ]
}

@MainActor
final class VYBESpaceManager: ObservableObject {
    static let shared = VYBESpaceManager()
    @Published private(set) var spaces: [VYBESpace] = []
    @Published private(set) var activeSpaceID: UUID
    private let storageKey = "VYBE.spaces.v2"
    private let activeKey = "VYBE.activeSpace.v2"

    var activeSpace: VYBESpace { spaces.first(where: { $0.id == activeSpaceID }) ?? spaces[0] }

    private init() {
        // Build the initial state in local variables. Do not access `self.spaces`
        // or `self.activeSpaceID` until every stored property has been initialized.
        var initialSpaces: [VYBESpace]
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([VYBESpace].self, from: data), !decoded.isEmpty {
            initialSpaces = decoded
        } else {
            initialSpaces = VYBESpace.defaults
            // First-run migration: seed COMMAND with the user's existing 1.8.0
            // desktop configuration instead of replacing their selected widgets.
            if let existingWidgets = UserDefaults.standard.stringArray(forKey: "VYBE.selectedWidgets") {
                initialSpaces[0].widgetIDs = existingWidgets
            }
            if let existingWallpaper = UserDefaults.standard.string(forKey: "VYBE.backgroundPreset") {
                initialSpaces[0].wallpaperPreset = existingWallpaper
            }
        }

        let initialActiveID: UUID
        if let raw = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: raw), initialSpaces.contains(where: { $0.id == id }) {
            initialActiveID = id
        } else {
            initialActiveID = initialSpaces[0].id
        }

        self.spaces = initialSpaces
        self.activeSpaceID = initialActiveID
        persist()
    }

    func restoreActiveConfiguration() {
        applyActiveConfiguration()
    }

    func activate(_ id: UUID) {
        guard let target = spaces.first(where: { $0.id == id }), target.id != activeSpaceID else { return }
        saveCurrentConfiguration()
        activeSpaceID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        VYBEWidgetSelection.shared.setSelection(Set(target.widgetIDs))
        VYBEBackgroundPresets.shared.apply(target.wallpaperPreset)
        VYBEHUD.shared.show("SPACE // \(target.name)", detail: "Workspace environment activated", symbol: target.symbol)
    }

    func createSpace() {
        let new = VYBESpace(id: UUID(), name: "NEW SPACE", symbol: "square.dashed", accent: "cyan",
                            widgetIDs: Array(VYBEWidgetSelection.shared.selectedIDs), wallpaperPreset: VYBEBackgroundPresets.shared.selectedName)
        spaces.append(new)
        persist()
        activate(new.id)
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        spaces[index].name = String(clean.prefix(22)).uppercased()
        persist()
    }

    func delete(_ id: UUID) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = spaces[index].id == activeSpaceID
        spaces.remove(at: index)
        if wasActive {
            activeSpaceID = spaces[min(index, spaces.count - 1)].id
            UserDefaults.standard.set(activeSpaceID.uuidString, forKey: activeKey)
            applyActiveConfiguration()
        }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        spaces.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func updateActiveWallpaper(_ name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        spaces[index].wallpaperPreset = name
        persist()
    }

    func saveCurrentConfiguration() {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        spaces[index].widgetIDs = Array(VYBEWidgetSelection.shared.selectedIDs)
        spaces[index].wallpaperPreset = VYBEBackgroundPresets.shared.selectedName
        persist()
    }

    private func applyActiveConfiguration() {
        let current = activeSpace
        VYBEWidgetSelection.shared.setSelection(Set(current.widgetIDs))
        VYBEBackgroundPresets.shared.apply(current.wallpaperPreset)
        VYBEHUD.shared.show("SPACE // \(current.name)", detail: "Workspace environment restored", symbol: current.symbol)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(spaces) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Holographic HUD

@MainActor
final class VYBEHUD: ObservableObject {
    static let shared = VYBEHUD()
    @Published private(set) var message = ""
    @Published private(set) var detail = ""
    @Published private(set) var symbol = "sparkles"
    @Published private(set) var isVisible = false
    private var dismissTask: DispatchWorkItem?

    func show(_ message: String, detail: String = "", symbol: String = "sparkles") {
        self.message = message
        self.detail = detail
        self.symbol = symbol
        isVisible = true
        dismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.isVisible = false }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: task)
    }
}

struct VYBEHUDView: View {
    @ObservedObject private var hud = VYBEHUD.shared
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: hud.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Color.cyan)
            Text(hud.message).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.4)
            if !hud.detail.isEmpty { Text(hud.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 15)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.48), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.18), radius: 22)
        .opacity(hud.isVisible ? 1 : 0)
        .scaleEffect(hud.isVisible ? 1 : 0.94)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: hud.isVisible)
        .allowsHitTesting(false)
    }
}

// MARK: - Floating overlay windows

@MainActor
final class VYBEOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class VYBENonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class VYBEOverlayController {
    static let shared = VYBEOverlayController()
    private var commandPanel: VYBEOverlayPanel?
    private var radialPanel: VYBEOverlayPanel?
    private var radialReturnPID: pid_t?
    private var lastExternalPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var dictationPanel: VYBENonActivatingPanel?
    private var utilityPanel: VYBEOverlayPanel?
    private var capturePanel: VYBEOverlayPanel?
    private var converterPanel: VYBEOverlayPanel?
    private var focusSprintTask: DispatchWorkItem?

    private init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalPID = frontmost.processIdentifier
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = (notification.object as? NSRunningApplication)
                    ?? (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication),
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.lastExternalPID = app.processIdentifier }
        }
    }

    func toggleCommand() {
        if let panel = commandPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            let panel = commandPanel ?? makePanel(size: NSSize(width: 620, height: 430), identifier: "vybe-command") {
                VYBECommandView { [weak self] in self?.commandPanel?.orderOut(nil) }
            }
            commandPanel = panel
            show(panel)
        }
    }

    func toggleRadial() {
        if let panel = radialPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            let current = NSWorkspace.shared.frontmostApplication
            radialReturnPID = lastExternalPID ?? (current?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : current?.processIdentifier)
            let panel = radialPanel ?? makePanel(size: NSSize(width: 720, height: 720), identifier: "vybe-radial") {
                VYBERadialView { [weak self] in self?.radialPanel?.orderOut(nil) }
            }
            radialPanel = panel
            show(panel)
        }
    }

    func runRadialAction(_ action: VYBERadialAction) {
        radialPanel?.orderOut(nil)
        switch action.kind {
        case .openURL:
            if let url = URL(string: action.payload), url.scheme != nil { NSWorkspace.shared.open(url) }
        case .voiceAssistant:
            VYBEAssistantWindow.shared.toggleAndListen()
        case .dictation:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                VYBEGlobalDictation.shared.start()
            }
        case .openApp:
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.payload) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
        default:
            runUtilityAction(action.kind)
        }
    }

    func showDictationHUD() {
        if dictationPanel == nil {
            let panel = VYBENonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 230),
                                               styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: VYBEDictationHUDView())
            dictationPanel = panel
        }
        if let panel = dictationPanel {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            panel.setContentSize(NSSize(width: 520, height: 230))
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - panel.frame.height - 24))
            // Keep dictation available without stealing keyboard focus from the app
            // the user was working in. The panel remains a non-activating utility panel.
            panel.orderFrontRegardless()
        }
    }

    func hideDictationHUD() { dictationPanel?.orderOut(nil) }

    func dismissDictationHUD() {
        if VYBEGlobalDictation.shared.isListening { VYBEGlobalDictation.shared.stop() }
        dictationPanel?.orderOut(nil)
    }

    private func runUtilityAction(_ kind: VYBERadialActionKind) {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        switch kind {
        case .cleanClipboard:
            let clean = clipboard.replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: .newlines).map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            writeClipboard(clean)
            VYBEHUD.shared.show("TEXT CLEANED", detail: "Cleaned text copied to clipboard", symbol: "text.alignleft")
        case .searchClipboard, .translateClipboard:
            var queryCharacters = CharacterSet.urlQueryAllowed
            queryCharacters.remove(charactersIn: "&+=#?")
            guard !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let encoded = clipboard.addingPercentEncoding(withAllowedCharacters: queryCharacters) else {
                VYBEHUD.shared.show("CLIPBOARD EMPTY", detail: "Copy some text first", symbol: "doc.on.clipboard"); return
            }
            let address = kind == .searchClipboard ? "https://www.google.com/search?q=\(encoded)" : "https://translate.google.com/?sl=auto&tl=en&text=\(encoded)&op=translate"
            if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        case .calculateClipboard:
            let expression = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep parsing bounded: this runs from a radial action on the main actor.
            // Very large clipboard payloads or pathological nesting must never stall VYBE.
            guard !expression.isEmpty, expression.count <= 120 else {
                VYBEHUD.shared.show("CALCULATION TOO COMPLEX", detail: "Use a valid expression under 120 characters", symbol: "function"); return
            }
            let nesting = expression.reduce(into: (depth: 0, maximum: 0)) { state, character in
                if character == "(" { state.depth += 1; state.maximum = max(state.maximum, state.depth) }
                if character == ")" { state.depth -= 1 }
            }
            guard nesting.maximum <= 24, nesting.depth == 0,
                  expression.range(of: #"^[0-9\s+\-*/().%]+$"#, options: .regularExpression) != nil else {
                VYBEHUD.shared.show("INVALID CALCULATION", detail: "Example: (125 * 4) / 2", symbol: "function"); return
            }
            var parser = VYBEMathParser(expression)
            if let value = parser.evaluate(), value.isFinite {
                let result = String(value)
                writeClipboard(result)
                VYBEHUD.shared.show("RESULT COPIED", detail: "\(expression) = \(result)", symbol: "equal")
            } else {
                VYBEHUD.shared.show("CALCULATION FAILED", detail: "Check the expression", symbol: "exclamationmark.triangle")
            }
        case .quickNote:
            showMemoryCardEditor(initialText: clipboard)
        case .convertFile:
            openFileConverter()
        case .screenshotOCR:
            captureAndRecognizeScreen()
        case .generatePassword:
            let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*+-_")
            var generator = SystemRandomNumberGenerator()
            let password = String((0..<22).compactMap { _ in alphabet.randomElement(using: &generator) })
            writeClipboard(password)
            VYBEHUD.shared.show("PASSWORD GENERATED", detail: "22-character password copied", symbol: "key.fill")
        case .toggleDesktopIcons:
            let hidden = UserDefaults.standard.bool(forKey: "VYBE.hideFinderDesktop")
            FinderDesktopVisibility.setHidden(!hidden)
            VYBEHUD.shared.show(hidden ? "DESKTOP ICONS SHOWN" : "DESKTOP ICONS HIDDEN", detail: "Finder desktop visibility changed", symbol: "macwindow")
        case .saveClipboard:
            let panel = NSSavePanel(); panel.title = "Save Clipboard as Text"; panel.nameFieldStringValue = "VYBE-Clipboard.txt"; panel.allowedContentTypes = [.plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do { try clipboard.write(to: url, atomically: true, encoding: .utf8) }
                catch { Task { @MainActor in VYBEHUD.shared.show("SAVE FAILED", detail: error.localizedDescription, symbol: "exclamationmark.triangle") } }
            }
        case .makeQR:
            guard !clipboard.isEmpty else { VYBEHUD.shared.show("CLIPBOARD EMPTY", detail: "Copy a link or text first", symbol: "qrcode"); return }
            let filter = CIFilter.qrCodeGenerator(); filter.message = Data(clipboard.utf8); filter.correctionLevel = "H"
            guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 9, y: 9)),
                  let cgImage = CIContext().createCGImage(output, from: output.extent) else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            showUtilityImage(image, title: "CLIPBOARD QR CODE")
        case .openClipboardURL:
            let raw = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = raw.contains("://") ? raw : "https://\(raw)"
            if let url = URL(string: candidate), let scheme = url.scheme, ["http", "https"].contains(scheme) { NSWorkspace.shared.open(url) }
            else { VYBEHUD.shared.show("NO VALID LINK", detail: "Copy a website URL first", symbol: "link") }
        case .focusSprint:
            focusSprintTask?.cancel()
            VYBEHUD.shared.show("FOCUS SPRINT STARTED", detail: "25 minutes • Protect your flow", symbol: "timer")
            let task = DispatchWorkItem { VYBEHUD.shared.show("SPRINT COMPLETE", detail: "25 minutes finished. Take a short break.", symbol: "checkmark.circle") }
            focusSprintTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 25 * 60, execute: task)
        default: break
        }
    }

    private func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyDictationText() {
        let text = VYBEGlobalDictation.shared.liveText
        guard !text.isEmpty else { VYBEHUD.shared.show("NOTHING TO COPY", detail: "Speak first", symbol: "doc.on.clipboard"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        VYBEHUD.shared.show("DICTATION COPIED", detail: "Transcript copied to clipboard", symbol: "checkmark")
    }

    private func showMemoryCardEditor(initialText: String) {
        let content = VYBEMemoryCardEditor(initialText: initialText) { [weak self] in self?.capturePanel?.orderOut(nil) }
        let panel = capturePanel ?? makePanel(size: NSSize(width: 520, height: 420), identifier: "vybe-memory-card") { content }
        capturePanel = panel
        panel.setContentSize(NSSize(width: 520, height: 420))
        panel.contentView = NSHostingView(rootView: content)
        show(panel)
    }

    private func openFileConverter() {
        if let selected = finderSelectedFile() {
            showConverter(for: selected)
            return
        }
        let picker = NSOpenPanel()
        picker.title = "Choose a file to convert"
        picker.message = "Select an image, video or PDF. The original file will never be overwritten."
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor in self?.showConverter(for: url) }
        }
    }

    private func finderSelectedFile() -> URL? {
        // If Finder is frontmost, use its selected file; otherwise present a file picker.
        guard let pid = radialReturnPID,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" else { return nil }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        let script = NSAppleScript(source: "tell application \"Finder\" to get POSIX path of (selection as alias list)")
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), result.numberOfItems > 0,
              let path = result.atIndex(1)?.stringValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func showConverter(for url: URL) {
        let content = VYBEFileConverterView(sourceURL: url) { [weak self] in self?.converterPanel?.orderOut(nil) }
        let panel = converterPanel ?? makePanel(size: NSSize(width: 560, height: 430), identifier: "vybe-file-converter") { content }
        converterPanel = panel
        panel.setContentSize(NSSize(width: 560, height: 430))
        panel.contentView = NSHostingView(rootView: content)
        show(panel)
    }

    private func captureAndRecognizeScreen() {
        // User explicitly chooses the screen region to share. No continuous screen
        // capture or background OCR is performed; the selected image is sent to AI.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VYBE-Screenshot-AI-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus == 0,
                  let image = NSImage(contentsOf: url),
                  let data = try? Data(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url)
                return // User cancelled the screenshot selector or capture failed.
            }
            Task { @MainActor in
                self?.analyzeScreenshot(data: data, image: image, temporaryURL: url)
            }
        }
        do {
            try process.run()
            VYBEHUD.shared.show("TAKE A SCREENSHOT", detail: "Select the area you want VYBE AI to understand", symbol: "camera.viewfinder")
        } catch {
            VYBEHUD.shared.show("SCREENSHOT FAILED", detail: error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    private func analyzeScreenshot(data: Data, image: NSImage, temporaryURL: URL) {
        showScreenshotAnalysis(image: image, analysis: "Analyzing your screenshot with VYBE AI…")
        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            do {
                let result = try await OpenRouterService.shared.analyzeScreenshot(data: data)
                self.showScreenshotAnalysis(image: image, analysis: result)
            } catch {
                self.showScreenshotAnalysis(image: image, analysis: "Could not analyze this screenshot. \(error.localizedDescription)\n\nCheck that an OpenRouter API key is configured and that your selected free model supports image input.")
            }
        }
    }

    private func showUtilityImage(_ image: NSImage, title: String) {
        let content = VYBEUtilityImageView(image: image, title: title) { [weak self] in
            self?.closeUtilityPanel()
        }
        let panel = utilityPanel ?? makePanel(size: NSSize(width: 430, height: 470), identifier: "vybe-utility-image") { content }
        utilityPanel = panel
        panel.setContentSize(NSSize(width: 430, height: 470))
        panel.contentView = NSHostingView(rootView: content)
        show(panel)
    }

    private func closeUtilityPanel() {
        utilityPanel?.orderOut(nil)
    }

    private func showScreenshotAnalysis(image: NSImage, analysis: String) {
        let content = VYBEScreenshotAnalysisView(image: image, analysis: analysis) { [weak self] in
            self?.closeUtilityPanel()
        }
        let panel = utilityPanel ?? makePanel(size: NSSize(width: 620, height: 680), identifier: "vybe-screenshot-ai") { content }
        utilityPanel = panel
        panel.setContentSize(NSSize(width: 620, height: 680))
        panel.contentView = NSHostingView(rootView: content)
        show(panel)
    }

    private func makePanel<Content: View>(size: NSSize, identifier: String, @ViewBuilder content: () -> Content) -> VYBEOverlayPanel {
        let panel = VYBEOverlayPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content())
        return panel
    }

    private func show(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                     y: visible.midY - panel.frame.height / 2))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Safe arithmetic parser for the radial calculator

private struct VYBEMathParser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) { characters = Array(expression) }

    mutating func evaluate() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipSpaces()
        return index == characters.count ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while true {
            skipSpaces()
            guard index < characters.count, characters[index] == "+" || characters[index] == "-" else { return value }
            let operation = characters[index]; index += 1
            guard let rhs = parseTerm() else { return nil }
            value = operation == "+" ? value + rhs : value - rhs
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parseFactor() else { return nil }
        while true {
            skipSpaces()
            guard index < characters.count, characters[index] == "*" || characters[index] == "/" else { return value }
            let operation = characters[index]; index += 1
            guard let rhs = parseFactor() else { return nil }
            if operation == "/" && rhs == 0 { return nil }
            value = operation == "*" ? value * rhs : value / rhs
        }
    }

    private mutating func parseFactor() -> Double? {
        skipSpaces()
        guard index < characters.count else { return nil }
        if characters[index] == "+" { index += 1; return parseFactor() }
        if characters[index] == "-" { index += 1; return parseFactor().map { -$0 } }
        if characters[index] == "(" {
            index += 1
            guard let value = parseExpression() else { return nil }
            skipSpaces()
            guard index < characters.count, characters[index] == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        var decimalSeen = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber { index += 1; continue }
            if character == ".", !decimalSeen { decimalSeen = true; index += 1; continue }
            break
        }
        guard index > start, let number = Double(String(characters[start..<index])) else { return nil }
        skipSpaces()
        if index < characters.count, characters[index] == "%" { index += 1; return number / 100 }
        return number
    }

    private mutating func skipSpaces() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }
}

// MARK: - VYBE Command

private struct VYBECommandResult: Identifiable {
    enum Action {
        case app(URL), space(UUID), control, wallpaper, dock, assistant
    }
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let action: Action
    var iconURL: URL? = nil
}

struct VYBECommandView: View {
    let onClose: () -> Void
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    @ObservedObject private var spaces = VYBESpaceManager.shared

    private var results: [VYBECommandResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items: [VYBECommandResult] = [
            .init(title: "Open VYBE Control Centre", subtitle: "Desktop settings and configuration", symbol: "slider.horizontal.3", action: .control),
            .init(title: "Toggle video / static wallpaper", subtitle: "Switch the active desktop background", symbol: "rectangle.on.rectangle", action: .wallpaper),
            .init(title: "Toggle VYBE Dock", subtitle: "Show or hide the floating Dock", symbol: "dock.rectangle", action: .dock),
            .init(title: "Open VYBE AI", subtitle: "Voice and text assistant", symbol: "waveform", action: .assistant)
        ]
        items += spaces.spaces.map { .init(title: "Switch to \($0.name)", subtitle: "VYBE Space", symbol: $0.symbol, action: .space($0.id)) }
        items += Self.applicationURLs.map { url in
            .init(title: url.deletingPathExtension().lastPathComponent, subtitle: url.path,
                  symbol: "app", action: .app(url), iconURL: url)
        }
        guard !q.isEmpty else { return Array(items.prefix(12)) }
        return items.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }.prefix(18).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "command").font(.system(size: 20, weight: .light)).foregroundStyle(.cyan)
                TextField("Search apps, Spaces and actions…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 18, weight: .medium))
                    .focused($focused)
                    .onChange(of: query) { _ in selectedIndex = 0 }
                    .onSubmit { runSelected() }
                Text("ESC").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(6).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
            Rectangle().fill(Color.cyan.opacity(0.24)).frame(height: 1)
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(.cyan.opacity(0.7))
                    Text("NO MATCHING COMMANDS").font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text("Try an app name, Space or VYBE action.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(results.indices, id: \.self) { index in
                            let item = results[index]
                            Button {
                                selectedIndex = index
                                run(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Group {
                                        if let iconURL = item.iconURL {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                                                .resizable().aspectRatio(contentMode: .fit)
                                        } else {
                                            Image(systemName: item.symbol).font(.system(size: 16)).foregroundStyle(.cyan)
                                        }
                                    }.frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.system(size: 12, weight: .semibold))
                                        Text(item.subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                    }
                                    Spacer()
                                    if index == selectedIndex { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.cyan) }
                                }
                                .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 9)
                                .background(index == selectedIndex ? Color.cyan.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(12)
                }
            }
            HStack {
                Text("VYBE COMMAND").tracking(1.6)
                Spacer()
                Text("⌘⌥SPACE  •  ↑↓ NAVIGATE  •  RETURN SELECT")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.36))
            .padding(.horizontal, 18).padding(.vertical, 11)
        }
        .frame(width: 620, height: 430)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.15), radius: 35)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            if direction == .down { selectedIndex = min(selectedIndex + 1, results.count - 1) }
            if direction == .up { selectedIndex = max(selectedIndex - 1, 0) }
        }
    }

    private func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        run(results[selectedIndex])
    }

    private func run(_ item: VYBECommandResult) {
        switch item.action {
        case .app(let url): NSWorkspace.shared.open(url)
        case .space(let id): spaces.activate(id)
        case .control: DesktopEnvironment.shared.showControlCentre()
        case .wallpaper:
            let engine = WallpaperEngine.shared
            engine.setVideoBackgroundEnabled(!engine.isVideoBackgroundEnabled)
        case .dock: DesktopEnvironment.shared.toggleDockVisibility()
        case .assistant: VYBEAssistantWindow.shared.toggleAndListen()
        }
        onClose()
    }

    private static let applicationURLs: [URL] = installedApps()

    private static func installedApps() -> [URL] {
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        var found: [URL] = []
        for path in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else { continue }
            found += urls.filter { $0.pathExtension == "app" }
        }
        return found.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}

// MARK: - Custom radial actions

enum VYBERadialActionKind: String, Codable {
    case openURL, voiceAssistant, dictation, openApp
    case cleanClipboard, searchClipboard, translateClipboard, calculateClipboard, quickNote
    case screenshotOCR, generatePassword, toggleDesktopIcons, saveClipboard, makeQR, openClipboardURL, focusSprint, convertFile
}

struct VYBERadialAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var symbol: String
    var kind: VYBERadialActionKind
    var payload: String = ""

    static let defaults: [VYBERadialAction] = [
        .init(title: "Safari", symbol: "safari", kind: .openApp, payload: "com.apple.Safari"),
        .init(title: "Voice AI", symbol: "waveform", kind: .voiceAssistant),
        .init(title: "Dictate", symbol: "mic.fill", kind: .dictation),
        .init(title: "Clean Text", symbol: "text.alignleft", kind: .cleanClipboard),
        .init(title: "Web Search", symbol: "magnifyingglass", kind: .searchClipboard),
        .init(title: "Translate", symbol: "character.bubble", kind: .translateClipboard),
        .init(title: "Calculate", symbol: "function", kind: .calculateClipboard),
        .init(title: "Memory Card", symbol: "square.stack.3d.up.fill", kind: .quickNote),
        .init(title: "Screenshot AI", symbol: "camera.viewfinder", kind: .screenshotOCR),
        .init(title: "Password", symbol: "key.fill", kind: .generatePassword),
        .init(title: "Desktop Icons", symbol: "macwindow", kind: .toggleDesktopIcons),
        .init(title: "Save Clipboard", symbol: "square.and.arrow.down", kind: .saveClipboard),
        .init(title: "QR Code", symbol: "qrcode", kind: .makeQR),
        .init(title: "Open Link", symbol: "link", kind: .openClipboardURL),
        .init(title: "Focus 25", symbol: "timer", kind: .focusSprint),
        .init(title: "Convert File", symbol: "arrow.trianglehead.2.clockwise.rotate.90", kind: .convertFile)
    ]
}

@MainActor
final class VYBERadialActionStore: ObservableObject {
    static let shared = VYBERadialActionStore()
    @Published private(set) var actions: [VYBERadialAction] = []
    private let key = "VYBE.radial.customActions.v1"

    private init() {
        // v3 migration repairs installations whose earlier saved radial array
        // contained only a partial set of built-in actions. Preserve user-added
        // actions and IDs, then append any missing built-ins exactly once.
        let migrationKey = "VYBE.radial.defaults.v4.migrated"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([VYBERadialAction].self, from: data) {
            var merged = saved
            for index in merged.indices where merged[index].kind == .quickNote {
                merged[index].title = "Memory Card"
                merged[index].symbol = "square.stack.3d.up.fill"
            }
            if !UserDefaults.standard.bool(forKey: migrationKey) {
                for item in VYBERadialAction.defaults where !merged.contains(where: { $0.kind == item.kind && $0.title == item.title && $0.payload == item.payload }) {
                    merged.append(item)
                }
                UserDefaults.standard.set(true, forKey: migrationKey)
            }
            actions = Array(merged.prefix(22))
            if actions.count != saved.count { persist() }
        } else {
            actions = VYBERadialAction.defaults
            UserDefaults.standard.set(true, forKey: migrationKey)
            persist()
        }
    }

    func restoreBuiltInActions() {
        var merged = actions
        for item in VYBERadialAction.defaults where !merged.contains(where: { $0.kind == item.kind && $0.title == item.title && $0.payload == item.payload }) {
            merged.append(item)
        }
        actions = Array(merged.prefix(22))
        persist()
    }

    func add(_ action: VYBERadialAction) {
        guard actions.count < 22,
              !actions.contains(where: { $0.kind == action.kind && $0.title == action.title && $0.payload == action.payload }) else { return }
        actions.append(action)
        persist()
    }

    func remove(_ id: UUID) { actions.removeAll { $0.id == id }; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(actions) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Global dictation

@MainActor
final class VYBEGlobalDictation: ObservableObject {
    static let shared = VYBEGlobalDictation()
    @Published private(set) var isListening = false
    @Published private(set) var liveText = ""
    @Published private(set) var statusMessage = "Ready to dictate"

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggle() {
        if isListening { stop() }
        else { start() }
    }

    func start() {
        guard !isListening else { return }
        // Dictation is a capture workflow, not keyboard injection. The transcript
        // remains in VYBE's panel until the user explicitly copies it.
        requestPermissionsAndStart()
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        statusMessage = "Dictation stopped"
        // Keep the transcript panel open after stopping so it can be reviewed/copied.
    }

    private func requestPermissionsAndStart() {
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Apple Speech Recognition is unavailable for the selected language."
            VYBEHUD.shared.show("SPEECH UNAVAILABLE", detail: statusMessage, symbol: "mic.slash")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.statusMessage = "Microphone access was denied."
                    VYBEHUD.shared.show("MICROPHONE BLOCKED", detail: "Allow VYBE in Privacy & Security → Microphone", symbol: "mic.slash")
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    guard let self else { return }
                    guard status == .authorized else {
                        self.statusMessage = "Speech Recognition permission was denied."
                        VYBEHUD.shared.show("SPEECH ACCESS BLOCKED", detail: "Allow VYBE in Privacy & Security → Speech Recognition", symbol: "mic.slash")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        Task { @MainActor in self?.begin(using: recognizer) }
                    }
                }
            }
        }
    }

    private func begin(using recognizer: SFSpeechRecognizer) {
        guard !isListening else { return }
        liveText = ""
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        speechRequest.addsPunctuation = true
        request = speechRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusMessage = "No usable microphone input is available."
            VYBEHUD.shared.show("NO AUDIO INPUT", detail: statusMessage, symbol: "mic.slash")
            request = nil
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            speechRequest.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
            request = nil
            statusMessage = "Could not start microphone: \(error.localizedDescription)"
            VYBEHUD.shared.show("DICTATION FAILED", detail: statusMessage, symbol: "exclamationmark.triangle")
            return
        }

        isListening = true
        statusMessage = "Listening — words appear as you speak"
        VYBEOverlayController.shared.showDictationHUD()
        task = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.liveText = transcript
                    if result.isFinal { self.stop() }
                }
                if let error {
                    self.statusMessage = error.localizedDescription
                    if self.liveText.isEmpty { VYBEHUD.shared.show("DICTATION ERROR", detail: error.localizedDescription, symbol: "exclamationmark.triangle") }
                    self.stop()
                }
            }
        }
    }


}

struct VYBEDictationHUDView: View {
    @ObservedObject private var dictation = VYBEGlobalDictation.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: dictation.isListening ? "waveform" : "waveform.circle.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("VYBE DICTATION STUDIO").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.1)
                    Text(dictation.isListening ? "Listening · transcript updates live" : "Transcript ready · review and copy")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button { VYBEOverlayController.shared.dismissDictationHUD() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28)
                        .background(.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help("Close dictation panel")
            }
            ScrollView {
                Text(dictation.liveText.isEmpty ? (dictation.isListening ? "Start speaking…" : "Your transcript will appear here.") : dictation.liveText)
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).padding(10)
            }
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
            HStack {
                Button { VYBEOverlayController.shared.copyDictationText() } label: { Label("Copy transcript", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent).tint(.cyan).disabled(dictation.liveText.isEmpty)
                Spacer()
                if dictation.isListening {
                    Button { dictation.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered)
                } else {
                    Button("Done") { VYBEOverlayController.shared.hideDictationHUD() }.buttonStyle(.bordered)
                }
            }
        }
        .padding(16).foregroundStyle(.white)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.2), radius: 24)
        .preferredColorScheme(.dark)
        .onExitCommand { VYBEOverlayController.shared.dismissDictationHUD() }
    }
}

struct VYBEMemoryCardEditor: View {
    let initialText: String
    let onClose: () -> Void
    @State private var title = "Untitled thought"
    @State private var bodyText = ""
    @State private var savedMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VYBE MEMORY CARDS", systemImage: "square.stack.3d.up.fill").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                Spacer(); Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
            Text("A private capture space inside VYBE — not Apple Notes.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            TextField("Card title", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $bodyText).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(savedMessage).font(.system(size: 9)).foregroundStyle(.green)
                Spacer()
                Button("Save Memory Card") { saveCard() }.buttonStyle(.borderedProminent).tint(.cyan)
            }
        }
        .padding(18).frame(width: 520, height: 420)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.45), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onAppear { bodyText = initialText }
    }

    private func saveCard() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VYBE/Memory Cards", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled thought" : title
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(6))-\(safeTitle.replacingOccurrences(of: "/", with: "-")).md")
            try ("# \(safeTitle)\n\n\(bodyText)\n").write(to: url, atomically: true, encoding: .utf8)
            savedMessage = "Saved in VYBE / Memory Cards"
        } catch { savedMessage = "Could not save: \(error.localizedDescription)" }
    }
}

struct VYBEFileConverterView: View {
    let sourceURL: URL
    let onClose: () -> Void
    @State private var status = "Choose an output format. Original file is preserved."
    @State private var isWorking = false

    private var ext: String { sourceURL.pathExtension.lowercased() }
    private var isImage: Bool { ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "jp2", "icns", "ico"].contains(ext) }
    private var isPDF: Bool { ext == "pdf" }
    private var isVideo: Bool { ["mov", "mp4", "m4v", "3gp"].contains(ext) }
    private var isAudio: Bool { ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "flac"].contains(ext) }
    private var isPagesDocument: Bool { ext == "pages" }
    private var isKeynoteDocument: Bool { ext == "key" }
    private var isWordDocument: Bool { ext == "docx" || ext == "doc" }
    private var isPowerPointDocument: Bool { ext == "pptx" || ext == "ppt" }
    private var availableImageFormats: [String] {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let candidates: [(String, String)] = [("PNG", "public.png"), ("JPEG", "public.jpeg"), ("HEIC", "public.heic"), ("TIFF", "public.tiff"), ("GIF", "com.compuserve.gif"), ("BMP", "com.microsoft.bmp"), ("WebP", "public.webp"), ("JPEG 2000", "public.jpeg-2000"), ("PDF", "com.adobe.pdf")]
        return candidates.filter { supported.contains($0.1) && $0.0.lowercased().replacingOccurrences(of: " ", with: "") != ext }.map(\.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Label("VYBE FILE CONVERTER", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan); Spacer(); Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceURL.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(ext.uppercased()) · \(sourceURL.deletingLastPathComponent().path)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Text("CONVERT TO").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            if isImage {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(availableImageFormats, id: \.self) { format in formatButton(format) }
                }
            } else if isPDF {
                HStack { formatButton("PNG pages"); formatButton("JPEG pages") }
                Text("PDF → Pages is not a direct faithful format conversion. VYBE can export pages as images; editable Pages reconstruction needs OCR/document layout processing.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isVideo {
                HStack { formatButton("MP4"); formatButton("MOV"); formatButton("M4V"); formatButton("M4A Audio") }
                Text("Video conversion uses macOS AVFoundation export presets. Some codecs and containers depend on the source file.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isAudio {
                formatButton("M4A")
                Text("Audio conversion uses macOS AVFoundation where the source codec is supported.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isPagesDocument {
                HStack { formatButton("DOCX"); formatButton("PDF") }
                Text("Uses Apple Pages if installed. Export availability depends on the Pages version.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isKeynoteDocument {
                HStack { formatButton("PPTX"); formatButton("PDF") }
                Text("Uses Apple Keynote if installed. Export availability depends on the Keynote version.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isWordDocument {
                formatButton("PDF")
                Text("Uses Apple Pages to open the Word document and export a PDF.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else if isPowerPointDocument {
                formatButton("PDF")
                Text("Uses Apple Keynote to open the presentation and export a PDF.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else {
                Text("This file type needs an installed specialist app or an additional conversion engine. VYBE will not rename the extension and pretend it converted the contents.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            HStack { if isWorking { ProgressView().controlSize(.small) }; Text(status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(3); Spacer() }
        }
        .padding(18).frame(width: 560, height: 430)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.45), lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func formatButton(_ format: String) -> some View {
        Button(format) { convert(format) }.buttonStyle(.borderedProminent).tint(.cyan).disabled(isWorking)
    }

    private func convert(_ format: String) {
        isWorking = true; status = "Converting…"
        let source = sourceURL
        Task.detached(priority: .userInitiated) {
            do {
                let output = try await VYBEFileConversion.convert(source: source, format: format)
                await MainActor.run { status = "Created \(output.lastPathComponent)"; isWorking = false; NSWorkspace.shared.activateFileViewerSelecting([output]) }
            } catch {
                await MainActor.run { status = error.localizedDescription; isWorking = false }
            }
        }
    }
}

enum VYBEFileConversion {
    private static func uniqueOutput(base: URL, suffix: String) -> URL {
        let stem = base.lastPathComponent + "-converted"
        var candidate = base.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(suffix)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent().appendingPathComponent(stem + "-\(counter)").appendingPathExtension(suffix)
            counter += 1
        }
        return candidate
    }

    static func convert(source: URL, format: String) async throws -> URL {
        let base = source.deletingPathExtension()
        let suffix = format.lowercased().replacingOccurrences(of: " pages", with: "").replacingOccurrences(of: " audio", with: "").replacingOccurrences(of: "jpeg 2000", with: "jp2")
        if suffix == "png" || suffix == "jpeg", source.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: source) else { throw NSError(domain: "VYBEConvert", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not open this PDF."]) }
            let parent = base.deletingLastPathComponent()
            let folderStem = base.lastPathComponent + "-" + suffix.uppercased() + "-Pages"
            var folder = parent.appendingPathComponent(folderStem, isDirectory: true)
            var folderIndex = 2
            while FileManager.default.fileExists(atPath: folder.path) {
                folder = parent.appendingPathComponent(folderStem + "-\(folderIndex)", isDirectory: true)
                folderIndex += 1
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = min(2.0, 3000 / max(bounds.width, bounds.height))
                let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: suffix == "png", isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: rep) else {
                    throw NSError(domain: "VYBEConvert", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not allocate an image buffer for this PDF page."])
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                NSColor.white.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
                context.cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                NSGraphicsContext.restoreGraphicsState()
                let type: NSBitmapImageRep.FileType = suffix == "png" ? .png : .jpeg
                guard let data = rep.representation(using: type, properties: [:]) else { continue }
                try data.write(to: folder.appendingPathComponent(String(format: "Page-%03d.%@", index + 1, suffix)), options: .atomic)
            }
            return folder
        }
        if ["png", "jpeg", "heic", "tiff", "gif", "bmp", "webp", "jp2", "pdf"].contains(suffix) {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { throw NSError(domain: "VYBEConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "This image could not be decoded."]) }
            let uti: String = ["jpeg": "public.jpeg", "png": "public.png", "heic": "public.heic", "tiff": "public.tiff", "gif": "com.compuserve.gif", "bmp": "com.microsoft.bmp", "webp": "public.webp", "jp2": "public.jpeg-2000", "pdf": "com.adobe.pdf"][suffix] ?? "public.png"
            let output = uniqueOutput(base: base, suffix: suffix)
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, uti as CFString, 1, nil) else { throw NSError(domain: "VYBEConvert", code: 2, userInfo: [NSLocalizedDescriptionKey: "macOS does not support writing this image format on this system."]) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "VYBEConvert", code: 3, userInfo: [NSLocalizedDescriptionKey: "Image export failed."]) }
            return output
        }
        if ["mp4", "mov", "m4v", "m4a"].contains(suffix) {
            let asset = AVURLAsset(url: source)
            let preset = suffix == "m4a" ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw NSError(domain: "VYBEConvert", code: 5, userInfo: [NSLocalizedDescriptionKey: "No compatible video export session is available."]) }
            let output = uniqueOutput(base: base, suffix: suffix)
            session.outputURL = output
            guard let fileType = ["mp4": AVFileType.mp4, "mov": AVFileType.mov, "m4v": AVFileType.m4v, "m4a": AVFileType.m4a][suffix],
                  session.supportedFileTypes.contains(fileType) else {
                throw NSError(domain: "VYBEConvert", code: 7, userInfo: [NSLocalizedDescriptionKey: "This source cannot be exported to .\(suffix) with the available macOS codecs."])
            }
            session.outputFileType = fileType
            session.shouldOptimizeForNetworkUse = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed: continuation.resume()
                    case .failed: continuation.resume(throwing: session.error ?? NSError(domain: "VYBEConvert", code: 8, userInfo: [NSLocalizedDescriptionKey: "Video export failed."]))
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default: continuation.resume(throwing: NSError(domain: "VYBEConvert", code: 9, userInfo: [NSLocalizedDescriptionKey: "Video export ended unexpectedly."]))
                    }
                }
            }
            return output
        }
        let documentApp: String?
        let appleScriptFormat: String?
        switch (source.pathExtension.lowercased(), suffix) {
        case ("pages", "docx"): documentApp = "Pages"; appleScriptFormat = "Microsoft Word"
        case ("pages", "pdf"): documentApp = "Pages"; appleScriptFormat = "PDF"
        case ("key", "pptx"): documentApp = "Keynote"; appleScriptFormat = "Microsoft PowerPoint"
        case ("key", "pdf"): documentApp = "Keynote"; appleScriptFormat = "PDF"
        case ("docx", "pdf"), ("doc", "pdf"): documentApp = "Pages"; appleScriptFormat = "PDF"
        case ("pptx", "pdf"), ("ppt", "pdf"): documentApp = "Keynote"; appleScriptFormat = "PDF"
        default: documentApp = nil; appleScriptFormat = nil
        }
        if let documentApp, let appleScriptFormat {
            let output = uniqueOutput(base: base, suffix: suffix)
            let sourcePath = source.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let outputPath = output.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            try await MainActor.run {
                let script = "tell application \"\(documentApp)\"\nset sourceDoc to open POSIX file \"\(sourcePath)\"\nexport sourceDoc to POSIX file \"\(outputPath)\" as \(appleScriptFormat)\nclose sourceDoc saving no\nend tell"
                var errorInfo: NSDictionary?
                guard let appleScript = NSAppleScript(source: script), appleScript.executeAndReturnError(&errorInfo) != nil else {
                    let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "\(documentApp) could not export this document."
                    throw NSError(domain: "VYBEConvert", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
                }
            }
            return output
        }
        throw NSError(domain: "VYBEConvert", code: 6, userInfo: [NSLocalizedDescriptionKey: "This format pair is not supported by the installed macOS conversion engines."])
    }
}

struct VYBEUtilityImageView: View {
    let image: NSImage
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(.cyan)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help("Close")
            }
            Image(nsImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit).padding(12)
            Text("Generated from your clipboard").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            Button("Close", action: onClose).buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 430, height: 470)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cyan.opacity(0.42), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onExitCommand(perform: onClose)
    }
}

struct VYBEScreenshotAnalysisView: View {
    let image: NSImage
    let analysis: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("VYBE SCREENSHOT AI", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help("Close")
            }
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 290)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
            Text("AI ANALYSIS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.cyan.opacity(0.8))
            ScrollView {
                Text(analysis).font(.system(size: 12)).foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Button("Close", action: onClose).buttonStyle(.bordered)
        }
        .padding(18)
        .frame(width: 620, height: 680)
        .background(Color(red: 0.025, green: 0.045, blue: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cyan.opacity(0.42), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onExitCommand(perform: onClose)
    }
}

// MARK: - Radial Launcher

struct VYBERadialView: View {
    let onClose: () -> Void
    @ObservedObject private var spaces = VYBESpaceManager.shared
    @ObservedObject private var actionStore = VYBERadialActionStore.shared
    @State private var showAddMenu = false
    @State private var customTitle = ""
    @State private var customURL = ""
    @State private var showCustomEditor = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.78)).overlay(Circle().stroke(Color.cyan.opacity(0.42), lineWidth: 1)).padding(20)
            Circle().stroke(Color.cyan.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 6])).padding(52)
            VStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 28, weight: .light)).foregroundStyle(.cyan)
                Text("VYBE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                Text("RADIAL COMMAND").font(.system(size: 7, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                Text("⌃ ⌥ G").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.cyan.opacity(0.8))
            }
            ForEach(Array(spaces.spaces.enumerated()), id: \.element.id) { index, space in
                let angle = Double(index) * (2 * Double.pi / Double(max(spaces.spaces.count, 1))) - .pi / 2
                Button {
                    spaces.activate(space.id)
                    onClose()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: space.symbol).font(.system(size: 17))
                        Text(space.name).font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(spaces.activeSpaceID == space.id ? Color.cyan : .white)
                    .frame(width: 72, height: 62)
                    .background(.white.opacity(spaces.activeSpaceID == space.id ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.cyan.opacity(spaces.activeSpaceID == space.id ? 0.6 : 0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(cos(angle)) * 126, y: CGFloat(sin(angle)) * 126)
            }
            ForEach(Array(actionStore.actions.enumerated()), id: \.element.id) { index, action in
                let angle = Double(index) * (2 * Double.pi / Double(max(actionStore.actions.count, 1))) - .pi / 2
                Button { VYBEOverlayController.shared.runRadialAction(action) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol).font(.system(size: 15, weight: .medium))
                        Text(action.title).font(.system(size: 8, weight: .semibold, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 60)
                    .background(Color.purple.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(cos(angle)) * 300, y: CGFloat(sin(angle)) * 300)
                .contextMenu { Button("Remove Button", role: .destructive) { actionStore.remove(action.id) } }
            }
            Button { DesktopEnvironment.shared.showControlCentre(); onClose() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.cyan.opacity(0.18), in: Circle())
            }.buttonStyle(.plain).offset(x: -44, y: 0)
            Button { VYBEAssistantWindow.shared.toggleAndListen(); onClose() } label: {
                Image(systemName: "waveform").font(.system(size: 14)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Color.purple.opacity(0.22), in: Circle())
            }.buttonStyle(.plain).offset(x: 44, y: 0)
            Menu {
                Button { actionStore.restoreBuiltInActions() } label: { Label("Restore All Built-in Actions", systemImage: "arrow.counterclockwise") }
                Divider()
                Button { actionStore.add(.init(title: "Safari", symbol: "safari", kind: .openApp, payload: "com.apple.Safari")) } label: { Label("Add Safari", systemImage: "safari") }
                Button { actionStore.add(.init(title: "Voice AI", symbol: "waveform", kind: .voiceAssistant)) } label: { Label("Add Voice Recognition", systemImage: "waveform") }
                Button { actionStore.add(.init(title: "Dictate", symbol: "mic.fill", kind: .dictation)) } label: { Label("Add Speech-to-Text", systemImage: "mic.fill") }
                Button { actionStore.add(.init(title: "Screenshot AI", symbol: "camera.viewfinder", kind: .screenshotOCR)) } label: { Label("Add Screenshot AI", systemImage: "camera.viewfinder") }
                Button { actionStore.add(.init(title: "Memory Card", symbol: "square.stack.3d.up.fill", kind: .quickNote)) } label: { Label("Add Memory Card", systemImage: "square.stack.3d.up.fill") }
                Button { actionStore.add(.init(title: "Convert File", symbol: "arrow.trianglehead.2.clockwise.rotate.90", kind: .convertFile)) } label: { Label("Add File Converter", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                Button { showCustomEditor = true } label: { Label("Add Website / App URL…", systemImage: "plus.circle") }
                if !actionStore.actions.isEmpty {
                    Divider()
                    ForEach(actionStore.actions) { action in
                        Button("Remove \(action.title)", role: .destructive) { actionStore.remove(action.id) }
                    }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(.white.opacity(0.12), in: Circle()).overlay(Circle().stroke(.cyan.opacity(0.5), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .offset(x: 0, y: 78)
            .help("Customize radial buttons")
        }
        .frame(width: 720, height: 720)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: onClose)
        .alert("Add Custom Radial Button", isPresented: $showCustomEditor) {
            TextField("Button name", text: $customTitle)
            TextField("https://example.com or app URL", text: $customURL)
            Button("Add") {
                let raw = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = raw.contains("://") ? raw : "https://\(raw)"
                if !customTitle.isEmpty, URL(string: normalized) != nil {
                    actionStore.add(.init(title: customTitle, symbol: "globe", kind: .openURL, payload: normalized))
                }
                customTitle = ""; customURL = ""
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Create a button that opens a website or app URL. Custom URLs are stored on this Mac.") }
    }
}

// MARK: - Spaces control surface

struct VYBESpacesView: View {
    @ObservedObject private var manager = VYBESpaceManager.shared
    @ObservedObject private var backgrounds = VYBEBackgroundPresets.shared
    @State private var editingID: UUID?
    @State private var editedName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VYBE SPACES", systemImage: "square.3.layers.3d")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2)
                Spacer()
                Button { manager.createSpace() } label: { Label("New Space", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.cyan)
            }
            Text("Independent VYBE workspaces. Switching applies each Space's saved widgets and static wallpaper; this does not replace Apple's native Mission Control Spaces.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
            ForEach(manager.spaces) { space in
                HStack(spacing: 10) {
                    Image(systemName: space.symbol).font(.system(size: 16)).foregroundStyle(.cyan).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(space.name).font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("\(space.widgetIDs.count) widgets  •  \(space.wallpaperPreset)")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    if manager.activeSpaceID == space.id {
                        Text("ACTIVE").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                    } else {
                        Button("Activate") { manager.activate(space.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Button { editingID = space.id; editedName = space.name } label: {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }.buttonStyle(.borderless)
                    Button(role: .destructive) { manager.delete(space.id) } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }.buttonStyle(.borderless).disabled(manager.spaces.count <= 1)
                }
                .padding(10).background(manager.activeSpaceID == space.id ? Color.cyan.opacity(0.10) : .white.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 10))
            }
            if manager.activeSpaceID == manager.activeSpace.id {
                HStack {
                    Text("ACTIVE WALLPAPER").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Picker("Wallpaper", selection: Binding(get: { backgrounds.selectedName }, set: {
                        backgrounds.apply($0); manager.updateActiveWallpaper($0)
                    })) {
                        ForEach(backgrounds.names, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 170)
                }
            }
            Button { manager.saveCurrentConfiguration(); VYBEHUD.shared.show("SPACE SAVED", detail: "Current layout stored", symbol: "checkmark") } label: {
                Label("Save current Space layout", systemImage: "square.and.arrow.down")
            }.buttonStyle(.borderless).font(.system(size: 10))
        }
        .sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            VStack(spacing: 14) {
                Text("RENAME SPACE").font(.system(size: 12, weight: .bold, design: .monospaced))
                TextField("Space name", text: $editedName).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { editingID = nil }
                    Spacer()
                    Button("Save") { if let id = editingID { manager.rename(id, to: editedName) }; editingID = nil }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(22).frame(width: 300).preferredColorScheme(.dark)
        }
    }
}
