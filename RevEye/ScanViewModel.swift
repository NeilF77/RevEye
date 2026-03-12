//
//  ScanViewModel.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Fixed 12/03/2026 — clears stale classifier state before every new scan

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AVKit
import PhotosUI

enum ScanMode: Equatable { case idle, photo, video }

@MainActor
final class ScanViewModel: ObservableObject {

    // MARK: - Published State

    @Published var scanMode: ScanMode = .idle
    @Published var capturedImage: UIImage?
    @Published var photoSaved = false
    @Published var photoSkipped = false
    @Published var selectedVideoURL: URL?
    @Published var isProcessingVideo = false
    @Published var videoProgress: Double = 0
    @Published var videoTotal: Double = 1
    @Published var videoDetections: [(label: String, confidence: Double, appearedAt: Double)] = []
    @Published var videoDetectionIds: [Int64] = []
    @Published var statusMessage: String?
    @Published var toastBadge: Badge?
    @Published var showBadgeToast = false
    @Published var showAudioPrompt = false
    @Published var savedDetections: [Detection] = []

    /// True when the classifier is actively working on a new image
    @Published var isClassifying = false

    // MARK: - Dependencies

    let classifier = CarClassifier()
    private let db = DatabaseManager.shared
    private let badges = BadgeService.shared
    private var videoTask: Task<Void, Never>?
    private var classifierSub: AnyCancellable?

    // MARK: - Init

    init() {
        savedDetections = db.fetchAllDetections()

        // Watch for classifier completing — clears isClassifying flag
        classifierSub = classifier.$lastOutput
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isClassifying = false
            }
    }

    func refreshDetections() {
        savedDetections = db.fetchAllDetections()
    }

    // MARK: - Reset (called before every new scan)

    /// Clears ALL stale state so the UI shows a clean loading screen
    private func resetForNewScan() {
        // Clear classifier state so UI doesn't show old results
        classifier.lastOutput = nil
        classifier.result = "No result yet"

        // Clear view state
        capturedImage = nil
        photoSaved = false
        photoSkipped = false
        statusMessage = nil
        isClassifying = true
        showAudioPrompt = false

        // Clear video state
        selectedVideoURL = nil
        videoDetections = []
        videoDetectionIds = []
        isProcessingVideo = false
    }

    // MARK: - Photo Handling

    func handlePickedImage(_ image: UIImage) {
        cancelVideo()
        resetForNewScan()

        scanMode = .photo
        capturedImage = image

        classifier.classify(image: image)
        if let b = badges.award("first_photo") { showToast(b) }
    }

    func handlePhotoPickerItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        cancelVideo()
        resetForNewScan()
        scanMode = .photo

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                isClassifying = false
                return
            }
            capturedImage = image
            classifier.classify(image: image)
            if let b = badges.award("first_photo") { showToast(b) }
        }
    }

    func savePhotoDetection() {
        guard let output = classifier.lastOutput else {
            statusMessage = "No result to save yet."
            return
        }
        saveDetectionWithLabel(output.label, confidence: output.confidence)
    }

    func saveDetectionWithLabel(_ label: String, confidence: Double) {
        let clamped = max(0.0, min(1.0, confidence))
        if let saved = insertDetection(label: label, confidence: clamped) {
            FirebaseService.shared.uploadDetection(saved) { [weak self] success in
                guard let self else { return }
                if success, let b = self.badges.award("first_sync") { self.showToast(b) }
            }
            savedDetections = db.fetchAllDetections()
            for badge in badges.checkAfterPhotoSave(confidence: clamped, allDetections: savedDetections) {
                showToast(badge)
            }
            statusMessage = "Saved: \(label)"
            photoSaved = true
        }
    }

    func skipDetection() {
        photoSkipped = true
        statusMessage = "Skipped — scan another to continue"
    }

    /// Go back to idle scan screen
    func returnToScan() {
        scanMode = .idle
        classifier.lastOutput = nil
        classifier.result = "No result yet"
        capturedImage = nil
        selectedVideoURL = nil
        videoDetections = []
        statusMessage = nil
        showAudioPrompt = false
        photoSaved = false
        photoSkipped = false
        isClassifying = false
    }

    // MARK: - Video Processing

    func startVideoProcessing(url: URL) {
        cancelVideo()
        resetForNewScan()
        scanMode = .video
        selectedVideoURL = url
        isClassifying = false // video has its own progress tracking
        videoTask = Task { await processVideo(url: url) }
    }

    func cancelVideo() {
        videoTask?.cancel()
        videoTask = nil
    }

    private func processVideo(url: URL) async {
        isProcessingVideo = true

        if let b = badges.award("first_video") { showToast(b) }

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            isProcessingVideo = false
            statusMessage = "Could not read video."
            return
        }
        let times = stride(from: 0.0, to: duration, by: 1.0)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }
        videoTotal = Double(times.count)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        var framesProcessed = 0
        var seenLabels = Set<String>()

        for time in times {
            guard !Task.isCancelled else { isProcessingVideo = false; return }
            framesProcessed += 1

            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                videoProgress = Double(framesProcessed)
                continue
            }

            let output: ClassificationOutput?
            do {
                output = try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    var cancellable: AnyCancellable?
                    cancellable = classifier.$lastOutput.dropFirst().first().sink { result in
                        cancellable?.cancel()
                        continuation.resume(returning: result)
                    }
                    classifier.classify(image: UIImage(cgImage: cgImage))
                }
            } catch {
                isProcessingVideo = false; return
            }

            if let output,
               output.isVehicle,
               output.tier != .tooLow,
               max(0.0, min(1.0, output.confidence)) >= 0.15,
               !seenLabels.contains(output.label) {

                seenLabels.insert(output.label)
                let confidence = max(0.0, min(1.0, output.confidence))
                if let saved = insertDetection(label: output.label, confidence: confidence) {
                    FirebaseService.shared.uploadDetection(saved, source: .video)
                    if let id = saved.id { videoDetectionIds.append(id) }
                    savedDetections = db.fetchAllDetections()
                }
                videoDetections.append((label: output.label,
                                        confidence: output.confidence,
                                        appearedAt: time.seconds))
            }
            videoProgress = Double(framesProcessed)
        }

        isProcessingVideo = false
        let count = videoDetections.count
        statusMessage = count == 0
            ? "No vehicles detected. Try a clearer video."
            : "Found \(count) unique vehicle\(count == 1 ? "" : "s")."

        for badge in badges.checkAfterVideoDetection(allDetections: savedDetections) {
            showToast(badge)
        }
        if count > 0 { showAudioPrompt = true }
    }

    // MARK: - Helpers

    private func insertDetection(label: String, confidence: Double) -> Detection? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let toInsert = Detection(id: nil, vehicleLabel: label, confidence: confidence,
                                 timestamp: timestamp, synced: 0, audioSampleId: nil)
        guard let newId = db.insertDetection(toInsert) else { return nil }
        return Detection(id: newId, vehicleLabel: label, confidence: confidence,
                         timestamp: timestamp, synced: 0, audioSampleId: nil)
    }

    func showToast(_ badge: Badge) {
        guard !showBadgeToast else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.showToast(badge)
            }
            return
        }
        toastBadge = badge
        showBadgeToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.showBadgeToast = false
        }
    }

    func formatVideoTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
