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

    /// Uploads a detection to Firestore and marks it as synced locally on success.
    /// - Parameters:
    ///   - detection: The detection to upload.
    ///   - sourceType: Where the detection came from — `.photo` or `.video`.
    func uploadDetection(_ detection: Detection, source: SourceType = .photo) {
        db.collection("detections").addDocument(data: [
            "vehicleLabel": detection.vehicleLabel,
            "confidence":   detection.confidence,
            "timestamp":    detection.timestamp,
            "sourceType":   source.rawValue
        ]) { error in
            if let error = error {
                print("Firebase upload error: \(error.localizedDescription)")
            } else {
                print("Uploaded \(detection.vehicleLabel) (\(source.rawValue)) to Firestore")
                if let id = detection.id {
                    DatabaseManager.shared.markAsSynced(id: id)
                }
            }
        }
    }
}

// Describes where a detection originated
enum SourceType: String {
    case photo = "photo"
    case video = "video"
}
