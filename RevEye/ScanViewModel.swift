//
//  ScanViewModel.swift
//  RevEye
//
//  UI overhaul v7 — saves images on detection, bigger ring coming in ScanView

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AVKit
import PhotosUI

enum ScanMode: Equatable { case idle, photo, video }

struct VideoDetection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Double
    let appearedAt: Double
    let thumbnail: UIImage?
    var saved: Bool = false
    var skipped: Bool = false
    var handled: Bool { saved || skipped }
}

@MainActor
final class ScanViewModel: ObservableObject {

    @Published var scanMode: ScanMode = .idle
    @Published var capturedImage: UIImage?
    @Published var photoSaved = false
    @Published var photoSkipped = false
    @Published var selectedVideoURL: URL?
    @Published var isProcessingVideo = false
    @Published var videoProgress: Double = 0
    @Published var videoTotal: Double = 1
    @Published var videoDetections: [VideoDetection] = []
    @Published var videoDetectionIds: [Int64] = []
    @Published var statusMessage: String?
    @Published var toastBadge: Badge?
    @Published var showBadgeToast = false
    @Published var showAudioPrompt = false
    @Published var savedDetections: [Detection] = []
    @Published var isClassifying = false

    let classifier = CarClassifier()
    private let db = DatabaseManager.shared
    private let badges = BadgeService.shared
    private var videoTask: Task<Void, Never>?
    private var classifierSub: AnyCancellable?

