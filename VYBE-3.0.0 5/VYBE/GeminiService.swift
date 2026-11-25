import Foundation
import Combine
import Security

// MARK: - Gemini Keychain

enum GeminiKeychainStore {
    private static let service = "com.vybe.desktop.gemini"
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(cleaned.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct GeminiModel: Identifiable, Decodable, Hashable {
    let name: String
    let displayName: String?
    let supportedGenerationMethods: [String]?
    var id: String { name.replacingOccurrences(of: "models/", with: "") }
    var title: String { displayName?.isEmpty == false ? displayName! : id }

    enum CodingKeys: String, CodingKey {
        case name, displayName = "displayName", supportedGenerationMethods = "supportedGenerationMethods"
    }
}

@MainActor
final class GeminiService: ObservableObject {
    static let shared = GeminiService()

    @Published var apiKey: String = ""
    private var didLoadKeychainKey = false
    @Published var models: [GeminiModel] = []
    @Published var selectedModelID: String = UserDefaults.standard.string(forKey: "VYBE.geminiModel") ?? ""
    @Published var isLoadingModels = false
    @Published var isValidatingKey = false
    @Published var apiKeyValid: Bool?
    @Published var modelLoadError: String?

    private init() {}

    func loadKeychainIfNeeded() {
        guard !didLoadKeychainKey else { return }
        didLoadKeychainKey = true
        apiKey = GeminiKeychainStore.read() ?? ""
    }

    var hasAPIKey: Bool {
        loadKeychainIfNeeded()
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveSettings() {
        loadKeychainIfNeeded()
        GeminiKeychainStore.save(apiKey)
        UserDefaults.standard.set(selectedModelID, forKey: "VYBE.geminiModel")
    }

    func selectModel(_ id: String) {
        selectedModelID = id
        UserDefaults.standard.set(id, forKey: "VYBE.geminiModel")
    }

    func fetchModels() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { modelLoadError = "Add your Google AI Studio API key first."; return }
        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }
        do {
            var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!)
            request.timeoutInterval = 25
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GeminiServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw GeminiServiceError.http(http.statusCode, Self.errorMessage(from: data))
            }
            let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            let usable = decoded.models
                .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            models = usable
            if !usable.contains(where: { $0.id == selectedModelID }), let first = usable.first {
                selectModel(first.id)
            }
            if usable.isEmpty { modelLoadError = "No models supporting generateContent were returned for this API key." }
            apiKeyValid = true
        } catch {
            modelLoadError = error.localizedDescription
            apiKeyValid = false
        }
    }

    func validateAPIKey() async {
        isValidatingKey = true
        defer { isValidatingKey = false }
        await fetchModels()
        if models.isEmpty { apiKeyValid = false }
        else { apiKeyValid = true }
    }

    func generate(messages: [[String: String]]) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeminiServiceError.noAPIKey }
        guard !selectedModelID.isEmpty else { throw GeminiServiceError.noModel }

        let systemText = messages.first(where: { $0["role"] == "system" })?["content"] ?? "You are VYBE, a concise and helpful macOS desktop assistant."
        let contents: [[String: Any]] = messages.compactMap { message in
            guard let role = message["role"], let text = message["content"], role != "system" else { return nil }
            let geminiRole = role == "assistant" ? "model" : "user"
            return ["role": geminiRole, "parts": [["text": text]]]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemText]]],
            "contents": contents,
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": 1024]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModelID):generateContent"
        guard let url = URL(string: endpoint) else { throw GeminiServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.httpBody = encoded
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiServiceError.http(http.statusCode, Self.errorMessage(from: data))
        }
        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined(separator: "\n") ?? ""
        guard !text.isEmpty else { throw GeminiServiceError.emptyResponse }
        return text
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String { return message }
        return String(data: data, encoding: .utf8) ?? "Unknown Google API error"
    }
}

private struct GeminiModelsResponse: Decodable { let models: [GeminiModel] }
private struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

enum GeminiServiceError: LocalizedError {
    case noAPIKey, noModel, invalidResponse, emptyResponse, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Add your Google Gemini API key in VYBE AI Settings."
        case .noModel: return "Choose a Gemini model in VYBE AI Settings."
        case .invalidResponse: return "Google Gemini returned an invalid response."
        case .emptyResponse: return "Gemini returned no text. Try another model or prompt."
        case .http(let code, let detail):
            if code == 400 || code == 403 { return "Gemini API rejected the request (HTTP \(code)): \(detail)" }
            if code == 429 { return "Gemini quota or rate limit reached. Check your Google AI Studio limits." }
            if code == 404 { return "Gemini model not found. Refresh the model list and choose an available model." }
            return "Gemini API error (HTTP \(code)): \(detail)"
        }
    }
}
