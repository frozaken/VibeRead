import Combine
import Foundation

struct ProviderModelOption: Identifiable, Hashable, Sendable {
    let modelID: String
    let displayName: String
    let detail: String

    var id: String { modelID }
}

enum ProviderCredential: String, CaseIterable, Identifiable, Sendable {
    case elevenLabs
    case groq
    case openRouter
    case openAI
    case customDictation
    case customText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .customDictation: return "custom dictation provider"
        case .customText: return "custom Cmd+E provider"
        }
    }

    var keychainAccount: String {
        switch self {
        case .elevenLabs: return "elevenlabs_api_key"
        case .groq: return "groq_api_key"
        case .openRouter: return "openrouter_api_key"
        case .openAI: return "openai_api_key"
        case .customDictation: return "custom_dictation_api_key"
        case .customText: return "custom_text_action_api_key"
        }
    }

    var environmentVariableName: String {
        switch self {
        case .elevenLabs: return "ELEVENLABS_API_KEY"
        case .groq: return "GROQ_API_KEY"
        case .openRouter: return "OPENROUTER_API_KEY"
        case .openAI: return "OPENAI_API_KEY"
        case .customDictation: return "CUSTOM_DICTATION_API_KEY"
        case .customText: return "CUSTOM_TEXT_ACTION_API_KEY"
        }
    }
}

enum ProviderCredentialStatus: Equatable, Sendable {
    case missing
    case configured
    case inaccessible(String)

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }

    var hasStoredCredential: Bool {
        switch self {
        case .configured, .inaccessible:
            return true
        case .missing:
            return false
        }
    }

    var errorMessage: String? {
        if case .inaccessible(let message) = self { return message }
        return nil
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case english = "en"
    case danish = "da"
    case swedish = "sv"
    case norwegian = "no"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case ukrainian = "uk"
    case japanese = "ja"
    case mandarinChinese = "zh"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Auto detect"
        case .english: return "English"
        case .danish: return "Danish"
        case .swedish: return "Swedish"
        case .norwegian: return "Norwegian"
        case .german: return "German"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .ukrainian: return "Ukrainian"
        case .japanese: return "Japanese"
        case .mandarinChinese: return "Mandarin Chinese"
        case .korean: return "Korean"
        }
    }

    var apiCode: String? { self == .automatic ? nil : rawValue }
}

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case elevenLabs
    case groq
    case openRouter
    case openAI
    case customOpenAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .customOpenAICompatible: return "Advanced"
        }
    }

    var credential: ProviderCredential {
        switch self {
        case .elevenLabs: return .elevenLabs
        case .groq: return .groq
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .customOpenAICompatible: return .customDictation
        }
    }

    var supportsEditableModel: Bool { self != .elevenLabs }

    var modelOptions: [ProviderModelOption] {
        switch self {
        case .elevenLabs:
            return [
                .init(
                    modelID: AIProviderCatalog.elevenLabsSpeechModel,
                    displayName: "Scribe v2",
                    detail: "Tested with Vibe Read for multilingual dictation"
                )
            ]
        case .groq: return AIProviderCatalog.groqSpeechModels
        case .openRouter: return AIProviderCatalog.openRouterSpeechModels
        case .openAI: return AIProviderCatalog.openAISpeechModels
        case .customOpenAICompatible: return []
        }
    }
}

enum TextActionProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter
    case groq
    case openAI
    case customOpenAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        case .customOpenAICompatible: return "Advanced"
        }
    }

    var credential: ProviderCredential {
        switch self {
        case .openRouter: return .openRouter
        case .groq: return .groq
        case .openAI: return .openAI
        case .customOpenAICompatible: return .customText
        }
    }

    /// Presets are convenience choices; every text provider also accepts an
    /// explicit model slug so the app does not lag provider catalogs.
    var supportsEditableModel: Bool { true }

    var modelOptions: [ProviderModelOption] {
        switch self {
        case .openRouter: return AIProviderCatalog.openRouterTextModels
        case .groq: return AIProviderCatalog.groqTextModels
        case .openAI: return AIProviderCatalog.openAITextModels
        case .customOpenAICompatible: return []
        }
    }
}

enum AIProviderCatalog {
    static let elevenLabsSpeechModel = "scribe_v2"

