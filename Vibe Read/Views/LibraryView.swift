import SwiftUI
import AppKit

struct LocalLibraryView: View {
    @ObservedObject private var store = LocalLibraryStore.shared
    @ObservedObject private var tts = InstantTTSService.shared
    @State private var selection: UUID?
    @State private var search = ""
    @State private var showingAddLink = false
    @State private var isSummarizing = false
    @State private var actionError: Error?

    private var filteredItems: [LocalLibraryItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.text?.localizedCaseInsensitiveContains(query) == true
                || $0.author?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var selectedItem: LocalLibraryItem? {
        guard let selection else { return filteredItems.first }
        return store.items.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library").font(.largeTitle.bold())
                    Text("Text, pages, Wikipedia, and YouTube links saved on this Mac.")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showingAddLink = true
                } label: {
                    Label("Add Link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)

            Divider()

            if store.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.secondary)
                    Text("Nothing saved yet").font(.title2.bold())
                    Text("Select text or copy a link, press Cmd + E, then choose Save to Library.")
                        .foregroundColor(.secondary)
                    Button("Add a Link") { showingAddLink = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        TextField("Search Library", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .padding(12)
                        List(filteredItems, selection: $selection) { item in
                            LibraryRow(item: item).tag(item.id)
                        }
                        .listStyle(.inset)
                    }
                    .frame(minWidth: 230, idealWidth: 280, maxWidth: 340)

                    if let item = selectedItem {
                        libraryDetail(item)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.title)
                            Text("No Match").font(.headline)
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddLink) {
            AddLibraryLinkView { url in
                Task {
                    do {
                        let item = try await store.saveURL(url)
                        selection = item.id
                    } catch {
                        actionError = error
                    }
                }
            }
        }
        .alert("Vibe Read", isPresented: Binding(
            get: { actionError != nil || store.lastError != nil || tts.error != nil },
            set: { if !$0 { actionError = nil; store.lastError = nil; tts.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((actionError ?? store.lastError ?? tts.error)?.localizedDescription ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func libraryDetail(_ item: LocalLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(item.kind.displayName, systemImage: item.kind.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.title).font(.title2.bold()).textSelection(.enabled)
                    if let author = item.author {
                        Text(author).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Copy Text") { copy(item.text ?? item.summary ?? item.title) }
                    if let url = item.sourceURL {
                        Button("Open Original") { NSWorkspace.shared.open(url) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.remove(item)
                        selection = nil
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 10) {
                Button {
                    if let text = item.text ?? item.summary { tts.speak(text) }
                } label: {
                    Label("Read Aloud", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled((item.text ?? item.summary)?.isEmpty != false)

                Button {
                    summarize(item)
                } label: {
                    if isSummarizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Summarize", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isSummarizing || item.text?.isEmpty != false)

                if let url = item.sourceURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                }
            }

            if let summary = item.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary").font(.headline)
                    Text(summary).textSelection(.enabled)
                }
                .padding(14)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Divider()

            if let text = item.text, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.bottom, 30)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "link").font(.title)
                    Text("Saved as a link").font(.headline)
                    Text(item.kind == .youtube
                        ? "No public captions were available. The video link is still saved locally."
                        : "No readable page text was available.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summarize(_ item: LocalLibraryItem) {
        guard let text = item.text, !text.isEmpty else { return }
        isSummarizing = true
        actionError = nil
        Task {
            do {
                let summary = try await APIService.shared.transformText(
                    text,
                    systemPrompt: "Summarize this clearly and accurately. Preserve the important facts and names. Return only the summary."
                )
                store.setSummary(summary, for: item.id)
            } catch {
                actionError = error
            }
            isSummarizing = false
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct LibraryRow: View {
    let item: LocalLibraryItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.icon)
                .frame(width: 22)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).lineLimit(2).font(.headline)
                HStack(spacing: 5) {
                    Text(item.kind.displayName)
                    Text("·")
                    Text(item.updatedAt, style: .date)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AddLibraryLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    let onAdd: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add to Library").font(.title2.bold())
            Text("Paste an article, Wikipedia, or YouTube link. Vibe Read stores the result on this Mac.")
                .foregroundColor(.secondary)
            TextField("https://", text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            HStack {
                Button("Paste") {
                    value = NSPasteboard.general.string(forType: .string) ?? value
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") { add() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func add() {
        guard let url = ContentExtractionService.normalizedWebURL(from: value) else {
            error = ContentExtractionError.invalidURL.localizedDescription
            return
        }
        onAdd(url)
        dismiss()
    }
}
