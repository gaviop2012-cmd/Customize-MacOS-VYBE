import AppKit
import AVFoundation
import Combine
import CoreGraphics

@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    @Published private(set) var currentVideoURL: URL?
    @Published private(set) var savedVideoURLs: [URL] = []
    @Published private(set) var isMuted = false
    @Published private(set) var isLooping = true
    @Published private(set) var isPlaying = false
    @Published private(set) var isVideoBackgroundEnabled = UserDefaults.standard.object(forKey: "VYBE.videoBackgroundEnabled") as? Bool ?? true
    @Published var statusMessage = "Choose a video to get started."
    @Published private(set) var isDeletingVideos = false

    private let libraryFolderName = "Library"
    private let lastVideoKey = "VYBE.lastVideoFilename"
    private var outputs: [Output] = []
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var wakeResumeTask: Task<Void, Never>?
    private var shouldResumeAfterWake = false
    private var playbackGeneration = UUID()

    private final class Output {
        let window: NSWindow
        let playerView: WallpaperPlayerView
        let player: AVQueuePlayer
        var looper: AVPlayerLooper?

        init(window: NSWindow, playerView: WallpaperPlayerView, player: AVQueuePlayer, looper: AVPlayerLooper?) {
            self.window = window
            self.playerView = playerView
            self.player = player
            self.looper = looper
        }
    }

    private init() {
        refreshLibrary()

        // Remember the user's playback intent before macOS sleeps. A wallpaper
        // that was manually paused must remain paused after wake.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.shouldResumeAfterWake = self.isPlaying
                self.wakeResumeTask?.cancel()
                // Freeze at the current frame/time before system sleep so the
                // player cannot race macOS while its audio output is shutting down.
                if self.shouldResumeAfterWake {
                    self.outputs.forEach { $0.player.pause() }
                }
            }
        }

        // Audio output devices can take a moment to become available after wake
        // (especially when Bluetooth headphones or a dock are reconnecting).
        // Delay one gentle resume instead of immediately restarting/rebuilding
        // AVPlayers, which can produce a short audio dropout or desynchronization.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.shouldResumeAfterWake, !self.outputs.isEmpty else { return }
                self.statusMessage = "Restoring playback after sleep…"
                self.wakeResumeTask?.cancel()
                self.wakeResumeTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                    } catch {
                        return
                    }
                    guard let self, !Task.isCancelled,
                          self.shouldResumeAfterWake, !self.outputs.isEmpty else { return }
                    self.outputs.forEach { $0.player.play() }
                    self.isPlaying = true
                    self.shouldResumeAfterWake = false
                    self.statusMessage = "Playback restored after sleep."
                }
            }
        }
    }

    deinit {
        wakeResumeTask?.cancel()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Persistent local library

    private var libraryDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("VYBE", isDirectory: true)
            .appendingPathComponent(libraryFolderName, isDirectory: true)
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "Add a video to your VYBE library"
        panel.prompt = "Add to VYBE"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importVideo(from: url) }
    }

    private func importVideo(from sourceURL: URL) async {
        statusMessage = "Saving video to your VYBE library…"
        let didStartScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let destinationFolder = libraryDirectory
            let destination = try await Task.detached(priority: .userInitiated) { [destinationFolder] in
                let fm = FileManager.default
                try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                let safeName = sourceURL.deletingPathExtension().lastPathComponent
                let uniqueName = "\(safeName)-\(UUID().uuidString.prefix(8)).\(ext)"
                let target = destinationFolder.appendingPathComponent(uniqueName)
                try fm.copyItem(at: sourceURL, to: target)
                return target
            }.value

            refreshLibrary()
            UserDefaults.standard.set(destination.lastPathComponent, forKey: lastVideoKey)
            startPlayback(from: destination)
            statusMessage = "Saved in your VYBE library."
        } catch {
            statusMessage = "Couldn't save this video: \(error.localizedDescription)"
        }
    }

    func refreshLibrary() {
        do {
            try FileManager.default.createDirectory(
                at: libraryDirectory,
                withIntermediateDirectories: true
            )
            savedVideoURLs = try FileManager.default.contentsOfDirectory(
                at: libraryDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { ["mp4", "mov", "m4v", "avi", "mpg", "mpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            statusMessage = "Couldn't read your VYBE library: \(error.localizedDescription)"
        }
    }

    func deleteSavedVideo(_ url: URL) {
        guard !isDeletingVideos else { return }
        let libraryRoot = libraryDirectory.standardizedFileURL
        let target = url.standardizedFileURL
        // Never allow a UI action to delete an arbitrary file outside VYBE's own library.
        guard target.deletingLastPathComponent() == libraryRoot else {
            statusMessage = "That file is not inside VYBE's video library."
            return
        }
        let wasCurrent = currentVideoURL?.standardizedFileURL == target
        if wasCurrent {
            tearDownOutputs()
            currentVideoURL = nil
            isVideoBackgroundEnabled = false
            UserDefaults.standard.set(false, forKey: "VYBE.videoBackgroundEnabled")
            UserDefaults.standard.removeObject(forKey: lastVideoKey)
        }
        isDeletingVideos = true
        statusMessage = "Deleting video…"
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.removeItem(at: target)
                }.value
                self?.refreshLibrary()
                self?.statusMessage = "Video deleted from your VYBE library."
            } catch {
                self?.refreshLibrary()
                self?.statusMessage = "Couldn't delete video: \(error.localizedDescription)"
            }
            self?.isDeletingVideos = false
        }
    }

    func deleteAllSavedVideos() {
        guard !savedVideoURLs.isEmpty, !isDeletingVideos else { return }
        let alert = NSAlert()
        alert.messageText = "Delete all saved VYBE videos?"
        alert.informativeText = "This permanently deletes copied video files from VYBE's local library. Original source files are not affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urls = savedVideoURLs.map(\.standardizedFileURL)
        let root = libraryDirectory.standardizedFileURL
        guard urls.allSatisfy({ $0.deletingLastPathComponent() == root }) else {
            statusMessage = "Delete cancelled: the library contains an unexpected file location."
            return
        }
        tearDownOutputs()
        currentVideoURL = nil
        isVideoBackgroundEnabled = false
        UserDefaults.standard.set(false, forKey: "VYBE.videoBackgroundEnabled")
        UserDefaults.standard.removeObject(forKey: lastVideoKey)
        isDeletingVideos = true
        statusMessage = "Deleting saved videos in the background…"
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    for url in urls where FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                }.value
                self?.statusMessage = "All saved VYBE videos were deleted. Your static background remains selected."
            } catch {
                self?.statusMessage = "Some videos could not be deleted: \(error.localizedDescription)"
            }
            self?.refreshLibrary()
            self?.isDeletingVideos = false
        }
    }

    func setVideoBackgroundEnabled(_ enabled: Bool) {
        guard enabled != isVideoBackgroundEnabled else { return }
        isVideoBackgroundEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "VYBE.videoBackgroundEnabled")
        if enabled {
            guard let url = currentVideoURL, FileManager.default.fileExists(atPath: url.path) else {
                statusMessage = "Choose a video to enable video wallpaper."; isVideoBackgroundEnabled = false; return
            }
            startPlayback(from: url)
        } else {
            tearDownOutputs()
            statusMessage = "Video wallpaper off. Your selected static macOS background is visible."
        }
    }

    func selectSavedVideo(_ url: URL) {
        UserDefaults.standard.set(url.lastPathComponent, forKey: lastVideoKey)
        startPlayback(from: url)
    }

    func restoreSavedVideo() async {
        refreshLibrary()
        guard let filename = UserDefaults.standard.string(forKey: lastVideoKey) else { return }
        let savedURL = libraryDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: savedURL.path) else {
            UserDefaults.standard.removeObject(forKey: lastVideoKey)
            statusMessage = "Your previously selected video is missing from the VYBE library."
            return
        }
        currentVideoURL = savedURL
        if isVideoBackgroundEnabled { startPlayback(from: savedURL); statusMessage = "Restored your last wallpaper." }
        else { statusMessage = "Video wallpaper is off. Your static desktop background is active." }
    }

    // MARK: - Playback

    private func startPlayback(from url: URL) {
        tearDownOutputs()
        currentVideoURL = url
        isVideoBackgroundEnabled = true
        UserDefaults.standard.set(true, forKey: "VYBE.videoBackgroundEnabled")

        do {
            try buildWallpaperOutputs(for: url)
            isPlaying = true
            statusMessage = "Playing on your desktop."
        } catch {
            isPlaying = false
            statusMessage = "Couldn't play this video: \(error.localizedDescription)"
            tearDownOutputs()
        }
    }

    private func buildWallpaperOutputs(for url: URL) throws {
        guard !NSScreen.screens.isEmpty else {
            throw NSError(domain: "VYBE", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display was found."])
        }

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

            let desktopIconLevel = CGWindowLevelForKey(.desktopIconWindow)
            window.level = NSWindow.Level(rawValue: Int(desktopIconLevel) - 1)

            let player = AVQueuePlayer()
            player.isMuted = isMuted
            player.volume = 1.0
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = true

            let template = AVPlayerItem(url: url)
            // A small forward buffer helps the local file settle after the
            // system audio device is reinitialized on wake.
            template.preferredForwardBufferDuration = 1.0
            let looper = isLooping ? AVPlayerLooper(player: player, templateItem: template) : nil
            if !isLooping { player.insert(template, after: nil) }

            let playerView = WallpaperPlayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            playerView.playerLayer.videoGravity = .resizeAspectFill
            playerView.playerLayer.player = player
            window.contentView = playerView
            window.setFrame(screen.frame, display: true)
            window.orderBack(nil)

            let output = Output(window: window, playerView: playerView, player: player, looper: looper)
            outputs.append(output)
            player.play()
        }
    }

    private func tearDownOutputs() {
        // Stop any delayed wake resume before touching the playback graph.
        wakeResumeTask?.cancel()
        wakeResumeTask = nil
        shouldResumeAfterWake = false
        playbackGeneration = UUID()

        // AVPlayerLayer can outlive the SwiftUI/AppKit state change that removed
        // the wallpaper window. Detach it explicitly before releasing its player;
        // otherwise CoreAnimation may briefly render through a stale player pointer.
        let retiringOutputs = outputs
        outputs.removeAll(keepingCapacity: false)
        isPlaying = false

        for output in retiringOutputs {
            output.player.pause()
            output.player.rate = 0
            output.player.cancelPendingPrerolls()
            output.player.currentItem?.cancelPendingSeeks()

            output.playerView.detachPlayer()
            output.window.contentView = nil
            output.window.orderOut(nil)

            // Release AVPlayerLooper only after the layer no longer references
            // the queue player, then clear the queue and close the window.
            output.looper = nil
            output.player.removeAllItems()
            output.window.close()
        }
    }

    func stopWallpaper() {
        tearDownOutputs()
        isVideoBackgroundEnabled = false
        UserDefaults.standard.set(false, forKey: "VYBE.videoBackgroundEnabled")
        statusMessage = "Wallpaper stopped. Your saved video is still in your library."
    }

    func toggleMute() {
        isMuted.toggle()
        outputs.forEach { $0.player.isMuted = isMuted }
    }

    func toggleLoop() {
        isLooping.toggle()
        guard !outputs.isEmpty else {
            statusMessage = isLooping ? "Infinite loop enabled." : "Infinite loop disabled."
            return
        }

        // Reconfigure each existing player. Do not recreate desktop windows.
        for output in outputs {
            guard let asset = output.player.currentItem?.asset else { continue }
            output.player.pause()
            output.looper = nil
            output.player.removeAllItems()

            let template = AVPlayerItem(asset: asset)
            if isLooping {
                output.looper = AVPlayerLooper(player: output.player, templateItem: template)
            } else {
                output.player.insert(template, after: nil)
            }
            output.player.play()
        }
        isPlaying = true
        statusMessage = isLooping ? "Infinite loop enabled." : "Infinite loop disabled."
    }

    func restartVideo() {
        guard !outputs.isEmpty else {
            statusMessage = "Choose a video before restarting."
            return
        }
        // Seeking the existing players avoids tearing down and recreating every desktop window.
        let generation = playbackGeneration
        for output in outputs {
            output.player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self, weak player = output.player] finished in
                guard finished else { return }
                Task { @MainActor [weak self, weak player] in
                    guard let self, self.playbackGeneration == generation,
                          !self.outputs.isEmpty else { return }
                    player?.play()
                }
            }
        }
        isPlaying = true
        statusMessage = "Video restarted."
    }

    func togglePlayback() {
        guard !outputs.isEmpty else { return }
        if isPlaying {
            outputs.forEach { $0.player.pause() }
            isPlaying = false
            statusMessage = "Paused."
        } else {
            outputs.forEach { $0.player.play() }
            isPlaying = true
            statusMessage = "Playing on your desktop."
        }
    }

    func handleShortcut(_ shortcut: VYBEHotKey) {
        switch shortcut {
        case .mute: toggleMute()
        case .loop: toggleLoop()
        case .restart: restartVideo()
        case .playPause: togglePlayback()
        case .assistant: VYBEAssistantWindow.shared.toggleAndListen()
        case .toggleDock: DesktopEnvironment.shared.toggleDockVisibility()
        case .commandPalette: VYBEOverlayController.shared.toggleCommand()
        case .radialLauncher: VYBEOverlayController.shared.toggleRadial()
        }
    }
}

final class WallpaperPlayerView: NSView {
    override var wantsUpdateLayer: Bool { true }
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func detachPlayer() {
        playerLayer.player = nil
        playerLayer.removeFromSuperlayer()
    }

}
