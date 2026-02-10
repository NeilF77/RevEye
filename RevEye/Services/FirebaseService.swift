//
//  FirebaseService.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//


import Foundation
import FirebaseFirestore

// Handles uploading vehicle detection data to Firebase Firestore
final class FirebaseService {
    static let shared = FirebaseService() // only one Firebase service instance needed
    private let db = Firestore.firestore() // Reference to Firestore database

    // Private init ensures only one instance exists
    private init() {}

    // Uploads a detection to Firestore and marks it as synced in local database
    func uploadDetection(_ detection: Detection) {
        // Add new document to "detections" collection with auto-generated ID
        db.collection("detections").addDocument(data: [
            "vehicleLabel": detection.vehicleLabel,
            "confidence": detection.confidence,
            "timestamp": detection.timestamp,
            "sourceType": "photo",   // later send "video" for video-based detections
            "imageUrl": NSNull(),    // will be replaced with a Storage URL once upload images
            "audioUrl": NSNull()     // will be replaced with a Storage URL once upload audio
        ]) { error in
            // Completion handler called after upload attempt finishes

            if let error = error {
                print("Error uploading detection: \(error)")
            } else {
                print("Uploaded detection to Firestore")
                
                // Mark the local row as synced so you keep it for history.
                if let id = detection.id {
                    DatabaseManager.shared.markAsSynced(id: id)
                }
            }
        }
    }
}
