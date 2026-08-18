import Foundation
import Combine

struct AIProviderConfiguration: Sendable {
    let baseURL: URL
    let apiKey: String
    let transcriptionModel: String
    let textModel: String
}

/// User-owned AI configuration. Non-secret fields live in UserDefaults; the API
/// key lives in macOS Keychain and is never synced by Vibe Read.
@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()

    private enum Key {
        static let baseURL = "aiProviderBaseURL"
        static let transcriptionModel = "aiProviderTranscriptionModel"
        static let textModel = "aiProviderTextModel"
        static let apiKey = "ai_provider_api_key"
    }

    private static let defaultTextModel = "openai/gpt-oss-120b"
    private static let retiredGroqTextModel = "llama-3.3-70b-versatile"

    private let defaults = UserDefaults.standard

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Key.baseURL) }
    }

    @Published var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: Key.transcriptionModel) }
    }

    @Published var textModel: String {
        didSet { defaults.set(textModel, forKey: Key.textModel) }
    }

    @Published private(set) var hasAPIKey: Bool

    private init() {
        baseURL = defaults.string(forKey: Key.baseURL) ?? "https://api.groq.com/openai/v1"
        transcriptionModel = defaults.string(forKey: Key.transcriptionModel) ?? "whisper-large-v3-turbo"
        let storedTextModel = defaults.string(forKey: Key.textModel)
        textModel = storedTextModel == Self.retiredGroqTextModel
            ? Self.defaultTextModel
            : (storedTextModel ?? Self.defaultTextModel)
        if storedTextModel == Self.retiredGroqTextModel {
            defaults.set(Self.defaultTextModel, forKey: Key.textModel)
        }
        hasAPIKey = KeychainHelper.shared.get(key: Key.apiKey)?.isEmpty == false
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainHelper.shared.delete(key: Key.apiKey)
        } else {
            try KeychainHelper.shared.save(token: trimmed, for: Key.apiKey)
        }
        hasAPIKey = KeychainHelper.shared.get(key: Key.apiKey)?.isEmpty == false
        if !trimmed.isEmpty && !hasAPIKey {
            throw KeychainError.couldNotVerifySecret
        }
    }

    func clearAPIKey() throws {
        try saveAPIKey("")
    }

    var configuration: AIProviderConfiguration? {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized), url.scheme == "https" || url.isLoopback else {
            return nil
        }

        return AIProviderConfiguration(
            baseURL: url,
            apiKey: KeychainHelper.shared.get(key: Key.apiKey) ?? "",
            transcriptionModel: transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines),
            textModel: textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private extension URL {
    var isLoopback: Bool {
        guard scheme == "http" else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
