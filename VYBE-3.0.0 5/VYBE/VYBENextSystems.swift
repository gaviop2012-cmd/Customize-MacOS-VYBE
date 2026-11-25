import AppKit
import Combine
import SwiftUI

extension Notification.Name {
  static let vybeShowAISettings = Notification.Name("VYBE.ShowAISettings")
}

// MARK: - VYBE 3.0 shared system models

struct VYBEFlowStep: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var title: String
  var kind: String
  var value: String
}

@MainActor
final class VYBEFlowStore: ObservableObject {
  static let shared = VYBEFlowStore()
  @Published var steps: [VYBEFlowStep] = []
  @Published var lastRun = "No automation has run yet."
  private let key = "VYBE.flow.steps.v1"

  private init() {
    if let data = UserDefaults.standard.data(forKey: key),
      let decoded = try? JSONDecoder().decode([VYBEFlowStep].self, from: data)
    {
      steps = decoded
    }
  }

  func add(kind: String, value: String) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    steps.append(
      VYBEFlowStep(title: kind == "Website" ? clean : "\(kind): \(clean)", kind: kind, value: clean)
    )
    persist()
  }

  func remove(_ step: VYBEFlowStep) {
    steps.removeAll { $0.id == step.id }
    persist()
  }

  func run() {
    guard !steps.isEmpty else {
      lastRun = "Add at least one action first."
      return
    }
    var completed = 0
    for step in steps {
      switch step.kind {
      case "Website":
        guard let url = URL(string: step.value),
          ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        else { continue }
        NSWorkspace.shared.open(url)
        completed += 1
      case "App":
        let candidate =
          step.value.hasSuffix(".app") ? step.value : "/Applications/\(step.value).app"
        if NSWorkspace.shared.open(URL(fileURLWithPath: candidate)) { completed += 1 }
      case "Copy text":
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(step.value, forType: .string)
        completed += 1
      default: break
      }
    }
    lastRun =
      "Executed \(completed) of \(steps.count) actions. Unsupported or invalid actions were skipped."
    VYBEHUD.shared.show(
      "FLOW COMPLETE", detail: lastRun, symbol: "point.3.connected.trianglepath.dotted")
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(steps) { UserDefaults.standard.set(data, forKey: key) }
  }
}

@MainActor
final class VYBEStudioSettings: ObservableObject {
  static let shared = VYBEStudioSettings()
  @Published var accent: String {
    didSet { UserDefaults.standard.set(accent, forKey: "VYBE.studio.accent") }
  }
  @Published var density: String {
    didSet { UserDefaults.standard.set(density, forKey: "VYBE.studio.density") }
  }
  @Published var glow: Bool {
    didSet { UserDefaults.standard.set(glow, forKey: "VYBE.studio.glow") }
  }
  let accents = ["Cyan", "Violet", "Blue", "Magenta", "Emerald", "Amber"]
  private init() {
    accent = UserDefaults.standard.string(forKey: "VYBE.studio.accent") ?? "Cyan"
    density = UserDefaults.standard.string(forKey: "VYBE.studio.density") ?? "Comfortable"
    glow = UserDefaults.standard.object(forKey: "VYBE.studio.glow") as? Bool ?? true
  }
  var color: Color {
    switch accent {
    case "Violet": return .purple
    case "Blue": return .blue
    case "Magenta": return .pink
    case "Emerald": return .green
    case "Amber": return .orange
    default: return .cyan
    }
  }
}

@MainActor
final class VYBEClipboardStore: ObservableObject {
  static let shared = VYBEClipboardStore()
  @Published private(set) var items: [String] = []
  @Published var status = "Clipboard access is manual. Nothing is monitored in the background."
  private let key = "VYBE.clipboard.items.v1"
  private init() { items = UserDefaults.standard.stringArray(forKey: key) ?? [] }

  func captureCurrent() {
    guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
      status = "The clipboard does not currently contain text."
      return
    }
    items.removeAll { $0 == value }
    items.insert(value, at: 0)
    items = Array(items.prefix(30))
    UserDefaults.standard.set(items, forKey: key)
    status = "Captured current clipboard text."
  }
  func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    status = "Copied to clipboard."
  }
  func clear() {
    items.removeAll()
    UserDefaults.standard.removeObject(forKey: key)
    status = "Clipboard history cleared."
  }
}

