//
//  DatabaseManager.swift
//  RevEye
//
//  Updated 10/03/2026 — added audioSamples table, audio CRUD, streak query

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    // All DB work runs on this serial queue, preventing concurrent reads/writes
    // from the main thread and the video-processing background task colliding.
    private let queue = DispatchQueue(label: "com.reveye.db", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    // MARK: - Setup

    private func openDatabase() {
        guard let fileURL = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("reveyedb.sqlite") else {
            print("DB error: could not build file URL")
            return
        }
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("DB error: could not open — \(errorMessage)")
        } else {
            print("Database opened at: \(fileURL.path)")
        }
    }

    private func createTables() {
        // ── Detections table ──────────────────────────────────────────
        let createDetections = """
        CREATE TABLE IF NOT EXISTS detections (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel   TEXT    NOT NULL,
            confidence     REAL    NOT NULL,
            timestamp      TEXT    NOT NULL,
            synced         INTEGER NOT NULL DEFAULT 0,
            audioSampleId  INTEGER
        );
        """
        if sqlite3_exec(db, createDetections, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create detections table — \(errorMessage)")
        } else {
            print("detections table ready")
        }

        // ── Badges table ──────────────────────────────────────────────
        // Migration: if the table exists but has the wrong schema (from an
        // earlier version), drop and recreate it. This is safe because badge
        // state is also stored in Firestore and will be re-synced.
        migrateBadgesTableIfNeeded()
        seedBadgesIfNeeded()

        // ── Audio Samples table ───────────────────────────────────────
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
            print("DB error: could not create audioSamples table — \(errorMessage)")
        } else {
            print("audioSamples table ready")
        }

        migrateVehicleModelColumnIfNeeded()
        migrateAudioSampleIdColumn()
    }

    // Inserts a row for every known badge if it doesn't already exist.
    private func seedBadgesIfNeeded() {
        var seeded = 0
        for badge in Badge.all {
            let sql = "INSERT OR IGNORE INTO badges (id, earned, earnedAt) VALUES (?, 0, NULL);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(stmt, 1, badge.id, -1, transient)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    seeded += 1
                }
            }
            sqlite3_finalize(stmt)
        }
        print("Badge seeding: processed \(Badge.all.count) badges, \(seeded) inserts attempted")
        
        // Verify: count rows in badges table
        let countSQL = "SELECT COUNT(*) FROM badges;"
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                let count = sqlite3_column_int(countStmt, 0)
                print("Badge seeding: \(count) badges now in table")
            }
        }
        sqlite3_finalize(countStmt)
    }

    /// Checks if the badges table has the correct schema (id, earned, earnedAt).
    /// If the table exists but is missing the 'earned' column (from an earlier app version),
    /// drops and recreates it. Safe because Firestore is the cross-device source of truth.
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
            // Old schema — drop and recreate
            print("DB migration: badges table has wrong schema, recreating...")
            let drop = "DROP TABLE IF EXISTS badges;"
            sqlite3_exec(db, drop, nil, nil, nil)
        }

        // Create the table (will be created fresh if we just dropped it,
        // or created new if it never existed, or no-op if schema is correct)
        let createBadges = """
        CREATE TABLE IF NOT EXISTS badges (
            id       TEXT PRIMARY KEY,
            earned   INTEGER NOT NULL DEFAULT 0,
            earnedAt TEXT
        );
        """
        if sqlite3_exec(db, createBadges, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create badges table — \(errorMessage)")
        } else {
            print("badges table ready (has 'earned' column: \(!tableExists || hasEarned ? "already" : "recreated"))")
        }
    }

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

        print("DB migration: renaming vehicleModel → vehicleLabel")
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
        } else {
            print("DB migration complete")
        }
    }

    /// Adds the audioSampleId column to detections if it doesn't exist yet.
    /// Safe to run on databases created before the audio feature.
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
        if sqlite3_exec(db, alter, nil, nil, nil) != SQLITE_OK {
            print("DB migration (audioSampleId): \(errorMessage)")
        } else {
            print("DB migration: added audioSampleId column")
        }
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }
}

