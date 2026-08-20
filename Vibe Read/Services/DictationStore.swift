import Combine
import Foundation

// MARK: - Models

struct DictationHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let rawTranscript: String
    let polishedText: String
    let createdAt: Date
    var audioFilePath: String?
    var durationMs: Int?

    var audioFileURL: URL? {
        guard let audioFilePath,
              let url = DictationStore.audioURL(forRelativePath: audioFilePath),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func replacingID(with id: UUID) -> DictationHistoryItem {
        DictationHistoryItem(
            id: id,
            rawTranscript: rawTranscript,
            polishedText: polishedText,
            createdAt: createdAt,
            audioFilePath: audioFilePath,
            durationMs: durationMs
        )
    }
}

struct DictationDateGroup: Identifiable {
    var id: Date { date }
    let date: Date
    let items: [DictationHistoryItem]
}

// MARK: - Store

final class DictationStore: ObservableObject {
    enum AudioRetention: Int, CaseIterable, Codable, Identifiable {
        /// Remove a recording as soon as its history row is saved.
        case immediately = 0
        case oneDay = 1
        case sevenDays = 7
        case thirtyDays = 30
        case never = -1

        static let defaultValue: AudioRetention = .sevenDays

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneDay: return "After 1 day"
            case .sevenDays: return "After 7 days"
            case .thirtyDays: return "After 30 days"
            case .never: return "Never"
            }
        }

        fileprivate func cutoff(relativeTo now: Date) -> Date? {
            switch self {
            case .never:
                return nil
            case .immediately:
                return now
            case .oneDay, .sevenDays, .thirtyDays:
                return Calendar(identifier: .gregorian).date(
                    byAdding: .day,
                    value: -rawValue,
                    to: now
                )
            }
        }
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    static let shared: DictationStore = {
        guard isRunningTests else { return DictationStore() }

        let identifier = UUID().uuidString
        let suiteName = "VibeRead.XCTest.\(identifier)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated defaults for Vibe Read tests")
        }
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeRead-XCTest", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        return DictationStore(
            applicationSupportDirectory: testDirectory,
            defaults: testDefaults
        )
    }()
    static let pageSize = 20
    static let audioRetentionDefaultsKey = "dictationAudioRetentionDays"

    @Published private(set) var items: [DictationHistoryItem] = []
    @Published var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var retryingIDs: Set<UUID> = []
    @Published private(set) var retryErrors: [UUID: String] = [:]
    @Published var audioRetention: AudioRetention {
        didSet {
            defaults.set(audioRetention.rawValue, forKey: Self.audioRetentionDefaultsKey)
            cleanupExpiredAudio()
            refreshDisplayedItems()
        }
    }

    private static let legacyStorageKeyPrefix = "dictation_history_v1"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let audioDirectory: URL
    private var database: LocalDictationDatabase?
    private var displayLimit = DictationStore.pageSize
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var retryGenerations: [UUID: UUID] = [:]

    /// Kept as an instance accessor so existing views and recording code do not
    /// need to know about the database layout. There is no user scoping.
    var userDictationsDirectory: URL? { audioDirectory }

    /// The default initializer uses Application Support/VibeRead. Tests may
    /// provide a disposable Application Support directory and defaults suite.
    init(
        applicationSupportDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.now = now
        if defaults.object(forKey: Self.audioRetentionDefaultsKey) == nil {
            audioRetention = .defaultValue
        } else {
            audioRetention = AudioRetention(
                rawValue: defaults.integer(forKey: Self.audioRetentionDefaultsKey)
            ) ?? .defaultValue
        }

        let applicationSupport = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootDirectory = applicationSupport.appendingPathComponent("VibeRead", isDirectory: true)
        audioDirectory = rootDirectory.appendingPathComponent("Dictations", isDirectory: true)

        do {
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            let databaseURL = rootDirectory.appendingPathComponent("dictations.sqlite3")
            database = try LocalDictationDatabase(databaseURL: databaseURL)
            try migrateLegacyUserDefaults()
            cleanupExpiredAudio()
            loadHistory()
        } catch {
            record(error)
        }
    }

    // MARK: - Pagination and Grouping

    func loadHistory() {
        displayLimit = Self.pageSize
        refreshDisplayedItems()
    }

    func loadMore() {
        guard hasMore else { return }
        displayLimit += Self.pageSize
        refreshDisplayedItems()
    }

    var groupedByDate: [DictationDateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.createdAt)
        }
        return grouped
            .map {
                DictationDateGroup(
                    date: $0.key,
                    items: $0.value.sorted { $0.createdAt > $1.createdAt }
                )
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - CRUD

    func add(
        _ result: DictationResult,
        audioURL: URL?,
        durationMs: Int? = nil,
        clientId: UUID? = nil
    ) {
        addItem(
            rawTranscript: result.rawTranscript,
            polishedText: result.polishedText,
            audioURL: audioURL,
            durationMs: durationMs ?? result.durationMs,
            clientId: clientId,
            isSuccessful: true
        )
    }

    /// Saves a failed recording as a retryable history row when the selected
    /// audio-retention policy keeps the underlying file.
    func addFailed(
        audioURL: URL,
        durationMs: Int? = nil,
        clientId: UUID? = nil
    ) {
        addItem(
            rawTranscript: "",
            polishedText: "",
            audioURL: audioURL,
            durationMs: durationMs,
            clientId: clientId,
            isSuccessful: false
        )
    }

    func delete(_ item: DictationHistoryItem) {
        cancelRetry(item)
        performOnMain { [weak self] in
            guard let self, let database = self.database else { return }

            do {
                if let relativePath = item.audioFilePath,
                   let audioURL = self.audioURL(forRelativePath: relativePath),
                   self.fileManager.fileExists(atPath: audioURL.path) {
                    // Only remove the row after its audio was removed. A file
                    // permission error therefore cannot leave private orphaned
                    // audio behind while making the UI claim deletion worked.
                    try self.fileManager.removeItem(at: audioURL)
                }
                try database.delete(id: item.id)
                self.refreshDisplayedItems()
            } catch {
                self.record(error)
            }
        }
    }

    func clearAll() {
        cancelAllRetries()
        performOnMain { [weak self] in
            guard let self, let database = self.database else { return }

            // A late provider response must not recreate history after the user
            // explicitly deletes it. This also removes recordings that have not
            // reached the database yet.
            DictationService.shared.discardActiveWork()

            do {
                if self.fileManager.fileExists(atPath: self.audioDirectory.path) {
                    try self.fileManager.removeItem(at: self.audioDirectory)
                }
                try self.fileManager.createDirectory(
                    at: self.audioDirectory,
                    withIntermediateDirectories: true
                )
                try database.deleteAll()
                self.displayLimit = Self.pageSize
                self.refreshDisplayedItems()
            } catch {
                self.record(error)
            }
        }
    }

    /// Deletes every retained recording while keeping transcript history.
    func deleteAllAudio() {
        performOnMain { [weak self] in
            guard let self, let database = self.database else { return }

            do {
                if self.fileManager.fileExists(atPath: self.audioDirectory.path) {
                    try self.fileManager.removeItem(at: self.audioDirectory)
                }
                try self.fileManager.createDirectory(
                    at: self.audioDirectory,
                    withIntermediateDirectories: true
                )
                try database.clearAllAudioReferences()
                self.refreshDisplayedItems()
            } catch {
                self.record(error)
            }
        }
    }

    // MARK: - Retry

    func retryTranscription(_ item: DictationHistoryItem) {
        guard retryTasks[item.id] == nil else { return }
        guard let audioURL = item.audioFileURL else {
            retryErrors[item.id] = "The retained recording is no longer available"
            return
        }

        retryErrors[item.id] = nil
        retryingIDs.insert(item.id)
        isLoading = true
        let retryGeneration = UUID()
        retryGenerations[item.id] = retryGeneration
        retryTasks[item.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await APIService.shared.transcribeDictation(
                    audioURL: audioURL,
                    vocabulary: AppSettings.shared.customVocabulary,
                    // Legacy history does not record whether a dictation used
                    // Smart mode. A retry therefore stays direct STT rather
                    // than unexpectedly sending transcript text elsewhere.
                    transformPrompt: nil
                )
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.retryGenerations[item.id] == retryGeneration else { return }
                    do {
                        try self.database?.updateTranscription(
                            id: item.id,
                            rawTranscript: result.rawTranscript,
                            polishedText: result.polishedText,
                            durationMs: result.durationMs ?? item.durationMs
                        )
                        self.cleanupExpiredAudio()
                        self.refreshDisplayedItems()
                    } catch {
                        self.record(error)
                        self.retryErrors[item.id] = error.localizedDescription
                    }
                    self.finishRetry(item.id, generation: retryGeneration)
                }
            } catch {
                await MainActor.run {
                    guard self.retryGenerations[item.id] == retryGeneration else { return }
                    if !(error is CancellationError) {
                        self.retryErrors[item.id] = error.localizedDescription
                    }
                    self.finishRetry(item.id, generation: retryGeneration)
                }
            }
        }
    }

    func cancelRetry(_ item: DictationHistoryItem) {
        retryGenerations[item.id] = nil
        retryTasks[item.id]?.cancel()
        finishRetry(item.id)
    }

    func clearRetryError(for item: DictationHistoryItem) {
        retryErrors[item.id] = nil
    }

    private func finishRetry(_ id: UUID, generation: UUID? = nil) {
        if let generation, retryGenerations[id] != generation { return }
        retryGenerations[id] = nil
        retryTasks[id] = nil
        retryingIDs.remove(id)
        isLoading = !retryTasks.isEmpty
    }

    private func cancelAllRetries() {
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
        retryGenerations.removeAll()
        retryingIDs.removeAll()
        retryErrors.removeAll()
        isLoading = false
    }

    // MARK: - Audio Retention

    /// Removes expired recordings and clears only their file references. Text
    /// history is never expired automatically.
    func cleanupExpiredAudio() {
        guard let database else { return }

        do {
            let currentDate = now()
            let configuredCutoff = audioRetention.cutoff(relativeTo: currentDate)
            // `Never` applies only to recordings represented in history. A
            // crash between copying audio and committing its row can leave an
            // inaccessible orphan, so even that policy gives untracked files a
            // seven-day cleanup ceiling.
            let orphanCutoff = configuredCutoff
                ?? Calendar(identifier: .gregorian).date(
                    byAdding: .day,
                    value: -AudioRetention.sevenDays.rawValue,
                    to: currentDate
                )
            let references = try database.audioReferences()
            var clearedReferenceIDs: [UUID] = []
            var referencedPaths = Set<String>()

            for reference in references {
                referencedPaths.insert(reference.relativePath)
                guard let audioURL = audioURL(forRelativePath: reference.relativePath) else {
                    clearedReferenceIDs.append(reference.id)
                    continue
                }

                let isExpired = configuredCutoff.map { reference.createdAt <= $0 } ?? false
                let exists = fileManager.fileExists(atPath: audioURL.path)
                guard isExpired || !exists else { continue }

                if exists {
                    do {
                        try fileManager.removeItem(at: audioURL)
                    } catch {
                        record(error)
                        continue
                    }
                }
                clearedReferenceIDs.append(reference.id)
            }

            try database.clearAudioReferences(ids: clearedReferenceIDs)
            try cleanupOrphanedAudio(referencedPaths: referencedPaths, cutoff: orphanCutoff)
        } catch {
            record(error)
        }
    }

    // MARK: - Static Compatibility

    static var dictationsDirectory: URL? {
        shared.userDictationsDirectory
    }

    static func audioURL(forRelativePath path: String) -> URL? {
        shared.audioURL(forRelativePath: path)
    }

    // MARK: - Legacy Migration

    private func migrateLegacyUserDefaults() throws {
        guard let database else { return }

        let legacyKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.legacyStorageKeyPrefix) }
            .sorted()

        for key in legacyKeys {
            guard let data = defaults.data(forKey: key) else {
                // It is not one of the history JSON values this migration owns.
                continue
            }

            let decoded: [DictationHistoryItem]
            do {
                decoded = try JSONDecoder().decode([DictationHistoryItem].self, from: data)
            } catch {
                // Leave the source untouched so a future migration or manual
                // recovery remains possible. Never print transcript contents.
                record(error)
                continue
            }

            let normalized = try decoded.map { try normalizeLegacyItem($0, sourceKey: key) }
            _ = try database.importLegacyItems(normalized, sourceKey: key)

            // Delete a migrated source only after SQLite has durably committed
            // the replacement reference, and only when it is a recognized audio
            // file below a known Vibe Read Application Support directory. An
            // arbitrary absolute path from legacy JSON is never deleted.
            for (original, migrated) in zip(decoded, normalized) {
                if let sourceURL = safeLegacySourceForRemoval(
                    original: original,
                    migrated: migrated
                ) {
                    do {
                        try fileManager.removeItem(at: sourceURL)
                    } catch {
                        record(error)
                    }
                }
            }

            // SQLite has durably committed the whole source (or confirmed a
            // prior commit), so its duplicate UserDefaults copy can go.
            defaults.removeObject(forKey: key)
        }
    }

    private func normalizeLegacyItem(
        _ item: DictationHistoryItem,
        sourceKey: String
    ) throws -> DictationHistoryItem {
        guard let path = item.audioFilePath, !path.isEmpty else { return item }

        var normalized = item
        let pathURL = URL(fileURLWithPath: path)

        if pathURL.path == path, path.hasPrefix("/") {
            if let relativePath = relativeAudioPath(for: pathURL) {
                normalized.audioFilePath = relativePath
            } else {
                let fileExtension = pathURL.pathExtension
                let destinationName = "migrated_\(item.id.uuidString)"
                    + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
                let destinationURL = audioDirectory.appendingPathComponent(destinationName)
                if fileManager.fileExists(atPath: pathURL.path),
                   !fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.copyItem(at: pathURL, to: destinationURL)
                }
                // A previous migration may have copied and committed this
                // deterministic destination before source cleanup or a crash.
                normalized.audioFilePath = fileManager.fileExists(atPath: destinationURL.path)
                    ? destinationName
                    : nil
            }
            return normalized
        }

        if path.contains("/") {
            normalized.audioFilePath = audioURL(forRelativePath: path)
                .flatMap(relativeAudioPath(for:))
            return normalized
        }

        // User-scoped versions stored files in Dictations/<scope>. Prefer that
        // location only for a scoped defaults key.
        if let scope = legacyScope(from: sourceKey) {
            let scopedPath = scope + "/" + path
            if let scopedURL = audioURL(forRelativePath: scopedPath),
               fileManager.fileExists(atPath: scopedURL.path) {
                normalized.audioFilePath = scopedPath
                return normalized
            }
        }

        // Newer recording code saved directly in Dictations.
        if let rootURL = audioURL(forRelativePath: path),
           fileManager.fileExists(atPath: rootURL.path) {
            normalized.audioFilePath = path
            return normalized
        }

        // An interim local-only build used Dictations/local even with the
        // unscoped defaults key.
        let localPath = "local/" + path
        if let localURL = audioURL(forRelativePath: localPath),
           fileManager.fileExists(atPath: localURL.path) {
            normalized.audioFilePath = localPath
            return normalized
        }

        normalized.audioFilePath = audioURL(forRelativePath: path) == nil ? nil : path
        return normalized
    }

    private func legacyScope(from sourceKey: String) -> String? {
        let suffix = sourceKey.dropFirst(Self.legacyStorageKeyPrefix.count)
        guard suffix.first == "_" else { return nil }
        let scope = String(suffix.dropFirst())
        guard !scope.isEmpty,
              scope != ".",
              scope != "..",
              !scope.contains("/"),
              !scope.contains(":") else {
            return nil
        }
        return scope
    }

    private func safeLegacySourceForRemoval(
        original: DictationHistoryItem,
        migrated: DictationHistoryItem
    ) -> URL? {
        guard let originalPath = original.audioFilePath,
              originalPath.hasPrefix("/"),
              let migratedPath = migrated.audioFilePath,
              let destinationURL = audioURL(forRelativePath: migratedPath),
              fileManager.fileExists(atPath: destinationURL.path) else {
            return nil
        }

        let sourceURL = URL(fileURLWithPath: originalPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard sourceURL != destinationURL.standardizedFileURL.resolvingSymlinksInPath(),
              fileManager.fileExists(atPath: sourceURL.path),
              ["m4a", "wav", "aac", "caf", "aif", "aiff", "mp3", "mp4"]
                .contains(sourceURL.pathExtension.lowercased()) else {
            return nil
        }

        let applicationSupport = rootDirectory.deletingLastPathComponent()
        let knownOwnedRoots = [
            rootDirectory,
            applicationSupport.appendingPathComponent("Vibe Read", isDirectory: true)
        ]
        guard knownOwnedRoots.contains(where: { root in
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            let rootPath = resolvedRoot.path.hasSuffix("/")
                ? resolvedRoot.path
                : resolvedRoot.path + "/"
            return sourceURL.path.hasPrefix(rootPath)
        }) else {
            return nil
        }
        return sourceURL
    }

    // MARK: - Helpers

    private func addItem(
        rawTranscript: String,
        polishedText: String,
        audioURL: URL?,
        durationMs: Int?,
        clientId: UUID?,
        isSuccessful: Bool
    ) {
        performOnMain { [weak self] in
            guard let self, let database = self.database else { return }

            let relativeAudioPath = audioURL.flatMap(self.relativeAudioPath(for:))

            let item = DictationHistoryItem(
                id: clientId ?? UUID(),
                rawTranscript: rawTranscript,
                polishedText: polishedText,
                createdAt: self.now(),
                audioFilePath: relativeAudioPath,
                durationMs: durationMs
            )

            do {
                try database.upsert(item)
            } catch {
                self.record(error)
                return
            }

            // Persist the transcript before enforcing immediate cleanup. If
            // deletion fails, its DB reference remains for a later retry.
            if isSuccessful,
               self.audioRetention == .immediately,
               relativeAudioPath != nil,
               let audioURL {
                do {
                    if self.fileManager.fileExists(atPath: audioURL.path) {
                        try self.fileManager.removeItem(at: audioURL)
                    }
                    try database.clearAudioReferences(ids: [item.id])
                } catch {
                    self.record(error)
                }
            }
            // Enforce time-based retention during long-running sessions too,
            // rather than waiting for the next app launch.
            self.cleanupExpiredAudio()
            self.refreshDisplayedItems()
        }
    }

    private func refreshDisplayedItems() {
        guard let database else { return }

        do {
            let total = try database.count()
            items = try database.fetch(limit: displayLimit)
            hasMore = total > items.count
            persistenceError = nil
        } catch {
            record(error)
        }
    }

    private func relativeAudioPath(for url: URL) -> String? {
        let base = audioDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePath) else { return nil }
        return String(candidate.path.dropFirst(basePath.count))
    }

    private func audioURL(forRelativePath path: String) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let base = audioDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePath) else { return nil }
        return candidate
    }

    private func cleanupOrphanedAudio(
        referencedPaths: Set<String>,
        cutoff: Date?
    ) throws {
        guard let cutoff,
              let enumerator = fileManager.enumerator(
                at: audioDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
            )
            guard values.isRegularFile == true,
                  let relativePath = relativeAudioPath(for: fileURL),
                  !referencedPaths.contains(relativePath) else {
                continue
            }

            let fileDate = values.contentModificationDate ?? values.creationDate ?? .distantPast
            if fileDate <= cutoff {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func record(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "Local dictation storage failed."
        if Thread.isMainThread {
            persistenceError = message
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.persistenceError = message
            }
        }
        // Avoid logging record text or SQLite statements.
        print("[DictationStore] \(message)")
    }
}
