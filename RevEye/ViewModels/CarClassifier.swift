//
//  CarClassifier.swift
//  RevEye
//
//  Created by user on 17/11/2025.
//  Updated 10/03/2026 — confidence mitigations (tiers, top-K gap, OOD guard)
//  Fixed  10/03/2026 — thresholds calibrated for 196-class EfficientNet-B4
//

import Foundation
import Vision
import CoreML
import UIKit
import Combine

// MARK: - Confidence Tier

/// Confidence tiers calibrated for a 196-class classifier with T=0.5 softmax.
/// With this many classes, even correct predictions may have modest
/// softmax probabilities — a 35% score is actually quite strong.
///
///   - .high:    >= 30% — show normally (strong signal with 196 classes)
///   - .low:     15–29% — show with a warning
///   - .tooLow:  < 15%  — model is essentially guessing
enum ConfidenceTier: String {
    case high   = "high"
    case low    = "low"
    case tooLow = "tooLow"

    static func tier(for confidence: Double) -> ConfidenceTier {
        switch confidence {
        case 0.30...:      return .high
        case 0.15..<0.30:  return .low
        default:           return .tooLow
        }
    }
}

// MARK: - Classification Output

/// Holds the full classification result including top predictions.
struct ClassificationOutput {
    let label: String
    let confidence: Double
    let tier: ConfidenceTier
    let top3: [(label: String, confidence: Double)]
    let isAmbiguous: Bool       // true if gap between #1 and #2 is very small
    let isVehicle: Bool         // false if OOD pre-check found no vehicle

    /// User-facing description string
    var displayText: String {
        if !isVehicle {
            return "No vehicle detected in this image."
        }
        switch tier {
        case .tooLow:
            return "Could not confidently identify this vehicle. Try a clearer photo."
        case .low:
            let pct = Int(confidence * 100)
            let base = "Best guess: \(label) (\(pct)%)"
            if isAmbiguous, top3.count >= 2 {
                return "\(base) — also possible: \(top3[1].label)"
            }
            return base
        case .high:
            let pct = Int(confidence * 100)
            if isAmbiguous, top3.count >= 2 {
                return "\(label) — \(pct)% (also possible: \(top3[1].label))"
            }
            return "\(label) — \(pct)% confidence"
        }
    }
}

// MARK: - CarClassifier ViewModel

class CarClassifier: ObservableObject {
    @Published var result: String = "No result yet"
    @Published var lastOutput: ClassificationOutput?

    private var visionModel: VNCoreMLModel

    init() {
        do {
            let coreMLModel = try RevEyeCars(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Could not load ML model: \(error)")
        }
    }

    // MARK: - Public API

    /// Classifies a vehicle image.
    /// Always publishes to `lastOutput` on the main thread so any Combine
    /// subscriber (including the video scanning continuation) gets unblocked.
    func classify(image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            publishError("Could not process image")
            return
        }

        // Step 1: Out-of-distribution pre-check using Apple's built-in classifier.
        // This only rejects images that are clearly NOT vehicles (flowers, food, etc.).
        // Intentionally lenient — better to show a low-confidence car prediction
        // than reject a real car image.
        checkForVehicle(ciImage: ciImage) { [weak self] isVehicle in
            guard let self else { return }

            if !isVehicle {
                DispatchQueue.main.async {
                    let output = ClassificationOutput(
                        label: "", confidence: 0, tier: .tooLow,
                        top3: [], isAmbiguous: false, isVehicle: false
                    )
                    self.result = output.displayText
                    self.lastOutput = output
                }
                return
            }

            // Step 2: Run the car-specific model
            self.runCarModel(ciImage: ciImage)
        }
    }

    // MARK: - Private: OOD Pre-Check (Mitigation C)