// MARK: - Detection CRUD

extension DatabaseManager {

    func insertDetection(_ detection: Detection) -> Int64? {
        var newId: Int64?
        queue.sync {
            let sql = """
            INSERT INTO detections (vehicleLabel, confidence, timestamp, synced, audioSampleId)
            VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (insert prepare): \(errorMessage)"); return
            }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text  (stmt, 1, detection.vehicleLabel, -1, transient)
            sqlite3_bind_double(stmt, 2, detection.confidence)
            sqlite3_bind_text  (stmt, 3, detection.timestamp,    -1, transient)
            sqlite3_bind_int   (stmt, 4, Int32(detection.synced))
            if let audioId = detection.audioSampleId {
                sqlite3_bind_int64(stmt, 5, audioId)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("DB error (insert step): \(errorMessage)"); return
            }
            newId = sqlite3_last_insert_rowid(db)
        }
        return newId
    }

    func fetchAllDetections() -> [Detection] { fetch(where: nil) }

    func fetchUnsyncedDetections() -> [Detection] { fetch(where: "synced = 0") }

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

    private func fetch(where condition: String?) -> [Detection] {
        var results: [Detection] = []
        queue.sync {
            let whereClause = condition.map { "WHERE \($0)" } ?? ""
            let sql = """
            SELECT id, vehicleLabel, confidence, timestamp, synced, audioSampleId
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
                results.append(Detection(
                    id:            sqlite3_column_int64(stmt, 0),
                    vehicleLabel:  String(cString: sqlite3_column_text(stmt, 1)),
                    confidence:    sqlite3_column_double(stmt, 2),
                    timestamp:     String(cString: sqlite3_column_text(stmt, 3)),
                    synced:        Int(sqlite3_column_int(stmt, 4)),
                    audioSampleId: audioId
                ))
            }
        }
        return results
    }

    // MARK: - Streak Query

    /// Returns the number of consecutive calendar days (ending today) that
    /// have at least one detection. Used for the streak_3 badge.
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
        while true {
            let key = fmt.string(from: day)
            if dates.contains(key) {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else {
                break
            }
        }
        return streak
    }
}

// MARK: - Badge CRUD

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
    func earnBadge(id: String) -> Bool {
        var wasNew = false
        queue.sync {
            // First check if badge row exists and is unearned
            let checkSQL = "SELECT earned FROM badges WHERE id = ?;"
            var checkStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(checkStmt, 1, id, -1, transient)
                let stepResult = sqlite3_step(checkStmt)
                if stepResult == SQLITE_ROW {
                    let currentEarned = sqlite3_column_int(checkStmt, 0)
                    wasNew = currentEarned == 0
                    print("DB earnBadge(\(id)): found row, earned=\(currentEarned), wasNew=\(wasNew)")
                } else {
                    print("DB earnBadge(\(id)): NO ROW FOUND — badge not seeded! step=\(stepResult)")
                }
            } else {
                print("DB earnBadge(\(id)): prepare failed — \(errorMessage)")
            }
            sqlite3_finalize(checkStmt)
            guard wasNew else { return }

            let earnedAt = ISO8601DateFormatter().string(from: Date())
            let sql = "UPDATE badges SET earned = 1, earnedAt = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (earnBadge prepare): \(errorMessage)"); wasNew = false; return
            }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, earnedAt, -1, transient)
            sqlite3_bind_text(stmt, 2, id,       -1, transient)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("DB error (earnBadge step): \(errorMessage)"); wasNew = false
            } else {
                print("DB earnBadge(\(id)): EARNED at \(earnedAt)")
            }
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
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(stmt, 1, item.id,       -1, transient)
                sqlite3_bind_text(stmt, 2, item.earnedAt, -1, transient)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    /// Resets all badges to unearned. Called on logout so the next user
    /// starts with a clean slate before their badges sync from Firestore.
    func resetAllBadges() {
        queue.sync {
            let sql = "UPDATE badges SET earned = 0, earnedAt = NULL;"
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                print("DB error (resetAllBadges): \(errorMessage)")
            } else {
                print("DB: all badges reset to unearned")
            }
        }
    }

    /// Deletes all detections. Called on logout.
    func resetAllDetections() {
        queue.sync {
            let sql = "DELETE FROM detections;"
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                print("DB error (resetAllDetections): \(errorMessage)")
            } else {
                print("DB: all detections deleted")
            }
        }
    }

    /// Deletes all audio samples. Called on logout.
    func resetAllAudioSamples() {
        queue.sync {
            let sql = "DELETE FROM audioSamples;"
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                print("DB error (resetAllAudioSamples): \(errorMessage)")
            } else {
                print("DB: all audio samples deleted")
            }
        }
    }

    /// Wipes all user data from local DB. Called on logout so the next
    /// account starts with a clean slate.
    func resetAllUserData() {
        resetAllBadges()
        resetAllDetections()
        resetAllAudioSamples()
        print("DB: all user data reset for logout")
    }
}

