//
//  DatabaseManager.swift
//  RevEye
//

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    
    private init() {
        openDatabase()
        createTables()
    }
    
    // Open (or create) the SQLite database in the app’s Documents directory.
    private func openDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("reveyedb.sqlite")
        
        // Try to open the database. If it doesn't exist yet, SQLite will create it.
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error: could not open SQLite database")
        } else {
            print("Database opened at: \(fileURL.path)")
        }
    }
    
    // Create the necessary tables if they do not already exist.
    private func createTables() {
        // Table for storing vehicle detection results
        let detectionsTable = """
        CREATE TABLE IF NOT EXISTS detections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            localFilePath TEXT,
            vehicleModel TEXT,
            confidence REAL,
            timestamp TEXT,
            synced INTEGER DEFAULT 0
        );
        """
        
        // Table for storing badges earned by the user
        let badgesTable = """
        CREATE TABLE IF NOT EXISTS badges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            badgeName TEXT,
            description TEXT,
            earnedDate TEXT
        );
        """
        
        // Table for keeping track of media files that need to be uploaded later
        let pendingUploadsTable = """
        CREATE TABLE IF NOT EXISTS pending_uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            localFilePath TEXT,
            mediaType TEXT,
            createdAt TEXT
        );
        """
        
        // Execute the SQL commands to create the tables
        sqlite3_exec(db, detectionsTable, nil, nil, nil)
        sqlite3_exec(db, badgesTable, nil, nil, nil)
        sqlite3_exec(db, pendingUploadsTable, nil, nil, nil)
        
        print("SQLite tables are ready")
    }
}

// MARK: - Detection helpers
extension DatabaseManager {

    func insertDetection(_ detection: Detection) -> Int64? {
        let sql = """
        INSERT INTO detections (localFilePath, vehicleModel, confidence, timestamp, synced)
        VALUES (?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing insert: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }

        sqlite3_bind_text(stmt, 1, (detection.localFilePath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (detection.vehicleLabel as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, detection.confidence)
        sqlite3_bind_text(stmt, 4, (detection.timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 5, Int32(detection.synced))

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Error inserting detection: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_finalize(stmt)
            return nil
        }

        sqlite3_finalize(stmt)
        let newId = sqlite3_last_insert_rowid(db)
        print("Inserted detection with id \(newId)")
        return newId
    }

    func fetchAllDetections() -> [Detection] {
        let sql = """
        SELECT id, localFilePath, vehicleModel, confidence, timestamp, synced
        FROM detections
        ORDER BY id DESC;
        """

        var stmt: OpaquePointer?
        var results: [Detection] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing select: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id        = sqlite3_column_int64(stmt, 0)
            let path      = String(cString: sqlite3_column_text(stmt, 1))
            let label     = String(cString: sqlite3_column_text(stmt, 2))
            let conf      = sqlite3_column_double(stmt, 3)
            let ts        = String(cString: sqlite3_column_text(stmt, 4))
            let syncedVal = Int(sqlite3_column_int(stmt, 5))

            let det = Detection(
                id: id,
                localFilePath: path,
                vehicleLabel: label,
                confidence: conf,
                timestamp: ts,
                synced: syncedVal
            )
            results.append(det)
        }

        sqlite3_finalize(stmt)
        return results
    }
}


