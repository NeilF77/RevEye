//
//  FirebaseService.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//


import Foundation
import FirebaseFirestore

final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    private init() {}

    func syncUnsyncedDetections() {
        let all = DatabaseManager.shared.fetchAllDetections()
        let unsynced = all.filter { $0.synced == 0 }
        print("Would sync \(unsynced.count) detections to Firestore")
        // we’ll fill in the actual upload logic next
    }
}