// MARK: - Audio Sample CRUD

extension DatabaseManager {

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
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text  (stmt, 1,  sample.vehicleLabel, -1, t)
            sqlite3_bind_double(stmt, 2,  sample.confidence)
            sqlite3_bind_double(stmt, 3,  sample.audioDuration)
            sqlite3_bind_text  (stmt, 4,  sample.engineAudible.rawValue, -1, t)
            sqlite3_bind_text  (stmt, 5,  sample.recordingContext.rawValue, -1, t)
            sqlite3_bind_text  (stmt, 6,  sample.vehicleState.rawValue, -1, t)
            sqlite3_bind_text  (stmt, 7,  sample.backgroundNoise.rawValue, -1, t)
            sqlite3_bind_text  (stmt, 8,  sample.userNotes, -1, t)
            sqlite3_bind_text  (stmt, 9,  sample.localFilePath, -1, t)
            if let fbPath = sample.firebaseStoragePath {
                sqlite3_bind_text(stmt, 10, fbPath, -1, t)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_bind_text(stmt, 11, sample.timestamp, -1, t)
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
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text (stmt, 1, storagePath, -1, t)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    private func audioSampleFromRow(_ stmt: OpaquePointer?) -> AudioSample {
        let fbPath: String? = sqlite3_column_type(stmt, 10) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt!, 10)) : nil
        return AudioSample(
            id:                  sqlite3_column_int64(stmt!, 0),
            vehicleLabel:        String(cString: sqlite3_column_text(stmt!, 1)),
            confidence:          sqlite3_column_double(stmt!, 2),
            audioDuration:       sqlite3_column_double(stmt!, 3),
            engineAudible:       EngineAudible(rawValue: String(cString: sqlite3_column_text(stmt!, 4))) ?? .unsure,
            recordingContext:    RecordingContext(rawValue: String(cString: sqlite3_column_text(stmt!, 5))) ?? .other,
            vehicleState:        VehicleState(rawValue: String(cString: sqlite3_column_text(stmt!, 6))) ?? .unknown,
            backgroundNoise:     NoiseLevel(rawValue: String(cString: sqlite3_column_text(stmt!, 7))) ?? .moderate,
            userNotes:           String(cString: sqlite3_column_text(stmt!, 8)),
            localFilePath:       String(cString: sqlite3_column_text(stmt!, 9)),
            firebaseStoragePath: fbPath,
            timestamp:           String(cString: sqlite3_column_text(stmt!, 11)),
            synced:              Int(sqlite3_column_int(stmt!, 12))
        )
    }
}
