import AppKit
import SwiftUI
import Combine

/// VYBE-branded manager for the MIT-licensed AnyDisplay host.
/// The virtual-display, capture, codec, pairing and Android receiver engines remain upstream
/// components; VYBE installs and launches the host and presents the connection workflow.
@MainActor
final class VYBEDisplayManager: ObservableObject {
    static let shared = VYBEDisplayManager()

    @Published private(set) var isInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var isInstalling = false
    @Published private(set) var status = "Checking display engine…"
    @Published private(set) var installedPath: URL?

    static let releaseTag = "v0.1.3"
    static let hostDownloadURL = URL(string: "https://github.com/efekurucay/anydisplay/releases/download/v0.1.3/AnyDisplay-macOS.zip")!
    static let receiverDownloadURL = URL(string: "https://github.com/efekurucay/anydisplay/releases/download/v0.1.3/AnyDisplay.apk")!
    static let projectURL = URL(string: "https://github.com/efekurucay/anydisplay")!
    static let setupURL = URL(string: "https://efekurucay.com/anydisplay/")!

    private let bundleID = "dev.anydisplay.host"
    private let supportDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDirectory = base.appendingPathComponent("VYBE/Display", isDirectory: true)
        refresh()
    }

    private var appCandidates: [URL] {
        [
            supportDirectory.appendingPathComponent("AnyDisplay.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/AnyDisplay.app", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/AnyDisplay.app", isDirectory: true),
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        ].compactMap { $0 }
    }

    private func isValidHostBundle(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path),
              let bundle = Bundle(url: url) else { return false }
        return bundle.bundleIdentifier == bundleID
    }

    func refresh() {
        installedPath = appCandidates.first(where: { isValidHostBundle(at: $0) })
        isInstalled = installedPath != nil
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard !isInstalling else { return }
        if isRunning {
            status = "Display host is running"
        } else if isInstalled {
            status = "Display host installed · ready to connect"
        } else {
            status = "Display engine not installed"
        }
    }

    /// Called when VYBE launches. It never downloads or reinstalls the host;
    /// it only starts the already-installed copy when it is not running.
    func launchInstalledHostIfNeeded() {
        refresh()
        guard isInstalled, !isRunning,
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 else { return }
        launchHost()
    }

    func installAndLaunch() async {
        guard !isInstalling else { return }
        refresh()
        if isInstalled {
            launchHost()
            return
        }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 else {
            status = "VYBE Display requires macOS 14 or newer."
            return
        }
        isInstalling = true
        status = "Downloading VYBE Display engine…"
        defer { isInstalling = false }

        do {
            let (archive, response) = try await URLSession.shared.download(from: Self.hostDownloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DisplayInstallError.downloadFailed(http.statusCode)
            }

            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let extraction = supportDirectory.appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: extraction) }

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, extraction.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { throw DisplayInstallError.extractFailed }

            let enumerator = FileManager.default.enumerator(at: extraction, includingPropertiesForKeys: [.isDirectoryKey])
            var appURL: URL?
            while let item = enumerator?.nextObject() as? URL {
                if item.lastPathComponent == "AnyDisplay.app" {
                    appURL = item
                    break
                }
            }
            guard let source = appURL else { throw DisplayInstallError.appNotFound }

            let destination = supportDirectory.appendingPathComponent("AnyDisplay.app", isDirectory: true)
            if isValidHostBundle(at: destination) {
                installedPath = destination
                isInstalled = true
                status = "Existing display engine found · launching…"
                launchHost()
                return
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                let backup = supportDirectory.appendingPathComponent("AnyDisplay-invalid-\(UUID().uuidString).app", isDirectory: true)
                try FileManager.default.moveItem(at: destination, to: backup)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            guard isValidHostBundle(at: destination) else {
                try? FileManager.default.removeItem(at: destination)
                throw DisplayInstallError.appNotFound
            }
            installedPath = destination
            isInstalled = true
            status = "Installed · launching display host…"
            launchHost()
        } catch {
            status = "Installation failed: \(error.localizedDescription)"
        }
    }

    func launchHost() {
        refresh()
        guard let appURL = installedPath ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            status = "Install the display engine first."
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.status = "Couldn't launch display host: \(error.localizedDescription)"
                } else {
                    self?.status = "Display host launched · look for its menu-bar icon"
                    self?.refresh()
                }
            }
        }
    }

    func openAndroidReceiver() {
        NSWorkspace.shared.open(Self.receiverDownloadURL)
    }

    func openSetupGuide() {
        NSWorkspace.shared.open(Self.setupURL)
    }

    func openSourceAndLicense() {
        NSWorkspace.shared.open(Self.projectURL)
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func stopHost() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
        status = "Sent quit request to display host"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }
}

private enum DisplayInstallError: LocalizedError {
    case downloadFailed(Int)
    case extractFailed
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let code): return "Download server returned HTTP \(code)."
        case .extractFailed: return "The display host archive could not be extracted."
        case .appNotFound: return "The downloaded archive did not contain AnyDisplay.app."
        }
    }
}

struct VYBEDisplayCard: View {
    @ObservedObject private var manager = VYBEDisplayManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Color.cyan.opacity(0.13))
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 20, weight: .semibold)).foregroundStyle(.cyan)
                }.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("VYBE DISPLAY").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.4)
                    Text("Turn your Android tablet into a real second monitor")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Circle().fill(manager.isRunning ? Color.green : Color.gray.opacity(0.7)).frame(width: 8, height: 8)
            }

            HStack(spacing: 8) {
                Label("Extended desktop", systemImage: "rectangle.split.2x1")
                Spacer(minLength: 0)
                Label("Wi-Fi + USB", systemImage: "cable.connector")
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))

            Text(manager.status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(manager.isRunning ? Color.green : .white.opacity(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if manager.isInstalled {
                    Button { manager.launchHost() } label: {
                        Label("Launch Host", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.cyan)
                } else {
                    Button {
                        Task { await manager.installAndLaunch() }
                    } label: {
                        Label(manager.isInstalling ? "Installing…" : "Install Display Engine",
                              systemImage: manager.isInstalling ? "arrow.down.circle" : "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(manager.isInstalling)
                }

                Button { manager.openAndroidReceiver() } label: {
                    Label("Android App", systemImage: "tablet").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                Button { manager.openSetupGuide() } label: {
                    Label("Setup guide", systemImage: "book").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { manager.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                if manager.isRunning {
                    Button(role: .destructive) { manager.stopHost() } label: {
                        Image(systemName: "stop.fill")
                    }.buttonStyle(.bordered).help("Stop display host")
                }
            }
            HStack(spacing: 8) {
                Button { manager.openScreenRecordingSettings() } label: {
                    Label("Screen Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { manager.openAccessibilitySettings() } label: {
                    Label("Accessibility", systemImage: "hand.tap").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }

            Text("VYBE installs and manages the external MIT-licensed AnyDisplay host. First connection and pairing are completed from its menu-bar icon. Grant permissions to AnyDisplay itself when macOS prompts. The upstream release is not notarized; macOS may require Open Anyway in Privacy & Security on first launch.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(
            LinearGradient(colors: [Color.cyan.opacity(0.10), Color.blue.opacity(0.055), Color.white.opacity(0.025)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
        .onAppear { manager.refresh() }
    }
}
