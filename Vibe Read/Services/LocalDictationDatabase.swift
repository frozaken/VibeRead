import Foundation
import SQLite3

enum LocalDictationDatabaseError: LocalizedError {
    case couldNotOpenDatabase(Int32)
    case sqliteFailure(operation: String, code: Int32)
    case invalidStoredIdentifier

    var errorDescription: String? {
        switch self {
        case .couldNotOpenDatabase(let code):
            return "The local dictation database could not be opened (SQLite error \(code))."
        case .sqliteFailure(let operation, let code):
            return "The local dictation database failed while \(operation) (SQLite error \(code))."
        case .invalidStoredIdentifier:
            return "The local dictation database contains an invalid record identifier."
        }
    }
}

/// A small SQLite-backed repository for local dictation history.
///
/// SQLite is built into macOS, works on macOS 13, and lets the history screen
/// page through many thousands of transcripts without decoding a large JSON
/// blob or retaining the entire history in memory.
final class LocalDictationDatabase {
    struct AudioReference {
        let id: UUID
        let relativePath: String
        let createdAt: Date
        let isRetryableFailure: Bool
    }

    enum LegacyImportResult {
        case imported(recordCount: Int)
        case alreadyImported
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let lock = NSLock()
    private var connection: OpaquePointer?

    init(databaseURL: URL) throws {
        var database: OpaquePointer?
        let openResult = databaseURL.path.withCString { path in
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }

        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw LocalDictationDatabaseError.couldNotOpenDatabase(openResult)
        }

        connection = database
        sqlite3_busy_timeout(database, 5_000)

        do {
            // Ask SQLite to overwrite deleted cells instead of leaving their
            // previous transcript bytes in reusable database pages.
            try execute("PRAGMA secure_delete = ON", operation: "enabling secure deletion")
            try execute("PRAGMA journal_mode = WAL", operation: "enabling write-ahead logging")
            try execute("PRAGMA synchronous = FULL", operation: "configuring durability")
            try createSchema()
        } catch {
            sqlite3_close(database)
            connection = nil
            throw error
        }
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    func count() throws -> Int {
        try withLock {
            let statement = try prepare(
                "SELECT COUNT(*) FROM dictations",
                operation: "counting dictations"
            )
            defer { sqlite3_finalize(statement) }

            try requireRow(statement, operation: "counting dictations")
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func fetch(limit: Int, offset: Int = 0) throws -> [DictationHistoryItem] {
        try withLock {
            let statement = try prepare(
                """
                SELECT id, raw_transcript, polished_text, created_at, audio_file_path, duration_ms
                FROM dictations
                ORDER BY created_at DESC, id ASC
                LIMIT ? OFFSET ?
                """,
                operation: "loading dictations"
            )
            defer { sqlite3_finalize(statement) }

            try bind(Int64(max(0, limit)), to: 1, in: statement, operation: "loading dictations")
            try bind(Int64(max(0, offset)), to: 2, in: statement, operation: "loading dictations")

            var items: [DictationHistoryItem] = []
            items.reserveCapacity(max(0, limit))

            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    items.append(try decodeItem(from: statement))
                case SQLITE_DONE:
                    return items
                default:
                    throw sqliteError(operation: "loading dictations")
                }
            }
        }
    }

    func upsert(_ item: DictationHistoryItem) throws {
        try withLock {
            try upsertUnlocked(item)
        }
    }

    func updateTranscription(
        id: UUID,
        rawTranscript: String,
        polishedText: String,
        durationMs: Int?
    ) throws {
        try withLock {
            let statement = try prepare(
                """
                UPDATE dictations
                SET raw_transcript = ?, polished_text = ?, duration_ms = ?
                WHERE id = ?
                """,
                operation: "updating a dictation"
            )
            defer { sqlite3_finalize(statement) }

            try bind(rawTranscript, to: 1, in: statement, operation: "updating a dictation")
            try bind(polishedText, to: 2, in: statement, operation: "updating a dictation")
            try bind(durationMs.map(Int64.init), to: 3, in: statement, operation: "updating a dictation")
            try bind(id.uuidString, to: 4, in: statement, operation: "updating a dictation")
            try requireDone(statement, operation: "updating a dictation")
        }
    }

