// DatabaseManager.swift
// RevEye
//
// Local SQLite layer for detections, badges and audio samples.
// Writes happen here first and get pushed to Firestore later when online.
// Everything runs on a serial queue so the main thread and the video
// processing thread don't trample each other.

import Foundation
import SQLite3

// SQLite has two "special" destructors: STATIC (don't copy the string, it
// stays valid) and TRANSIENT (copy the string, I'm about to free it).
// The C macros for these aren't bridged into Swift, so the usual trick is
// to bitcast -1 to a destructor function pointer. Pulling it out as a
// named constant so the call sites read clearly.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    // All database operations run on this serial queue to prevent concurrent
    // reads and writes from crashing. The main thread and video processing
    // thread both access the database, so serialisation is essential.
    private let queue = DispatchQueue(label: "com.reveye.db", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    // Opens the SQLite database file in the app's documents directory.
    // Creates the file if it doesn't exist yet.
    private func openDatabase() {
        guard let fileURL = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("reveyedb.sqlite") else {
            print("DB error: could not build file URL")
            return
        }
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("DB error: could not open - \(errorMessage)")
        }
    }

    // Creates all the tables the app needs if they don't already exist.
    // Safe to call on every launch - "IF NOT EXISTS" means it won't
    // overwrite existing data.
    private func createTables() {
        let createDetections = """
        CREATE TABLE IF NOT EXISTS detections (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel   TEXT    NOT NULL,
            confidence     REAL    NOT NULL,
            timestamp      TEXT    NOT NULL,
            synced         INTEGER NOT NULL DEFAULT 0,
            audioSampleId  INTEGER,
            imageKey       TEXT
        );
        """
        if sqlite3_exec(db, createDetections, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create detections table - \(errorMessage)")
        }

        migrateBadgesTableIfNeeded()
        seedBadgesIfNeeded()

        let createAudio = """
        CREATE TABLE IF NOT EXISTS audioSamples (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel     TEXT    NOT NULL,
            confidence       REAL    NOT NULL,
            audioDuration    REAL    NOT NULL DEFAULT 0,
            engineAudible    TEXT    NOT NULL DEFAULT 'unsure',
            recordingContext  TEXT    NOT NULL DEFAULT 'other',
            vehicleState     TEXT    NOT NULL DEFAULT 'unknown',
            backgroundNoise  TEXT    NOT NULL DEFAULT 'moderate',
            userNotes        TEXT    NOT NULL DEFAULT '',
            localFilePath    TEXT    NOT NULL,
            firebaseStoragePath TEXT,
            timestamp        TEXT    NOT NULL,
            synced           INTEGER NOT NULL DEFAULT 0
        );
        """
        if sqlite3_exec(db, createAudio, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create audioSamples table - \(errorMessage)")
        }

        migrateVehicleModelColumnIfNeeded()
        migrateAudioSampleIdColumn()
        migrateImageKeyColumn()
    }

    // Populates the badges table with all badge definitions on first run.
    // Skips if badges already exist.
    private func seedBadgesIfNeeded() {
        for badge in Badge.all {
            let sql = "INSERT OR IGNORE INTO badges (id, earned, earnedAt) VALUES (?, 0, NULL);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, badge.id, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // Checks if the badges table has the correct schema (id, earned, earnedAt).
    // If the table exists with a wrong schema, drops and recreates it.
    // Safe because Firestore is the source of truth.
    private func migrateBadgesTableIfNeeded() {
        let pragma = "PRAGMA table_info(badges);"
        var stmt: OpaquePointer?
        var hasEarned = false
        var tableExists = false

        if sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                tableExists = true
                if let cName = sqlite3_column_text(stmt, 1) {
                    if String(cString: cName) == "earned" { hasEarned = true }
                }
            }
        }
        sqlite3_finalize(stmt)

        if tableExists && !hasEarned {
            let drop = "DROP TABLE IF EXISTS badges;"
            sqlite3_exec(db, drop, nil, nil, nil)
        }

        let createBadges = """
        CREATE TABLE IF NOT EXISTS badges (
            id       TEXT PRIMARY KEY,
            earned   INTEGER NOT NULL DEFAULT 0,
            earnedAt TEXT
        );
        """
        if sqlite3_exec(db, createBadges, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create badges table - \(errorMessage)")
        }
    }

    // Renames the old 'vehicleModel' column to 'vehicleLabel' for existing
    // installs. SQLite doesn't support ALTER COLUMN RENAME on older iOS
    // versions, so this recreates the table and copies all data.
    private func migrateVehicleModelColumnIfNeeded() {
        let pragma = "PRAGMA table_info(detections);"
        var stmt: OpaquePointer?
        var hasVehicleLabel = false

        if sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 1) {
                    if String(cString: cName) == "vehicleLabel" { hasVehicleLabel = true }
                }
            }
        }
        sqlite3_finalize(stmt)
        guard !hasVehicleLabel else { return }

        let migration = """
        BEGIN TRANSACTION;
        CREATE TABLE detections_new (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel   TEXT    NOT NULL,
            confidence     REAL    NOT NULL,
            timestamp      TEXT    NOT NULL,
            synced         INTEGER NOT NULL DEFAULT 0,
            audioSampleId  INTEGER
        );
        INSERT INTO detections_new (id, vehicleLabel, confidence, timestamp, synced)
        SELECT id, vehicleModel, confidence, timestamp, synced FROM detections;
        DROP TABLE detections;
        ALTER TABLE detections_new RENAME TO detections;
        COMMIT;
        """
        if sqlite3_exec(db, migration, nil, nil, nil) != SQLITE_OK {
            print("DB migration error: \(errorMessage)")
        }
    }

    // Adds the audioSampleId column to detections if it doesn't exist yet.
    private func migrateAudioSampleIdColumn() {
        let pragma = "PRAGMA table_info(detections);"
        var stmt: OpaquePointer?
        var hasAudioSampleId = false

        if sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 1) {
                    if String(cString: cName) == "audioSampleId" { hasAudioSampleId = true }
                }
            }
        }
        sqlite3_finalize(stmt)
        guard !hasAudioSampleId else { return }

        let alter = "ALTER TABLE detections ADD COLUMN audioSampleId INTEGER;"
        sqlite3_exec(db, alter, nil, nil, nil)
    }

    // Adds the imageKey column to detections if it doesn't exist yet.
    // Stores a stable UUID used as the on-disk filename for each detection's
    // image, so images survive sign-out/sign-in even though the SQLite id resets.
    private func migrateImageKeyColumn() {
        let pragma = "PRAGMA table_info(detections);"
        var stmt: OpaquePointer?
        var hasImageKey = false

        if sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 1) {
                    if String(cString: cName) == "imageKey" { hasImageKey = true }
                }
            }
        }
        sqlite3_finalize(stmt)
        guard !hasImageKey else { return }

        let alter = "ALTER TABLE detections ADD COLUMN imageKey TEXT;"
        sqlite3_exec(db, alter, nil, nil, nil)
    }

    // Helper to get the last SQLite error message for debugging
    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }
}

