//
//  DatabaseManager.swift
//  RevEye
//

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
        // Create the table using vehicleLabel if it doesn't exist yet (fresh installs)
        let createSQL = """
        CREATE TABLE IF NOT EXISTS detections (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel TEXT    NOT NULL,
            confidence   REAL    NOT NULL,
            timestamp    TEXT    NOT NULL,
            synced       INTEGER NOT NULL DEFAULT 0
        );
        """
        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            print("DB error: could not create detections table — \(errorMessage)")
        } else {
            print("detections table ready")
        }

        // Migration: existing installs have the column named "vehicleModel".
        // SQLite doesn't support RENAME COLUMN before version 3.25, so we check
        // whether vehicleLabel already exists — if not, we recreate the table with
        // the correct column name and copy all existing rows across.
        migrateVehicleModelColumnIfNeeded()
    }

    private func migrateVehicleModelColumnIfNeeded() {
        // Check existing column names via PRAGMA
        let pragma = "PRAGMA table_info(detections);"
        var stmt: OpaquePointer?
        var hasVehicleLabel = false

        if sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 1) {
                    let name = String(cString: cName)
                    if name == "vehicleLabel" {
                        hasVehicleLabel = true
                    }
                }
            }
        }
        sqlite3_finalize(stmt)

        guard !hasVehicleLabel else {
            // Column already correct — nothing to do
            return
        }

        print("DB migration: renaming vehicleModel → vehicleLabel")

        // Recreate the table with the correct column name and copy data across
        let migration = """
        BEGIN TRANSACTION;

        CREATE TABLE detections_new (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicleLabel TEXT    NOT NULL,
            confidence   REAL    NOT NULL,
            timestamp    TEXT    NOT NULL,
            synced       INTEGER NOT NULL DEFAULT 0
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
            print("DB migration complete — vehicleModel renamed to vehicleLabel")
        }
    }

    // Reads the last SQLite error as a Swift String
    private var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - Detection CRUD

extension DatabaseManager {

    /// Inserts a detection and returns its new auto-generated ID, or nil on failure.
    /// Safe to call from any thread.
    func insertDetection(_ detection: Detection) -> Int64? {
        var newId: Int64?
        queue.sync {
            let sql = """
            INSERT INTO detections (vehicleLabel, confidence, timestamp, synced)
            VALUES (?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (insert prepare): \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            // SQLITE_TRANSIENT tells SQLite to copy the string — safe when the Swift
            // string may be released before SQLite finishes with it.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text  (stmt, 1, detection.vehicleLabel, -1, transient)
            sqlite3_bind_double(stmt, 2, detection.confidence)
            sqlite3_bind_text  (stmt, 3, detection.timestamp,    -1, transient)
            sqlite3_bind_int   (stmt, 4, Int32(detection.synced))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("DB error (insert step): \(errorMessage)")
                return
            }
            newId = sqlite3_last_insert_rowid(db)
        }
        return newId
    }

    /// Returns every detection, newest first.
    func fetchAllDetections() -> [Detection] {
        fetch(where: nil)
    }

    /// Returns only detections that haven't been synced to Firebase yet.
    func fetchUnsyncedDetections() -> [Detection] {
        fetch(where: "synced = 0")
    }

    /// Marks a single detection as synced in the local database.
    func markAsSynced(id: Int64) {
        queue.sync {
            let sql = "UPDATE detections SET synced = 1 WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (markAsSynced prepare): \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("DB error (markAsSynced step): \(errorMessage)")
            }
        }
    }

    /// Permanently deletes a detection by ID.
    func deleteDetection(id: Int64) {
        queue.sync {
            let sql = "DELETE FROM detections WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (delete prepare): \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("DB error (delete step): \(errorMessage)")
            }
        }
    }

    // MARK: - Private fetch helper

    /// Shared row-reading logic used by fetchAllDetections and fetchUnsyncedDetections.
    /// Pass a SQL WHERE clause (without the keyword), or nil for all rows.
    private func fetch(where condition: String?) -> [Detection] {
        var results: [Detection] = []
        queue.sync {
            let whereClause = condition.map { "WHERE \($0)" } ?? ""
            let sql = """
            SELECT id, vehicleLabel, confidence, timestamp, synced
            FROM detections
            \(whereClause)
            ORDER BY id DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("DB error (fetch prepare): \(errorMessage)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Detection(
                    id:           sqlite3_column_int64 (stmt, 0),
                    vehicleLabel: String(cString: sqlite3_column_text(stmt, 1)),
                    confidence:   sqlite3_column_double(stmt, 2),
                    timestamp:    String(cString: sqlite3_column_text(stmt, 3)),
                    synced:       Int(sqlite3_column_int(stmt, 4))
                ))
            }
        }
        return results
    }
}
