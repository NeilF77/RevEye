// ImageStore.swift
// RevEye
//
// Handles saving, loading, and deleting detection images on disk.
// Each image is stored as a JPEG file named by a stable UUID (the
// detection's imageKey) inside a per-user subfolder:
//   detection_images/<uid>/<imageKey>.jpg
//
// Scoping by uid keeps one account's images invisible to another, and
// naming by imageKey (rather than the SQLite id) lets images survive
// sign-out/sign-in even though the local database is wiped and rebuilt
// from Firestore with new auto-increment ids.

import UIKit
import FirebaseAuth

struct ImageStore {

    // Root folder that holds every user's image subfolder.
    private static var rootDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("detection_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Current signed-in user's image folder. Returns nil if nobody is signed in.
    private static func directory(for uid: String) -> URL {
        let dir = rootDirectory.appendingPathComponent(uid, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var currentUid: String? { Auth.auth().currentUser?.uid }

    private static func fileURL(for key: String, uid: String) -> URL {
        directory(for: uid).appendingPathComponent("\(key).jpg")
    }

    // Save a UIImage as a compressed JPEG for the given image key.
    // Silently fails if no user is signed in (images are per-account).
    @discardableResult
    static func save(_ image: UIImage, forKey key: String) -> Bool {
        guard let uid = currentUid else { return false }
        guard let data = image.jpegData(compressionQuality: 0.7) else { return false }
        let url = fileURL(for: key, uid: uid)
        do {
            try data.write(to: url)
            return true
        } catch {
            print("ImageStore save error: \(error.localizedDescription)")
            return false
        }
    }

    // Load the saved image for the given key, or nil if none exists.
    static func load(forKey key: String?) -> UIImage? {
        guard let key, let uid = currentUid else { return nil }
        let url = fileURL(for: key, uid: uid)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // Check whether an image has been saved for this key.
    static func exists(forKey key: String?) -> Bool {
        guard let key, let uid = currentUid else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: key, uid: uid).path)
    }

    // Delete the image for a specific key.
    static func delete(forKey key: String?) {
        guard let key, let uid = currentUid else { return }
        try? FileManager.default.removeItem(at: fileURL(for: key, uid: uid))
    }

    // Delete every image belonging to the current signed-in user. Called
    // when the user deletes their account (not on plain sign-out - images
    // need to persist across sign-out/sign-in for the same account).
    static func deleteAllForCurrentUser() {
        guard let uid = currentUid else { return }
        deleteAll(forUid: uid)
    }

    // Delete every image belonging to the given uid. Exposed separately so
    // callers (e.g. account deletion) can capture the uid before signing out.
    static func deleteAll(forUid uid: String) {
        try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(uid, isDirectory: true))
    }
}
