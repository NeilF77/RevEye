//
//  Vehicle.swift
//  RevEye
//
//  Created by user on 11/11/2025.
//


import Foundation

struct Vehicle: Identifiable, Codable {
    let id: UUID = UUID()
    let make: String
    let model: String
    let year: Int?
    let confidence: Float
    let detectedAt: Date = Date()
    let imageURL: URL?
}

struct DetectionResult {
    let vehicle: Vehicle
    let boundingBox: CGRect?
    let processingTime: TimeInterval
}
