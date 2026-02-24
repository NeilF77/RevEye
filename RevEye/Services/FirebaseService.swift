//
//  FirebaseService.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//

import Foundation
import FirebaseFirestore
import Network

final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    // Monitors network reachability so we know when to attempt retries
    private let monitor = NWPathMonitor()
    private var isOnline = false

    private init() {
        // Watch for connectivity changes and auto-sync any unsynced detections
        // when the device comes back online
        monitor.pathUpdateHandler = { [weak self] path in
            let wasOffline = !(self?.isOnline ?? true)
            self?.isOnline = path.status == .satisfied
            if wasOffline && self?.isOnline == true {
                print("Network restored — syncing pending detections")
                self?.syncAllUnsynced()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.reveye.network"))
    }

    // MARK: - Upload

    /// Uploads a detection to Firestore.
    /// - Parameters:
    ///   - detection: The detection to upload.
    ///   - source: Whether it came from a photo or video.
    ///   - completion: Called on the main thread with `true` on success, `false` on failure.
    func uploadDetection(_ detection: Detection, source: SourceType = .photo,
                         completion: ((Bool) -> Void)? = nil) {
        db.collection("detections").addDocument(data: [
            "vehicleLabel": detection.vehicleLabel,
            "confidence":   detection.confidence,
            "timestamp":    detection.timestamp,
            "sourceType":   source.rawValue
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Firebase upload error: \(error.localizedDescription)")
                    completion?(false)
                } else {
                    print("Uploaded \(detection.vehicleLabel) (\(source.rawValue))")
                    if let id = detection.id {
                        DatabaseManager.shared.markAsSynced(id: id)
                    }
                    completion?(true)
                }
            }
        }
    }

    // MARK: - Auto-retry on reconnect

    /// Called automatically when the device comes back online.
    /// Uploads all locally stored unsynced detections.
    private func syncAllUnsynced() {
        let unsynced = DatabaseManager.shared.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else { return }
        print("Auto-syncing \(unsynced.count) pending detection(s)")
        for det in unsynced {
            uploadDetection(det, source: .photo)
        }
    }
}

// Describes where a detection originated
enum SourceType: String {
    case photo = "photo"
    case video = "video"
}
