import SwiftUI
import AppKit

private enum LocalAppTab: String, CaseIterable, Identifiable {
    case dictation = "Dictate"
    case read = "Read"
    case library = "Library"
    case actions = "Actions"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dictation: return "mic.fill"
        case .read: return "speaker.wave.2.fill"
        case .library: return "bookmark.fill"
        case .actions: return "wand.and.stars"
        }
    }
}

struct MainView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @State private var selection: LocalAppTab = .dictation
    @State private var isSidebarCollapsed = false
    @State private var showConfetti = false
    @State private var showingSettings = false
    @State private var settingsStartsOnProvider = false
    @State private var checkedProviderSetup = false

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                LocalSidebarView(
                    isCollapsed: $isSidebarCollapsed,
                    selection: $selection,
                    showConfetti: $showConfetti,
                    onOpenSettings: openSettings
                )
                .frame(
                    width: isSidebarCollapsed ? 60 : AppTheme.Dimensions.sidebarWidth,
                    alignment: .leading
                )
                .clipped()

                ZStack(alignment: .bottom) {
                    AppTheme.Colors.contentBackground
                        .clipShape(RoundedRectangle(
                            cornerRadius: AppTheme.Dimensions.contentCornerRadius,
                            style: .continuous
                        ))
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: AppTheme.Dimensions.contentCornerRadius,
                                style: .continuous
                            )
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)

                    contentViews
                        .clipShape(RoundedRectangle(
                            cornerRadius: AppTheme.Dimensions.contentCornerRadius,
                            style: .continuous
                        ))

                    if tts.isLoading || tts.isSpeaking || tts.isPaused {
                        InstantPlayerView()
                            .padding(20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.trailing, AppTheme.Dimensions.contentPadding)
            }
            .padding(.top, AppTheme.Dimensions.titlebarHeight)
            .padding(.bottom, AppTheme.Dimensions.contentPadding)

            ConfettiView(isActive: $showConfetti)

            TitlebarSidebarToggle(isCollapsed: $isSidebarCollapsed)
                .padding(.leading, 78)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(AppTheme.Colors.brandAccent)
        .background(AppTheme.Colors.sidebarBackground)
        .ignoresSafeArea(.container, edges: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSidebarCollapsed)
        .sheet(isPresented: $showingSettings) {
            SettingsView(startsOnProvider: settingsStartsOnProvider)
                .dismissableSheet()
        }
        .onAppear {
            guard !checkedProviderSetup else { return }
            checkedProviderSetup = true
            if AIProviderSettings.shared.needsDictationSetup {
                settingsStartsOnProvider = true
                showingSettings = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showProviderSettings)) { _ in
            settingsStartsOnProvider = true
            showingSettings = true
        }
    }

    private func openSettings() {
        settingsStartsOnProvider = false
        showingSettings = true
    }

    private var contentViews: some View {
        ZStack {
            DictationView()
                .opacity(selection == .dictation ? 1 : 0)
                .allowsHitTesting(selection == .dictation)
                .accessibilityHidden(selection != .dictation)

            LocalReadView()
                .opacity(selection == .read ? 1 : 0)
                .allowsHitTesting(selection == .read)
                .accessibilityHidden(selection != .read)

            LocalLibraryView()
                .opacity(selection == .library ? 1 : 0)
                .allowsHitTesting(selection == .library)
                .accessibilityHidden(selection != .library)

            LocalActionsView()
                .opacity(selection == .actions ? 1 : 0)
                .allowsHitTesting(selection == .actions)
                .accessibilityHidden(selection != .actions)
        }
    }
}

