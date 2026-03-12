//
//  Detection.swift
//  RevEye
//
//  Created by user on 26/11/2025.
//

import Foundation

struct Detection: Identifiable {
    var id: Int64?              // Primary key
    var vehicleLabel: String    // e.g. "BMW 3 Series"
    var confidence: Double      // ML confidence score
    var timestamp: String       // ISO8601 string
    var synced: Int             // 0 = not synced, 1 = synced
    var audioSampleId: Int64?   // FK to audioSamples table, nil if no audio attached
}