    static let groqSpeechModels: [ProviderModelOption] = [
        .init(
            modelID: "whisper-large-v3-turbo",
            displayName: "Whisper Large V3 Turbo",
            detail: "Groq's faster, lower-cost Whisper option"
        ),
        .init(
            modelID: "whisper-large-v3",
            displayName: "Whisper Large V3",
            detail: "Groq's lower-WER Whisper option"
        )
    ]

    static let openRouterSpeechModels: [ProviderModelOption] = [
        .init(
            modelID: "openai/gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            detail: "Full OpenAI transcription model through OpenRouter"
        ),
        .init(
            modelID: "openai/gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe",
            detail: "Lower-cost OpenAI transcription model"
        )
    ]

    static let openAISpeechModels: [ProviderModelOption] = [
        .init(
            modelID: "gpt-transcribe",
            displayName: "GPT Transcribe",
            detail: "Supports language and keyword hints"
        ),
        .init(
            modelID: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe",
            detail: "Lower cost"
        ),
        .init(
            modelID: "whisper-1",
            displayName: "Whisper 1",
            detail: "Original Whisper API model"
        )
    ]

    static let groqTextModels: [ProviderModelOption] = [
        .init(
            modelID: "openai/gpt-oss-20b",
            displayName: "GPT OSS 20B",
            detail: "Fast option for Smart Dictation and actions"
        ),
        .init(
            modelID: "openai/gpt-oss-120b",
            displayName: "GPT OSS 120B",
            detail: "Larger model for more involved actions"
        )
    ]

    static let openRouterTextModels: [ProviderModelOption] = [
        .init(
            modelID: "openai/gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            detail: "Fast option for Smart Dictation and actions"
        ),
        .init(
            modelID: "openai/gpt-oss-20b",
            displayName: "GPT OSS 20B",
            detail: "Low cost open model"
        )
    ]

    static let openAITextModels: [ProviderModelOption] = [
        .init(
            modelID: "gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            detail: "Fast option for Smart Dictation and actions"
        )
    ]
}

struct ElevenLabsDictationConfiguration: Equatable, Sendable {
    let apiKey: String
    let languageCode: String?
}

struct GroqDictationConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
    let languageCode: String?
}

struct OpenRouterDictationConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
    let languageCode: String?
}

struct OpenAIDictationConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
    let languageCode: String?
}

struct CustomOpenAICompatibleDictationConfiguration: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String
    let model: String
    let languageCode: String?
}

enum DictationProviderConfiguration: Equatable, Sendable {
    case elevenLabs(ElevenLabsDictationConfiguration)
    case groq(GroqDictationConfiguration)
    case openRouter(OpenRouterDictationConfiguration)
    case openAI(OpenAIDictationConfiguration)
    case customOpenAICompatible(CustomOpenAICompatibleDictationConfiguration)

    var provider: DictationProvider {
        switch self {
        case .elevenLabs: return .elevenLabs
        case .groq: return .groq
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .customOpenAICompatible: return .customOpenAICompatible
        }
    }
}

struct GroqTextActionConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
}

struct OpenRouterTextActionConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
}

struct OpenAITextActionConfiguration: Equatable, Sendable {
    let apiKey: String
    let model: String
}

struct CustomOpenAICompatibleTextActionConfiguration: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String
    let model: String
}

enum TextActionProviderConfiguration: Equatable, Sendable {
    case groq(GroqTextActionConfiguration)
    case openRouter(OpenRouterTextActionConfiguration)
    case openAI(OpenAITextActionConfiguration)
    case customOpenAICompatible(CustomOpenAICompatibleTextActionConfiguration)

    var provider: TextActionProvider {
        switch self {
        case .groq: return .groq
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .customOpenAICompatible: return .customOpenAICompatible
        }
    }
}

