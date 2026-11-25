import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

struct AISettingsView: View {
    @EnvironmentObject private var assistant: VYBEAssistant
    @ObservedObject private var router = OpenRouterService.shared
    @ObservedObject private var gemini = GeminiService.shared
    @State private var customModelID = ""
    @State private var statusMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                providerSection
                Divider().background(Color.white.opacity(0.1))
                if assistant.provider == .openRouter {
                    apiSection
                    Divider().background(Color.white.opacity(0.1))
                    modelSection
                } else {
                    geminiSection
                }

                Divider().background(Color.white.opacity(0.1))

                // Voice Section
                voiceSection

                Divider().background(Color.white.opacity(0.1))

                // Assistant Section
                assistantSection

                Divider().background(Color.white.opacity(0.1))

                // Permissions Section
                permissionsSection

                // Footer
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 420, maxWidth: 500)
        .background(Color(red: 0.055, green: 0.065, blue: 0.09))
        .preferredColorScheme(.dark)
        .onAppear {
            // Defer Keychain access until the user actually opens AI settings.
            // This avoids login-keychain dialogs during ordinary VYBE startup.
            if assistant.provider == .gemini {
                gemini.loadKeychainIfNeeded()
                if gemini.hasAPIKey, gemini.models.isEmpty {
                    Task { await gemini.fetchModels() }
                }
            } else {
                router.loadKeychainIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(.cyan)
                    Text("VYBE AI SETTINGS")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(1.5)
                }
                Text("Configure your AI assistant")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(assistant.provider == .openRouter ? "OPENROUTER" : "GEMINI")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .padding(6)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Provider Selection

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("AI PROVIDER", icon: "brain.head.profile")
            Picker("Provider", selection: $assistant.provider) {
                ForEach(VYBEAIProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: assistant.provider) { value in
                UserDefaults.standard.set(value.rawValue, forKey: "VYBE.aiProvider")
                if value == .gemini { gemini.loadKeychainIfNeeded() }
                else { router.loadKeychainIfNeeded() }
            }
            Text(assistant.provider == .openRouter ? "Use an OpenRouter model. Your key stays in Keychain." : "Use a Gemini model from Google AI Studio. Your key stays in Keychain.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
        }
    }

    private var geminiSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("GOOGLE GEMINI API", icon: "sparkles")
            VStack(alignment: .leading, spacing: 6) {
                Text("Google AI Studio API Key").font(.system(size: 11, weight: .semibold))
                SecureField("Paste your Gemini API key", text: $gemini.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: gemini.apiKey) { _ in gemini.apiKeyValid = nil }
                Text("Stored in macOS Keychain. Sent only to Google's Generative Language API.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
            }
            HStack(spacing: 10) {
                Button {
                    Task { gemini.saveSettings(); await gemini.validateAPIKey() }
                } label: {
                    HStack(spacing: 5) {
                        if gemini.isValidatingKey { ProgressView().controlSize(.small) }
                        Text(gemini.isValidatingKey ? "Checking…" : "Validate & load models")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!gemini.hasAPIKey || gemini.isValidatingKey)
                if let valid = gemini.apiKeyValid {
                    Label(valid ? "Connected" : "Check key", systemImage: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(valid ? .green : .red)
                }
                Spacer()
                Link("Get API key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                    .font(.system(size: 10))
            }
            HStack {
                Text("AVAILABLE MODELS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.58))
                Spacer()
                Button { Task { await gemini.fetchModels() } } label: {
                    Label(gemini.isLoadingModels ? "Loading…" : "Refresh", systemImage: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.bordered).disabled(gemini.isLoadingModels || !gemini.hasAPIKey)
            }
            if !gemini.models.isEmpty {
                Picker("Gemini model", selection: $gemini.selectedModelID) {
                    ForEach(gemini.models) { model in Text(model.title).tag(model.id) }
                }
                .labelsHidden()
                .onChange(of: gemini.selectedModelID) { gemini.selectModel($0) }
                Text("Model ID: \(gemini.selectedModelID)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.42))
            } else if !gemini.isLoadingModels {
                Text("Add your API key and select Validate & load models.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
            }
            if let error = gemini.modelLoadError {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Google AI Studio free-tier eligibility, quotas and model access depend on your Google account and region. VYBE does not guarantee free usage.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - API Section

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("API CONFIGURATION", icon: "key.fill")

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenRouter API Key")
                    .font(.system(size: 11, weight: .semibold))
                SecureField("Paste your API key", text: $router.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: router.apiKey) { _ in router.apiKeyValid = nil }
                Text("Stored securely in macOS Keychain. Never logged or transmitted except to OpenRouter.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        router.saveSettings()
                        await router.validateAPIKey()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if router.isValidatingKey {
                            ProgressView().controlSize(.small)
                        }
                        Text(router.isValidatingKey ? "Validating…" : "Validate Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(router.apiKey.trimmingCharacters(in: .whitespaces).isEmpty || router.isValidatingKey)

                if let valid = router.apiKeyValid {
                    HStack(spacing: 4) {
                        Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(valid ? .green : .red)
                        Text(valid ? "Key is valid" : "Key is invalid")
                            .font(.system(size: 11))
                            .foregroundStyle(valid ? .green : .red)
                    }
                }

                Spacer()
                Link("Get API key", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.system(size: 10))
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("FREE MODEL", icon: "cpu")
                Spacer()
                Button {
                    Task { await router.fetchModels() }
                } label: {
                    HStack(spacing: 4) {
                        if router.isLoadingModels {
                            ProgressView().controlSize(.small)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .disabled(router.isLoadingModels)
            }

            if router.availableFreeModels.isEmpty && !router.isLoadingModels {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No models loaded. Tap Refresh to fetch available free models.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if !router.availableFreeModels.isEmpty {
                Picker("Select model", selection: $router.selectedModelID) {
                    ForEach(router.availableFreeModels) { model in
                        HStack {
                            Text(model.displayName)
                            if let ctx = model.contextLengthFormatted {
                                Text("· \(ctx)").foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.id)
                    }
                }
                .labelsHidden()
                .onChange(of: router.selectedModelID) { newValue in
                    router.selectModel(newValue)
                    // Also sync to the assistant
                    assistant.model = newValue
                }

                if let selected = router.selectedModel {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Model ID: \(selected.id)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        if let ctx = selected.contextLengthFormatted {
                            Text("Context: \(ctx)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }

            if let error = router.modelLoadError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let refresh = router.lastModelRefresh {
                Text("Last refreshed: \(refresh, format: .relative(presentation: .named))")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }

            // Custom model
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom free model ID (optional)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    TextField("provider/model-name:free", text: $customModelID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("Use") {
                        let value = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.hasSuffix(":free") {
                            router.selectModel(value)
                            assistant.model = value
                            statusMessage = "Custom model selected."
                        } else {
                            statusMessage = "Model ID must end with :free"
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(customModelID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Link("Browse free models on OpenRouter", destination: URL(string: "https://openrouter.ai/models?max_price=0")!)
                .font(.system(size: 10))
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("VOICE", icon: "mic.fill")

            Toggle("Speak AI responses", isOn: $assistant.speakResponses)
                .font(.system(size: 12))

            Toggle("Auto-listen on launch", isOn: $assistant.autoListenOnLaunch)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Speech speed: \(String(format: "%.1f", assistant.speechRate))x")
                    .font(.system(size: 11))
                Slider(value: $assistant.speechRate, in: 0.3...0.7, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice")
                    .font(.system(size: 11, weight: .medium))
                Picker("Voice", selection: $assistant.selectedVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Assistant Section

    private var assistantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ASSISTANT", icon: "waveform")

            VStack(alignment: .leading, spacing: 4) {
                Text("Global shortcut")
                    .font(.system(size: 11, weight: .medium))
                Text("⌥ Space (Option + Space)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text("Opens VYBE AI and starts listening.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Toggle("Show transcript", isOn: .constant(true))
                .font(.system(size: 12))
                .disabled(true)
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PERMISSIONS", icon: "lock.shield")

            permissionRow(
                "Microphone",
                icon: "mic.fill",
                status: micPermissionStatus
            )
            permissionRow(
                "Speech Recognition",
                icon: "ear.fill",
                status: speechPermissionStatus
            )
            permissionRow(
                "Notifications",
                icon: "bell.fill",
                status: "Grant in System Settings → Notifications"
            )

            Text("Dictation opens a VYBE panel with a live transcript. It does not type into other apps or require Accessibility / keyboard-event permission. Copy the transcript when you are ready.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
            }
            .font(.system(size: 10))
            .buttonStyle(.bordered)
        }
    }

    private var micPermissionStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "✅ Granted"
        case .denied: return "❌ Denied — open System Settings"
        case .restricted: return "⚠️ Restricted"
        case .notDetermined: return "⏳ Not yet requested"
        @unknown default: return "Unknown"
        }
    }

    private var speechPermissionStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "✅ Granted"
        case .denied: return "❌ Denied — open System Settings"
        case .restricted: return "⚠️ Restricted"
        case .notDetermined: return "⏳ Not yet requested"
        @unknown default: return "Unknown"
        }
    }

    private func permissionRow(_ name: String, icon: String, status: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            Text(name)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save & Close") {
                router.saveSettings()
                gemini.saveSettings()
                assistant.saveVoiceSettings()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.cyan)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
