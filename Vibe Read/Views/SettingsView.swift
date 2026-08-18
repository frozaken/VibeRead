import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .general

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case provider = "AI Provider"
        case shortcuts = "Shortcuts"
        case storage = "Local Data"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gear"
            case .provider: return "key"
            case .shortcuts: return "keyboard"
            case .storage: return "internaldrive"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Settings")
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(tab.rawValue).font(.title2.bold())
                    Spacer()
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)

                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .general: LocalGeneralSettings()
                        case .provider: AIProviderSettingsView()
                        case .shortcuts: LocalShortcutSettings()
                        case .storage: LocalDataSettingsView()
                        case .about: LocalAboutSettings()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 820, height: 620)
    }
}

private struct LocalGeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    private let voices = InstantTTSService.availableVoices

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Dictation") {
                Toggle("Paste after dictation", isOn: $settings.autoPasteAfterDictation)
                Toggle("Sound effects", isOn: $settings.dictationSoundEffectsEnabled)
            }

            SettingsSection(title: "Local read-aloud") {
                Picker("macOS voice", selection: $settings.preferredVoiceId) {
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) — \(voice.language)").tag(voice.identifier)
                    }
                }
                HStack {
                    Text("Speed")
                    Slider(value: $settings.voiceSpeed, in: 0.6...1.8, step: 0.05)
                    Text(String(format: "%.2fx", settings.voiceSpeed)).monospacedDigit()
                }
                Button("Preview voice") {
                    InstantTTSService.shared.previewVoice(voiceId: settings.preferredVoiceId)
                }
            }

            SettingsSection(title: "Appearance") {
                Picker("Theme", selection: $settings.themeMode) {
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear {
            if !voices.contains(where: { $0.identifier == settings.preferredVoiceId }),
               let defaultVoice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
                    ?? voices.first {
                settings.preferredVoiceId = defaultVoice.identifier
            }
        }
    }
}

private struct AIProviderSettingsView: View {
    @ObservedObject private var provider = AIProviderSettings.shared
    @State private var apiKey = ""
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "OpenAI-compatible endpoint") {
                TextField("Base URL", text: $provider.baseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Examples: https://api.groq.com/openai/v1 or http://127.0.0.1:11434/v1")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SecureField(provider.hasAPIKey ? "API key saved — enter to replace" : "API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Key") {
                        do {
                            try provider.saveAPIKey(apiKey)
                            apiKey = ""
                            status = "Saved in macOS Keychain"
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if provider.hasAPIKey {
                        Button("Remove Key", role: .destructive) {
                            do {
                                try provider.clearAPIKey()
                                status = "API key removed"
                            } catch {
                                status = error.localizedDescription
                            }
                        }
                    }
                }
            }

            SettingsSection(title: "Models") {
                TextField("Transcription model", text: $provider.transcriptionModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Text action model", text: $provider.textModel)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(testing)
                if testing { ProgressView().controlSize(.small) }
                if let status { Text(status).font(.caption).foregroundColor(.secondary) }
            }

            Label(
                "Dictation audio and action text are sent directly to this endpoint. Vibe Read has no relay, account, analytics, or cloud database.",
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func testConnection() {
        testing = true
        status = nil
        Task {
            do {
                try await APIService.shared.testProviderConnection()
                await MainActor.run { status = "Connection succeeded"; testing = false }
            } catch {
                await MainActor.run { status = error.localizedDescription; testing = false }
            }
        }
    }
}

private struct LocalShortcutSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var editingAction: ShortcutAction?
    @State private var editingShortcutID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("All shortcuts are stored locally. Cmd+E is an ordinary action and can be rebound here.")
                .foregroundColor(.secondary)

            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.displayName).font(.headline)
                        Text(action.description).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(settings.primaryShortcut(for: action)?.displayString ?? "Not set")
                        .font(.system(.body, design: .monospaced))
                    Button("Change") {
                        editingAction = action
                        editingShortcutID = settings.primaryShortcut(for: action)?.id
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button("Reset Shortcuts") { settings.resetShortcutsToDefault() }
        }
        .sheet(item: $editingAction) { action in
            ShortcutEditorSheet(action: action, existingShortcutId: editingShortcutID)
                .environmentObject(settings)
                .dismissableSheet()
        }
    }
}

private struct LocalDataSettingsView: View {
    @ObservedObject private var store = DictationStore.shared
    @State private var confirmingClearHistory = false
    @State private var confirmingClearAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Audio retention") {
                Picker("Delete recordings", selection: Binding(
                    get: { store.audioRetention },
                    set: { store.audioRetention = $0 }
                )) {
                    ForEach(DictationStore.AudioRetention.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text("Transcripts stay until you delete them. Audio is removed after seven days by default; failed recordings remain retryable for up to seven days.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsSection(title: "Storage") {
                Button("Open Dictations Folder") {
                    if let url = DictationStore.dictationsDirectory { NSWorkspace.shared.open(url) }
                }
                Button("Delete All Audio…", role: .destructive) { confirmingClearAudio = true }
                Button("Delete All History and Audio…", role: .destructive) { confirmingClearHistory = true }
            }

            Label("History is stored in Application Support/VibeRead/dictations.sqlite3. Nothing is synced.", systemImage: "internaldrive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .confirmationDialog("Delete all retained audio?", isPresented: $confirmingClearAudio) {
            Button("Delete Audio", role: .destructive) { store.deleteAllAudio() }
        }
        .confirmationDialog("Delete all dictation history and audio?", isPresented: $confirmingClearHistory) {
            Button("Delete Everything", role: .destructive) { store.clearAll() }
        }
    }
}

private struct LocalAboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable().frame(width: 64, height: 64)
            Text("Vibe Read").font(.title.bold())
            Text("Version \(version)").foregroundColor(.secondary)
            Text("A small, local-first macOS app for dictation, read-aloud, and rebindable text actions. No accounts, subscriptions, analytics, or Vibe Read cloud.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Open-source builds are updated by pulling the repository and rebuilding locally.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