    init() {
        savedDetections = db.fetchAllDetections()
        classifierSub = classifier.$lastOutput
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isClassifying = false }
    }

    func refreshDetections() { savedDetections = db.fetchAllDetections() }

    private func resetForNewScan() {
        classifier.lastOutput = nil
        classifier.result = "No result yet"
        capturedImage = nil
        photoSaved = false
        photoSkipped = false
        statusMessage = nil
        isClassifying = true
        showAudioPrompt = false
        selectedVideoURL = nil
        videoDetections = []
        videoDetectionIds = []
        isProcessingVideo = false
    }

    // MARK: - Photo

    func handlePickedImage(_ image: UIImage) {
        cancelVideo(); resetForNewScan()
        scanMode = .photo; capturedImage = image
        classifier.classify(image: image)
        if let b = badges.award("first_photo") { showToast(b) }
    }

    func handlePhotoPickerItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        cancelVideo(); resetForNewScan(); scanMode = .photo
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { isClassifying = false; return }
            capturedImage = image
            classifier.classify(image: image)
            if let b = badges.award("first_photo") { showToast(b) }
        }
    }

    func savePhotoDetection() {
        guard let output = classifier.lastOutput else { statusMessage = "No result to save yet."; return }
        saveDetectionWithLabel(output.label, confidence: output.confidence)
    }

    func saveDetectionWithLabel(_ label: String, confidence: Double) {
        let c = max(0, min(1, confidence))
        if let saved = insertDetection(label: label, confidence: c) {
            // Save image to disk
            if let image = capturedImage, let id = saved.id {
                ImageStore.save(image, for: id)
            }
            FirebaseService.shared.uploadDetection(saved) { [weak self] ok in
                if ok, let b = self?.badges.award("first_sync") { self?.showToast(b) }
            }
            savedDetections = db.fetchAllDetections()
            for b in badges.checkAfterPhotoSave(confidence: c, allDetections: savedDetections) { showToast(b) }
            photoSaved = true
            scheduleReturnToScan()
        }
    }

    func saveAsUnknown() {
        if let saved = insertDetection(label: "Unknown Vehicle", confidence: 0) {
            if let image = capturedImage, let id = saved.id {
                ImageStore.save(image, for: id)
            }
            FirebaseService.shared.uploadDetection(saved)
            savedDetections = db.fetchAllDetections()
            photoSaved = true
            scheduleReturnToScan()
        }
    }

    func skipDetection() {
        photoSkipped = true
        scheduleReturnToScan()
    }

    func returnToScan() {
        scanMode = .idle
        classifier.lastOutput = nil; classifier.result = "No result yet"
        capturedImage = nil; selectedVideoURL = nil; videoDetections = []
        statusMessage = nil; showAudioPrompt = false
        photoSaved = false; photoSkipped = false; isClassifying = false
    }

    private func scheduleReturnToScan() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.returnToScan() }
    }

    // MARK: - Video: Per-detection save/skip

    func saveVideoDetection(at index: Int) {
        guard index < videoDetections.count else { return }
        let det = videoDetections[index]
        let c = max(0, min(1, det.confidence))
        if let saved = insertDetection(label: det.label, confidence: c) {
            // Save video frame thumbnail as the detection image
            if let thumb = det.thumbnail, let id = saved.id {
                ImageStore.save(thumb, for: id)
            }
            FirebaseService.shared.uploadDetection(saved, source: .video)
            if let id = saved.id { videoDetectionIds.append(id) }
            savedDetections = db.fetchAllDetections()
            for b in badges.checkAfterVideoDetection(allDetections: savedDetections) { showToast(b) }
        }
        videoDetections[index].saved = true
        checkAllVideoHandled()
    }

    func skipVideoDetection(at index: Int) {
        guard index < videoDetections.count else { return }
        videoDetections[index].skipped = true
        checkAllVideoHandled()
    }

    func saveAllVideoDetections() {
        for i in videoDetections.indices where !videoDetections[i].handled { saveVideoDetection(at: i) }
    }

    func skipAllVideoDetections() {
        for i in videoDetections.indices where !videoDetections[i].handled { videoDetections[i].skipped = true }
        checkAllVideoHandled()
    }

    private func checkAllVideoHandled() {
        if videoDetections.allSatisfy({ $0.handled }) {
            if videoDetections.contains(where: { $0.saved }) { showAudioPrompt = true }
        }
    }

    // MARK: - Video Processing

    func startVideoProcessing(url: URL) {
        cancelVideo(); resetForNewScan()
        scanMode = .video; selectedVideoURL = url; isClassifying = false
        videoTask = Task { await processVideo(url: url) }
    }

    func cancelVideo() { videoTask?.cancel(); videoTask = nil }

    private func processVideo(url: URL) async {
        isProcessingVideo = true
        if let b = badges.award("first_video") { showToast(b) }

        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration).seconds, dur > 0 else {
            isProcessingVideo = false; statusMessage = "Could not read video."; return
        }
        let times = stride(from: 0, to: dur, by: 1.0).map { CMTime(seconds: $0, preferredTimescale: 600) }
        videoTotal = Double(times.count)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        var done = 0
        var seen = Set<String>()

        for t in times {
            guard !Task.isCancelled else { isProcessingVideo = false; return }
            done += 1
            guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else {
                videoProgress = Double(done); continue
            }

            let frameImage = UIImage(cgImage: cg)
            let out: ClassificationOutput?
            do {
                out = try await withCheckedThrowingContinuation { cont in
                    if Task.isCancelled { cont.resume(throwing: CancellationError()); return }
                    var sub: AnyCancellable?
                    sub = classifier.$lastOutput.dropFirst().first().sink { r in sub?.cancel(); cont.resume(returning: r) }
                    classifier.classify(image: frameImage)
                }
            } catch { isProcessingVideo = false; return }

            if let out, out.isVehicle, out.tier != .tooLow,
               max(0, min(1, out.confidence)) >= 0.15, !seen.contains(out.label) {
                seen.insert(out.label)
                videoDetections.append(VideoDetection(
                    label: out.label,
                    confidence: max(0, min(1, out.confidence)),
                    appearedAt: t.seconds,
                    thumbnail: frameImage
                ))
            }
            videoProgress = Double(done)
        }

        isProcessingVideo = false
        let n = videoDetections.count
        statusMessage = n == 0 ? "No vehicles detected." : "Found \(n) vehicle\(n == 1 ? "" : "s") — review below."
    }

    // MARK: - Helpers

    private func insertDetection(label: String, confidence: Double) -> Detection? {
        let ts = ISO8601DateFormatter().string(from: Date())
        let d = Detection(id: nil, vehicleLabel: label, confidence: confidence, timestamp: ts, synced: 0, audioSampleId: nil)
        guard let id = db.insertDetection(d) else { return nil }
        return Detection(id: id, vehicleLabel: label, confidence: confidence, timestamp: ts, synced: 0, audioSampleId: nil)
    }

    func showToast(_ badge: Badge) {
        guard !showBadgeToast else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.showToast(badge) }
            return
        }
        toastBadge = badge; showBadgeToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in self?.showBadgeToast = false }
    }

    func fmtTime(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
