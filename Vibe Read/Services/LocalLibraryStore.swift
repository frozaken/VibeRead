import Foundation
import Combine

struct LocalLibraryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: LocalContentKind
    var title: String
    var sourceURL: URL?
    var text: String?
    var summary: String?
    var author: String?
    var thumbnailURL: URL?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: LocalContentKind,
        title: String,
        sourceURL: URL? = nil,
        text: String? = nil,
        summary: String? = nil,
        author: String? = nil,
        thumbnailURL: URL? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceURL = sourceURL
        self.text = text
        self.summary = summary
        self.author = author
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class LocalLibraryStore: ObservableObject {
    static let shared = LocalLibraryStore()

    @Published private(set) var items: [LocalLibraryItem] = []
    @Published private(set) var isWorking = false
    @Published var lastError: Error?

    private let fileURL: URL
    private let extractor: ContentExtractionService

    init(
        fileURL: URL? = nil,
        extractor: ContentExtractionService = ContentExtractionService()
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.extractor = extractor
        load()
    }

    static var defaultFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("VibeRead", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    @discardableResult
    func saveText(_ text: String, title: String? = nil) -> LocalLibraryItem? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let item = LocalLibraryItem(
            kind: .selection,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? Self.title(from: cleaned),
            text: cleaned
        )
        upsert(item)
        return item
    }

    @discardableResult
    func saveURL(_ url: URL) async throws -> LocalLibraryItem {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let extracted = try await extractor.extract(url)
            let item = LocalLibraryItem(
                kind: extracted.kind,
                title: extracted.title,
                sourceURL: extracted.sourceURL,
                text: extracted.text,
                author: extracted.author,
                thumbnailURL: extracted.thumbnailURL
            )
            upsert(item)
            return item
        } catch {
            // YouTube remains useful as a local bookmark even when captions
            // are private or unavailable.
            if ContentExtractionService.kind(for: url) == .youtube,
               let videoID = ContentExtractionService.youtubeVideoID(from: url),
               let canonical = URL(string: "https://www.youtube.com/watch?v=\(videoID)") {
                let bookmark = LocalLibraryItem(
                    kind: .youtube,
                    title: "YouTube video",
                    sourceURL: canonical
                )
                upsert(bookmark)
                lastError = error
                return bookmark
            }
            lastError = error
            throw error
        }
    }

    func update(_ item: LocalLibraryItem) {
        var changed = item
        changed.updatedAt = Date()
        upsert(changed)
    }

    func setSummary(_ summary: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].updatedAt = Date()
        sortAndPersist()
    }

    func remove(_ item: LocalLibraryItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    private func upsert(_ item: LocalLibraryItem) {
        if let sourceURL = item.sourceURL,
           let index = items.firstIndex(where: { $0.sourceURL == sourceURL }) {
            var merged = item
            merged = LocalLibraryItem(
                id: items[index].id,
                kind: item.kind,
                title: item.title,
                sourceURL: item.sourceURL,
                text: item.text ?? items[index].text,
                summary: items[index].summary,
                author: item.author ?? items[index].author,
                thumbnailURL: item.thumbnailURL ?? items[index].thumbnailURL,
                createdAt: items[index].createdAt,
                updatedAt: Date()
            )
            items[index] = merged
        } else if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        sortAndPersist()
    }

    private func sortAndPersist() {
        items.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LocalLibraryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private static func title(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(10).joined(separator: " ")
        return words + (firstLine.split(whereSeparator: \.isWhitespace).count > 10 ? "…" : "")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
