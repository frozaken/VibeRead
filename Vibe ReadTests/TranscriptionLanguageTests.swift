import Foundation
import Testing
@testable import Vibe_Read

struct TranscriptionLanguageTests {
    @Test func russianHasAStableLabelAndISOCode() throws {
        let russian = try #require(TranscriptionLanguage(rawValue: "ru"))

        #expect(russian.displayName == "Russian")
        #expect(russian.apiCode == "ru")
        #expect(TranscriptionLanguage.allCases.contains(russian))
    }

    @Test func languageCatalogHasUniqueStablePickerValues() {
        let languages = TranscriptionLanguage.allCases
        let explicitLanguages = Array(languages.dropFirst())

        #expect(languages.first == .automatic)
        #expect(languages.count == 53)
        #expect(languages.map(\.rawValue).count == Set(languages.map(\.rawValue)).count)
        #expect(languages.map(\.displayName).count == Set(languages.map(\.displayName)).count)
        #expect(TranscriptionLanguage.automatic.apiCode == nil)
        #expect(
            explicitLanguages
                .allSatisfy { $0.apiCode == $0.rawValue && !$0.displayName.isEmpty }
        )
        #expect(
            explicitLanguages.allSatisfy { language in
                let bytes = Array(language.rawValue.utf8)
                return bytes.count == 2 && bytes.allSatisfy { (97...122).contains($0) }
            }
        )
        #expect(
            explicitLanguages.map(\.displayName)
                == explicitLanguages.map(\.displayName).sorted()
        )
    }

    @Test func expandedCatalogIncludesLanguagesAcrossScriptsAndRegions() {
        let expectedLanguages = [
            "ar": "Arabic",
            "bn": "Bengali",
            "cs": "Czech",
            "el": "Greek",
            "fi": "Finnish",
            "he": "Hebrew",
            "hi": "Hindi",
            "ru": "Russian",
            "sw": "Swahili",
            "th": "Thai",
            "tr": "Turkish",
            "vi": "Vietnamese"
        ]

        for (code, displayName) in expectedLanguages {
            let language = TranscriptionLanguage(rawValue: code)
            #expect(language?.displayName == displayName)
            #expect(language?.apiCode == code)
        }
    }

    @Test @MainActor func russianPersistsAcrossSettingsReloadWithoutKeychainAccess() {
        let fixture = LanguageSettingsFixture()
        defer { fixture.cleanup() }

        let settings = fixture.makeSettings()
        settings.dictationLanguage = .russian

        #expect(
            fixture.defaults.string(forKey: AIProviderSettings.StorageKey.dictationLanguage)
                == "ru"
        )
        let reloaded = fixture.makeSettings()
        #expect(reloaded.dictationLanguage == .russian)
        #expect(fixture.secrets.reads.isEmpty)
        #expect(fixture.secrets.writes.isEmpty)
        #expect(fixture.secrets.deletes.isEmpty)
    }

    @Test @MainActor func existingElevenLabsCredentialAllowsLanguagePersistenceWithoutReadingOrReplacingIt() {
        let fixture = LanguageSettingsFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(
            true,
            forKey: AIProviderSettings.StorageKey.credentialConfigured(.elevenLabs)
        )
        fixture.secrets.values[ProviderCredential.elevenLabs.keychainAccount] = "existing-key"

        let settings = fixture.makeSettings()
        #expect(settings.credentialStatus(for: .elevenLabs).hasStoredCredential)

        settings.dictationProvider = .elevenLabs
        settings.dictationLanguage = .russian

        #expect(settings.dictationLanguage == .russian)
        #expect(fixture.makeSettings().dictationLanguage == .russian)
        #expect(fixture.secrets.reads.isEmpty)
        #expect(fixture.secrets.writes.isEmpty)
        #expect(fixture.secrets.deletes.isEmpty)
        #expect(fixture.secrets.values[ProviderCredential.elevenLabs.keychainAccount] == "existing-key")
    }

    @Test func russianSerializesUsingEachProvidersExactLanguageContract() async throws {
        let fixture = try LanguageAudioFixture()
        defer { fixture.cleanup() }

        let russian = try #require(TranscriptionLanguage(rawValue: "ru"))
        let languageCode = try #require(russian.apiCode)

        for providerCase in russianProviderCases(languageCode: languageCode) {
            let capture = LanguageRequestCapture()
            let service = APIService(
                transport: { request in
                    await capture.record(request)
                    return .init(
                        data: Data(#"{"text":"Russian transcript"}"#.utf8),
                        statusCode: 200
                    )
                },
                dictationConfiguration: { providerCase.configuration },
                textActionConfiguration: {
                    .openRouter(.init(apiKey: "unused", model: "unused"))
                }
            )

            _ = try await service.transcribeDictation(audioURL: fixture.audioURL)
            let recordedRequest = await capture.lastRequest
            let request = try #require(
                recordedRequest,
                "\(providerCase.name) did not issue a transcription request"
            )

            switch providerCase.contract {
            case .multipart(let fieldName):
                let body = try #require(request.httpBody)
                let multipart = String(decoding: body, as: UTF8.self)
                #expect(
                    multipart.contains("name=\"\(fieldName)\"\r\n\r\nru\r\n"),
                    "\(providerCase.name) must serialize Russian as \(fieldName)=ru"
                )

            case .json:
                let body = try #require(request.httpBody)
                let object = try #require(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                #expect(
                    object["language"] as? String == "ru",
                    "\(providerCase.name) must serialize Russian as language=ru"
                )
            }
        }
    }
}