@MainActor
final class VYBENoteStore: ObservableObject {
  static let shared = VYBENoteStore()
  @Published var note: String {
    didSet { UserDefaults.standard.set(note, forKey: "VYBE.utility.note") }
  }
  private init() { note = UserDefaults.standard.string(forKey: "VYBE.utility.note") ?? "" }
}

// MARK: - Main hub for all eight VYBE systems

struct VYBENextSystemsHub: View {
  private let systems: [(String, String, String)] = [
    ("Desktop", "square.grid.2x2.fill", "Wallpaper, widgets and desktop layouts"),
    ("Command", "command", "Search and launch apps"),
    ("Intelligence", "brain.head.profile", "Cloud AI and local Ollama"),
    ("Control", "slider.horizontal.3", "Displays and macOS controls"),
    ("Flow", "point.3.connected.trianglepath.dotted", "Build repeatable action sequences"),
    ("Workspace", "rectangle.3.group", "VYBE Spaces and saved environments"),
    ("Studio", "slider.horizontal.2.square", "Personalise VYBE's visual identity"),
    ("Utilities", "wrench.and.screwdriver", "Clipboard, notes and quick tools"),
  ]
  @State private var selected = "Desktop"
  @ObservedObject private var studio = VYBEStudioSettings.shared

  var body: some View {
    VStack(
      alignment: .leading,
      spacing: studio.density == "Compact" ? 9 : (studio.density == "Spacious" ? 18 : 14)
    ) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 4) {
          Text("VYBE SYSTEMS").font(.system(size: 12, weight: .black, design: .monospaced))
            .tracking(2)
          Text("Eight connected layers. One native Mac experience.").font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        Spacer()
        Text("VYBE 3.0").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(
          studio.color
        )
        .padding(.horizontal, 9).padding(.vertical, 6).background(
          studio.color.opacity(0.12), in: Capsule())
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
        ForEach(systems, id: \.0) { item in
          Button {
            selected = item.0
          } label: {
            HStack(spacing: 9) {
              Image(systemName: item.1).font(.system(size: 15)).foregroundStyle(studio.color)
              VStack(alignment: .leading, spacing: 3) {
                Text(item.0).font(.system(size: 11, weight: .bold))
                Text(item.2).font(.system(size: 8)).foregroundStyle(.white.opacity(0.48)).lineLimit(
                  2)
              }
              Spacer(minLength: 0)
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
              selected == item.0 ? studio.color.opacity(0.15) : Color.white.opacity(0.045),
              in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 10).stroke(
                selected == item.0 ? studio.color.opacity(0.55) : Color.white.opacity(0.07),
                lineWidth: 1))
          }.buttonStyle(.plain)
        }
      }
      Group {
        switch selected {
        case "Desktop": DesktopSystemPanel()
        case "Command": CommandSystemPanel()
        case "Intelligence": IntelligenceSystemPanel()
        case "Control": ControlSystemPanel()
        case "Flow": FlowSystemPanel()
        case "Workspace": WorkspaceSystemPanel()
        case "Studio": StudioSystemPanel()
        default: UtilitiesSystemPanel()
        }
      }
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(studio.color.opacity(0.16), lineWidth: 1))
    }
    .padding(studio.density == "Compact" ? 10 : (studio.density == "Spacious" ? 20 : 15))
    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 17))
    .overlay(
      RoundedRectangle(cornerRadius: 17).stroke(
        studio.color.opacity(studio.glow ? 0.22 : 0.07), lineWidth: studio.glow ? 1 : 0.5)
    )
    .shadow(color: studio.glow ? studio.color.opacity(0.08) : .clear, radius: 18)
  }
}

private struct SystemPanelTitle: View {
  let title: String
  let subtitle: String
  let symbol: String
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(
        VYBEStudioSettings.shared.color)
      VStack(alignment: .leading, spacing: 3) {
        Text(title.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced))
          .tracking(1)
        Text(subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
      }
      Spacer()
    }
  }
}

