// CarClassifier.swift
// RevEye
//
// Loads and runs the Core ML vehicle classification model. Takes a UIImage,
// preprocesses it through the Vision framework, runs inference, and publishes
// the result. Uses a two-stage approach: first checks if the image contains a
// vehicle at all (using objectness saliency), then classifies the vehicle
// make and model if one is found.

import Foundation
import Vision
import CoreML
import UIKit
import Combine

// Confidence Tier

// Confidence tiers calibrated for a 196-class classifier.
// With this many classes, even correct predictions can have modest softmax
// probabilities, so the thresholds need to be realistic.
//
//   - .high:    >= 60%  - confident enough to show a simple save/skip card
//   - .low:     15-59%  - show suggestion picker with top 3 options
//   - .tooLow:  < 15%   - model is essentially guessing
enum ConfidenceTier {
    case high, low, tooLow

    static func tier(for confidence: Double) -> ConfidenceTier {
        if confidence >= 0.60 { return .high }
        if confidence >= 0.15 { return .low }
        return .tooLow
    }
}

// Classification Output

// Holds the full classification result including top predictions.
struct ClassificationOutput {
    let label: String
    let confidence: Double
    let tier: ConfidenceTier
    let top3: [(label: String, confidence: Double)]
    let isAmbiguous: Bool       // true if gap between #1 and #2 is very small
    let isVehicle: Bool         // false if OOD pre-check found no vehicle
}

// CarClassifier ViewModel

class CarClassifier: ObservableObject {
    // The most recent classification result, observed by ScanView
    @Published var lastOutput: ClassificationOutput?

    private var visionModel: VNCoreMLModel

    init() {
        // The .mlpackage is bundled in the app, so if this fails something is
        // badly wrong (missing resource, corrupted build). Crash loudly rather
        // than silently leave the scan feature broken.
        do {
            let coreMLModel = try RevEyeCarsVideo(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Could not load ML model: \(error)")
        }
    }

    // Public API

    // Classifies a vehicle image. Publishes to `lastOutput` on the main thread.
    func classify(image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            publishError("Could not process image")
            return
        }

        checkForVehicle(ciImage: ciImage) { [weak self] isVehicle in
            guard let self else { return }

            if !isVehicle {
                DispatchQueue.main.async {
                    self.lastOutput = ClassificationOutput(
                        label: "", confidence: 0, tier: .tooLow,
                        top3: [], isAmbiguous: false, isVehicle: false
                    )
                }
                return
            }

            self.runCarModel(ciImage: ciImage)
        }
    }

    // Quick "does this look like a vehicle?" pre-check using Apple's generic
    // image classifier. Intentionally lenient: if Vision errors out or returns
    // nothing usable, we assume yes and let the car model have a go anyway.
    // Only flat-out rejects obvious non-vehicles (flowers, faces, food).
    private func checkForVehicle(ciImage: CIImage, completion: @escaping (Bool) -> Void) {
        let request = VNClassifyImageRequest { request, error in
            if error != nil {
                completion(true)
                return
            }

            guard let observations = request.results as? [VNClassificationObservation] else {
                completion(true)
                return
            }

            // Only look at the top 10 most confident predictions, and
            // require a match of at least 5% confidence.
            let vehicleKeywords = [
                "car", "truck", "bus", "van", "suv", "vehicle", "automobile",
                "sports car", "minivan", "jeep", "cab", "ambulance", "taxi",
                "convertible", "pickup", "sedan", "wagon", "limousine", "coupe",
                "hatchback", "roadster", "motor vehicle", "race car",
                "wheel", "tire", "grille", "bumper", "headlight", "windshield",
                "license plate", "fender",
            ]

            let topObservations = observations.prefix(10)
            let foundVehicle = topObservations.contains { obs in
                guard obs.confidence > 0.05 else { return false }
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
                completion(true)
            }
        }
    }

    // Runs the EfficientNet-B4 CoreML model on the image.

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

            let top3 = observations.prefix(3).map { obs in
                (label: obs.identifier, confidence: Double(obs.confidence))
            }

            let topLabel = top3[0].label
            let topConf  = top3[0].confidence

            print("ML Top-3: \(top3.map { "\($0.label): \(Int($0.confidence * 100))%" }.joined(separator: ", "))")

            let isAmbiguous = top3.count >= 2 && (topConf - top3[1].confidence) < 0.05

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

    // Helpers

    private func publishError(_ message: String) {
        print("CarClassifier: \(message)")
        DispatchQueue.main.async {
            self.lastOutput = nil
        }
    }
}
