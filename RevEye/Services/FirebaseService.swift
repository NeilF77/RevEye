//
//  FirebaseService.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//  Updated 10/03/2026 — added audio upload (Firebase Storage + Firestore metadata)

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Network

final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // Monitors network reachability so we know when to attempt retries
    private let monitor = NWPathMonitor()
    private var isOnline = false

    private init() {
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

    // MARK: - Detection Upload

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
                if let error {
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

    // MARK: - Audio Upload

    /// Uploads an audio file to Firebase Storage and creates a Firestore metadata document.
    /// - Parameters:
    ///   - sample: The local AudioSample with metadata.
    ///   - completion: Called on main thread with `true` on success.
    func uploadAudio(_ sample: AudioSample, completion: ((Bool) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid,
              let sampleId = sample.id else {
            completion?(false); return
        }

        let localURL = URL(fileURLWithPath: sample.localFilePath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            print("Audio file not found at: \(localURL.path)")
            completion?(false)
            return
        }

        // Storage path: audio/{userId}/{sampleId}_{timestamp}.m4a
        let storagePath = "audio/\(uid)/\(sampleId)_\(sample.timestamp).m4a"
        let storageRef = storage.reference().child(storagePath)

        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"

        storageRef.putFile(from: localURL, metadata: metadata) { [weak self] _, error in
            if let error {
                print("Audio upload error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            // File uploaded — now create the Firestore metadata document
            var firestoreData = sample.firestoreData
            firestoreData["userId"] = uid
            firestoreData["audioStoragePath"] = storagePath

            self?.db.collection("audioSamples").addDocument(data: firestoreData) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("Audio Firestore error: \(error.localizedDescription)")
                        completion?(false)
                    } else {
                        print("Audio uploaded: \(storagePath)")
                        DatabaseManager.shared.markAudioAsSynced(id: sampleId, storagePath: storagePath)
                        completion?(true)
                    }
                }
            }
        }
    }

    // MARK: - Auto-retry on reconnect

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
