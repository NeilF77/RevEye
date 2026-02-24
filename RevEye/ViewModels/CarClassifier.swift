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
    @Published var result: String = "No result yet"
    @Published var lastOutput: ClassificationOutput?  // nil means no result or error

    private var visionModel: VNCoreMLModel

    init() {
        do {
            let coreMLModel = try CarRecognition(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Could not load ML model: \(error)")
        }
    }

    // Classifies a vehicle image using the ML model.
    // Always publishes to lastOutput on the main thread — either a result or nil —
    // so any Combine subscriber waiting on $lastOutput will always get a value
    // and never hang indefinitely.
    func classify(image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            // Publish nil so waiting continuations are unblocked
            DispatchQueue.main.async {
                self.result = "Could not process image"
                self.lastOutput = nil
            }
            return
        }

        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            // Handle Vision errors explicitly rather than silently dropping them
            if let error = error {
                print("Vision error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.result = "Detection error"
                    self?.lastOutput = nil  // unblocks any waiting continuation
                }
                return
            }

            guard let observations = request.results as? [VNClassificationObservation],
                  let top = observations.first else {
                DispatchQueue.main.async {
                    self?.result = "No vehicle detected"
                    self?.lastOutput = nil  // unblocks any waiting continuation
                }
                return
            }

            let label = top.identifier
            let conf  = Double(top.confidence)

            DispatchQueue.main.async {
                self?.result = "\(label) — \(Int(conf * 100))% confidence"
                self?.lastOutput = ClassificationOutput(label: label, confidence: conf)
            }
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                // Catch perform errors and publish nil so waiting continuations unblock
                print("Vision perform error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.result = "Detection failed"
                    self.lastOutput = nil
                }
            }
        }
    }
}

extension CarClassifier {
    var lastLabel: String      { lastOutput?.label      ?? "" }
    var lastConfidence: Double { lastOutput?.confidence ?? 0.0 }
}
