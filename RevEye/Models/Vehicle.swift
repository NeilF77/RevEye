//
//  Vehicle.swift
//  RevEye
//
//  Created by user on 11/11/2025.
//

import Foundation

// Represents a vehicle detected by the ML model
struct Vehicle: Identifiable, Codable {
    let id: UUID = UUID()
    let make: String
    let model: String
    let year: Int?
    let confidence: Float
    let detectedAt: Date = Date()
    let imageURL: URL?
}

// Combines vehicle data with detection metadata for display/analysis
struct DetectionResult {
    let vehicle: Vehicle
    let processingTime: TimeInterval
}