@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()

    enum ConfigurationError: LocalizedError, Equatable {
        case missingAPIKey(ProviderCredential)
        case inaccessibleAPIKey(ProviderCredential, String)
        case invalidBaseURL
        case missingModel(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let provider):
                return "Add your \(provider.displayName) API key in Settings"
            case .inaccessibleAPIKey(let provider, let message):
                return "The \(provider.displayName) API key is unavailable. \(message)"
            case .invalidBaseURL:
                return "Enter a valid HTTPS provider URL or an HTTP loopback URL"
            case .missingModel(let feature):
                return "Choose a model for \(feature)"
            }
        }
    }

    enum StorageKey {
        static let dictationProvider = "provider.v2.dictation.provider"
        static let dictationLanguage = "provider.v2.dictation.language"
        static let groqDictationModel = "provider.v2.dictation.groq.model"
        static let openRouterDictationModel = "provider.v2.dictation.openrouter.model"
        static let openAIDictationModel = "provider.v2.dictation.openai.model"
        static let customDictationModel = "provider.v2.dictation.custom.model"
        static let textActionProvider = "provider.v2.text.provider"
        static let groqTextModel = "provider.v2.text.groq.model"
        static let openRouterTextModel = "provider.v2.text.openrouter.model"
        static let openAITextModel = "provider.v2.text.openai.model"
        static let customTextModel = "provider.v2.text.custom.model"
        static let customDictationBaseURL = "provider.v2.dictation.custom.baseURL"
        static let customTextBaseURL = "provider.v2.text.custom.baseURL"
        // A short-lived local-only build used one custom URL for both features.
        // Read it as a non-secret fallback, then persist independent values.
        static let sharedCustomBaseURL = "provider.v2.custom.baseURL"
        static let legacyDictationProvider = "dictationProvider"
        static let legacyBaseURL = "aiProviderBaseURL"
        static let legacyTranscriptionModel = "aiProviderTranscriptionModel"
        static let legacyTextModel = "aiProviderTextModel"
        static func credentialConfigured(_ credential: ProviderCredential) -> String {
            "provider.v3.credential.\(credential.rawValue).configured"
        }
        static func environmentFilePath(_ credential: ProviderCredential) -> String {
            "provider.v3.credential.\(credential.rawValue).environmentFilePath"
        }
    }

    private enum LegacyProviderKind: Equatable {
        case groq
        case openRouter
        case openAI
        case custom

        var dictationProvider: DictationProvider {
            switch self {
            case .groq: return .groq
            case .openRouter: return .openRouter
            case .openAI: return .openAI
            case .custom: return .customOpenAICompatible
            }
        }

        var textActionProvider: TextActionProvider {
            switch self {
            case .groq: return .groq
            case .openRouter: return .openRouter
            case .openAI: return .openAI
            case .custom: return .customOpenAICompatible
            }
        }

    }

    typealias SecretReader = (String) throws -> String?
    typealias SecretWriter = (String, String) throws -> Void
    typealias SecretDeleter = (String) throws -> Void

    nonisolated private static let groqBaseURL = URL(
        string: "https://api.groq.com/openai/v1"
    )!
    nonisolated private static let openRouterBaseURL = URL(
        string: "https://openrouter.ai/api/v1"
    )!
    nonisolated private static let openAIBaseURL = URL(
        string: "https://api.openai.com/v1"
    )!
    private static let retiredGroqTextModel = "llama-3.3-70b-versatile"

    private let defaults: UserDefaults
    private let readSecret: SecretReader
    private let readPreviousSecret: SecretReader
    private let writeSecret: SecretWriter
    private let deleteSecret: SecretDeleter

    @Published var dictationProvider: DictationProvider {
        didSet { defaults.set(dictationProvider.rawValue, forKey: StorageKey.dictationProvider) }
    }
    @Published var dictationLanguage: TranscriptionLanguage {
        didSet { defaults.set(dictationLanguage.rawValue, forKey: StorageKey.dictationLanguage) }
    }
    @Published var groqDictationModel: String {
        didSet { defaults.set(groqDictationModel, forKey: StorageKey.groqDictationModel) }
    }
    @Published var openRouterDictationModel: String {
        didSet {
            defaults.set(openRouterDictationModel, forKey: StorageKey.openRouterDictationModel)
        }
    }
    @Published var openAIDictationModel: String {
        didSet { defaults.set(openAIDictationModel, forKey: StorageKey.openAIDictationModel) }
    }
    @Published var customDictationModel: String {
        didSet { defaults.set(customDictationModel, forKey: StorageKey.customDictationModel) }
    }
    @Published var textActionProvider: TextActionProvider {
        didSet { defaults.set(textActionProvider.rawValue, forKey: StorageKey.textActionProvider) }
    }
    @Published var groqTextModel: String {
        didSet { defaults.set(groqTextModel, forKey: StorageKey.groqTextModel) }
    }
    @Published var openRouterTextModel: String {
        didSet { defaults.set(openRouterTextModel, forKey: StorageKey.openRouterTextModel) }
    }
    @Published var openAITextModel: String {
        didSet { defaults.set(openAITextModel, forKey: StorageKey.openAITextModel) }
    }
    @Published var customTextModel: String {
        didSet { defaults.set(customTextModel, forKey: StorageKey.customTextModel) }
    }
    @Published var customDictationBaseURL: String {
        didSet {
            defaults.set(customDictationBaseURL, forKey: StorageKey.customDictationBaseURL)
        }
    }
    @Published var customTextBaseURL: String {
        didSet { defaults.set(customTextBaseURL, forKey: StorageKey.customTextBaseURL) }
    }
    @Published private(set) var credentialStatuses: [ProviderCredential: ProviderCredentialStatus]
    private var cachedSecrets: [ProviderCredential: String] = [:]

    init(
        defaults: UserDefaults = .standard,
        readSecret: @escaping SecretReader = { try KeychainHelper.shared.read(key: $0) },
        readPreviousSecret: @escaping SecretReader = {
            try KeychainHelper.shared.readPreviousVersion(key: $0)
        },
        writeSecret: @escaping SecretWriter = { value, account in
            try KeychainHelper.shared.save(token: value, for: account)
        },
        deleteSecret: @escaping SecretDeleter = { try KeychainHelper.shared.delete(key: $0) }
    ) {
        self.defaults = defaults
        self.readSecret = readSecret
        self.readPreviousSecret = readPreviousSecret
        self.writeSecret = writeSecret
        self.deleteSecret = deleteSecret

        let legacyDictationValue = defaults.string(forKey: StorageKey.legacyDictationProvider)
        let legacyBaseURL = defaults.string(forKey: StorageKey.legacyBaseURL)
        let legacyTranscriptionValue = defaults.string(
            forKey: StorageKey.legacyTranscriptionModel
        )
        let legacyTextValue = defaults.string(forKey: StorageKey.legacyTextModel)
        let legacyUsedOriginalGroqDefault = legacyDictationValue == "openAICompatible"
            || Self.nonempty(legacyTranscriptionValue) != nil
            || Self.nonempty(legacyTextValue) != nil
        let legacyProvider = Self.providerForLegacyBaseURL(legacyBaseURL)
            ?? (legacyUsedOriginalGroqDefault ? .groq : nil)

        if let stored = defaults.string(forKey: StorageKey.dictationProvider),
           let provider = DictationProvider(rawValue: stored) {
            dictationProvider = provider
        } else if legacyDictationValue == "elevenLabs" {
            dictationProvider = .elevenLabs
        } else if let legacyProvider {
            dictationProvider = legacyProvider.dictationProvider
        } else {
            dictationProvider = .elevenLabs
        }

        dictationLanguage = defaults.string(forKey: StorageKey.dictationLanguage)
            .flatMap(TranscriptionLanguage.init(rawValue:)) ?? .automatic

        let legacyTranscriptionModel = Self.nonempty(
            legacyTranscriptionValue
        )
        groqDictationModel = Self.nonempty(defaults.string(forKey: StorageKey.groqDictationModel))
            ?? (legacyProvider == .groq ? legacyTranscriptionModel : nil)
            ?? AIProviderCatalog.groqSpeechModels[0].modelID
        openRouterDictationModel = Self.nonempty(
            defaults.string(forKey: StorageKey.openRouterDictationModel)
        ) ?? (legacyProvider == .openRouter ? legacyTranscriptionModel : nil)
            ?? AIProviderCatalog.openRouterSpeechModels[0].modelID
        openAIDictationModel = Self.nonempty(
            defaults.string(forKey: StorageKey.openAIDictationModel)
        ) ?? (legacyProvider == .openAI ? legacyTranscriptionModel : nil)
            ?? AIProviderCatalog.openAISpeechModels[0].modelID
        customDictationModel = Self.nonempty(
            defaults.string(forKey: StorageKey.customDictationModel)
        ) ?? (legacyProvider == .custom ? legacyTranscriptionModel : nil) ?? ""

        if let stored = defaults.string(forKey: StorageKey.textActionProvider),
           let provider = TextActionProvider(rawValue: stored) {
            textActionProvider = provider
        } else {
            textActionProvider = legacyProvider?.textActionProvider ?? .openRouter
        }

        var legacyTextModel = Self.nonempty(legacyTextValue)
        if legacyTextModel == Self.retiredGroqTextModel {
            legacyTextModel = AIProviderCatalog.groqTextModels[0].modelID
        }
        groqTextModel = Self.nonempty(defaults.string(forKey: StorageKey.groqTextModel))
            ?? (legacyProvider == .groq ? legacyTextModel : nil)
            ?? AIProviderCatalog.groqTextModels[0].modelID
        openRouterTextModel = Self.nonempty(defaults.string(forKey: StorageKey.openRouterTextModel))
            ?? (legacyProvider == .openRouter ? legacyTextModel : nil)
            ?? AIProviderCatalog.openRouterTextModels[0].modelID
        openAITextModel = Self.nonempty(defaults.string(forKey: StorageKey.openAITextModel))
            ?? (legacyProvider == .openAI ? legacyTextModel : nil)
            ?? AIProviderCatalog.openAITextModels[0].modelID
        customTextModel = Self.nonempty(defaults.string(forKey: StorageKey.customTextModel))
            ?? (legacyProvider == .custom ? legacyTextModel : nil) ?? ""
        let sharedCustomBaseURL = Self.nonempty(
            defaults.string(forKey: StorageKey.sharedCustomBaseURL)
        )
        customDictationBaseURL = Self.nonempty(
            defaults.string(forKey: StorageKey.customDictationBaseURL)
        ) ?? sharedCustomBaseURL
            ?? (legacyProvider == .custom ? legacyBaseURL : nil)
            ?? "http://127.0.0.1:11434/v1"
        customTextBaseURL = Self.nonempty(
            defaults.string(forKey: StorageKey.customTextBaseURL)
        ) ?? sharedCustomBaseURL
            ?? (legacyProvider == .custom ? legacyBaseURL : nil)
            ?? "http://127.0.0.1:11434/v1"

        credentialStatuses = Dictionary(
            uniqueKeysWithValues: ProviderCredential.allCases.map { credential in
                (
                    credential,
                    defaults.bool(forKey: StorageKey.credentialConfigured(credential))
                        ? .configured
                        : .missing
                )
            }
        )
        persistNonsecretMigration()
    }

    var selectedDictationModel: String {
        get {
            switch dictationProvider {
            case .elevenLabs: return AIProviderCatalog.elevenLabsSpeechModel
            case .groq: return groqDictationModel
            case .openRouter: return openRouterDictationModel
            case .openAI: return openAIDictationModel
            case .customOpenAICompatible: return customDictationModel
            }
        }
        set {
            switch dictationProvider {
            case .elevenLabs: break
            case .groq: groqDictationModel = newValue
            case .openRouter: openRouterDictationModel = newValue
            case .openAI: openAIDictationModel = newValue
            case .customOpenAICompatible: customDictationModel = newValue
            }
        }
    }

    var selectedTextActionModel: String {
        get {
            switch textActionProvider {
            case .openRouter: return openRouterTextModel
            case .groq: return groqTextModel
            case .openAI: return openAITextModel
            case .customOpenAICompatible: return customTextModel
            }
        }
        set {
            switch textActionProvider {
            case .openRouter: openRouterTextModel = newValue
            case .groq: groqTextModel = newValue
            case .openAI: openAITextModel = newValue
            case .customOpenAICompatible: customTextModel = newValue
            }
        }
    }

    var availableDictationModels: [ProviderModelOption] { dictationProvider.modelOptions }
    var availableTextActionModels: [ProviderModelOption] { textActionProvider.modelOptions }

    /// A nonsecret readiness check used by launch and Settings routing. It
    /// never reads Keychain. A missing or inaccessible item is discovered only
    /// after the user explicitly verifies or invokes the selected provider.
    var needsDictationSetup: Bool {
        guard Self.nonempty(selectedDictationModel) != nil else { return true }
        if dictationProvider == .customOpenAICompatible {
            guard let url = Self.validatedProviderURL(customDictationBaseURL) else {
                return true
            }
            if url.isLoopbackProvider { return false }
        }
        return !defaults.bool(
            forKey: StorageKey.credentialConfigured(dictationProvider.credential)
        )
    }

    func credentialStatus(for credential: ProviderCredential) -> ProviderCredentialStatus {
        credentialStatuses[credential] ?? .missing
    }

    func environmentFileURL(for credential: ProviderCredential) -> URL? {
        guard let path = Self.nonempty(
            defaults.string(forKey: StorageKey.environmentFilePath(credential))
        ) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func environmentFileDisplayName(for credential: ProviderCredential) -> String? {
        environmentFileURL(for: credential)?.lastPathComponent
    }

    /// Refreshes display state from nonsecret UserDefaults markers only.
    /// It deliberately never probes Keychain.
    func refreshCredentialStatuses() {
        credentialStatuses = Dictionary(
            uniqueKeysWithValues: ProviderCredential.allCases.map { credential in
                let marked = defaults.bool(
                    forKey: StorageKey.credentialConfigured(credential)
                )
                let current = credentialStatuses[credential]
                return (
                    credential,
                    marked && current?.errorMessage != nil ? current! : (marked ? .configured : .missing)
                )
            }
        )
    }

    func saveAPIKey(_ value: String, for credential: ProviderCredential) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConfigurationError.missingAPIKey(credential)
        }
        try writeSecret(trimmed, credential.keychainAccount)
        cachedSecrets[credential] = trimmed
        defaults.removeObject(forKey: StorageKey.environmentFilePath(credential))
        defaults.set(true, forKey: StorageKey.credentialConfigured(credential))
        credentialStatuses[credential] = .configured
    }

    /// Uses a user-selected local file as the credential source. The secret is
    /// validated now but is never copied into UserDefaults or Keychain. Only
    /// the file path is remembered, and the exact provider variable is read
    /// again when that provider is intentionally used.
    func useEnvironmentFile(_ fileURL: URL, for credential: ProviderCredential) throws {
        _ = try EnvironmentKeyImporter.value(
            named: credential.environmentVariableName,
            in: fileURL
        )
        cachedSecrets.removeValue(forKey: credential)
        defaults.set(
            fileURL.standardizedFileURL.path,
            forKey: StorageKey.environmentFilePath(credential)
        )
        defaults.set(true, forKey: StorageKey.credentialConfigured(credential))
        credentialStatuses[credential] = .configured
    }

    func clearAPIKey(for credential: ProviderCredential) throws {
        if environmentFileURL(for: credential) == nil {
            try deleteSecret(credential.keychainAccount)
        }
        cachedSecrets.removeValue(forKey: credential)
        defaults.removeObject(forKey: StorageKey.environmentFilePath(credential))
        defaults.removeObject(forKey: StorageKey.credentialConfigured(credential))
        credentialStatuses[credential] = .missing
    }

    /// User-initiated recovery from the immediately previous local build.
    /// Keychain is not allowed to display authentication UI for this read.
    func recoverPreviousAPIKey(for credential: ProviderCredential) throws {
        guard let value = try readPreviousSecret(credential.keychainAccount),
              Self.nonempty(value) != nil else {
            throw ConfigurationError.missingAPIKey(credential)
        }
        try saveAPIKey(value, for: credential)
    }

    func dictationConfiguration() throws -> DictationProviderConfiguration {
        try dictationConfiguration(
            provider: dictationProvider,
            model: selectedDictationModel,
            language: dictationLanguage,
            customBaseURL: customDictationBaseURL,
            replacementAPIKey: nil
        )
    }

    /// Builds an unsaved Settings draft. A nonempty replacement key is used
    /// only in the returned value. A saved credential is read only when a
    /// nonsecret configured marker exists and the user explicitly verifies or
    /// invokes that provider.
    func dictationConfiguration(
        provider: DictationProvider,
        model: String,
        language: TranscriptionLanguage,
        customBaseURL: String,
        replacementAPIKey: String? = nil
    ) throws -> DictationProviderConfiguration {
        let languageCode = language.apiCode
        switch provider {
        case .elevenLabs:
            return .elevenLabs(
                .init(
                    apiKey: try requiredSecret(
                        for: .elevenLabs,
                        replacementAPIKey: replacementAPIKey
                    ),
                    languageCode: languageCode
                )
            )
        case .groq:
            return .groq(
                .init(
                    apiKey: try requiredSecret(
                        for: .groq,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "Groq dictation"),
                    languageCode: languageCode
                )
            )
        case .openRouter:
            return .openRouter(
                .init(
                    apiKey: try requiredSecret(
                        for: .openRouter,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "OpenRouter dictation"),
                    languageCode: languageCode
                )
            )
        case .openAI:
            return .openAI(
                .init(
                    apiKey: try requiredSecret(
                        for: .openAI,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "OpenAI dictation"),
                    languageCode: languageCode
                )
            )
        case .customOpenAICompatible:
            guard let baseURL = Self.validatedProviderURL(customBaseURL) else {
                throw ConfigurationError.invalidBaseURL
            }
            return .customOpenAICompatible(
                .init(
                    baseURL: baseURL,
                    apiKey: try secretAllowingLoopback(
                        for: .customDictation,
                        baseURL: baseURL,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "custom dictation"),
                    languageCode: languageCode
                )
            )
        }
    }

    func textActionConfiguration() throws -> TextActionProviderConfiguration {
        try textActionConfiguration(
            provider: textActionProvider,
            model: selectedTextActionModel,
            customBaseURL: customTextBaseURL,
            replacementAPIKey: nil
        )
    }

    /// Builds an unsaved Cmd+E Settings draft without persisting its provider,
    /// model, URL, or replacement key.
    func textActionConfiguration(
        provider: TextActionProvider,
        model: String,
        customBaseURL: String,
        replacementAPIKey: String? = nil
    ) throws -> TextActionProviderConfiguration {
        switch provider {
        case .openRouter:
            return .openRouter(
                .init(
                    apiKey: try requiredSecret(
                        for: .openRouter,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "Cmd+E")
                )
            )
        case .groq:
            return .groq(
                .init(
                    apiKey: try requiredSecret(
                        for: .groq,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "Cmd+E")
                )
            )
        case .openAI:
            return .openAI(
                .init(
                    apiKey: try requiredSecret(
                        for: .openAI,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "Cmd+E")
                )
            )
        case .customOpenAICompatible:
            guard let baseURL = Self.validatedProviderURL(customBaseURL) else {
                throw ConfigurationError.invalidBaseURL
            }
            return .customOpenAICompatible(
                .init(
                    baseURL: baseURL,
                    apiKey: try secretAllowingLoopback(
                        for: .customText,
                        baseURL: baseURL,
                        replacementAPIKey: replacementAPIKey
                    ),
                    model: try requiredModel(model, feature: "Cmd+E")
                )
            )
        }
    }

    var hasElevenLabsAPIKey: Bool { credentialStatus(for: .elevenLabs).isConfigured }
    var hasTextAPIKey: Bool { credentialStatus(for: textActionProvider.credential).isConfigured }
    /// Compatibility alias for the retired single custom URL setting.
    /// New UI should use `customDictationBaseURL` and `customTextBaseURL` explicitly.
    var customBaseURL: String {
        get { customTextBaseURL }
        set { customTextBaseURL = newValue }
    }
    var textBaseURL: String {
        get { customTextBaseURL }
        set { customTextBaseURL = newValue }
    }
    var transcriptionModel: String {
        get { selectedDictationModel }
        set { selectedDictationModel = newValue }
    }
    var textModel: String {
        get { selectedTextActionModel }
        set { selectedTextActionModel = newValue }
    }
    var textProviderAllowsEmptyAPIKey: Bool {
        textActionProvider == .customOpenAICompatible
            && Self.validatedProviderURL(customTextBaseURL)?.isLoopbackProvider == true
    }

    func saveElevenLabsAPIKey(_ value: String) throws { try saveAPIKey(value, for: .elevenLabs) }
    func clearElevenLabsAPIKey() throws { try clearAPIKey(for: .elevenLabs) }
    /// Reads the ElevenLabs credential only after a user explicitly starts
    /// speech generation, refreshes voices, or previews a voice.
    func elevenLabsAPIKeyForExplicitUse() throws -> String {
        try requiredSecret(for: .elevenLabs)
    }
    func saveTextAPIKey(_ value: String) throws {
        try saveAPIKey(value, for: textActionProvider.credential)
    }
    func clearTextAPIKey() throws { try clearAPIKey(for: textActionProvider.credential) }

    nonisolated static func validatedProviderURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            return nil
        }
        guard components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.percentEncodedFragment == nil,
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        let scheme = components.scheme?.lowercased()
        let normalizedHost = normalizedProviderHost(host)
        let isLoopback = normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else { return nil }
        components.scheme = scheme
        components.host = normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    nonisolated static func validatedTextProviderURL(_ value: String) -> URL? {
        validatedProviderURL(value)
    }

    nonisolated static var groqProviderBaseURL: URL { groqBaseURL }
    nonisolated static var openRouterProviderBaseURL: URL { openRouterBaseURL }
    nonisolated static var openAIProviderBaseURL: URL { openAIBaseURL }

    private func requiredSecret(
        for credential: ProviderCredential,
        replacementAPIKey: String? = nil
    ) throws -> String {
        if let replacement = Self.nonempty(replacementAPIKey) {
            return replacement
        }
        guard defaults.bool(forKey: StorageKey.credentialConfigured(credential)) else {
            throw ConfigurationError.missingAPIKey(credential)
        }
        return try storedSecret(for: credential)
    }

    private func secretAllowingLoopback(
        for credential: ProviderCredential,
        baseURL: URL,
        replacementAPIKey: String? = nil
    ) throws -> String {
        if let replacement = Self.nonempty(replacementAPIKey) {
            return replacement
        }
        guard defaults.bool(forKey: StorageKey.credentialConfigured(credential)) else {
            if baseURL.isLoopbackProvider { return "" }
            throw ConfigurationError.missingAPIKey(credential)
        }
        return try storedSecret(for: credential)
    }

    private func requiredModel(_ value: String, feature: String) throws -> String {
        guard let model = Self.nonempty(value) else {
            throw ConfigurationError.missingModel(feature)
        }
        return model
    }

    private func storedSecret(for credential: ProviderCredential) throws -> String {
        if let fileURL = environmentFileURL(for: credential) {
            do {
                return try EnvironmentKeyImporter.value(
                    named: credential.environmentVariableName,
                    in: fileURL
                )
            } catch {
                credentialStatuses[credential] = .inaccessible(error.localizedDescription)
                throw ConfigurationError.inaccessibleAPIKey(
                    credential,
                    "The selected .env file is unavailable. \(error.localizedDescription)"
                )
            }
        }
        if let cached = cachedSecrets[credential] {
            return cached
        }
        do {
            guard let stored = Self.nonempty(try readSecret(credential.keychainAccount)) else {
                defaults.removeObject(forKey: StorageKey.credentialConfigured(credential))
                credentialStatuses[credential] = .missing
                throw ConfigurationError.missingAPIKey(credential)
            }
            cachedSecrets[credential] = stored
            credentialStatuses[credential] = .configured
            return stored
        } catch let error as ConfigurationError {
            throw error
        } catch {
            credentialStatuses[credential] = .inaccessible(error.localizedDescription)
            throw ConfigurationError.inaccessibleAPIKey(
                credential,
                error.localizedDescription
            )
        }
    }

    private func persistNonsecretMigration() {
        defaults.set(dictationProvider.rawValue, forKey: StorageKey.dictationProvider)
        defaults.set(dictationLanguage.rawValue, forKey: StorageKey.dictationLanguage)
        defaults.set(groqDictationModel, forKey: StorageKey.groqDictationModel)
        defaults.set(openRouterDictationModel, forKey: StorageKey.openRouterDictationModel)
        defaults.set(openAIDictationModel, forKey: StorageKey.openAIDictationModel)
        defaults.set(customDictationModel, forKey: StorageKey.customDictationModel)
        defaults.set(textActionProvider.rawValue, forKey: StorageKey.textActionProvider)
        defaults.set(groqTextModel, forKey: StorageKey.groqTextModel)
        defaults.set(openRouterTextModel, forKey: StorageKey.openRouterTextModel)
        defaults.set(openAITextModel, forKey: StorageKey.openAITextModel)
        defaults.set(customTextModel, forKey: StorageKey.customTextModel)
        defaults.set(customDictationBaseURL, forKey: StorageKey.customDictationBaseURL)
        defaults.set(customTextBaseURL, forKey: StorageKey.customTextBaseURL)
    }

    private static func providerForLegacyBaseURL(_ value: String?) -> LegacyProviderKind? {
        guard let value, let url = validatedProviderURL(value), let host = url.host?.lowercased() else {
            return nil
        }
        switch normalizedProviderHost(host) {
        case "api.groq.com": return .groq
        case "openrouter.ai": return .openRouter
        case "api.openai.com": return .openAI
        default: return .custom
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private func normalizedProviderHost(_ host: String) -> String {
    let lowercased = host.lowercased()
    guard lowercased.hasPrefix("["), lowercased.hasSuffix("]") else {
        return lowercased
    }
    return String(lowercased.dropFirst().dropLast())
}

extension URL {
    var isLoopbackProvider: Bool {
        guard scheme?.lowercased() == "http" else { return false }
        let normalizedHost = host.map(normalizedProviderHost)
        return normalizedHost == "127.0.0.1"
            || normalizedHost == "localhost"
            || normalizedHost == "::1"
    }
}
