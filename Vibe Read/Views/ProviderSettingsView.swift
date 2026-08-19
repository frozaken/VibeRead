import SwiftUI
import AppKit

private enum ProviderSaveResult {
    case success(String)
    case failure(String)
}

private struct DictationDraftFingerprint: Equatable {
    let provider: DictationProvider
    let model: String
    let language: TranscriptionLanguage
    let baseURL: String
    let key: String
}

private struct TextDraftFingerprint: Equatable {
    let provider: TextActionProvider
    let model: String
    let baseURL: String
    let key: String
}

private struct ProviderCredentialStatusLabel: View {
    let result: ProviderSaveResult?
    let status: ProviderCredentialStatus
    let allowsEmptyKey: Bool
    let environmentFileName: String?

    var body: some View {
        Group {
            switch result {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case nil:
                switch status {
                case .configured:
                    Label(
                        environmentFileName.map {
                            "Using \($0). The key is read only when you use this provider."
                        } ?? "API key saved. It is read only when you verify or use this provider.",
                        systemImage: environmentFileName == nil ? "checkmark.circle" : "doc.badge.checkmark"
                    )
                    .foregroundColor(.secondary)
                case .missing:
                    Label(
                        allowsEmptyKey
                            ? "A key is optional for this local endpoint"
                            : "No API key saved",
                        systemImage: allowsEmptyKey ? "checkmark.circle" : "circle.dashed"
                    )
                    .foregroundColor(.secondary)
                case .inaccessible(let message):
                    Label(
                        "Keychain could not read this key. \(message)",
                        systemImage: "lock.trianglebadge.exclamationmark"
                    )
                    .foregroundColor(.orange)
                }
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ProviderConfigurationSettingsView: View {
    @ObservedObject private var settings = AIProviderSettings.shared

    @State private var dictationProvider: DictationProvider = .elevenLabs
    @State private var dictationModel = AIProviderCatalog.elevenLabsSpeechModel
    @State private var dictationLanguage: TranscriptionLanguage = .automatic
    @State private var dictationBaseURL = ""
    @State private var dictationKey = ""
    @State private var dictationResult: ProviderSaveResult?
    @State private var isVerifyingDictation = false
    @State private var suppressNextDictationDraftReset = false
    @State private var dictationVerificationTask: Task<Void, Never>?
    @State private var dictationVerificationID = UUID()

    @State private var textProvider: TextActionProvider = .openRouter
    @State private var textModel = ""
    @State private var textBaseURL = ""
    @State private var textKey = ""
    @State private var textResult: ProviderSaveResult?
    @State private var isVerifyingText = false
    @State private var suppressNextTextDraftReset = false
    @State private var textVerificationTask: Task<Void, Never>?
    @State private var textVerificationID = UUID()
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Dictation and Cmd + E are configured independently. A key saved for Groq, OpenRouter, or OpenAI can be reused by both features.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsSection(title: "Dictation") {
                Picker("Provider", selection: $dictationProvider) {
                    ForEach(DictationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isVerifyingDictation)

                Text(dictationProviderDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                dictationModelControls.disabled(isVerifyingDictation)

                Picker("Language", selection: $dictationLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isVerifyingDictation)

                if dictationProvider == .customOpenAICompatible {
                    TextField("Base URL", text: $dictationBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isVerifyingDictation)
                    Text("Use HTTPS for remote services. Plain HTTP is allowed only for localhost, 127.0.0.1, or ::1.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                credentialEditor(
                    credential: dictationProvider.credential,
                    key: $dictationKey,
                    result: dictationResult,
                    allowsEmptyKey: dictationAllowsEmptyKey,
                    saveOnly: dictationProvider == .elevenLabs,
                    isVerifying: isVerifyingDictation,
                    saveAction: saveAndVerifyDictation,
                    importAction: importDictationKey,
                    recoverAction: recoverPreviousDictationKey,
                    removeAction: removeDictationKey
                )
            }

            SettingsSection(title: "Cmd + E text actions") {
                Text("Optional. Copy and Read aloud stay local and work without a text provider. Provider actions show a preview before anything is applied.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Provider", selection: $textProvider) {
                    ForEach(TextActionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isVerifyingText)

                Text(textProviderDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                textModelControls.disabled(isVerifyingText)

                if textProvider == .customOpenAICompatible {
                    TextField("Base URL", text: $textBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isVerifyingText)
                    Text("The endpoint must provide OpenAI compatible /models and /chat/completions routes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                credentialEditor(
                    credential: textProvider.credential,
                    key: $textKey,
                    result: textResult,
                    allowsEmptyKey: textAllowsEmptyKey,
                    isVerifying: isVerifyingText,
                    saveAction: saveAndVerifyText,
                    importAction: importTextKey,
                    recoverAction: recoverPreviousTextKey,
                    removeAction: removeTextKey
                )
            }

            Label(
                "Paste a key to store it in macOS Keychain, or choose a .env file and keep the key there. Previous-build recovery never allows a password prompt. Audio and text go directly to the providers you choose. Vibe Read has no relay or cloud database.",
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            loadDraftsOnce()
        }
        .onChange(of: dictationProvider) { provider in
            guard didLoad else { return }
            dictationModel = savedDictationModel(for: provider)
            dictationBaseURL = settings.customDictationBaseURL
            dictationKey = ""
            dictationResult = nil
        }
        .onChange(of: textProvider) { provider in
            guard didLoad else { return }
            textModel = savedTextModel(for: provider)
            textBaseURL = settings.customTextBaseURL
            textKey = ""
            textResult = nil
        }
        .onChange(of: dictationDraftFingerprint) { _ in
            if suppressNextDictationDraftReset {
                suppressNextDictationDraftReset = false
            } else if didLoad {
                dictationResult = nil
            }
        }
        .onChange(of: textDraftFingerprint) { _ in
            if suppressNextTextDraftReset {
                suppressNextTextDraftReset = false
            } else if didLoad {
                textResult = nil
            }
        }
        .onDisappear {
            dictationVerificationTask?.cancel()
            textVerificationTask?.cancel()
            dictationVerificationTask = nil
            textVerificationTask = nil
            dictationVerificationID = UUID()
            textVerificationID = UUID()
            isVerifyingDictation = false
            isVerifyingText = false
            dictationKey = ""
            textKey = ""
        }
    }

    @ViewBuilder
    private var dictationModelControls: some View {
        let options = dictationProvider.modelOptions
        if dictationProvider == .elevenLabs {
            LabeledContent("Model", value: "Scribe v2")
            Text("Scribe v2 is the supported ElevenLabs file transcription model.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if options.isEmpty {
            TextField("Transcription model ID", text: $dictationModel)
                .textFieldStyle(.roundedBorder)
        } else {
            Picker("Model", selection: modelPickerBinding(options: options, value: $dictationModel)) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option.modelID)
                }
                Divider()
                Text("Custom model ID").tag(customModelTag)
            }
            .pickerStyle(.menu)
            if !options.contains(where: { $0.modelID == dictationModel }) {
                TextField("Custom transcription model ID", text: $dictationModel)
                    .textFieldStyle(.roundedBorder)
            } else if let option = options.first(where: { $0.modelID == dictationModel }) {
                Text(option.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var textModelControls: some View {
        let options = textProvider.modelOptions
        if options.isEmpty {
            TextField("Text model ID", text: $textModel)
                .textFieldStyle(.roundedBorder)
        } else {
            Picker("Model", selection: modelPickerBinding(options: options, value: $textModel)) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option.modelID)
                }
                Divider()
                Text("Custom model ID").tag(customModelTag)
            }
            .pickerStyle(.menu)
            if !options.contains(where: { $0.modelID == textModel }) {
                TextField("Custom text model ID", text: $textModel)
                    .textFieldStyle(.roundedBorder)
            } else if let option = options.first(where: { $0.modelID == textModel }) {
                Text(option.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func credentialEditor(
        credential: ProviderCredential,
        key: Binding<String>,
        result: ProviderSaveResult?,
        allowsEmptyKey: Bool,
        saveOnly: Bool = false,
        isVerifying: Bool,
        saveAction: @escaping () -> Void,
        importAction: @escaping () -> Void,
        recoverAction: @escaping () -> Void,
        removeAction: @escaping () -> Void
    ) -> some View {
        ProviderCredentialStatusLabel(
            result: result,
            status: settings.credentialStatus(for: credential),
            allowsEmptyKey: allowsEmptyKey,
            environmentFileName: settings.environmentFileDisplayName(for: credential)
        )

        SecureField(
            settings.credentialStatus(for: credential).isConfigured
                ? "Key saved. Enter a new key to replace it"
                : (allowsEmptyKey ? "API key optional for this local endpoint" : "API key"),
            text: key
        )
        .textFieldStyle(.roundedBorder)
        .disabled(isVerifying)

        HStack(spacing: 10) {
            let hasEnteredKey = !key.wrappedValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            let hasStoredKey = settings.credentialStatus(for: credential)
                .hasStoredCredential
            let buttonTitle = saveOnly
                ? (hasStoredKey && !hasEnteredKey ? "Key Saved" : "Save Key")
                : (hasEnteredKey
                    ? "Save & Verify"
                    : (hasStoredKey ? "Verify Saved Key" : "Verify Connection"))
            Button(buttonTitle, action: saveAction)
                .disabled(
                    isVerifying
                        || (saveOnly && !hasEnteredKey)
                        || (!saveOnly && !hasEnteredKey && !hasStoredKey && !allowsEmptyKey)
                )
            if isVerifying {
                ProgressView().controlSize(.small)
            }
            Menu("Use Existing Key") {
                Button("Use .env File", action: importAction)
                Button("Recover from Previous Vibe Read", action: recoverAction)
            }
            .disabled(isVerifying)
            if let keyURL = apiKeyURL(for: credential) {
                Link("Get API key", destination: keyURL)
                    .font(.caption)
            }
            Spacer()
            if settings.credentialStatus(for: credential).hasStoredCredential {
                Button("Remove Key", role: .destructive, action: removeAction)
                    .disabled(isVerifying)
            }
        }

        Text(
            saveOnly
                ? "Paste a key, use a local .env file, or recover the previous build. Setup does not contact ElevenLabs. Your first dictation sends audio directly to Scribe v2 and is the end-to-end test."
                : "Opening Settings never reads Keychain. Save & Verify checks only this provider and does not upload audio or selected text. It also checks the selected model when the provider exposes an applicable model list. The selected model is exercised only when you use the feature."
        )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var customModelTag: String { "__viberead_custom_model__" }

    private func modelPickerBinding(
        options: [ProviderModelOption],
        value: Binding<String>
    ) -> Binding<String> {
        Binding(
            get: {
                options.contains(where: { $0.modelID == value.wrappedValue })
                    ? value.wrappedValue
                    : customModelTag
            },
            set: { selection in
                value.wrappedValue = selection == customModelTag ? "" : selection
            }
        )
    }

    private var dictationProviderDescription: String {
        switch dictationProvider {
        case .elevenLabs:
            return "The Vibe Read setup tested most heavily. Scribe v2 supports multilingual dictation."
        case .groq:
            return "Choose Whisper Turbo for speed and cost, or Whisper Large V3 for lower word error rate."
        case .openRouter:
            return "One OpenRouter key can power dictation and optional Cmd + E actions."
        case .openAI:
            return "Use OpenAI transcription directly with your OpenAI API key."
        case .customOpenAICompatible:
            return "Connect an OpenAI compatible transcription service, including a loopback service on this Mac."
        }
    }

    private var textProviderDescription: String {
        switch textProvider {
        case .openRouter:
            return "A useful one-key option with a broad model catalog."
        case .groq:
            return "Fast text actions using Groq hosted models."
        case .openAI:
            return "Text actions sent directly to the OpenAI API."
        case .customOpenAICompatible:
            return "Use a separate compatible endpoint for Cmd + E."
        }
    }

    private var dictationAllowsEmptyKey: Bool {
        guard dictationProvider == .customOpenAICompatible,
              let url = AIProviderSettings.validatedProviderURL(dictationBaseURL) else {
            return false
        }
        return url.isLoopbackProvider
    }

    private var textAllowsEmptyKey: Bool {
        guard textProvider == .customOpenAICompatible,
              let url = AIProviderSettings.validatedProviderURL(textBaseURL) else {
            return false
        }
        return url.isLoopbackProvider
    }

    private var dictationDraftFingerprint: DictationDraftFingerprint {
        DictationDraftFingerprint(
            provider: dictationProvider,
            model: dictationModel,
            language: dictationLanguage,
            baseURL: dictationBaseURL,
            key: dictationKey
        )
    }

    private var textDraftFingerprint: TextDraftFingerprint {
        TextDraftFingerprint(
            provider: textProvider,
            model: textModel,
            baseURL: textBaseURL,
            key: textKey
        )
    }

    private func loadDraftsOnce() {
        guard !didLoad else { return }
        dictationProvider = settings.dictationProvider
        dictationModel = settings.selectedDictationModel
        dictationLanguage = settings.dictationLanguage
        dictationBaseURL = settings.customDictationBaseURL
        textProvider = settings.textActionProvider
        textModel = settings.selectedTextActionModel
        textBaseURL = settings.customTextBaseURL
        didLoad = true
    }

    private func savedDictationModel(for provider: DictationProvider) -> String {
        switch provider {
        case .elevenLabs: return AIProviderCatalog.elevenLabsSpeechModel
        case .groq: return settings.groqDictationModel
        case .openRouter: return settings.openRouterDictationModel
        case .openAI: return settings.openAIDictationModel
        case .customOpenAICompatible: return settings.customDictationModel
        }
    }

    private func savedTextModel(for provider: TextActionProvider) -> String {
        switch provider {
        case .openRouter: return settings.openRouterTextModel
        case .groq: return settings.groqTextModel
        case .openAI: return settings.openAITextModel
        case .customOpenAICompatible: return settings.customTextModel
        }
    }

    private func saveAndVerifyDictation() {
        dictationVerificationTask?.cancel()
        let verificationID = UUID()
        dictationVerificationID = verificationID
        dictationResult = nil
        let submittedFingerprint = dictationDraftFingerprint
        let selectedProvider = dictationProvider
        let selectedModel = dictationModel
        let selectedLanguage = dictationLanguage
        let selectedBaseURL = dictationBaseURL
        let enteredKey = dictationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = selectedProvider.credential
        if selectedProvider == .elevenLabs {
            guard !enteredKey.isEmpty else {
                dictationResult = .failure("Enter your ElevenLabs API key")
                return
            }
            do {
                try settings.saveAPIKey(enteredKey, for: credential)
                settings.dictationProvider = selectedProvider
                settings.dictationLanguage = selectedLanguage
                suppressNextDictationDraftReset = true
                dictationKey = ""
                dictationResult = .success(
                    "API key saved. No request was sent. Your first dictation tests Scribe v2."
                )
            } catch {
                dictationResult = .failure(error.localizedDescription)
            }
            return
        }
        let configuration: DictationProviderConfiguration
        do {
            configuration = try settings.dictationConfiguration(
                provider: selectedProvider,
                model: selectedModel,
                language: selectedLanguage,
                customBaseURL: selectedBaseURL,
                replacementAPIKey: enteredKey.isEmpty ? nil : enteredKey
            )
        } catch {
            dictationResult = .failure(error.localizedDescription)
            return
        }

        isVerifyingDictation = true
        dictationVerificationTask = Task {
            do {
                let verification = try await APIService.shared.testDictationConnection(
                    configuration: configuration
                )
                await MainActor.run {
                    guard !Task.isCancelled,
                          verificationID == dictationVerificationID else { return }
                    guard submittedFingerprint == dictationDraftFingerprint else {
                        dictationResult = .failure(
                            "The draft changed during verification. Verify the current settings again."
                        )
                        isVerifyingDictation = false
                        dictationVerificationTask = nil
                        return
                    }
                    do {
                        if !enteredKey.isEmpty {
                            try settings.saveAPIKey(enteredKey, for: credential)
                            suppressNextDictationDraftReset = true
                            dictationKey = ""
                        }
                        settings.dictationProvider = selectedProvider
                        settings.dictationLanguage = selectedLanguage
                        settings.selectedDictationModel = selectedModel
                        settings.customDictationBaseURL = selectedBaseURL
                        dictationResult = .success(verification.message)
                    } catch {
                        dictationResult = .failure(
                            "The connection worked, but the settings could not be saved. \(error.localizedDescription)"
                        )
                    }
                    isVerifyingDictation = false
                    dictationVerificationTask = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled,
                          verificationID == dictationVerificationID,
                          submittedFingerprint == dictationDraftFingerprint else {
                        return
                    }
                    dictationResult = .failure(error.localizedDescription)
                    isVerifyingDictation = false
                    dictationVerificationTask = nil
                }
            }
        }
    }

    private func saveAndVerifyText() {
        textVerificationTask?.cancel()
        let verificationID = UUID()
        textVerificationID = verificationID
        textResult = nil
        let submittedFingerprint = textDraftFingerprint
        let selectedProvider = textProvider
        let selectedModel = textModel
        let selectedBaseURL = textBaseURL
        let enteredKey = textKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = selectedProvider.credential
        let configuration: TextActionProviderConfiguration
        do {
            configuration = try settings.textActionConfiguration(
                provider: selectedProvider,
                model: selectedModel,
                customBaseURL: selectedBaseURL,
                replacementAPIKey: enteredKey.isEmpty ? nil : enteredKey
            )
        } catch {
            textResult = .failure(error.localizedDescription)
            return
        }

        isVerifyingText = true
        textVerificationTask = Task {
            do {
                let verification = try await APIService.shared.testTextActionConnection(
                    configuration: configuration
                )
                await MainActor.run {
                    guard !Task.isCancelled,
                          verificationID == textVerificationID else { return }
                    guard submittedFingerprint == textDraftFingerprint else {
                        textResult = .failure(
                            "The draft changed during verification. Verify the current settings again."
                        )
                        isVerifyingText = false
                        textVerificationTask = nil
                        return
                    }
                    do {
                        if !enteredKey.isEmpty {
                            try settings.saveAPIKey(enteredKey, for: credential)
                            suppressNextTextDraftReset = true
                            textKey = ""
                        }
                        settings.textActionProvider = selectedProvider
                        settings.selectedTextActionModel = selectedModel
                        settings.customTextBaseURL = selectedBaseURL
                        textResult = .success(verification.message)
                    } catch {
                        textResult = .failure(
                            "The connection worked, but the settings could not be saved. \(error.localizedDescription)"
                        )
                    }
                    isVerifyingText = false
                    textVerificationTask = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled,
                          verificationID == textVerificationID,
                          submittedFingerprint == textDraftFingerprint else {
                        return
                    }
                    textResult = .failure(error.localizedDescription)
                    isVerifyingText = false
                    textVerificationTask = nil
                }
            }
        }
    }

    private func removeDictationKey() {
        do {
            try settings.clearAPIKey(for: dictationProvider.credential)
            if !dictationKey.isEmpty {
                suppressNextDictationDraftReset = true
            }
            dictationKey = ""
            dictationResult = .success("API key removed")
        } catch {
            dictationResult = .failure(error.localizedDescription)
        }
    }

    private func removeTextKey() {
        do {
            try settings.clearAPIKey(for: textProvider.credential)
            if !textKey.isEmpty {
                suppressNextTextDraftReset = true
            }
            textKey = ""
            textResult = .success("API key removed")
        } catch {
            textResult = .failure(error.localizedDescription)
        }
    }

    private func importDictationKey() {
        do {
            let credential = dictationProvider.credential
            guard let fileURL = chooseEnvironmentFile(for: credential) else { return }
            try settings.useEnvironmentFile(fileURL, for: credential)
            settings.dictationProvider = dictationProvider
            settings.dictationLanguage = dictationLanguage
            settings.selectedDictationModel = dictationModel
            settings.customDictationBaseURL = dictationBaseURL
            dictationKey = ""
            dictationResult = .success(
                "Using \(fileURL.lastPathComponent). You do not need a new key."
            )
        } catch {
            dictationResult = .failure(error.localizedDescription)
        }
    }

    private func importTextKey() {
        do {
            let credential = textProvider.credential
            guard let fileURL = chooseEnvironmentFile(for: credential) else { return }
            try settings.useEnvironmentFile(fileURL, for: credential)
            settings.textActionProvider = textProvider
            settings.selectedTextActionModel = textModel
            settings.customTextBaseURL = textBaseURL
            textKey = ""
            textResult = .success(
                "Using \(fileURL.lastPathComponent). You do not need a new key."
            )
        } catch {
            textResult = .failure(error.localizedDescription)
        }
    }

    private func recoverPreviousDictationKey() {
        do {
            try settings.recoverPreviousAPIKey(for: dictationProvider.credential)
            settings.dictationProvider = dictationProvider
            dictationResult = .success("Recovered your existing key from the previous build.")
        } catch {
            dictationResult = .failure(previousKeyRecoveryMessage(for: error))
        }
    }

    private func recoverPreviousTextKey() {
        do {
            try settings.recoverPreviousAPIKey(for: textProvider.credential)
            settings.textActionProvider = textProvider
            textResult = .success("Recovered your existing key from the previous build.")
        } catch {
            textResult = .failure(previousKeyRecoveryMessage(for: error))
        }
    }

    private func chooseEnvironmentFile(for credential: ProviderCredential) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Local .env File"
        panel.message = "Vibe Read reads only \(credential.environmentVariableName) from the file you choose."
        panel.prompt = "Use This File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func previousKeyRecoveryMessage(for error: Error) -> String {
        "The previous build did not provide this key without a password prompt. No prompt was shown. Use your existing .env file or paste the key instead. \(error.localizedDescription)"
    }

    private func apiKeyURL(for credential: ProviderCredential) -> URL? {
        switch credential {
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .openRouter:
            return URL(string: "https://openrouter.ai/settings/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .customDictation, .customText:
            return nil
        }
    }
}
