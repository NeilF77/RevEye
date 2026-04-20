// Detection.swift
// RevEye
//
// Represents a single vehicle detection saved by the user.
// Stored in the local SQLite database and synced to Firebase.

import Foundation

struct Detection: Identifiable {
    var id: Int64?              // SQLite primary key (auto-incremented)
    var vehicleLabel: String    // The predicted vehicle name, e.g. "BMW 3 Series"
    var confidence: Double      // ML model confidence score between 0 and 1
    var timestamp: String       // When the detection was made (ISO 8601 format)
    var synced: Int             // 0 = not yet uploaded to Firebase, 1 = synced
    var audioSampleId: Int64?   // Links to an audio sample if one was extracted from video
    // Stable UUID used as the on-disk image filename. Synced to Firestore so
    // the image persists across sign-out/sign-in (where the SQLite id changes).
    var imageKey: String?
}