private struct DesktopSystemPanel: View {
  @EnvironmentObject private var engine: WallpaperEngine
  @ObservedObject private var widgets = VYBEWidgetSelection.shared
  @ObservedObject private var studio = VYBEStudioSettings.shared
  @ObservedObject private var backgrounds = VYBEBackgroundPresets.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      SystemPanelTitle(
        title: "Desktop environment",
        subtitle: "Control your existing wallpaper engine and desktop widgets.",
        symbol: "desktopcomputer")
      HStack {
        Label(
          engine.isVideoBackgroundEnabled ? "Video wallpaper active" : "Video wallpaper off",
          systemImage: "play.rectangle")
        Spacer()
        Button("Choose video") { engine.chooseVideo() }.buttonStyle(.borderedProminent).tint(
          studio.color)
        Button(engine.isVideoBackgroundEnabled ? "Turn video off" : "Turn video on") {
          engine.setVideoBackgroundEnabled(!engine.isVideoBackgroundEnabled)
        }.buttonStyle(.bordered)
          .disabled(!engine.isVideoBackgroundEnabled && engine.currentVideoURL == nil)
      }.font(.system(size: 10))
      HStack {
        Text("Static wallpaper preset").font(.system(size: 9))
        Spacer()
        Picker(
          "Preset",
          selection: Binding(get: { backgrounds.selectedName }, set: { backgrounds.apply($0) })
        ) {
          ForEach(backgrounds.names, id: \.self) { Text($0).tag($0) }
        }.frame(width: 160)
      }
      Text("Desktop widget visibility").font(.system(size: 10, weight: .semibold))
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
        ForEach(VYBEWidgetSelection.catalog, id: \.0) { item in
          Toggle(
            item.1,
            isOn: Binding(
              get: { widgets.selectedIDs.contains(item.0) },
              set: { enabled in
                var set = widgets.selectedIDs
                if enabled { set.insert(item.0) } else { set.remove(item.0) }
                widgets.setSelection(set)
              })
          ).toggleStyle(.checkbox).font(.system(size: 9))
        }
      }
      Text(
        "Use the existing desktop surface to drag and position widgets. Layout and wallpaper state remain managed by the original VYBE engine."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
    }
  }
}

private struct CommandSystemPanel: View {
  @State private var query = ""
  @State private var apps: [URL] = []
  private var results: [URL] {
    query.isEmpty
      ? Array(apps.prefix(8))
      : apps.filter {
        $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query)
      }.prefix(20).map { $0 }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Command", subtitle: "Find and launch installed Mac applications.", symbol: "command"
      )
      TextField("Search installed apps…", text: $query).textFieldStyle(.roundedBorder)
      if results.isEmpty {
        Text("No matching applications found.").font(.system(size: 10)).foregroundStyle(
          .white.opacity(0.45))
      }
      ForEach(results, id: \.path) { url in
        Button {
          NSWorkspace.shared.open(url)
        } label: {
          HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(
              width: 20, height: 20)
            Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 10))
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 9))
          }
        }.buttonStyle(.plain)
      }
      Button("Refresh application index") { apps = Self.findApps() }.font(.system(size: 9))
        .buttonStyle(.borderless)
    }.onAppear { if apps.isEmpty { apps = Self.findApps() } }
  }
  private static func findApps() -> [URL] {
    let roots = [
      URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
      URL(fileURLWithPath: "/System/Applications/Utilities"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]
    var found: [URL] = []
    for root in roots {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { continue }
      for case let url as URL in enumerator where url.pathExtension == "app" {
        found.append(url)
        enumerator.skipDescendants()
      }
    }
    return found.sorted {
      $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
        == .orderedAscending
    }
  }
}

