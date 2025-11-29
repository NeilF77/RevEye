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

struct ClassificationOutput {
    let label: String
    let confidence: Double
}

class CarClassifier: ObservableObject { // <-- must conform to ObservableObject
    @Published var result: String = "No result yet"  // <-- UI updates automatically
    @Published var lastOutput: ClassificationOutput?

    private var visionModel: VNCoreMLModel

    init() {
        do {
            // Replace CarRecogniser with your ML model class name
            let coreMLModel = try CarRecognition(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Could not load ML model: \(error)")
        }
    }

    func classify(image: UIImage) {
        guard let ciImage = CIImage(image: image) else { return }

        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let observations = request.results as? [VNClassificationObservation],
                  let top = observations.first else {
                DispatchQueue.main.async {
                    self?.result = "No car detected"
                    self?.lastOutput = nil
                }
                return
            }
            
            let label = top.identifier
            let conf  = Double(top.confidence)

            DispatchQueue.main.async {
                self?.result = "\(top.identifier) — \(Int(top.confidence * 100))% confidence"
                self?.lastOutput = ClassificationOutput(label: label, confidence: conf)
            }
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
