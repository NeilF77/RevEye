// AudioSample.swift
// RevEye
//
// Data model for audio samples extracted from user-uploaded videos.
// Each sample includes the extracted M4A audio file path plus user-provided
// metadata about the recording conditions. The metadata enums (RecordingContext,
// VehicleState, NoiseLevel, EngineAudible) are defined here too since they're
// only used with AudioSample.

import Foundation

// Audio Metadata Enums

// How the video was recorded relative to the vehicle
enum RecordingContext: String, CaseIterable, Codable {
    case outsideNear   = "outside_near"
    case insideVehicle = "inside_vehicle"
    case fromAnother   = "from_another"
    case other         = "other"

    var label: String {
        switch self {
        case .outsideNear:   return "Outside, near vehicle"
        case .insideVehicle: return "Inside the vehicle"
        case .fromAnother:   return "From another vehicle"
        case .other:         return "Other"
        }
    }
}

// What the vehicle was doing when recorded
enum VehicleState: String, CaseIterable, Codable {
    case idling       = "idling"
    case accelerating = "accelerating"
    case cruising     = "cruising"
    case revving      = "revving"
    case off          = "off"
    case unknown      = "unknown"

    var label: String {
        switch self {
        case .idling:       return "Idling"
        case .accelerating: return "Accelerating"
        case .cruising:     return "Cruising"
        case .revving:      return "Revving"
        case .off:          return "Off"
        case .unknown:      return "Unknown"
        }
    }
}

// Self-reported background noise level
enum NoiseLevel: String, CaseIterable, Codable {
    case quiet   = "quiet"
    case moderate = "moderate"
    case noisy   = "noisy"

    var label: String {
        switch self {
        case .quiet:    return "Quiet"
        case .moderate: return "Moderate"
        case .noisy:    return "Noisy"
        }
    }
}

// Whether the user can hear the engine in the recording
enum EngineAudible: String, CaseIterable, Codable {
    case yes    = "yes"
    case no     = "no"
    case unsure = "unsure"

    var label: String {
        switch self {
        case .yes:    return "Yes"
        case .no:     return "No"
        case .unsure: return "Not Sure"
        }
    }
}

// AudioSample Model

// Represents one audio sample extracted from a user-uploaded video.
// Stored locally and synced to Firebase (Firestore metadata + Storage file).
struct AudioSample: Identifiable, Codable {
    var id: Int64?                      // Local SQLite row ID
    let vehicleLabel: String            // ML prediction for the vehicle
    let confidence: Double              // ML confidence score
    let audioDuration: Double           // Duration in seconds
    let engineAudible: EngineAudible
    let recordingContext: RecordingContext
    let vehicleState: VehicleState
    let backgroundNoise: NoiseLevel
    let userNotes: String               // Free text (may be empty)
    let localFilePath: String           // Path to local M4A file
    let firebaseStoragePath: String?    // Firebase Storage path (nil until uploaded)
    let timestamp: String               // ISO8601 creation timestamp
    var synced: Int                      // 0 = local, 1 = uploaded to Firebase

    // Dictionary for Firestore upload
    var firestoreData: [String: Any] {
        [
            "vehicleLabel":      vehicleLabel,
            "confidence":        confidence,
            "audioDuration":     audioDuration,
            "engineAudible":     engineAudible.rawValue,
            "recordingContext":   recordingContext.rawValue,
            "vehicleState":      vehicleState.rawValue,
            "backgroundNoise":   backgroundNoise.rawValue,
            "userNotes":         userNotes,
            "audioStoragePath":  firebaseStoragePath ?? "",
            "timestamp":         timestamp,
            "verified":          false,
        ]
    }
}