// Detection CRUD

extension DatabaseManager {

    // Inserts a new detection into SQLite and returns the auto-generated ID.
    // Returns nil if the insert fails.
    func insertDetection(_ detection: Detection) -> Int64? {
        var newId: Int64?
        queue.sync {
            let sql = """
            INSERT INTO detections (vehicleLabel, confidence, timestamp, synced, audioSampleId, imageKey)
            VALUES (?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (insert prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text  (stmt, 1, detection.vehicleLabel, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, detection.confidence)
            sqlite3_bind_text  (stmt, 3, detection.timestamp,    -1, SQLITE_TRANSIENT)
            sqlite3_bind_int   (stmt, 4, Int32(detection.synced))
            if let audioId = detection.audioSampleId {
                sqlite3_bind_int64(stmt, 5, audioId)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            if let key = detection.imageKey {
                sqlite3_bind_text(stmt, 6, key, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("DB error (insert step): \(errorMessage)"); return
            }
            newId = sqlite3_last_insert_rowid(db)
        }
        return newId
    }

    // Sets or updates the imageKey for an existing detection. Used when an
    // image is saved for a detection that was inserted without one.
    func setImageKey(_ key: String, for detectionId: Int64) {
        queue.sync {
            let sql = "UPDATE detections SET imageKey = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text (stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, detectionId)
            sqlite3_step(stmt)
        }
    }

    // Fetches all detections, or just unsynced ones for the sync queue
    func fetchAllDetections() -> [Detection] { fetch(where: nil) }

    func fetchUnsyncedDetections() -> [Detection] { fetch(where: "synced = 0") }

    // Updates a detection's sync status to 1 (synced) after successful Firebase upload
    func markAsSynced(id: Int64) {
        queue.sync {
            let sql = "UPDATE detections SET synced = 1 WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (markAsSynced prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE { print("DB error (markAsSynced step): \(errorMessage)") }
        }
    }

    // Links an audio sample to a detection by setting the audioSampleId
    // foreign key on the detection record.
    func linkAudioToDetection(detectionId: Int64, audioSampleId: Int64) {
        queue.sync {
            let sql = "UPDATE detections SET audioSampleId = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, audioSampleId)
            sqlite3_bind_int64(stmt, 2, detectionId)
            sqlite3_step(stmt)
        }
    }

    // Deletes a single detection from the database by ID
    func deleteDetection(id: Int64) {
        queue.sync {
            let sql = "DELETE FROM detections WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (delete prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE { print("DB error (delete step): \(errorMessage)") }
        }
    }

    // Shared fetch function that runs a SELECT query and maps the results
    // into Detection structs. Used by fetchAllDetections and fetchUnsyncedDetections.
    private func fetch(where condition: String?) -> [Detection] {
        var results: [Detection] = []
        queue.sync {
            let whereClause = condition.map { "WHERE \($0)" } ?? ""
            let sql = """
            SELECT id, vehicleLabel, confidence, timestamp, synced, audioSampleId, imageKey
            FROM detections \(whereClause)
            ORDER BY id DESC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (fetch prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let audioId: Int64? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                    ? sqlite3_column_int64(stmt, 5) : nil
                let imgKey: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(stmt, 6)) : nil
                results.append(Detection(
                    id:            sqlite3_column_int64(stmt, 0),
                    vehicleLabel:  String(cString: sqlite3_column_text(stmt, 1)),
                    confidence:    sqlite3_column_double(stmt, 2),
                    timestamp:     String(cString: sqlite3_column_text(stmt, 3)),
                    synced:        Int(sqlite3_column_int(stmt, 4)),
                    audioSampleId: audioId,
                    imageKey:      imgKey
                ))
            }
        }
        return results
    }

    // Streak Query

    // Returns the number of consecutive days (ending today) with at least one detection.
    func currentStreak() -> Int {
        var dates: Set<String> = []
        queue.sync {
            let sql = "SELECT DISTINCT date(timestamp) FROM detections ORDER BY timestamp DESC LIMIT 60;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let val = sqlite3_column_text(stmt, 0) {
                    dates.insert(String(cString: val))
                }
            }
        }
        guard !dates.isEmpty else { return 0 }

        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        var streak = 0
        var day = cal.startOfDay(for: Date())
        while dates.contains(fmt.string(from: day)) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}