private struct IntelligenceSystemPanel: View {
  @ObservedObject private var assistant = VYBEAssistant.shared
  @State private var endpoint =
    UserDefaults.standard.string(forKey: "VYBE.ollama.endpoint") ?? "http://127.0.0.1:11434"
  @State private var status = "Not checked"
  @State private var checking = false
  @State private var models: [String] = []
  @State private var selectedModel = ""
  @State private var prompt = ""
  @State private var answer = ""
  @State private var generating = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Hybrid intelligence",
        subtitle: "Keep your existing cloud providers and optionally connect local Ollama.",
        symbol: "brain.head.profile")
      HStack {
        Text("Current provider")
        Spacer()
        Text(assistant.provider.title).foregroundStyle(.cyan)
      }.font(.system(size: 10))
      Button("Open AI provider settings") {
        NotificationCenter.default.post(name: .vybeShowAISettings, object: nil)
      }.buttonStyle(.bordered).font(.system(size: 10))
      Text("LOCAL OLLAMA ENDPOINT").font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.55))
      TextField("http://127.0.0.1:11434", text: $endpoint).textFieldStyle(.roundedBorder)
      HStack {
        Button(checking ? "Checking…" : "Test local connection") { Task { await checkOllama() } }
          .disabled(checking).buttonStyle(.borderedProminent)
        Text(status).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
      }
      if !models.isEmpty {
        Picker("Local model", selection: $selectedModel) {
          ForEach(models, id: \.self) { Text($0).tag($0) }
        }.font(.system(size: 9))
        TextField("Ask your local model…", text: $prompt).textFieldStyle(.roundedBorder)
        Button(generating ? "Generating…" : "Ask local model") { Task { await askOllama() } }
          .buttonStyle(.borderedProminent).disabled(
            generating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || selectedModel.isEmpty)
        if !answer.isEmpty {
          Text(answer).font(.system(size: 10)).textSelection(.enabled).padding(9).frame(
            maxWidth: .infinity, alignment: .leading
          ).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
      }
      Text(
        "The connection test reads the local /api/tags endpoint. Prompts are sent only to the Ollama endpoint you configured; no model is downloaded automatically."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
    }
  }
  private func checkOllama() async {
    let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    guard let base = URL(string: clean),
      ["http", "https"].contains(base.scheme?.lowercased() ?? "")
    else {
      status = "Invalid URL"
      return
    }
    checking = true
    defer { checking = false }
    UserDefaults.standard.set(clean, forKey: "VYBE.ollama.endpoint")
    do {
      var request = URLRequest(url: base.appendingPathComponent("api/tags"))
      request.timeoutInterval = 5
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        status = "Ollama returned an error"
        return
      }
      struct Tags: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
      }
      let decoded = try JSONDecoder().decode(Tags.self, from: data)
      models = decoded.models.map(\.name).sorted()
      if !models.contains(selectedModel) { selectedModel = models.first ?? "" }
      status = "Connected • \(decoded.models.count) model(s)"
    } catch {
      models = []
      status = "Unavailable • \(error.localizedDescription)"
    }
  }
  private func askOllama() async {
    let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    guard let base = URL(string: clean), !selectedModel.isEmpty else { return }
    generating = true
    answer = ""
    defer { generating = false }
    do {
      var request = URLRequest(url: base.appendingPathComponent("api/chat"))
      request.httpMethod = "POST"
      request.timeoutInterval = 120
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": selectedModel, "stream": false, "messages": [["role": "user", "content": prompt]],
      ])
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
      }
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let message = object?["message"] as? [String: Any]
      answer = message?["content"] as? String ?? "The local model returned an empty response."
    } catch { answer = "Local model request failed: \(error.localizedDescription)" }
  }
}

private struct ControlSystemPanel: View {
  private var displays: [NSScreen] { NSScreen.screens }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Control", subtitle: "Inspect connected displays and open native macOS controls.",
        symbol: "slider.horizontal.3")
      ForEach(Array(displays.enumerated()), id: \.offset) { index, screen in
        VStack(alignment: .leading, spacing: 3) {
          Text("DISPLAY \(index + 1)").font(.system(size: 9, weight: .bold, design: .monospaced))
          Text(
            "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) • Scale \(String(format: "%.2f", screen.backingScaleFactor))x"
          )
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(
          Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
      }
      HStack {
        Button("Display settings") {
          openSettings("x-apple.systempreferences:com.apple.Displays-Settings.extension")
        }
        Button("Sound settings") {
          openSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension")
        }
        Button("Keyboard settings") {
          openSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        }
      }.buttonStyle(.bordered).font(.system(size: 9))
      Text(
        "macOS controls remain owned by macOS. VYBE opens the relevant Settings panes rather than changing protected system settings behind your back."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
    }
  }
  private func openSettings(_ value: String) {
    if let url = URL(string: value) { NSWorkspace.shared.open(url) }
  }
}

