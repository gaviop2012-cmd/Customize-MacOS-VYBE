import AppKit
import SwiftUI
import Speech
import AVFoundation
import UserNotifications

enum VYBEAIProvider: String, CaseIterable, Identifiable, Hashable {
    case openRouter = "openrouter"
    case gemini = "gemini"
    var id: String { rawValue }
    var title: String { self == .openRouter ? "OpenRouter" : "Google Gemini" }
}

// MARK: - Assistant Message

struct AssistantMessage: Identifiable {
    enum Role: String { case user, assistant, system }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - VYBE Assistant (Core)

@MainActor
final class VYBEAssistant: ObservableObject {
    static let shared = VYBEAssistant()

    // MARK: Published State
    @Published var messages: [AssistantMessage] = [
        AssistantMessage(role: .assistant, text: "Hello. I'm VYBE, your desktop AI assistant. Press the microphone or use ⌥ Space to talk to me.")
    ]
    @Published var transcript = ""
    @Published var isListening = false
    @Published var isThinking = false
    @Published var isSpeaking = false
    @Published var isExecutingAction = false
    @Published var hasError = false
    @Published var status = "Ready"
    @Published var showSettings = false

    @Published var provider: VYBEAIProvider = VYBEAIProvider(rawValue: UserDefaults.standard.string(forKey: "VYBE.aiProvider") ?? "openrouter") ?? .openRouter

    // Model (synced with OpenRouterService)
    @Published var model: String = UserDefaults.standard.string(forKey: "VYBE.openRouterModel") ?? "deepseek/deepseek-r1:free"

    // Voice settings
    @Published var speakResponses: Bool = UserDefaults.standard.object(forKey: "VYBE.speakResponses") as? Bool ?? true
    @Published var autoListenOnLaunch: Bool = UserDefaults.standard.object(forKey: "VYBE.autoListenOnLaunch") as? Bool ?? true
    @Published var speechRate: Float = UserDefaults.standard.object(forKey: "VYBE.speechRate") as? Float ?? 0.5
    @Published var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "VYBE.selectedVoice") ?? ""

    // Speech recognition
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceWorkItem: DispatchWorkItem?
    private let recognizer = SFSpeechRecognizer()

    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsDelegate: TTSDelegate?

    // Timer/alarm notification observers
    private var timerObserver: NSObjectProtocol?
    private var alarmObserver: NSObjectProtocol?

    // Anti-loop: prevent assistant from hearing its own speech
    var isSpeakingOutput = false

    private let router = OpenRouterService.shared
    private let gemini = GeminiService.shared

    // System prompt for the AI
    private let systemPrompt = """
    You are VYBE, a futuristic AI assistant living on the user's macOS desktop. \
    You are helpful, concise, and friendly. You speak naturally like JARVIS. \
    You can perform real actions on the user's Mac using the tools provided. \
    When the user asks you to open an app, set a timer, check the time, etc., use the appropriate tool. \
    Keep responses concise — typically 1-3 sentences unless more detail is needed. \
    When you use a tool, also give a brief spoken confirmation of what you did. \
    You cannot browse the internet, read files, or run arbitrary shell commands. \
    You are powered by the AI provider selected in VYBE settings.
    """

    private init() {
        ttsDelegate = TTSDelegate(assistant: self)
        synthesizer.delegate = ttsDelegate

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Listen for timer/alarm fires
        timerObserver = NotificationCenter.default.addObserver(
            forName: .vybeTimerFired, object: nil, queue: .main
        ) { [weak self] notification in
            guard let name = notification.userInfo?["name"] as? String else { return }
            Task { @MainActor in
                self?.messages.append(AssistantMessage(role: .assistant, text: "⏰ Timer \"\(name)\" has finished!"))
                if self?.speakResponses == true {
                    self?.speak("Timer \(name) has finished!")
                }
            }
        }

        alarmObserver = NotificationCenter.default.addObserver(
            forName: .vybeAlarmFired, object: nil, queue: .main
        ) { [weak self] notification in
            guard let name = notification.userInfo?["name"] as? String else { return }
            Task { @MainActor in
                self?.messages.append(AssistantMessage(role: .assistant, text: "🔔 Alarm: \(name)"))
                if self?.speakResponses == true {
                    self?.speak("Alarm: \(name)")
                }
            }
        }
    }

    deinit {
        if let timerObserver { NotificationCenter.default.removeObserver(timerObserver) }
        if let alarmObserver { NotificationCenter.default.removeObserver(alarmObserver) }
    }

    var apiKey: String {
        get { provider == .gemini ? gemini.apiKey : router.apiKey }
        set {
            if provider == .gemini { gemini.apiKey = newValue }
            else { router.apiKey = newValue }
        }
    }

