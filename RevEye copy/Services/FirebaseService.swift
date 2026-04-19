// FirebaseService.swift
// RevEye
//
// Handles uploading detections and audio samples to Firebase Firestore.
// Uses NWPathMonitor to watch for network connectivity changes and
// automatically uploads any pending detections when the device comes
// back online. This is a singleton accessed via FirebaseService.shared.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Network

final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    // Network monitor to detect online/offline transitions
    private let monitor = NWPathMonitor()
    private var isOnline = false

    private init() {
    // Watch for network changes. When the device goes from offline to online,
    // automatically try to upload any detections that are still pending.
        monitor.pathUpdateHandler = { [weak self] path in
            let wasOffline = !(self?.isOnline ?? true)
            self?.isOnline = path.status == .satisfied
            if wasOffline && self?.isOnline == true { self?.syncAllUnsynced() }
        }
        monitor.start(queue: DispatchQueue(label: "com.reveye.network"))
    }

    // Uploads a single detection to the "detections" Firestore collection.
    // On success, marks the local SQLite record as synced so it won't be uploaded again.
    func uploadDetection(_ detection: Detection, source: SourceType = .photo,
                         completion: ((Bool) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(false); return
        }

        db.collection("detections").addDocument(data: [
            "userId":       uid,
            "vehicleLabel": detection.vehicleLabel,
            "confidence":   detection.confidence,
            "timestamp":    detection.timestamp,
            "sourceType":   source.rawValue
        ]) { error in
            DispatchQueue.main.async {
                if error != nil {
                    print("Firebase upload error: \(error!.localizedDescription)")
                    completion?(false)
                } else {
                    print("Uploaded: \(detection.vehicleLabel) (\(source.rawValue))")
                    if let id = detection.id {
                        DatabaseManager.shared.markAsSynced(id: id)
                    }
                    completion?(true)
                }
            }
        }
    }

    // Downloads all detections for the current user from Firestore and
    // inserts them into the local SQLite database. Called on sign-in so
    // the user's history is restored after signing out and back in.
    func downloadDetections(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(); return
        }

        db.collection("detections")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                if let error {
                    print("Firebase download error: \(error.localizedDescription)")
                    completion?()
                    return
                }

                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    print("No detections found in Firebase for this user")
                    completion?()
                    return
                }

                let localManager = DatabaseManager.shared
                var restored = 0

                for doc in docs {
                    let data = doc.data()
                    let label = data["vehicleLabel"] as? String ?? "Unknown"
                    let confidence = data["confidence"] as? Double ?? 0
                    let timestamp = data["timestamp"] as? String
                        ?? ISO8601DateFormatter().string(from: Date())

                    let detection = Detection(
                        id: nil,
                        vehicleLabel: label,
                        confidence: confidence,
                        timestamp: timestamp,
                        synced: 1,          // already in Firebase, no need to re-upload
                        audioSampleId: nil
                    )

                    if localManager.insertDetection(detection) != nil {
                        restored += 1
                    }
                }

                print("Restored \(restored) detections from Firebase")
                completion?()
            }
    }

    // Audio Upload (base64 in Firestore)

    // Reads the local M4A file, base64-encodes it, and stores it directly
    // in a Firestore document alongside all metadata. No Firebase Storage
    // (Blaze plan) required. Researchers can browse the audioSamples
    // collection in the Firebase Console and see everything.
    //
    // Typical M4A size: 30-100KB -> base64: 40-135KB. Well within the
    // Firestore 1MB document limit.
    func uploadAudio(_ sample: AudioSample, completion: ((Bool) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid,
              let sampleId = sample.id else {
            completion?(false); return
        }

        let localURL = URL(fileURLWithPath: sample.localFilePath)
        guard FileManager.default.fileExists(atPath: localURL.path),
              let audioData = try? Data(contentsOf: localURL) else {
            completion?(false)
            return
        }

        let base64Audio = audioData.base64EncodedString()

        var firestoreData = sample.firestoreData
        firestoreData["userId"] = uid
        firestoreData["audioBase64"] = base64Audio       // actual audio data
        firestoreData["audioFormat"] = "m4a"             // so researchers know the format
        firestoreData["audioFileSizeBytes"] = audioData.count

        db.collection("audioSamples").addDocument(data: firestoreData) { error in
            DispatchQueue.main.async {
                if error != nil {
                    completion?(false)
                } else {
                    DatabaseManager.shared.markAudioAsSynced(id: sampleId, storagePath: "firestore_base64")
                    completion?(true)
                }
            }
        }
    }

    // Auto-retry on reconnect

    private func syncAllUnsynced() {
        let unsynced = DatabaseManager.shared.fetchUnsyncedDetections()
        for det in unsynced { uploadDetection(det, source: .photo) }
    }
}

enum SourceType: String {
    case photo = "photo"
    case video = "video"
}
