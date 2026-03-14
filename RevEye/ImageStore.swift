//
//  ImageStore.swift
//  RevEye
//
//  Created by user on 14/03/2026.
//


//
//  ImageStore.swift
//  RevEye
//
//  Created 14/03/2026 — saves detection images to disk

import UIKit

/// Saves and loads detection images from the app's documents directory.
/// Images are stored as `detection_images/{detectionId}.jpg`.
/// No database changes needed — existence of the file IS the record.
struct ImageStore {

    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("detection_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Save a UIImage for a detection ID. Returns true on success.
    @discardableResult
    static func save(_ image: UIImage, for detectionId: Int64) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return false }
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        do {
            try data.write(to: url)
            return true
        } catch {
            print("ImageStore save error: \(error.localizedDescription)")
            return false
        }
    }

    /// Load the image for a detection ID. Returns nil if no image saved.
    static func load(for detectionId: Int64) -> UIImage? {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Check if an image exists for a detection ID.
    static func exists(for detectionId: Int64) -> Bool {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Delete the image for a detection ID.
    static func delete(for detectionId: Int64) {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete all saved images. Called on logout.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        print("ImageStore: all images deleted")
    }
}