    /// Uses Apple's built-in VNClassifyImageRequest to check whether the image
    /// likely contains a vehicle. Intentionally LENIENT — only rejects images
    /// where there is clearly no vehicle at all (flowers, faces, food, etc.).
    private func checkForVehicle(ciImage: CIImage, completion: @escaping (Bool) -> Void) {
        let request = VNClassifyImageRequest { request, error in
            if error != nil {
                // On failure, assume vehicle and let the car model decide
                completion(true)
                return
            }

            guard let observations = request.results as? [VNClassificationObservation] else {
                completion(true)
                return
            }

            // Broad set of vehicle-adjacent keywords.
            // Apple's taxonomy includes things like "grille", "wheel", "bumper",
            // "parking lot", "highway", "road" — all of which suggest a car context.
            let vehicleKeywords = [
                // Direct vehicle types
                "car", "truck", "bus", "van", "suv", "vehicle", "automobile",
                "sports car", "minivan", "jeep", "cab", "ambulance", "taxi",
                "convertible", "pickup", "sedan", "wagon", "limousine", "coupe",
                "hatchback", "roadster", "motor vehicle", "race car",
                // Vehicle parts (image might be zoomed in on a part)
                "wheel", "tire", "grille", "bumper", "headlight", "windshield",
                "license plate", "fender",
                // Road context (strong signal that a car is present)
                "road", "highway", "street", "parking", "traffic", "lane",
                "intersection", "freeway", "asphalt", "pavement",
                // Transport context
                "transport", "driving",
            ]

            // Check a very wide range of observations — be lenient.
            // We only want to catch truly non-vehicle images.
            let topObservations = observations.prefix(50)
            let foundVehicle = topObservations.contains { obs in
                let id = obs.identifier.lowercased()
                return vehicleKeywords.contains(where: { id.contains($0) })
            }

            completion(foundVehicle)
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                // On failure, allow the car model to proceed
                completion(true)
            }
        }
    }

    // MARK: - Private: Car Model Inference (Mitigations A + B)

    private func runCarModel(ciImage: CIImage) {
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            if let error {
                print("Vision error: \(error.localizedDescription)")
                self?.publishError("Detection error")
                return
            }

            guard let observations = request.results as? [VNClassificationObservation],
                  !observations.isEmpty else {
                self?.publishError("No result from model")
                return
            }

            // Collect top-3 results
            let top3 = observations.prefix(3).map { obs in
                (label: obs.identifier, confidence: Double(obs.confidence))
            }

            let topLabel = top3[0].label
            let topConf  = top3[0].confidence

            // Debug logging — see what the model actually returns
            // Remove before final submission if you want cleaner logs
            print("ML Top-3: \(top3.map { "\($0.label): \(Int($0.confidence * 100))%" }.joined(separator: ", "))")

            // Mitigation B: Top-K gap analysis
            // With 196 classes, a 5% gap between #1 and #2 is meaningful.
            let isAmbiguous: Bool
            if top3.count >= 2 {
                isAmbiguous = (topConf - top3[1].confidence) < 0.05
            } else {
                isAmbiguous = false
            }

            // Mitigation A: Confidence tier (calibrated for 196-class model)
            let tier = ConfidenceTier.tier(for: topConf)

            let output = ClassificationOutput(
                label: topLabel,
                confidence: topConf,
                tier: tier,
                top3: top3,
                isAmbiguous: isAmbiguous,
                isVehicle: true
            )

            DispatchQueue.main.async {
                self?.result = output.displayText
                self?.lastOutput = output
            }
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Vision perform error: \(error.localizedDescription)")
                self.publishError("Detection failed")
            }
        }
    }

    // MARK: - Helpers

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.result = message
            self.lastOutput = nil
        }
    }
}

// MARK: - Convenience accessors

extension CarClassifier {
    var lastLabel: String      { lastOutput?.label      ?? "" }
    var lastConfidence: Double { lastOutput?.confidence ?? 0.0 }
    var lastTier: ConfidenceTier { lastOutput?.tier ?? .tooLow }
}