private struct LocalSidebarView: View {
    @Binding var isCollapsed: Bool
    @Binding var selection: LocalAppTab
    @Binding var showConfetti: Bool
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoPressed = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isCollapsed {
                    logoButton
                } else {
                    HStack(spacing: 10) {
                        logoButton

                        Text("Vibe Read")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: .leading)))

                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 16)
            .padding(.bottom, 18)

            VStack(spacing: 4) {
                ForEach(LocalAppTab.allCases) { tab in
                    LocalSidebarButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selection == tab,
                        isCollapsed: isCollapsed
                    ) {
                        selection = tab
                    }
                }
            }
            .padding(.horizontal, isCollapsed ? 12 : 10)

            Spacer()

            LocalSidebarButton(
                title: "Settings",
                icon: "gearshape",
                isSelected: false,
                isCollapsed: isCollapsed,
                action: onOpenSettings
            )
            .padding(.horizontal, isCollapsed ? 12 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.sidebarBackground)
    }

    private var logoButton: some View {
        Button(action: celebrate) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .scaleEffect(logoPressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .help("Celebrate")
        .accessibilityLabel("Vibe Read logo")
        .accessibilityHint("Celebrate with confetti")
    }

    private func celebrate() {
        showConfetti = false
        if !reduceMotion {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                logoPressed = true
            }
        }
        DispatchQueue.main.async {
            showConfetti = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                logoPressed = false
            }
        }
    }
}

private struct TitlebarSidebarToggle: View {
    @Binding var isCollapsed: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
        .accessibilityLabel(isCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
    }
}

private struct LocalSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)

                if !isCollapsed {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(buttonBackground)
                    .shadow(
                        color: isSelected ? .black.opacity(0.07) : .clear,
                        radius: 1,
                        y: 1
                    )
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.sidebarTextSelected : AppTheme.Colors.sidebarText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCollapsed ? title : "")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var buttonBackground: Color {
        if isSelected { return AppTheme.Colors.sidebarSelection }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
    }
}

