import Foundation
import Security

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.vybe.desktop.openrouter"
    private static let account = "api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

// MARK: - Data Models

struct OpenRouterModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let contextLength: Int?
    let description: String?
    let architecture: Architecture?

    struct Architecture: Codable, Hashable {
        let tokenizer: String?
        let instructType: String?

        enum CodingKeys: String, CodingKey {
            case tokenizer
            case instructType = "instruct_type"
        }
    }

    var isFree: Bool { id.hasSuffix(":free") }

    var displayName: String {
        if name.isEmpty { return id }
        return name
    }

    var contextLengthFormatted: String? {
        guard let ctx = contextLength, ctx > 0 else { return nil }
        if ctx >= 1_000_000 { return "\(ctx / 1_000_000)M tokens" }
        if ctx >= 1000 { return "\(ctx / 1000)K tokens" }
        return "\(ctx) tokens"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, architecture
        case contextLength = "context_length"
    }
}

struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}

struct OpenRouterChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
    let error: ErrorDetail?

    struct ErrorDetail: Codable {
        let message: String?
        let code: Int?
    }
}

struct ToolCall: Codable {
    let id: String?
    let type: String?
    let function: FunctionCall?

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

// MARK: - OpenRouter Errors

enum OpenRouterError: LocalizedError {
    case noAPIKey
    case notFreeModel
    case invalidResponse
    case httpError(Int, String)
    case modelUnavailable(String)
    case rateLimited(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured. Add your key in VYBE AI Settings."
        case .notFreeModel:
            return "Only free models (ending in :free) are allowed."
        case .invalidResponse:
            return "The AI returned an unreadable response."
        case .httpError(let code, let detail):
            if code == 401 { return "Invalid API key. Check your OpenRouter key." }
            if code == 429 { return "Rate limited by OpenRouter. Wait a moment and try again." }
            if code == 404 { return "Model not found. It may have been removed from OpenRouter." }
            return "OpenRouter returned HTTP \(code): \(detail.prefix(300))"
        case .modelUnavailable(let model):
            return "Model \"\(model)\" is no longer available on OpenRouter. Please select a different free model."
        case .rateLimited(let detail):
            return "Rate limited: \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - OpenRouter Service

@MainActor
final class OpenRouterService: ObservableObject {
    static let shared = OpenRouterService()

    @Published var availableFreeModels: [OpenRouterModel] = []
    @Published var selectedModelID: String = UserDefaults.standard.string(forKey: "VYBE.openRouterModel") ?? "deepseek/deepseek-r1:free"
    @Published var apiKey: String = ""
    private var didLoadKeychainKey = false
    @Published var isLoadingModels = false
    @Published var modelLoadError: String?
    @Published var apiKeyValid: Bool?
    @Published var isValidatingKey = false
    @Published var lastModelRefresh: Date?

    // Cached models persist across sessions
    private let cachedModelsKey = "VYBE.cachedFreeModels"
    private let cachedModelsDateKey = "VYBE.cachedFreeModelsDate"

    private init() {
        loadCachedModels()
    }

    var selectedModel: OpenRouterModel? {
        availableFreeModels.first(where: { $0.id == selectedModelID })
    }

    func loadKeychainIfNeeded() {
        guard !didLoadKeychainKey else { return }
        didLoadKeychainKey = true
        apiKey = KeychainStore.read() ?? ""
    }

    var hasAPIKey: Bool {
        loadKeychainIfNeeded()
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isModelFree: Bool {
        selectedModelID.hasSuffix(":free")
    }

    // MARK: - Model Discovery

    func fetchModels() async {
        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }

        do {
            let url = URL(string: "https://openrouter.ai/api/v1/models")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("VYBE", forHTTPHeaderField: "X-Title")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OpenRouterError.httpError(http.statusCode, detail)
            }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let freeModels = decoded.data
                .filter { $0.id.hasSuffix(":free") }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            availableFreeModels = freeModels
            lastModelRefresh = Date()
            cacheModels(freeModels)

            // If selected model is no longer available, notify
            if !selectedModelID.isEmpty && !freeModels.contains(where: { $0.id == selectedModelID }) {
                modelLoadError = "Your selected model \"\(selectedModelID)\" is no longer available. Please select a different free model."
            }
        } catch let error as OpenRouterError {
            modelLoadError = error.localizedDescription
        } catch {
            modelLoadError = "Failed to fetch models: \(error.localizedDescription)"
        }
    }

    private func cacheModels(_ models: [OpenRouterModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: cachedModelsKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cachedModelsDateKey)
        }
    }

    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: cachedModelsKey),
              let models = try? JSONDecoder().decode([OpenRouterModel].self, from: data) else { return }
        availableFreeModels = models
        let timestamp = UserDefaults.standard.double(forKey: cachedModelsDateKey)
        if timestamp > 0 { lastModelRefresh = Date(timeIntervalSince1970: timestamp) }
    }

    // MARK: - API Key Validation

    func validateAPIKey() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyValid = false
            return
        }

        isValidatingKey = true
        defer { isValidatingKey = false }

        do {
            let url = URL(string: "https://openrouter.ai/api/v1/models")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("VYBE", forHTTPHeaderField: "X-Title")

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                apiKeyValid = false
                return
            }
            apiKeyValid = (200..<300).contains(http.statusCode)
        } catch {
            apiKeyValid = false
        }
    }

    // MARK: - Save Settings

    func saveSettings() {
        loadKeychainIfNeeded()
        let cleanedModel = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cleanedModel, forKey: "VYBE.openRouterModel")
        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func selectModel(_ id: String) {
        guard id.hasSuffix(":free") else { return }
        selectedModelID = id
        UserDefaults.standard.set(id, forKey: "VYBE.openRouterModel")
    }

    // Recommended free models pool for automatic fallback when rate limited (429)
    static let fallbackFreeModels: [String] = [
        "google/gemma-3-27b-it:free",
        "meta-llama/llama-3.3-70b-instruct:free",
        "mistralai/mistral-small-3.1-24b-instruct:free",
        "qwen/qwen3-4b:free",
        "deepseek/deepseek-r1:free"
    ]

    // MARK: - Chat Completion

    func sendChat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil
    ) async throws -> OpenRouterChatResponse {
        do {
            return try await executeChatRequest(model: selectedModelID, messages: messages, tools: tools)
        } catch OpenRouterError.rateLimited(let detail) {
            // When rate limited on the selected model, attempt fallback across other free models in the pool!
            var candidateModels = availableFreeModels.map(\.id).filter { $0 != selectedModelID }
            for fb in Self.fallbackFreeModels where fb != selectedModelID && !candidateModels.contains(fb) {
                candidateModels.append(fb)
            }

            for candidate in candidateModels.prefix(3) {
                do {
                    let response = try await executeChatRequest(model: candidate, messages: messages, tools: tools)
                    // Automatically adopt the working free model so subsequent calls succeed
                    selectModel(candidate)
                    return response
                } catch {
                    continue
                }
            }
            throw OpenRouterError.rateLimited(detail)
        }
    }

    /// Sends a user-selected screenshot to the selected OpenRouter model.
    /// The chosen model must support image input; no screenshot is stored remotely by VYBE.
    func analyzeScreenshot(data: Data) async throws -> String {
        loadKeychainIfNeeded()
        let base64 = data.base64EncodedString()
        let message: [String: Any] = [
            "role": "user",
            "content": [
                ["type": "text", "text": "Analyze this screenshot. Explain what is visible, identify important text and interface elements, and help me understand or act on it. Be specific and organize the answer clearly."],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64)"]]
            ]
        ]
        let response = try await sendChat(messages: [message])
        guard let answer = response.choices.first?.message.content,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.invalidResponse
        }
        return answer
    }

    private func executeChatRequest(
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil
    ) async throws -> OpenRouterChatResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenRouterError.noAPIKey }
        guard model.hasSuffix(":free") else { throw OpenRouterError.notFreeModel }

        let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://vybe.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("VYBE", forHTTPHeaderField: "X-Title")

        var payload: [String: Any] = [
            "model": model,
            "messages": messages
        ]
        if let tools, !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenRouterError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        if http.statusCode == 429 {
            let detail = String(data: data, encoding: .utf8) ?? "Rate limit exceeded"
            throw OpenRouterError.rateLimited(detail)
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown API error"
            if http.statusCode == 404 || (detail.lowercased().contains("model") && detail.lowercased().contains("not found")) {
                throw OpenRouterError.modelUnavailable(model)
            }
            throw OpenRouterError.httpError(http.statusCode, detail)
        }

        let decoded = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)

        if let error = decoded.error {
            let msg = error.message ?? "Unknown error"
            if msg.lowercased().contains("model") {
                throw OpenRouterError.modelUnavailable(model)
            }
            throw OpenRouterError.httpError(error.code ?? 500, msg)
        }

        return decoded
    }
}
