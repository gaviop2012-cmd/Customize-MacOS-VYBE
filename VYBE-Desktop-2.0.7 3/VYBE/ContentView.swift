import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var engine: WallpaperEngine
    @ObservedObject private var widgetSelection = VYBEWidgetSelection.shared
    @ObservedObject private var desktopApps = DockApplications.shared
    @ObservedObject private var assistant = VYBEAssistant.shared
    @State private var showingAISettings = false

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea()
            ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("VYBE")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .tracking(3)
                        Text("Your desktop, in motion.")
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Button { showingAISettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("VYBE AI settings — choose OpenRouter or Google Gemini")
                    Circle()
                        .fill(engine.isPlaying ? Color.green : Color.gray)
                        .frame(width: 9, height: 9)
                    Text(engine.isPlaying ? "LIVE" : "IDLE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }

                HStack(spacing: 10) {
                    Button { VYBEOverlayController.shared.toggleCommand() } label: {
                        Label("VYBE Command", systemImage: "command")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(11)
                            .background(Color.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    Button { VYBEOverlayController.shared.toggleRadial() } label: {
                        Label("Radial Launcher", systemImage: "circle.hexagongrid.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(11)
                            .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }

                VYBESpacesView()
                    .padding(14)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

                VYBEDisplayCard()

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.055))
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(engine.currentVideoURL?.lastPathComponent ?? "No video selected")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(engine.currentVideoURL == nil
                             ? "Choose a local video to turn it into your desktop background."
                             : engine.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                        Button {
                            engine.chooseVideo()
                        } label: {
                            Label("Choose Video", systemImage: "folder")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.38, green: 0.55, blue: 1.0))
                    }
                    .padding(28)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)

                HStack(spacing: 12) {
                    controlCard("Audio", detail: engine.isMuted ? "Muted" : "On",
                                icon: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        engine.toggleMute()
                    }
                    controlCard("Infinite loop", detail: engine.isLooping ? "On" : "Off",
                                icon: "repeat") {
                        engine.toggleLoop()
                    }
                    controlCard("Restart", detail: "From beginning",
                                icon: "backward.end.fill") {
                        engine.restartVideo()
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        engine.setVideoBackgroundEnabled(!engine.isVideoBackgroundEnabled)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: engine.isVideoBackgroundEnabled ? "play.rectangle.fill" : "photo.fill")
                                .font(.system(size: 21, weight: .semibold))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(engine.isVideoBackgroundEnabled ? "Video Background ON" : "Default Background ON")
                                    .font(.system(size: 13, weight: .bold))
                                Text(engine.isVideoBackgroundEnabled ? "Switch to your saved static background" : "Switch back to your video wallpaper")
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white).padding(14)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .background(LinearGradient(colors: [Color(red: 0.22, green: 0.32, blue: 0.62), Color(red: 0.12, green: 0.18, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(!engine.isVideoBackgroundEnabled && engine.currentVideoURL == nil)
                    controlCard("Add folder", detail: "VYBE Desktop", icon: "folder.badge.plus") { desktopApps.addFolderToDesktop() }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CHOOSE YOUR DESKTOP WIDGETS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.58))
                    Text("Select only the widgets you want on your desktop. Drag widgets or the Dock from any open surface to reposition them.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(VYBEWidgetSelection.catalog, id: \.0) { item in
                            Button { widgetSelection.toggle(item.0) } label: {
                                HStack(spacing: 7) { Image(systemName: widgetSelection.selectedIDs.contains(item.0) ? "checkmark.circle.fill" : "circle"); Text(item.1).lineLimit(1); Spacer(minLength: 0) }
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(widgetSelection.selectedIDs.contains(item.0) ? 0.95 : 0.55))
                                    .padding(9).background(Color.white.opacity(widgetSelection.selectedIDs.contains(item.0) ? 0.11 : 0.045), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                FolderIconSection()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("YOUR LIBRARY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("\(engine.savedVideoURLs.count) saved")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        if !engine.savedVideoURLs.isEmpty {
                            Button(role: .destructive) { engine.deleteAllSavedVideos() } label: {
                                Label("Delete all", systemImage: "trash").font(.system(size: 10, weight: .semibold))
                            }.buttonStyle(.borderless)
                        }
                    }
                    if engine.savedVideoURLs.isEmpty {
                        Text("Videos you add are copied into VYBE and kept here.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        ForEach(engine.savedVideoURLs, id: \.path) { videoURL in
                            HStack(spacing: 8) {
                                Button { engine.selectSavedVideo(videoURL) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "film")
                                        Text(videoURL.lastPathComponent).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if engine.currentVideoURL?.standardizedFileURL == videoURL.standardizedFileURL {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        }
                                    }
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                    .padding(.vertical, 5)
                                }.buttonStyle(.plain)
                                Button(role: .destructive) { engine.deleteSavedVideo(videoURL) } label: {
                                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                                }.buttonStyle(.borderless).help("Delete this video from VYBE")
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Label("VYBE AI", systemImage: "waveform")
                    Spacer()
                    Text("⌥ Space  Voice assistant")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Open AI") { VYBEAssistantWindow.shared.toggleAndListen() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)

                HStack {
                    Label("Global shortcuts", systemImage: "keyboard")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("⌥ D Dock  •  ⌃⌥ G Radial  •  ⌘⌥ Space Command  •  ⌥ Space AI")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 4)

                HStack {
                    Text("VYBE 2.0 FOUNDATION • Holographic workspace")
                    Spacer()
                    Button("Stop wallpaper") { engine.stopWallpaper() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .disabled(!engine.isPlaying)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            }
              .foregroundStyle(.white)
              .padding(28)
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAISettings) {
            AISettingsView()
                .environmentObject(assistant)
                .frame(minWidth: 460, minHeight: 520)
                .background(Color(red: 0.055, green: 0.065, blue: 0.09))
                .preferredColorScheme(.dark)
        }
    }

    private func controlCard(
        _ title: String,
        detail: String,
        icon: String = "square.grid.2x2",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}