// Badge CRUD

extension DatabaseManager {

    func fetchAllBadges() -> [Badge] {
        var dbRows: [(id: String, earned: Bool, earnedAt: String?)] = []
        queue.sync {
            let sql = "SELECT id, earned, earnedAt FROM badges;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (fetchAllBadges): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id       = String(cString: sqlite3_column_text(stmt, 0))
                let earned   = sqlite3_column_int(stmt, 1) == 1
                let earnedAt = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(stmt, 2)) : nil
                dbRows.append((id, earned, earnedAt))
            }
        }
        return Badge.all.map { template in
            if let row = dbRows.first(where: { $0.id == template.id }) {
                var b = template
                b.earned   = row.earned
                b.earnedAt = row.earnedAt
                return b
            }
            return template
        }
    }

    @discardableResult
    // Marks a badge as earned in the local database. Returns true if newly earned.
    func earnBadge(id: String) -> Bool {
        var wasNew = false
        queue.sync {
            let checkSQL = "SELECT earned FROM badges WHERE id = ?;"
            var checkStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, id, -1, SQLITE_TRANSIENT)
                if sqlite3_step(checkStmt) == SQLITE_ROW {
                    wasNew = sqlite3_column_int(checkStmt, 0) == 0
                }
            }
            sqlite3_finalize(checkStmt)
            guard wasNew else { return }

            let earnedAt = ISO8601DateFormatter().string(from: Date())
            let sql = "UPDATE badges SET earned = 1, earnedAt = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                wasNew = false; return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, earnedAt, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, id,       -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE { wasNew = false }
        }
        return wasNew
    }

    func mergeBadgesFromFirebase(_ earned: [(id: String, earnedAt: String)]) {
        queue.sync {
            let sql = """
            INSERT INTO badges (id, earned, earnedAt) VALUES (?, 1, ?)
            ON CONFLICT(id) DO UPDATE SET
                earned   = 1,
                earnedAt = excluded.earnedAt
            WHERE earned = 0;
            """
            for item in earned {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(stmt, 1, item.id,       -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, item.earnedAt, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    // Resets all badges to unearned. Called on logout so the next user
    // starts with a clean slate before their badges sync from Firestore.
    func resetAllBadges() {
        queue.sync {
            sqlite3_exec(db, "UPDATE badges SET earned = 0, earnedAt = NULL;", nil, nil, nil)
        }
    }

    // Deletes all detections. Called on logout.
    func resetAllDetections() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM detections;", nil, nil, nil)
        }
    }

    // Deletes all audio samples. Called on logout.
    func resetAllAudioSamples() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM audioSamples;", nil, nil, nil)
        }
    }

    // Wipes all user data from local DB. Called on logout.
    func resetAllUserData() {
        resetAllBadges()
        resetAllDetections()
        resetAllAudioSamples()
    }
}

