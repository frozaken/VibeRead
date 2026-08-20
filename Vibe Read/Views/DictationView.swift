import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Dictation View

struct DictationView: View {
    @ObservedObject private var store = DictationStore.shared
    @State private var selectedSubTab: DictationSubTab = .history

    enum DictationSubTab: String, CaseIterable {
        case history = "History"
        case vocabulary = "Vocabulary"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stats Header
            DictationStatsHeader(items: store.items)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background {
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.creamSurface.opacity(0.72),
                            AppTheme.Colors.creamSurface.opacity(0.24),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(AppTheme.Colors.border),
                    alignment: .bottom
                )

            // Sub-tab picker (optional, maybe keep it cleaner like Flow?)
            // Flow puts Dictionary (Vocabulary) on the sidebar or separate.
            // But user said "Dictation... is where you have dictionary".
            // Let's keep the picker but make it look nicer.

            HStack {
                Picker("", selection: $selectedSubTab) {
                    ForEach(DictationSubTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()
            }
            .padding()

            // Content
            switch selectedSubTab {
            case .history:
                DictationHistoryView()
            case .vocabulary:
                VocabularyView()
            }
        }
        .background(AppTheme.Colors.contentBackground)
    }
}

// MARK: - Stats Header

struct DictationStatsHeader: View {
    let items: [DictationHistoryItem]

    var totalWords: Int {
        items.reduce(0) { $0 + ($1.polishedText.split(separator: " ").count) }
    }

    var totalDurationSeconds: Double {
        let ms = items.reduce(0) { $0 + ($1.durationMs ?? 0) }
        return Double(ms) / 1000.0
    }

    var wpm: Int {
        let minutes = totalDurationSeconds / 60.0
        guard minutes > 0 else { return 0 }
        return Int(Double(totalWords) / minutes)
    }

    var body: some View {
        HStack(spacing: 44) {
            StatItem(value: "\(wpm)", label: "WPM", icon: "speedometer", color: AppTheme.Colors.brandAccent)
            StatItem(value: "\(totalWords)", label: "Words", icon: "text.alignleft", color: AppTheme.Colors.brandAccent)
            StatItem(value: formatDuration(totalDurationSeconds), label: "Time", icon: "clock", color: AppTheme.Colors.brandAccent)
            Spacer()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.13))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - History View

struct DictationHistoryView: View {
    @ObservedObject private var store = DictationStore.shared
    @State private var hoveredItemId: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Group by date
                ForEach(store.groupedByDate) { group in
                    // Date header
                    HStack {
                        Text(formatDateHeader(group.date))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                    // Items for this date in a card
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            DictationHistoryRow(
                                item: item,
                                isHovered: hoveredItemId == item.id
                            )
                            .onHover { hovering in
                                hoveredItemId = hovering ? item.id : nil
                            }

                            if index < group.items.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .background(AppTheme.Colors.secondaryContentBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }

                // Load more trigger
                if store.hasMore && !store.items.isEmpty {
                    DictationLoadMoreView {
                        store.loadMore()
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .overlay {
            if store.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor.opacity(0.2))
                    Text("No dictations yet")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text("Press fn to start dictating")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

/// Simple load more view for dictation history
struct DictationLoadMoreView: View {
    let onLoadMore: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onLoadMore) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text("Load more")
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 16)
        .onAppear {
            // Auto-trigger when scrolled into view
            onLoadMore()
        }
    }
}

// MARK: - History Row

struct DictationHistoryRow: View {
    let item: DictationHistoryItem
    let isHovered: Bool
    @ObservedObject private var store = DictationStore.shared
    @State private var showCopiedFeedback = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: "text.bubble")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.05))
                .clipShape(Circle())

            // Content - full text, no truncation
            VStack(alignment: .leading, spacing: 4) {
                if item.polishedText.isEmpty {
                    Text(item.audioFileURL == nil
                         ? "Transcription unavailable"
                         : "Transcription failed. Recording kept for retry")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } else {
                    Text(item.polishedText)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }

                Text(formatRelativeTime(item.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if let error = store.retryErrors[item.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            // Fixed-width action buttons column (always reserves space)
            HStack(spacing: 8) {
                if item.polishedText.isEmpty, item.audioFileURL != nil {
                    if store.retryingIDs.contains(item.id) {
                        Button(action: cancelRetry) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel retry")
                    } else {
                        Button(action: retryTranscription) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Retry transcription")
                    }
                }

                Button(action: copyToClipboard) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(showCopiedFeedback ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy")
                .disabled(item.polishedText.isEmpty)

                // Folder menu
                Menu {
                    if item.rawTranscript != item.polishedText,
                       !item.rawTranscript.isEmpty {
                        Button(action: copyOriginalTranscript) {
                            Label("Copy Provider Transcript", systemImage: "doc.on.doc")
                        }
                        Divider()
                    }
                    if item.audioFileURL != nil {
                        Button(action: showInFinder) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                    Button(action: openDictationsFolder) {
                        Label("Open Dictations Folder", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Storage location")

                Button(action: deleteItem) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .frame(width: item.polishedText.isEmpty && item.audioFileURL != nil ? 104 : 76)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isHovered ? Color.primary.opacity(0.02) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard()
        }
    }

    private func copyToClipboard() {
        guard !item.polishedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.polishedText, forType: .string)

        withAnimation {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    private func deleteItem() {
        DictationStore.shared.delete(item)
    }

    private func retryTranscription() {
        store.retryTranscription(item)
    }

    private func cancelRetry() {
        store.cancelRetry(item)
    }

    private func copyOriginalTranscript() {
        guard !item.rawTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.rawTranscript, forType: .string)
    }

    private func showInFinder() {
        guard let url = item.audioFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openDictationsFolder() {
        guard let dir = DictationStore.dictationsDirectory else { return }
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Vocabulary View
// (Reused from previous code, just minor styling updates if needed)
struct VocabularyView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a new word or phrase...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        addWord()
                    }

                Button(action: addWord) {
                    Text("Add")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            List {
                ForEach(settings.customVocabulary, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.body)
                        Spacer()
                        Button(action: { removeWord(word) }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteWords)
            }
            .listStyle(.plain)
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        guard !settings.customVocabulary.contains(word) else {
            newWord = ""
            return
        }
        settings.customVocabulary.append(word)
        newWord = ""
    }

    private func removeWord(_ word: String) {
        settings.customVocabulary.removeAll { $0 == word }
    }

    private func deleteWords(at offsets: IndexSet) {
        settings.customVocabulary.remove(atOffsets: offsets)
    }
}
