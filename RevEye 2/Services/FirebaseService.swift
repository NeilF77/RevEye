// FirebaseService.swift
// RevEye
//
// Uploads detections and audio samples to Firestore, and restores a user's
// detections from Firestore on sign-in. An NWPathMonitor watches for the
// device coming back online and retries anything that's still marked
// unsynced in the local DB. Singleton, accessed via FirebaseService.shared.

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
                if let error {
                    print("Firebase upload error: \(error.localizedDescription)")
                    completion?(false)
                    return
                }
                print("Uploaded: \(detection.vehicleLabel) (\(source.rawValue))")
                if let id = detection.id {
                    DatabaseManager.shared.markAsSynced(id: id)
                }
                completion?(true)
            }
        }
    }

    // Pulls the signed-in user's detections back from Firestore and writes
    // them into the local DB. Called on sign-in so that if someone signs out
    // and back in (or runs the app on a new device) their history reappears.
    //
    // Wipes the local detections table first so the same call can safely be
    // run more than once without producing duplicate rows.
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
                // Clear first so re-runs don't produce duplicates.
                localManager.resetAllDetections()

                var restored = 0
                for doc in docs {
                    let data = doc.data()
                    let label = data["vehicleLabel"] as? String ?? "Unknown"
                    let confidence = data["confidence"] as? Double ?? 0
                    let timestamp = data["timestamp"] as? String
                        ?? ISO8601DateFormatter().string(from: Date())

                    // synced = 1 because these came straight from Firebase;
                    // no point sending them straight back up.
                    let detection = Detection(
                        id: nil,
                        vehicleLabel: label,
                        confidence: confidence,
                        timestamp: timestamp,
                        synced: 1,
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

        let localURL = AudioExtractor.resolvedURL(for: sample.localFilePath)
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
                if let error {
                    print("Firebase audio upload error: \(error.localizedDescription)")
                    completion?(false)
                    return
                }
                DatabaseManager.shared.markAudioAsSynced(id: sampleId, storagePath: "firestore_base64")
                completion?(true)
            }
        }
    }

    // Auto-retry on reconnect

    private func syncAllUnsynced() {
        let unsynced = DatabaseManager.shared.fetchUnsyncedDetections()
        for det in unsynced { uploadDetection(det, source: .photo) }
    }

    // Delete Account support

    // Removes everything in Firestore that belongs to the signed-in user:
    // their detections, their audio contributions, their badges, and their
    // user document. Must be called before Auth.user.delete(), otherwise
    // the security rules will reject the writes.
    //
    // Done in batches of up to 500 deletes per WriteBatch (Firestore's limit).
    // Calls completion on the main queue once everything has been attempted.
    func deleteAllCloudData(completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(nil); return
        }

        // Collect the queries we need to clear out.
        let group = DispatchGroup()
        var firstError: Error?

        // Top-level collections filtered by userId.
        for collection in ["detections", "audioSamples"] {
            group.enter()
            db.collection(collection)
                .whereField("userId", isEqualTo: uid)
                .getDocuments { snapshot, error in
                    if let error {
                        firstError = firstError ?? error
                        group.leave()
                        return
                    }
                    self.batchDelete(snapshot?.documents ?? []) { err in
                        if let err { firstError = firstError ?? err }
                        group.leave()
                    }
                }
        }

        // Badges live in a subcollection under the user doc.
        group.enter()
        db.collection("users").document(uid).collection("badges")
            .getDocuments { snapshot, error in
                if let error {
                    firstError = firstError ?? error
                    group.leave()
                    return
                }
                self.batchDelete(snapshot?.documents ?? []) { err in
                    if let err { firstError = firstError ?? err }
                    group.leave()
                }
            }

        // Then the user doc itself.
        group.notify(queue: .main) {
            self.db.collection("users").document(uid).delete { error in
                completion(firstError ?? error)
            }
        }
    }

    // Helper: delete documents in batches of 500 (Firestore's batch limit).
    private func batchDelete(_ docs: [QueryDocumentSnapshot],
                             completion: @escaping (Error?) -> Void) {
        guard !docs.isEmpty else { completion(nil); return }

        let chunks = stride(from: 0, to: docs.count, by: 500).map {
            Array(docs[$0 ..< min($0 + 500, docs.count)])
        }

        let group = DispatchGroup()
        var firstError: Error?
        for chunk in chunks {
            group.enter()
            let batch = db.batch()
            for doc in chunk { batch.deleteDocument(doc.reference) }
            batch.commit { error in
                if let error { firstError = firstError ?? error }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(firstError) }
    }
}

enum SourceType: String {
    case photo = "photo"
    case video = "video"
}