// Audio Sample CRUD

extension DatabaseManager {

    // Inserts a new audio sample record into SQLite. Returns the auto-generated ID.
    func insertAudioSample(_ sample: AudioSample) -> Int64? {
        var newId: Int64?
        queue.sync {
            let sql = """
            INSERT INTO audioSamples
                (vehicleLabel, confidence, audioDuration, engineAudible, recordingContext,
                 vehicleState, backgroundNoise, userNotes, localFilePath,
                 firebaseStoragePath, timestamp, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (insertAudio prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text  (stmt, 1,  sample.vehicleLabel, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2,  sample.confidence)
            sqlite3_bind_double(stmt, 3,  sample.audioDuration)
            sqlite3_bind_text  (stmt, 4,  sample.engineAudible.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 5,  sample.recordingContext.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 6,  sample.vehicleState.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 7,  sample.backgroundNoise.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 8,  sample.userNotes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 9,  sample.localFilePath, -1, SQLITE_TRANSIENT)
            if let fbPath = sample.firebaseStoragePath {
                sqlite3_bind_text(stmt, 10, fbPath, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_bind_text(stmt, 11, sample.timestamp, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int (stmt, 12, Int32(sample.synced))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("DB error (insertAudio step): \(errorMessage)"); return
            }
            newId = sqlite3_last_insert_rowid(db)
        }
        return newId
    }

    func fetchAllAudioSamples() -> [AudioSample] {
        var results: [AudioSample] = []
        queue.sync {
            let sql = "SELECT * FROM audioSamples ORDER BY id DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (fetchAudio): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            guard let stmt else { return }
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(audioSampleFromRow(stmt))
            }
        }
        return results
    }

    func audioSampleCount() -> Int {
        var count = 0
        queue.sync {
            let sql = "SELECT COUNT(*) FROM audioSamples;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return count
    }

    func markAudioAsSynced(id: Int64, storagePath: String) {
        queue.sync {
            let sql = "UPDATE audioSamples SET synced = 1, firebaseStoragePath = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text (stmt, 1, storagePath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    // Maps a SQLite row into an AudioSample. Caller must pass a valid stmt.
    private func audioSampleFromRow(_ stmt: OpaquePointer) -> AudioSample {
        let fbPath: String? = sqlite3_column_type(stmt, 10) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 10)) : nil
        return AudioSample(
            id:                  sqlite3_column_int64(stmt, 0),
            vehicleLabel:        String(cString: sqlite3_column_text(stmt, 1)),
            confidence:          sqlite3_column_double(stmt, 2),
            audioDuration:       sqlite3_column_double(stmt, 3),
            engineAudible:       EngineAudible(rawValue: String(cString: sqlite3_column_text(stmt, 4))) ?? .unsure,
            recordingContext:    RecordingContext(rawValue: String(cString: sqlite3_column_text(stmt, 5))) ?? .other,
            vehicleState:        VehicleState(rawValue: String(cString: sqlite3_column_text(stmt, 6))) ?? .unknown,
            backgroundNoise:     NoiseLevel(rawValue: String(cString: sqlite3_column_text(stmt, 7))) ?? .moderate,
            userNotes:           String(cString: sqlite3_column_text(stmt, 8)),
            localFilePath:       String(cString: sqlite3_column_text(stmt, 9)),
            firebaseStoragePath: fbPath,
            timestamp:           String(cString: sqlite3_column_text(stmt, 11)),
            synced:              Int(sqlite3_column_int(stmt, 12))
        )
    }

}
