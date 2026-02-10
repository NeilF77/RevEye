//
//  CarClassifierViewModel.swift
//  RevEye
//
//  Created by user on 17/11/2025.
//


import Foundation
import Vision
import CoreML
import UIKit
import Combine

// Holds the classification result with label and confidence score
struct ClassificationOutput {
    let label: String
    let confidence: Double
}

// ViewModel that handles ML model classification using Vision and Core ML
class CarClassifier: ObservableObject {
    @Published var result: String = "No result yet"  // UI updates automatically
    @Published var lastOutput: ClassificationOutput? // Stores latest classification for saving to database

    // Vision wrapper around the Core ML model
    private var visionModel: VNCoreMLModel

    init() {
        do {
            // Load the Core ML model (CarRecognition.mlmodel)
            let coreMLModel = try CarRecognition(configuration: MLModelConfiguration())
            // Wrap it in VNCoreMLModel so Vision framework can use it
            visionModel = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Could not load ML model: \(error)")
        }
    }

    // Classifies a vehicle image using the ML model
    func classify(image: UIImage) {
        // Convert UIImage to CIImage for Vision processing
        guard let ciImage = CIImage(image: image) else { return }

        // Create Vision request with completion handler for results
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            // Extract classification results from the request
            guard let observations = request.results as? [VNClassificationObservation],
                  let top = observations.first else {
                // No car detected or error occurred
                DispatchQueue.main.async {
                    self?.result = "No car detected"
                    self?.lastOutput = nil
                }
                return
            }
           
            // Get the top prediction's label and confidence
            let label = top.identifier
            let conf  = Double(top.confidence)

            // Update UI on main thread (required for @Published properties)
            DispatchQueue.main.async {
                self?.result = "\(top.identifier) — \(Int(top.confidence * 100))% confidence"
                self?.lastOutput = ClassificationOutput(label: label, confidence: conf)
            }
        }

        // Create handler to perform the Vision request
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        // Run classification on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
// Convenience accessors for database and other logic
extension CarClassifier {
    var lastLabel: String {
        lastOutput?.label ?? ""
    }

    var lastConfidence: Double {
        lastOutput?.confidence ?? 0.0
    }
}