private actor LanguageRequestCapture {
    private(set) var lastRequest: URLRequest?

    func record(_ request: URLRequest) {
        lastRequest = request
    }
}

private final class LanguageSecretSpy {
    var values: [String: String] = [:]
    var reads: [String] = []
    var writes: [(account: String, value: String)] = []
    var deletes: [String] = []

    func read(_ account: String) -> String? {
        reads.append(account)
        return values[account]
    }

    func write(_ value: String, account: String) {
        values[account] = value
        writes.append((account, value))
    }

    func delete(_ account: String) {
        values.removeValue(forKey: account)
        deletes.append(account)
    }
}

@MainActor
private final class LanguageSettingsFixture {
    let suiteName = "VibeReadLanguageSettingsTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let secrets = LanguageSecretSpy()

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeSettings() -> AIProviderSettings {
        AIProviderSettings(
            defaults: defaults,
            readSecret: { [secrets] account in secrets.read(account) },
            readPreviousSecret: { _ in nil },
            writeSecret: { [secrets] value, account in
                secrets.write(value, account: account)
            },
            deleteSecret: { [secrets] account in secrets.delete(account) }
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct LanguageAudioFixture {
    let directory: URL
    let audioURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeReadLanguageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        audioURL = directory.appendingPathComponent("synthetic.m4a")
        try Data("synthetic-audio-payload".utf8).write(to: audioURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum LanguageRequestContract {
    case multipart(fieldName: String)
    case json
}

private struct RussianProviderCase {
    let name: String
    let configuration: DictationProviderConfiguration
    let contract: LanguageRequestContract
}

private func russianProviderCases(languageCode: String) -> [RussianProviderCase] {
    [
        .init(
            name: "ElevenLabs",
            configuration: .elevenLabs(
                .init(apiKey: "synthetic-key", languageCode: languageCode)
            ),
            contract: .multipart(fieldName: "language_code")
        ),
        .init(
            name: "Groq",
            configuration: .groq(
                .init(
                    apiKey: "synthetic-key",
                    model: "whisper-large-v3-turbo",
                    languageCode: languageCode
                )
            ),
            contract: .multipart(fieldName: "language")
        ),
        .init(
            name: "OpenRouter",
            configuration: .openRouter(
                .init(
                    apiKey: "synthetic-key",
                    model: "openai/gpt-4o-transcribe",
                    languageCode: languageCode
                )
            ),
            contract: .json
        ),
        .init(
            name: "OpenAI",
            configuration: .openAI(
                .init(
                    apiKey: "synthetic-key",
                    model: "gpt-transcribe",
                    languageCode: languageCode
                )
            ),
            contract: .multipart(fieldName: "languages[]")
        ),
        .init(
            name: "Custom provider",
            configuration: .customOpenAICompatible(
                .init(
                    baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
                    apiKey: "",
                    model: "synthetic-model",
                    languageCode: languageCode
                )
            ),
            contract: .multipart(fieldName: "language")
        )
    ]
}