private struct FlowSystemPanel: View {
  @ObservedObject private var flow = VYBEFlowStore.shared
  @State private var kind = "Website"
  @State private var value = "https://"
  private let kinds = ["Website", "App", "Copy text"]
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Flow automation",
        subtitle: "Create a saved sequence of explicit, allowlisted actions.",
        symbol: "point.3.connected.trianglepath.dotted")
      HStack {
        Picker("Action", selection: $kind) { ForEach(kinds, id: \.self) { Text($0).tag($0) } }
          .frame(width: 130)
        TextField(
          kind == "Website" ? "https://example.com" : kind == "App" ? "Calculator" : "Text to copy",
          text: $value
        ).textFieldStyle(.roundedBorder)
        Button {
          flow.add(kind: kind, value: value)
          value = kind == "Website" ? "https://" : ""
        } label: {
          Image(systemName: "plus.circle.fill")
        }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.font(.system(size: 9))
      ForEach(flow.steps) { step in
        HStack {
          Image(systemName: "arrow.turn.down.right").foregroundStyle(.cyan)
          Text(step.title).font(.system(size: 9)).lineLimit(1)
          Spacer()
          Button(role: .destructive) {
            flow.remove(step)
          } label: {
            Image(systemName: "trash")
          }.buttonStyle(.borderless)
        }
      }
      HStack {
        Button("Run flow") { flow.run() }.buttonStyle(.borderedProminent)
        Button("Clear all", role: .destructive) { for step in flow.steps { flow.remove(step) } }
          .buttonStyle(.bordered)
      }
      Text(flow.lastRun).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
      Text(
        "Actions are executed locally and only after you press Run. No arbitrary shell commands or background triggers are enabled."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
    }
  }
}

private struct WorkspaceSystemPanel: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Workspace profiles",
        subtitle: "Manage saved VYBE environments without replacing macOS Mission Control.",
        symbol: "rectangle.3.group")
      VYBESpacesView()
    }
  }
}

private struct StudioSystemPanel: View {
  @ObservedObject private var studio = VYBEStudioSettings.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      SystemPanelTitle(
        title: "VYBE Studio",
        subtitle: "Tune the holographic visual system. Changes save automatically.",
        symbol: "slider.horizontal.2.square")
      HStack {
        Text("Accent colour").font(.system(size: 10))
        Spacer()
        Picker("Accent", selection: $studio.accent) {
          ForEach(studio.accents, id: \.self) { Text($0).tag($0) }
        }.frame(width: 150)
      }
      HStack {
        Text("Interface density").font(.system(size: 10))
        Spacer()
        Picker("Density", selection: $studio.density) {
          Text("Compact").tag("Compact")
          Text("Comfortable").tag("Comfortable")
          Text("Spacious").tag("Spacious")
        }.frame(width: 150)
      }
      Toggle("Holographic glow", isOn: $studio.glow).font(.system(size: 10)).toggleStyle(.switch)
      RoundedRectangle(cornerRadius: 10).fill(studio.color.opacity(0.16)).overlay(
        RoundedRectangle(cornerRadius: 10).stroke(
          studio.color.opacity(studio.glow ? 0.8 : 0.2), lineWidth: 1)
      ).frame(height: 44)
      Text(
        "Accent and glow are applied to the new VYBE Systems hub. Existing wallpaper, widgets and radial surfaces retain their current styling to avoid breaking the established UI."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
    }
  }
}

private struct UtilitiesSystemPanel: View {
  @ObservedObject private var clipboard = VYBEClipboardStore.shared
  @ObservedObject private var notes = VYBENoteStore.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SystemPanelTitle(
        title: "Utilities", subtitle: "A practical home for small tools used throughout the day.",
        symbol: "wrench.and.screwdriver")
      HStack {
        Button("Capture clipboard now") { clipboard.captureCurrent() }.buttonStyle(
          .borderedProminent)
        Button("Clear history", role: .destructive) { clipboard.clear() }.buttonStyle(.bordered)
      }
      Text(clipboard.status).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
      if clipboard.items.isEmpty {
        Text("No captured clipboard entries.").font(.system(size: 9)).foregroundStyle(
          .white.opacity(0.4))
      }
      ForEach(Array(clipboard.items.enumerated()), id: \.offset) { entry in
        HStack(alignment: .top) {
          Text(entry.element).font(.system(size: 9)).lineLimit(2)
          Spacer()
          Button("Copy") { clipboard.copy(entry.element) }.buttonStyle(.borderless).font(
            .system(size: 9))
        }
        .padding(7).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
      }
      Divider().overlay(Color.white.opacity(0.1))
      Text("QUICK NOTE").font(.system(size: 9, weight: .bold, design: .monospaced))
      TextEditor(text: $notes.note).font(.system(size: 10)).frame(minHeight: 90)
        .scrollContentBackground(.hidden).padding(5).background(
          Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
      Text(
        "Clipboard capture is manual and opt-in; VYBE does not continuously monitor your clipboard. Notes are stored locally in this Mac's application preferences."
      )
      .font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
    }
  }
}
