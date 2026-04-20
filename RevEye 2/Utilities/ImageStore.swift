// ImageStore.swift
// RevEye
//
// Handles saving, loading, and deleting detection images on disk.
// Each image is stored as a JPEG file named by its detection ID inside
// the "detection_images" folder in the app's documents directory.
// No database entries needed - if the file exists, the image exists.

import UIKit

struct ImageStore {

    // The folder where all detection images are stored
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("detection_images", isDirectory: true)
        // Create the folder if it doesn't exist yet
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Save a UIImage as a compressed JPEG for the given detection ID
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

    // Load the saved image for a detection, or nil if none exists
    static func load(for detectionId: Int64) -> UIImage? {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // Check whether an image has been saved for this detection
    static func exists(for detectionId: Int64) -> Bool {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        return FileManager.default.fileExists(atPath: url.path)
    }

    // Delete the image for a specific detection
    static func delete(for detectionId: Int64) {
        let url = directory.appendingPathComponent("\(detectionId).jpg")
        try? FileManager.default.removeItem(at: url)
    }

    // Delete all saved images. Called when the user signs out.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
