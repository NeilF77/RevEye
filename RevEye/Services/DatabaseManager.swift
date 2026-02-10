//
//  DatabaseManager.swift
//  RevEye
//

import Foundation
import SQLite3

// Manages SQLite database operations for storing vehicle detections locally
class DatabaseManager {
    static let shared = DatabaseManager() // Singleton - only one database instance needed
    private var db: OpaquePointer? // Pointer to the SQLite database
    
    // Private init ensures only one instance exists (singleton pattern)
    private init() {
        openDatabase()
        createTables()
    }
    
    // Opens (or creates) the SQLite database in the app's Documents directory
    private func openDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("reveyedb.sqlite")
        
        // Try to open the database - creates it if it doesn't exist yet
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error: could not open SQLite database")
        } else {
            print("Database opened at: \(fileURL.path)")
        }
    }
    
    // Creates the necessary tables if they don't already exist
    private func createTables() {
        // Table for storing vehicle detection results
        let detectionsTable = """
        CREATE TABLE IF NOT EXISTS detections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        
        // Table for tracking media files that need to be uploaded later
        let pendingUploadsTable = """
        CREATE TABLE IF NOT EXISTS pending_uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
    
    // Inserts a new detection into the database and returns its auto-generated ID
    func insertDetection(_ detection: Detection) -> Int64? {
        let sql = """
        INSERT INTO detections (vehicleModel, confidence, timestamp, synced)
        VALUES (?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        // Prepare the SQL statement - compiles SQL into bytecode
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing insert: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        
        // Bind values to the SQL placeholders (?)
        // SQLite bind indexes start at 1, matching the order of VALUES
        // 1: vehicleModel (TEXT)
        sqlite3_bind_text(stmt, 1, (detection.vehicleLabel as NSString).utf8String, -1, nil)
        // 2: confidence (REAL)
        sqlite3_bind_double(stmt, 2, detection.confidence)
        // 3: timestamp (TEXT)
        sqlite3_bind_text(stmt, 3, (detection.timestamp as NSString).utf8String, -1, nil)
        // 4: synced (INTEGER)
        sqlite3_bind_int(stmt, 4, Int32(detection.synced))
        
        // Execute the INSERT statement, SQLITE_DONE means success
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Error inserting detection: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_finalize(stmt)
            return nil
        }
        
        // Clean up the statement to free memory
        sqlite3_finalize(stmt)
        // Get the auto-generated ID from the INSERT
        let newId = sqlite3_last_insert_rowid(db)
        print("Inserted detection with id \(newId)")
        return newId
    }
    
    // Retrieves all detections from the database, ordered by newest first
    func fetchAllDetections() -> [Detection] {
        let sql = """
        SELECT id, vehicleModel, confidence, timestamp, synced
        FROM detections
        ORDER BY id DESC;
        """
        
        var stmt: OpaquePointer?
        var results: [Detection] = []
        
        // Prepare the SELECT query
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing select: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        
        // Loop through each row returned from the query
        // SQLITE_ROW means there's more data to read
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Extract column values - column indexes start at 0
            // 0: id (INTEGER)
            let id = sqlite3_column_int64(stmt, 0)
            // 1: vehicleModel (TEXT)
            let label = String(cString: sqlite3_column_text(stmt, 1))
            // 2: confidence (REAL)
            let conf = sqlite3_column_double(stmt, 2)
            // 3: timestamp (TEXT)
            let ts = String(cString: sqlite3_column_text(stmt, 3))
            // 4: synced (INTEGER)
            let syncedVal = Int(sqlite3_column_int(stmt, 4))
            
            // Create Detection object from row data
            let det = Detection(
                id: id,
                vehicleLabel: label,
                confidence: conf,
                timestamp: ts,
                synced: syncedVal
            )
            results.append(det)
        }
        
        // Clean up statement
        sqlite3_finalize(stmt)
        return results
    }
    
    // Updates a detection to mark it as synced to Firebase
    func markAsSynced(id: Int64) {
        let sql = "UPDATE detections SET synced = 1 WHERE id = ?;"
        var stmt: OpaquePointer?
        
        // Prepare the UPDATE statement
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing markAsSynced: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
       
        // Bind the id value to the WHERE clause placeholder
        sqlite3_bind_int64(stmt, 1, id)
        
        // Execute the UPDATE
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Error executing markAsSynced: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Clean up statement
        sqlite3_finalize(stmt)
    }
    // Retrieves all detections that have not yet been synced to Firebase
    func fetchUnsyncedDetections() -> [Detection] {
        let sql = """
        SELECT id, vehicleModel, confidence, timestamp, synced
        FROM detections
        WHERE synced = 0
        ORDER BY id DESC;
        """

        var stmt: OpaquePointer?
        var results: [Detection] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("Error preparing fetchUnsynced: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let label = String(cString: sqlite3_column_text(stmt, 1))
            let conf = sqlite3_column_double(stmt, 2)
            let ts = String(cString: sqlite3_column_text(stmt, 3))
            let syncedVal = Int(sqlite3_column_int(stmt, 4))

            let det = Detection(
                id: id,
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