    // MARK: - Settings

    func saveVoiceSettings() {
        UserDefaults.standard.set(speakResponses, forKey: "VYBE.speakResponses")
        UserDefaults.standard.set(autoListenOnLaunch, forKey: "VYBE.autoListenOnLaunch")
        UserDefaults.standard.set(speechRate, forKey: "VYBE.speechRate")
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "VYBE.selectedVoice")
    }

    var isConfiguredForFreeModel: Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":free")
    }

    func saveSettings() {
        UserDefaults.standard.set(provider.rawValue, forKey: "VYBE.aiProvider")
        if provider == .gemini {
            gemini.saveSettings()
            status = gemini.hasAPIKey ? "Gemini settings saved" : "Add your Google Gemini API key"
            return
        }
        let cleanedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedModel.hasSuffix(":free") else {
            status = "Choose an OpenRouter model ending in :free"
            return
        }
        model = cleanedModel
        router.selectModel(cleanedModel)
        router.saveSettings()
        status = router.hasAPIKey ? "Settings saved" : "Add your OpenRouter API key"
    }

    // MARK: - Speech Recognition

    func startListening() {
        guard !isListening, !isThinking else { return }
        if provider == .openRouter {
            guard router.hasAPIKey else { showSettings = true; status = "Add your OpenRouter API key first"; return }
            guard isConfiguredForFreeModel else { showSettings = true; status = "Select a free OpenRouter model ending in :free"; return }
        } else {
            guard gemini.hasAPIKey, !gemini.selectedModelID.isEmpty else { showSettings = true; status = "Configure your Google Gemini API key and model"; return }
        }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition is unavailable"
            hasError = true
            return
        }

        // Stop any TTS output first (anti-loop)
        stopSpeaking()

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.status = "Microphone permission is required"
                    self?.hasError = true
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { auth in
                Task { @MainActor in
                    guard auth == .authorized else {
                        self?.status = "Speech recognition permission is required"
                        self?.hasError = true
                        return
                    }
                    self?.hasError = false
                    self?.beginRecognition(using: recognizer)
                }
            }
        }
    }

    private func beginRecognition(using recognizer: SFSpeechRecognizer) {
        stopListening()
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            status = "Could not start microphone: \(error.localizedDescription)"
            hasError = true
            return
        }
        isListening = true
        hasError = false
        status = "Listening… speak now"

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self?.finishRecognitionAndAsk()
                    } else {
                        self?.scheduleSilenceFinish()
                    }
                }
                if let error, self?.isListening == true {
                    self?.stopListening()
                    self?.status = "Speech error: \(error.localizedDescription)"
                    self?.hasError = true
                }
            }
        }
    }

    func finishRecognitionAndAsk() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        guard !text.isEmpty else {
            status = "I didn't catch that. Try again."
            return
        }
        Task { await send(text) }
    }

    private func scheduleSilenceFinish() {
        silenceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isListening,
                      !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.finishRecognitionAndAsk()
            }
        }
        silenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    func stopListening() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    // MARK: - TTS

    func speak(_ text: String) {
        guard speakResponses else { return }
        isSpeakingOutput = true
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.9

        if !selectedVoiceIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
        } else {
            // Try a good English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isSpeakingOutput = false
    }

    // MARK: - Send Message

    func sendTyped(_ text: String) async {
        await send(text)
    }

    func sendCurrentText() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcript = ""
        Task { await send(text) }
    }

    private func send(_ text: String) async {
        messages.append(AssistantMessage(role: .user, text: text))

        // 1. FAST-PATH LOCAL INTENT:
        // If this is a direct desktop command (e.g. "Open Safari", "What time is it", "Set a timer", etc.),
        // execute it locally immediately! Zero network call, zero latency, zero rate limit!
        if let action = IntentParser.parseFromText(text) {
            isExecutingAction = true
            status = "Executing…"
            hasError = false
            let result = await DesktopActionExecutor.shared.execute(action)
            isExecutingAction = false

            messages.append(AssistantMessage(role: .assistant, text: result.message))
            status = result.success ? "Done" : "Action failed"
            if speakResponses { speak(result.message) }
            return // Done! Never touches OpenRouter, completely avoids rate limits!
        }

        // 2. AI QUERY: route through the selected provider.
        if provider == .gemini {
            guard gemini.hasAPIKey else { showSettings = true; status = "Add your Google Gemini API key"; return }
            guard !gemini.selectedModelID.isEmpty else { showSettings = true; status = "Choose a Gemini model"; return }
            isThinking = true
            hasError = false
            status = "Processing with Gemini…"
            defer { isThinking = false }
            do {
                var history: [[String: String]] = [["role": "system", "content": systemPrompt]]
                history += messages.suffix(6).map { ["role": $0.role.rawValue, "content": $0.text] }
                let answer = try await gemini.generate(messages: history)
                if let action = IntentParser.parseFromText(answer) {
                    isExecutingAction = true
                    status = "Executing action…"
                    let result = await DesktopActionExecutor.shared.execute(action)
                    isExecutingAction = false
                    let finalText = result.message
                    messages.append(AssistantMessage(role: .assistant, text: finalText))
                    status = result.success ? "Done" : "Action failed"
                    if speakResponses { speak(finalText) }
                } else {
                    messages.append(AssistantMessage(role: .assistant, text: answer))
                    status = "Answered with Gemini"
                    if speakResponses { speak(answer) }
                }
            } catch {
                hasError = true
                messages.append(AssistantMessage(role: .assistant, text: error.localizedDescription))
                status = "Gemini request failed"
            }
            return
        }

        guard router.hasAPIKey else { showSettings = true; status = "Add your OpenRouter API key"; return }
        guard isConfiguredForFreeModel else { showSettings = true; status = "Select a free model ending in :free"; return }

        isThinking = true
        hasError = false
        status = "Processing…"
        defer { isThinking = false }

        do {
            // Keep recent 6 messages to stay well within free model token/rate limits
            var apiMessages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]
            for msg in messages.suffix(6) {
                apiMessages.append(["role": msg.role.rawValue, "content": msg.text])
            }

            // Send with tool definitions
            let response = try await router.sendChat(
                messages: apiMessages,
                tools: IntentParser.toolDefinitions
            )

            guard let choice = response.choices.first else {
                throw OpenRouterError.invalidResponse
            }

            // Check for tool calls
            if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
                isExecutingAction = true
                status = "Executing action…"
                defer { isExecutingAction = false }

                var resultMessages: [String] = []
                for call in toolCalls {
                    if let action = IntentParser.parseToolCall(call) {
                        let result = await DesktopActionExecutor.shared.execute(action)
                        resultMessages.append(result.message)
                    }
                }

                let combined = resultMessages.joined(separator: "\n")
                // Send tool results back to get a natural response
                apiMessages.append(["role": "assistant", "content": "I performed the following actions:\n\(combined)"])
                apiMessages.append(["role": "user", "content": "Briefly confirm what you just did in a natural way."])

                let followUp = try await router.sendChat(messages: apiMessages)
                let answer = followUp.choices.first?.message.content ?? combined
                messages.append(AssistantMessage(role: .assistant, text: answer))
                status = "Done"
                if speakResponses { speak(answer) }
            } else if let content = choice.message.content, !content.isEmpty {
                // Plain text response — check for implicit intent
                if let action = IntentParser.parseFromText(text) {
                    isExecutingAction = true
                    status = "Executing…"
                    let result = await DesktopActionExecutor.shared.execute(action)
                    isExecutingAction = false

                    let fullResponse = !content.isEmpty ? content : result.message
                    messages.append(AssistantMessage(role: .assistant, text: fullResponse))
                    status = result.success ? "Done" : "Action failed"
                    if speakResponses { speak(fullResponse) }
                } else {
                    messages.append(AssistantMessage(role: .assistant, text: content))
                    status = "Answered"
                    if speakResponses { speak(content) }
                }
            } else {
                throw OpenRouterError.invalidResponse
            }
        } catch let error as OpenRouterError {
            hasError = true
            let errorMsg: String
            switch error {
            case .modelUnavailable(let model):
                errorMsg = "Model \"\(model)\" is no longer available. Please select a different free model from AI Settings."
                showSettings = true
            case .rateLimited:
                errorMsg = "Rate limited by OpenRouter. Please wait a moment and try again."
            case .noAPIKey:
                errorMsg = "Please add your OpenRouter API key in AI Settings."
                showSettings = true
            default:
                errorMsg = error.localizedDescription ?? "An error occurred."
            }
            messages.append(AssistantMessage(role: .assistant, text: errorMsg))
            status = "Error"
        } catch {
            hasError = true
            messages.append(AssistantMessage(role: .assistant, text: "I couldn't get a response. \(error.localizedDescription)"))
            status = "Request failed"
        }
    }
}

// MARK: - TTS Delegate

private class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var assistant: VYBEAssistant?

    init(assistant: VYBEAssistant) {
        self.assistant = assistant
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            assistant?.isSpeaking = false
            assistant?.isSpeakingOutput = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            assistant?.isSpeaking = false
            assistant?.isSpeakingOutput = false
        }
    }
}