struct LocalReadView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @EnvironmentObject private var settings: AppSettings
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Read aloud").font(.largeTitle.bold())
                Text(readAloudDescription)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $text)
                .font(.body)
                .padding(14)
                .background(AppTheme.Colors.secondaryContentBackground.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }

            HStack {
                Button("Paste from Clipboard") {
                    text = NSPasteboard.general.string(forType: .string) ?? ""
                }
                Button("Save to Library") {
                    _ = LocalLibraryStore.shared.saveText(text)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if tts.isSpeaking || tts.isPaused {
                    Button("Stop", role: .destructive) { tts.stop() }
                }
                Button("Read") { tts.speak(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = tts.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, AppTheme.Dimensions.pageInset)
        .padding(.top, AppTheme.Dimensions.pageTopInset)
        .padding(.bottom, AppTheme.Dimensions.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readAloudDescription: String {
        settings.readAloudProvider == .elevenLabs
            ? "Reads with your ElevenLabs voice. Text goes directly to ElevenLabs when you press Read."
            : "Reads with a voice built into macOS. Text stays on this Mac."
    }
}

struct LocalActionsView: View {
    @ObservedObject private var store = LocalTextActionStore.shared
    @EnvironmentObject private var settings: AppSettings
    @State private var editorDraft: LocalActionEditorDraft?
    @State private var pendingConfirmation: LocalActionsConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cmd+E actions").font(.largeTitle.bold())
                    Text("Edit the prompts shown over selected text. They use only your configured provider.")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    editorDraft = LocalActionEditorDraft()
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                    .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-in actions").font(.headline)
                Text("Choose the useful actions that always appear before your custom prompts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    ForEach(BuiltInPaletteAction.allCases) { action in
                        Toggle(isOn: Binding(
                            get: { store.isEnabled(action) },
                            set: { store.setEnabled($0, for: action) }
                        )) {
                            Label(action.name, systemImage: action.icon)
                        }
                        .toggleStyle(.button)
                    }
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Custom actions")
                        .font(.headline)
                    Text("\(store.actions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.bottom, 8)

                if store.actions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(.secondary)
                        Text("No custom actions")
                            .font(.headline)
                        Text("Add a prompt for rewriting, drafting, translating, or anything else you do often.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 390)
                        Button("Add Your First Action") {
                            editorDraft = LocalActionEditorDraft()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.actions) { action in
                                actionRow(action)
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Text("Shortcut: \(paletteShortcut)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    pendingConfirmation = .reset
                }
            }
        }
        .padding(.horizontal, AppTheme.Dimensions.pageInset)
        .padding(.top, AppTheme.Dimensions.pageTopInset)
        .padding(.bottom, AppTheme.Dimensions.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editorDraft) { draft in
            LocalActionEditorSheet(store: store, draft: draft)
        }
        .alert(confirmationTitle, isPresented: confirmationIsPresented) {
            Button(confirmationButtonTitle, role: .destructive) {
                performPendingConfirmation()
            }
            Button("Cancel", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var paletteShortcut: String {
        settings.primaryShortcut(for: .openActionPalette)?.displayString ?? "Not set"
    }

    private func actionRow(_ action: LocalTextAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(action.prompt)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                editorDraft = LocalActionEditorDraft(action: action)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Edit \(action.name)")
            .accessibilityLabel("Edit \(action.name)")

            Button(role: .destructive) {
                pendingConfirmation = .delete(action)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Delete \(action.name)")
            .accessibilityLabel("Delete \(action.name)")
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented { pendingConfirmation = nil }
            }
        )
    }

    private var confirmationTitle: String {
        switch pendingConfirmation {
        case .delete: return "Delete this action?"
        case .reset: return "Restore the default actions?"
        case nil: return "Confirm"
        }
    }

    private var confirmationMessage: String {
        switch pendingConfirmation {
        case let .delete(action):
            return "\"\(action.name)\" will be removed from the Cmd+E palette."
        case .reset:
            return "Your custom prompts and built-in action choices will be replaced with the defaults."
        case nil:
            return ""
        }
    }

    private var confirmationButtonTitle: String {
        switch pendingConfirmation {
        case .delete: return "Delete"
        case .reset: return "Restore"
        case nil: return "Continue"
        }
    }

    private func performPendingConfirmation() {
        switch pendingConfirmation {
        case let .delete(action): store.remove(id: action.id)
        case .reset: store.reset()
        case nil: break
        }
        pendingConfirmation = nil
    }
}

private enum LocalActionsConfirmation {
    case delete(LocalTextAction)
    case reset
}

private struct LocalActionEditorDraft: Identifiable {
    let id = UUID()
    let actionID: UUID?
    let name: String
    let prompt: String

    init(action: LocalTextAction? = nil) {
        actionID = action?.id
        name = action?.name ?? ""
        prompt = action?.prompt ?? ""
    }
}

private struct LocalActionEditorSheet: View {
    private enum Field: Hashable {
        case name
        case prompt
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LocalTextActionStore
    let draft: LocalActionEditorDraft

    @State private var name: String
    @State private var prompt: String
    @FocusState private var focusedField: Field?

    init(store: LocalTextActionStore, draft: LocalActionEditorDraft) {
        self.store = store
        self.draft = draft
        _name = State(initialValue: draft.name)
        _prompt = State(initialValue: draft.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(draft.actionID == nil ? "New action" : "Edit action")
                    .font(.title2.bold())
                Text("This prompt runs on selected text when you choose it from Cmd+E.")
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Name")
                    .font(.headline)
                TextField("For example, Draft an email", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Instructions")
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(AppTheme.Colors.secondaryContentBackground.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .focused($focusedField, equals: .prompt)
            }

            HStack(alignment: .center) {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(isDuplicate ? .red : .secondary)
                } else {
                    Text("Only the prompt and selected text are sent to your configured provider.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 390)
        .onAppear {
            focusedField = draft.actionID == nil ? .name : .prompt
        }
    }

    private var validationMessage: String? {
        store.validationMessage(
            name: name,
            prompt: prompt,
            excluding: draft.actionID
        )
    }

    private var isDuplicate: Bool {
        validationMessage == "An identical action already exists."
    }

    private func save() {
        guard store.save(
            id: draft.actionID,
            name: name,
            prompt: prompt
        ) else { return }
        dismiss()
    }
}

struct InstantPlayerView: View {
    @ObservedObject private var tts = InstantTTSService.shared

    var body: some View {
        HStack(spacing: 14) {
            if tts.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Generating voice")
            } else {
                Button(action: tts.toggle) {
                    Image(systemName: tts.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
            }

            Text(tts.isLoading ? "Generating voice" : (tts.currentText ?? "Reading"))
                .lineLimit(1)
                .font(.caption)
            Spacer()
            Button(action: tts.stop) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

#Preview {
    MainView().environmentObject(AppSettings.shared)
}
