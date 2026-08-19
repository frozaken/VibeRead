import Foundation
import Testing
@testable import Vibe_Read

struct LocalDictationStoreTests {
    private struct LegacyItem: Encodable {
        let id: UUID
        let rawTranscript: String
        let polishedText: String
        let createdAt: Date
        let audioFilePath: String?
        let durationMs: Int?
        let serverId: String?
    }

    @Test func sqlitePersistsAndPagesMoreThanTenThousandRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let databaseURL = fixture.root.appendingPathComponent("history.sqlite3")
        let database = try LocalDictationDatabase(databaseURL: databaseURL)
        let baseDate = Date(timeIntervalSince1970: 2_000_000_000)
        let records = (0..<10_025).map { index in
            DictationHistoryItem(
                id: UUID(),
                rawTranscript: "synthetic-raw-\(index)",
                polishedText: "synthetic-polished-\(index)",
                createdAt: baseDate.addingTimeInterval(Double(index)),
                audioFilePath: nil,
                durationMs: index
            )
        }

        let result = try database.importLegacyItems(records, sourceKey: "synthetic_bulk_test")
        guard case .imported(let importedCount) = result else {
            Issue.record("Expected the synthetic source to import")
            return
        }

        #expect(importedCount == records.count)
        #expect(try database.count() == records.count)
        let page = try database.fetch(limit: 20, offset: 10_000)
        #expect(page.count == 20)
        #expect(page == page.sorted { $0.createdAt > $1.createdAt })
    }

    @Test @MainActor func migratesEveryLegacyDefaultsKeyTransactionally() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.never.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)

        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations/local", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("legacy.m4a")
        try Data([0x00]).write(to: audioURL)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let keysAndRecords: [(String, [LegacyItem])] = [
            (
                "dictation_history_v1",
                [LegacyItem(
                    id: UUID(),
                    rawTranscript: "synthetic-a",
                    polishedText: "synthetic-a-polished",
                    createdAt: now,
                    audioFilePath: "legacy.m4a",
                    durationMs: 10,
                    serverId: "obsolete-server-id"
                )]
            ),
            (
                "dictation_history_v1_profile_a",
                [LegacyItem(
                    id: UUID(),
                    rawTranscript: "synthetic-b",
                    polishedText: "synthetic-b-polished",
                    createdAt: now.addingTimeInterval(-1),
                    audioFilePath: nil,
                    durationMs: 20,
                    serverId: nil
                )]
            ),
            (
                "dictation_history_v1_profile_b",
                [LegacyItem(
                    id: UUID(),
                    rawTranscript: "synthetic-c",
                    polishedText: "synthetic-c-polished",
                    createdAt: now.addingTimeInterval(-2),
                    audioFilePath: nil,
                    durationMs: 30,
                    serverId: nil
                )]
            )
        ]

        for (key, records) in keysAndRecords {
            fixture.defaults.set(try JSONEncoder().encode(records), forKey: key)
        }

        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults,
            now: { now }
        )

        #expect(store.items.count == 3)
        for (key, _) in keysAndRecords {
            #expect(fixture.defaults.object(forKey: key) == nil)
        }
        #expect(store.items.first?.audioFilePath == "local/legacy.m4a")

        let database = try LocalDictationDatabase(
            databaseURL: fixture.root.appendingPathComponent("VibeRead/dictations.sqlite3")
        )
        #expect(try database.count() == 3)
    }

    @Test @MainActor func launchCleanupExpiresOnlyAudioAfterSevenDays() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let expiredURL = audioDirectory.appendingPathComponent("expired.m4a")
        let recentURL = audioDirectory.appendingPathComponent("recent.m4a")
        try Data([0x01]).write(to: expiredURL)
        try Data([0x02]).write(to: recentURL)

        let legacyItems = [
            LegacyItem(
                id: UUID(),
                rawTranscript: "synthetic-expired",
                polishedText: "synthetic-expired-polished",
                createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
                audioFilePath: expiredURL.lastPathComponent,
                durationMs: 10,
                serverId: nil
            ),
            LegacyItem(
                id: UUID(),
                rawTranscript: "synthetic-recent",
                polishedText: "synthetic-recent-polished",
                createdAt: now.addingTimeInterval(-24 * 60 * 60),
                audioFilePath: recentURL.lastPathComponent,
                durationMs: 20,
                serverId: nil
            )
        ]
        fixture.defaults.set(
            try JSONEncoder().encode(legacyItems),
            forKey: "dictation_history_v1_local"
        )

        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults,
            now: { now }
        )

        #expect(store.items.count == 2)
        #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
        #expect(FileManager.default.fileExists(atPath: recentURL.path))
        #expect(store.items.first { $0.polishedText == "synthetic-expired-polished" }?.audioFilePath == nil)
        #expect(store.items.first { $0.polishedText == "synthetic-recent-polished" }?.audioFilePath == "recent.m4a")
    }

    @Test @MainActor func legacyMigrationDeletesOnlyKnownOwnedAbsoluteAudioSources() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.never.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)
        let ownedDirectory = fixture.root
            .appendingPathComponent("Vibe Read/Dictations", isDirectory: true)
        let unrelatedDirectory = fixture.root
            .appendingPathComponent("Unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)
        let ownedSource = ownedDirectory.appendingPathComponent("owned.m4a")
        let unrelatedSource = unrelatedDirectory.appendingPathComponent("leave-alone.m4a")
        try Data([0x01]).write(to: ownedSource)
        try Data([0x02]).write(to: unrelatedSource)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let records = [
            LegacyItem(
                id: UUID(),
                rawTranscript: "owned",
                polishedText: "owned",
                createdAt: now,
                audioFilePath: ownedSource.path,
                durationMs: 10,
                serverId: nil
            ),
            LegacyItem(
                id: UUID(),
                rawTranscript: "unrelated",
                polishedText: "unrelated",
                createdAt: now,
                audioFilePath: unrelatedSource.path,
                durationMs: 20,
                serverId: nil
            )
        ]
        fixture.defaults.set(
            try JSONEncoder().encode(records),
            forKey: "dictation_history_v1_absolute_paths"
        )

        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults,
            now: { now }
        )

        #expect(store.items.count == 2)
        #expect(!FileManager.default.fileExists(atPath: ownedSource.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedSource.path))
        for item in store.items {
            let relativePath = try #require(item.audioFilePath)
            let migratedURL = try #require(
                store.userDictationsDirectory?.appendingPathComponent(relativePath)
            )
            #expect(FileManager.default.fileExists(atPath: migratedURL.path))
        }
    }

    @Test @MainActor func neverRetentionStillExpiresUntrackedCrashOrphans() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.never.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let orphanURL = audioDirectory.appendingPathComponent("orphan.m4a")
        try Data([0x03]).write(to: orphanURL)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: orphanURL.path
        )

        _ = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults,
            now: { now }
        )

        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @Test @MainActor func addingADictationEnforcesRetentionDuringLongRunningSessions() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults,
            now: { currentDate }
        )
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        let oldURL = audioDirectory.appendingPathComponent("old.m4a")
        try Data([0x01]).write(to: oldURL)
        store.add(
            DictationResult(rawTranscript: "old", polishedText: "old", durationMs: 10),
            audioURL: oldURL
        )

        currentDate = currentDate.addingTimeInterval(8 * 24 * 60 * 60)
        let newURL = audioDirectory.appendingPathComponent("new.m4a")
        try Data([0x02]).write(to: newURL)
        store.add(
            DictationResult(rawTranscript: "new", polishedText: "new", durationMs: 20),
            audioURL: newURL
        )

        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(store.items.first { $0.polishedText == "old" }?.audioFilePath == nil)
        #expect(store.items.first { $0.polishedText == "new" }?.audioFilePath == "new.m4a")
    }

    @Test @MainActor func deletionRemovesTheRowAndItsAudio() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.never.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)
        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults
        )
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        let audioURL = audioDirectory.appendingPathComponent("delete-me.m4a")
        try Data([0x03]).write(to: audioURL)

        store.add(
            DictationResult(
                rawTranscript: "synthetic-delete",
                polishedText: "synthetic-delete-polished",
                durationMs: 50
            ),
            audioURL: audioURL
        )
        let item = try #require(store.items.first)
        store.delete(item)

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test @MainActor func immediateRetentionAlsoRemovesFailedAudio() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.immediately.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)
        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults
        )
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        let audioURL = audioDirectory.appendingPathComponent("retry-me.m4a")
        try Data([0x04]).write(to: audioURL)

        store.addFailed(audioURL: audioURL, durationMs: 25)

        #expect(store.items.count == 1)
        #expect(store.items.first?.audioFilePath == nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test @MainActor func deleteAllAudioPreservesTranscriptRows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(DictationStore.AudioRetention.never.rawValue,
                             forKey: DictationStore.audioRetentionDefaultsKey)
        let store = DictationStore(
            applicationSupportDirectory: fixture.root,
            defaults: fixture.defaults
        )
        let audioDirectory = fixture.root
            .appendingPathComponent("VibeRead/Dictations", isDirectory: true)
        let audioURL = audioDirectory.appendingPathComponent("delete-audio-only.m4a")
        try Data([0x05]).write(to: audioURL)
        store.add(
            DictationResult(
                rawTranscript: "synthetic-keep",
                polishedText: "synthetic-keep-polished",
                durationMs: 60
            ),
            audioURL: audioURL
        )

        store.deleteAllAudio()

        #expect(store.items.count == 1)
        #expect(store.items.first?.audioFilePath == nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    }
}

private final class Fixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "LocalDictationStoreTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalDictationStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
