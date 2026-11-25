import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var engine: WallpaperEngine
    @Environment(\.openWindow) private var openWindow
    @State private var dockPreferenceMessage = ""
    @ObservedObject private var apps = DockApplications.shared
    @ObservedObject private var backgrounds = VYBEBackgroundPresets.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VYBE")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(1.5)
                    Text(engine.isVideoBackgroundEnabled ? "Your desktop is alive" : "Video background off")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(engine.isPlaying ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("NOW PLAYING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(engine.currentVideoURL?.lastPathComponent ?? "No video selected")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .help(engine.currentVideoURL?.path ?? "")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    engine.setVideoBackgroundEnabled(!engine.isVideoBackgroundEnabled)
                } label: {
                    Label(engine.isVideoBackgroundEnabled ? "Turn Video Background Off" : "Turn Video Background On",
                          systemImage: engine.isVideoBackgroundEnabled ? "photo" : "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!engine.isVideoBackgroundEnabled && engine.currentVideoURL == nil)
            }
            Text(engine.isVideoBackgroundEnabled ? "Video background is active" : "Video playback is off; macOS desktop is visible")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            HStack(spacing: 9) {
                controlButton(
                    title: engine.isPlaying ? "Pause" : "Play",
                    icon: engine.isPlaying ? "pause.fill" : "play.fill"
                ) { engine.togglePlayback() }
                controlButton(
                    title: engine.isMuted ? "Unmute" : "Mute",
                    icon: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                ) { engine.toggleMute() }
            }

            HStack(spacing: 9) {
                controlButton(
                    title: engine.isLooping ? "Loop on" : "Loop off",
                    icon: "repeat",
                    active: engine.isLooping
                ) { engine.toggleLoop() }
                controlButton(
                    title: "Restart",
                    icon: "backward.end.fill"
                ) { engine.restartVideo() }
            }

            if !engine.savedVideoURLs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIBRARY")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(engine.savedVideoURLs.count) saved videos").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { engine.deleteAllSavedVideos() } label: {
                            Label("Delete all", systemImage: "trash").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach(engine.savedVideoURLs, id: \.path) { videoURL in
                        HStack(spacing: 7) {
                            Button { engine.selectSavedVideo(videoURL) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "film")
                                    Text(videoURL.lastPathComponent).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if engine.currentVideoURL?.standardizedFileURL == videoURL.standardizedFileURL {
                                        Image(systemName: "checkmark").foregroundStyle(.green)
                                    }
                                }.font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { engine.deleteSavedVideo(videoURL) } label: {
                                Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderless).help("Delete this saved video")
                        }
                    }
                }
            }

            Button {
                openWindow(id: "control")
            } label: {
                Label("Open Control Centre", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                engine.chooseVideo()
            } label: {
                Label("Choose a video…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("VYBE DESKTOP")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button { apps.addApplication(to: .dock) } label: {
                        Label("Add to Dock", systemImage: "dock.rectangle")
                    }
                    Button { apps.addApplication(to: .desktop) } label: {
                        Label("Desktop icon", systemImage: "app.badge")
                    }
                    Button { apps.addFolderToDesktop() } label: { Label("Add folder", systemImage: "folder.badge.plus") }
                }
                .buttonStyle(.bordered)
                Text("Dock: \(apps.dockApplications.count) apps · Desktop: \(apps.desktopApplications.count) apps · \(apps.desktopFolders.count) folders")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Text("Background")
                    Spacer()
                    Picker("Background", selection: Binding(
                        get: { backgrounds.selectedName },
                        set: { backgrounds.apply($0) }
                    )) {
                        ForEach(backgrounds.names, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 145)
                }
                Text("Drag the widgets, desktop shortcuts and VYBE Dock to reposition them. Positions are saved.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 6) {
                Text("MACOS DESKTOP & DOCK")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Show Desktop Icons") {
                        FinderDesktopVisibility.setHidden(false)
                        dockPreferenceMessage = "macOS desktop icons visible."
                    }
                    Button("Hide Desktop Icons") {
                        FinderDesktopVisibility.setHidden(true)
                        dockPreferenceMessage = "macOS desktop icons hidden."
                    }
                }
                .buttonStyle(.bordered)

                HStack(spacing: 8) {
                    Button("Hide Apple Dock") { setAppleDockHidden(true) }
                    Button("Restore Apple Dock") { setAppleDockHidden(false) }
                }
                .buttonStyle(.bordered)
            }
            if !dockPreferenceMessage.isEmpty {
                Text(dockPreferenceMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("⌥ D  Dock     ⌥ M  Mute     ⌥ L  Loop     ⌥ R  Restart")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack {
                Text("VYBE Desktop 1.8.0")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Stop wallpaper") {
                    engine.stopWallpaper()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!engine.isPlaying)
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private func setAppleDockHidden(_ hidden: Bool) {
        do {
            try AppleDockVisibility.setAutoHide(hidden)
            dockPreferenceMessage = hidden
                ? "Apple Dock auto-hide enabled."
                : "Apple Dock restored."
        } catch {
            dockPreferenceMessage = "Couldn't change Dock setting: \(error.localizedDescription)"
        }
    }

    private func controlButton(
        title: String,
        icon: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