    func delete(id: UUID) throws {
        try withLock {
            do {
                let statement = try prepare(
                    "DELETE FROM dictations WHERE id = ?",
                    operation: "deleting a dictation"
                )
                defer { sqlite3_finalize(statement) }

                try bind(id.uuidString, to: 1, in: statement, operation: "deleting a dictation")
                try requireDone(statement, operation: "deleting a dictation")
            }
            try truncateWriteAheadLog(operation: "finishing dictation deletion")
        }
    }

    func deleteAll() throws {
        try withLock {
            try execute("DELETE FROM dictations", operation: "clearing dictations")
            // VACUUM rebuilds the main file so pages formerly occupied by the
            // deleted history are not retained in the local database. Truncate
            // the WAL afterwards so it cannot retain pre-deletion page images.
            try execute("VACUUM", operation: "compacting cleared dictation history")
            try truncateWriteAheadLog(operation: "finishing dictation history deletion")
        }
    }

    func audioReferences() throws -> [AudioReference] {
        try withLock {
            let statement = try prepare(
                """
                SELECT id, audio_file_path, created_at,
                       (raw_transcript = '' AND polished_text = '') AS is_retryable_failure
                FROM dictations
                WHERE audio_file_path IS NOT NULL
                """,
                operation: "loading audio references"
            )
            defer { sqlite3_finalize(statement) }

            var references: [AudioReference] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    guard
                        let identifier = columnString(statement, index: 0),
                        let id = UUID(uuidString: identifier),
                        let relativePath = columnString(statement, index: 1)
                    else {
                        throw LocalDictationDatabaseError.invalidStoredIdentifier
                    }

                    references.append(
                        AudioReference(
                            id: id,
                            relativePath: relativePath,
                            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                            isRetryableFailure: sqlite3_column_int(statement, 3) != 0
                        )
                    )
                case SQLITE_DONE:
                    return references
                default:
                    throw sqliteError(operation: "loading audio references")
                }
            }
        }
    }

    func clearAudioReferences(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        try withLock {
            try inTransaction {
                let statement = try prepare(
                    "UPDATE dictations SET audio_file_path = NULL WHERE id = ?",
                    operation: "clearing audio references"
                )
                defer { sqlite3_finalize(statement) }

                for id in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(id.uuidString, to: 1, in: statement, operation: "clearing audio references")
                    try requireDone(statement, operation: "clearing audio references")
                }
            }
        }
    }

    func clearAllAudioReferences() throws {
        try withLock {
            try execute(
                "UPDATE dictations SET audio_file_path = NULL WHERE audio_file_path IS NOT NULL",
                operation: "clearing all audio references"
            )
        }
    }

    /// Imports one complete legacy UserDefaults array atomically. A source
    /// marker in the same transaction makes the operation safe to retry if the
    /// app exits after the commit but before the old defaults key is removed.
    func importLegacyItems(
        _ items: [DictationHistoryItem],
        sourceKey: String
    ) throws -> LegacyImportResult {
        try withLock {
            if try legacySourceWasImportedUnlocked(sourceKey) {
                return .alreadyImported
            }

            try inTransaction {
                for item in items {
                    if let existing = try itemUnlocked(id: item.id) {
                        if representsSameLegacyRecord(existing, item) {
                            if existing.audioFilePath == nil, item.audioFilePath != nil {
                                try updateAudioPathUnlocked(id: existing.id, path: item.audioFilePath)
                            }
                            continue
                        }

                        var collisionSafeItem = item
                        repeat {
                            collisionSafeItem = item.replacingID(with: UUID())
                        } while try itemUnlocked(id: collisionSafeItem.id) != nil
                        try upsertUnlocked(collisionSafeItem)
                    } else {
                        try upsertUnlocked(item)
                    }
                }

                let statement = try prepare(
                    """
                    INSERT INTO legacy_import_sources (source_key, record_count, imported_at)
                    VALUES (?, ?, ?)
                    """,
                    operation: "recording legacy migration"
                )
                defer { sqlite3_finalize(statement) }

                try bind(sourceKey, to: 1, in: statement, operation: "recording legacy migration")
                try bind(Int64(items.count), to: 2, in: statement, operation: "recording legacy migration")
                try bind(Date().timeIntervalSince1970, to: 3, in: statement, operation: "recording legacy migration")
                try requireDone(statement, operation: "recording legacy migration")
            }

            return .imported(recordCount: items.count)
        }
    }

    // MARK: - Schema

    private func createSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS dictations (
                id TEXT PRIMARY KEY NOT NULL,
                raw_transcript TEXT NOT NULL,
                polished_text TEXT NOT NULL,
                created_at REAL NOT NULL,
                audio_file_path TEXT,
                duration_ms INTEGER
            )
            """,
            operation: "creating the dictation table"
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS dictations_created_at_index
            ON dictations (created_at DESC, id ASC)
            """,
            operation: "indexing dictation history"
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS legacy_import_sources (
                source_key TEXT PRIMARY KEY NOT NULL,
                record_count INTEGER NOT NULL,
                imported_at REAL NOT NULL
            )
            """,
            operation: "creating migration metadata"
        )
    }

    // MARK: - Item Operations

    private func upsertUnlocked(_ item: DictationHistoryItem) throws {
        let statement = try prepare(
            """
            INSERT INTO dictations (
                id, raw_transcript, polished_text, created_at, audio_file_path, duration_ms
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                raw_transcript = excluded.raw_transcript,
                polished_text = excluded.polished_text,
                created_at = excluded.created_at,
                audio_file_path = excluded.audio_file_path,
                duration_ms = excluded.duration_ms
            """,
            operation: "saving a dictation"
        )
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, to: 1, in: statement, operation: "saving a dictation")
        try bind(item.rawTranscript, to: 2, in: statement, operation: "saving a dictation")
        try bind(item.polishedText, to: 3, in: statement, operation: "saving a dictation")
        try bind(item.createdAt.timeIntervalSince1970, to: 4, in: statement, operation: "saving a dictation")
        try bind(item.audioFilePath, to: 5, in: statement, operation: "saving a dictation")
        try bind(item.durationMs.map(Int64.init), to: 6, in: statement, operation: "saving a dictation")
        try requireDone(statement, operation: "saving a dictation")
    }

    private func itemUnlocked(id: UUID) throws -> DictationHistoryItem? {
        let statement = try prepare(
            """
            SELECT id, raw_transcript, polished_text, created_at, audio_file_path, duration_ms
            FROM dictations
            WHERE id = ?
            """,
            operation: "checking a migrated dictation"
        )
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, to: 1, in: statement, operation: "checking a migrated dictation")
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return try decodeItem(from: statement)
        case SQLITE_DONE:
            return nil
        default:
            throw sqliteError(operation: "checking a migrated dictation")
        }
    }

    private func updateAudioPathUnlocked(id: UUID, path: String?) throws {
        let statement = try prepare(
            "UPDATE dictations SET audio_file_path = ? WHERE id = ?",
            operation: "preserving migrated audio"
        )
        defer { sqlite3_finalize(statement) }

        try bind(path, to: 1, in: statement, operation: "preserving migrated audio")
        try bind(id.uuidString, to: 2, in: statement, operation: "preserving migrated audio")
        try requireDone(statement, operation: "preserving migrated audio")
    }

    private func legacySourceWasImportedUnlocked(_ sourceKey: String) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM legacy_import_sources WHERE source_key = ? LIMIT 1",
            operation: "checking legacy migration"
        )
        defer { sqlite3_finalize(statement) }

        try bind(sourceKey, to: 1, in: statement, operation: "checking legacy migration")
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw sqliteError(operation: "checking legacy migration")
        }
    }

    private func representsSameLegacyRecord(
        _ existing: DictationHistoryItem,
        _ candidate: DictationHistoryItem
    ) -> Bool {
        existing.rawTranscript == candidate.rawTranscript
            && existing.polishedText == candidate.polishedText
            && abs(existing.createdAt.timeIntervalSince1970 - candidate.createdAt.timeIntervalSince1970) < 0.001
            && existing.durationMs == candidate.durationMs
    }

    private func decodeItem(from statement: OpaquePointer) throws -> DictationHistoryItem {
        guard
            let identifier = columnString(statement, index: 0),
            let id = UUID(uuidString: identifier),
            let rawTranscript = columnString(statement, index: 1),
            let polishedText = columnString(statement, index: 2)
        else {
            throw LocalDictationDatabaseError.invalidStoredIdentifier
        }

        let audioFilePath = columnString(statement, index: 4)
        let durationMs: Int?
        if sqlite3_column_type(statement, 5) == SQLITE_NULL {
            durationMs = nil
        } else {
            durationMs = Int(sqlite3_column_int64(statement, 5))
        }

        return DictationHistoryItem(
            id: id,
            rawTranscript: rawTranscript,
            polishedText: polishedText,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            audioFilePath: audioFilePath,
            durationMs: durationMs
        )
    }

    // MARK: - SQLite Helpers

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION", operation: "starting a transaction")
        do {
            try body()
            try execute("COMMIT TRANSACTION", operation: "committing a transaction")
        } catch {
            try? execute("ROLLBACK TRANSACTION", operation: "rolling back a transaction")
            throw error
        }
    }

    private func execute(_ sql: String, operation: String) throws {
        guard let connection else {
            throw LocalDictationDatabaseError.couldNotOpenDatabase(SQLITE_MISUSE)
        }

        let result = sqlite3_exec(connection, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func truncateWriteAheadLog(operation: String) throws {
        guard let connection else {
            throw LocalDictationDatabaseError.couldNotOpenDatabase(SQLITE_MISUSE)
        }

        var framesInLog: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let result = sqlite3_wal_checkpoint_v2(
            connection,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            &framesInLog,
            &checkpointedFrames
        )
        guard result == SQLITE_OK else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func prepare(_ sql: String, operation: String) throws -> OpaquePointer {
        guard let connection else {
            throw LocalDictationDatabaseError.couldNotOpenDatabase(SQLITE_MISUSE)
        }

        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
        return statement
    }

    private func bind(
        _ value: String?,
        to index: Int32,
        in statement: OpaquePointer,
        operation: String
    ) throws {
        let result: Int32
        if let value {
            result = value.withCString { pointer in
                sqlite3_bind_text(statement, index, pointer, -1, Self.sqliteTransient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func bind(
        _ value: Int64?,
        to index: Int32,
        in statement: OpaquePointer,
        operation: String
    ) throws {
        let result = value.map { sqlite3_bind_int64(statement, index, $0) }
            ?? sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func bind(
        _ value: Double,
        to index: Int32,
        in statement: OpaquePointer,
        operation: String
    ) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func requireRow(_ statement: OpaquePointer, operation: String) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func requireDone(_ statement: OpaquePointer, operation: String) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw LocalDictationDatabaseError.sqliteFailure(operation: operation, code: result)
        }
    }

    private func sqliteError(operation: String) -> LocalDictationDatabaseError {
        let code = connection.map(sqlite3_errcode) ?? SQLITE_MISUSE
        return .sqliteFailure(operation: operation, code: code)
    }

    private func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }
}
