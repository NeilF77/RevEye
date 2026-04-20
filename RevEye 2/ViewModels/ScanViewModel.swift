// ScanViewModel.swift
// RevEye
//
// The main view model for the Scan tab. Handles the full lifecycle of
// scanning: picking a photo or video, running classification, saving
// results to the database, uploading to Firebase, checking for badges,
// and managing the audio extraction prompt for video scans.

import Foundation
import SwiftUI
import Combine
import AVFoundation
import AVKit
import Vision

enum ScanMode: Equatable { case idle, photo, video }

struct VideoDetection: Identifiable {
    let id = UUID()
    var label: String
    var confidence: Double
    let appearedAt: Double
    let thumbnail: UIImage?
    let top3: [(label: String, confidence: Double)]   // for correction picker
    var saved: Bool = false
    var skipped: Bool = false
    var correcting: Bool = false   // true when user taps "Not right?"
    var handled: Bool { saved || skipped }
}

@MainActor
final class ScanViewModel: ObservableObject {

    // Current scan mode - idle (nothing happening), photo, or video
    @Published var scanMode: ScanMode = .idle
    // The image the user selected or captured, shown in the result view
    @Published var capturedImage: UIImage?
    // Tracks whether the current photo result has been saved or skipped
    @Published var photoSaved = false
    @Published var photoSkipped = false
    // The URL of the video being processed, shown in the video player
    @Published var selectedVideoURL: URL?
    // True while the video is being scanned frame by frame
    @Published var isProcessingVideo = false
    @Published var videoProgress: Double = 0
    @Published var videoTotal: Double = 1
    // All unique vehicles found in the current video scan
    @Published var videoDetections: [VideoDetection] = []
    @Published var statusMessage: String?
    // Badge toast queue system - shows earned badges one at a time
    @Published var toastBadge: Badge?
    @Published var showBadgeToast = false
    private var badgeQueue: [Badge] = []
    private var isShowingToast = false
    @Published var savedDetections: [Detection] = []
    @Published var isClassifying = false

    // The ML classifier instance that runs predictions on images
    let classifier = CarClassifier()
    // Database and badge service references
    private let db = DatabaseManager.shared
    private let badges = BadgeService.shared
    // Background task reference - stored so we can cancel it if the user
    // switches to a different mode mid-scan
    private var videoTask: Task<Void, Never>?
    // Combine subscription that listens for classifier output changes
    private var classifierSub: AnyCancellable?

    init() {
        savedDetections = db.fetchAllDetections()
        classifierSub = classifier.$lastOutput
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isClassifying = false }
    }

    func refreshDetections() {
        savedDetections = db.fetchAllDetections()
        // Safety reset in case toast got stuck from a previous session
        if !showBadgeToast { isShowingToast = false }
    }

    private func resetForNewScan() {
        classifier.lastOutput = nil
        capturedImage = nil
        photoSaved = false
        photoSkipped = false
        statusMessage = nil
        isClassifying = true
        selectedVideoURL = nil
        videoDetections = []
        isProcessingVideo = false
        // Reset toast state in case a previous toast got stuck
        isShowingToast = false
        showBadgeToast = false
        badgeQueue.removeAll()
    }

    // Photo

    // Called when the user picks or captures a photo. Resets the scan state,
    // sends the image to the classifier, and checks for the first_photo badge.
    func handlePickedImage(_ image: UIImage) {
        cancelVideo(); resetForNewScan()
        scanMode = .photo; capturedImage = image
        classifier.classify(image: image)
        if let b = badges.award("first_photo") { showToast(b) }
    }

    // Saves the current photo classification result to the local database
    func savePhotoDetection() {
        guard let output = classifier.lastOutput else { statusMessage = "No result to save yet."; return }
        saveDetectionWithLabel(output.label, confidence: output.confidence)
    }

    // Core save function - inserts detection into SQLite, saves the image,
    // uploads to Firebase, refreshes the detection list, and checks badges.
    func saveDetectionWithLabel(_ label: String, confidence: Double) {
        let c = max(0, min(1, confidence))
        if let saved = insertDetection(label: label, confidence: c) {
            if let image = capturedImage, let id = saved.id {
                ImageStore.save(image, for: id)
            }
            FirebaseService.shared.uploadDetection(saved)
            savedDetections = db.fetchAllDetections()
            for b in badges.checkAfterPhotoSave(confidence: c, allDetections: savedDetections) { showToast(b) }
            photoSaved = true
            scheduleReturnToScan()
        }
    }

    func saveAsUnknown() { saveDetectionWithLabel("Unknown Vehicle", confidence: 0) }

    // User chose not to save this detection - skip and return to scan
    func skipDetection() {
        photoSkipped = true
        scheduleReturnToScan(delay: 0.4)
    }

    // Resets all state back to idle so the user can start a fresh scan
    func returnToScan() {
        scanMode = .idle
        classifier.lastOutput = nil
        capturedImage = nil; selectedVideoURL = nil; videoDetections = []
        statusMessage = nil; showAudioContextPrompt = false
        pendingAudioLabel = nil; pendingAudioDetectionId = nil
        photoSaved = false; photoSkipped = false; isClassifying = false
    }

    private func scheduleReturnToScan(delay: Double = 2.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.returnToScan() }
    }

    // Video flow: save/skip -> audio prompt -> home

    // Info about the most recently saved video detection, for the audio prompt
    @Published var pendingAudioLabel: String?
    @Published var pendingAudioConfidence: Double = 0
    @Published var pendingAudioDetectionId: Int64?
    @Published var showAudioContextPrompt = false

    func saveVideoDetection(at index: Int) {
        guard index < videoDetections.count else { return }
        let det = videoDetections[index]
        let c = max(0, min(1, det.confidence))
        if let saved = insertDetection(label: det.label, confidence: c) {
            if let thumb = det.thumbnail, let id = saved.id {
                ImageStore.save(thumb, for: id)
            }
            FirebaseService.shared.uploadDetection(saved, source: .video)
            savedDetections = db.fetchAllDetections()
            for b in badges.checkAfterVideoDetection(allDetections: savedDetections) { showToast(b) }

            if selectedVideoURL != nil, let detId = saved.id {
                pendingAudioLabel = det.label
                pendingAudioConfidence = c
                pendingAudioDetectionId = detId
                showAudioContextPrompt = true
            } else {
                scheduleReturnToScan()
            }
        } else {
            scheduleReturnToScan()
        }
        videoDetections[index].saved = true
        videoDetections[index].correcting = false
    }

    // Called when the user submits the audio context form after a video scan.
    func submitAudioContext(engineAudible: EngineAudible, recordingContext: RecordingContext,
                           vehicleState: VehicleState, backgroundNoise: NoiseLevel) {
        guard let videoURL = selectedVideoURL,
              let label = pendingAudioLabel,
              let detId = pendingAudioDetectionId else {
            scheduleReturnToScan()
            return
        }

        let confidence = pendingAudioConfidence

        extractAndUploadAudio(
            videoURL: videoURL, label: label, confidence: confidence, detectionId: detId,
            engineAudible: engineAudible, recordingContext: recordingContext,
            vehicleState: vehicleState, backgroundNoise: backgroundNoise
        )

        showAudioContextPrompt = false
    }

    func saveVideoDetectionWithLabel(at index: Int, label: String, confidence: Double) {
        guard index < videoDetections.count else { return }
        videoDetections[index].label = label
        videoDetections[index].confidence = confidence
        if let b = badges.checkAfterCorrection() { showToast(b) }
        saveVideoDetection(at: index)
    }

    func saveVideoDetectionAsUnknown(at index: Int) {
        guard index < videoDetections.count else { return }
        videoDetections[index].label = "Unknown Vehicle"
        videoDetections[index].confidence = 0
        if let b = badges.checkAfterCorrection() { showToast(b) }
        saveVideoDetection(at: index)
    }

    func toggleVideoCorrection(at index: Int) {
        guard index < videoDetections.count, !videoDetections[index].handled else { return }
        videoDetections[index].correcting.toggle()
    }

    func skipVideoDetection(at index: Int) {
        guard index < videoDetections.count else { return }
        videoDetections[index].skipped = true
        videoDetections[index].correcting = false
        scheduleReturnToScan(delay: 0.4)
    }

    // Audio Extraction

    private func extractAndUploadAudio(videoURL: URL, label: String, confidence: Double, detectionId: Int64,
                                       engineAudible: EngineAudible = .unsure, recordingContext: RecordingContext = .other,
                                       vehicleState: VehicleState = .unknown, backgroundNoise: NoiseLevel = .moderate) {
        AudioExtractor.extract(from: videoURL) { [weak self] audioURL in
            guard let self else { return }
            guard let audioURL else { return }

            let duration = AudioExtractor.duration(of: audioURL)
            let timestamp = ISO8601DateFormatter().string(from: Date())

            // Move from temp to our managed Documents/RevEyeAudio folder so
            // iOS doesn't clean it up. Only the filename is stored in the DB;
            // the full path is rebuilt on read (the sandbox container UUID
            // changes between installs, so absolute paths go stale).
            let filename = audioURL.lastPathComponent
            let permanentURL = AudioExtractor.audioDirectory.appendingPathComponent(filename)
            do {
                if FileManager.default.fileExists(atPath: permanentURL.path) {
                    try FileManager.default.removeItem(at: permanentURL)
                }
                try FileManager.default.copyItem(at: audioURL, to: permanentURL)
                try? FileManager.default.removeItem(at: audioURL)
            } catch {
                print("Audio: failed to move to Documents - \(error.localizedDescription)")
                return
            }

            let sample = AudioSample(
                id: nil,
                vehicleLabel: label,
                confidence: confidence,
                audioDuration: duration > 0 ? duration : 0,
                engineAudible: engineAudible,
                recordingContext: recordingContext,
                vehicleState: vehicleState,
                backgroundNoise: backgroundNoise,
                userNotes: "",
                localFilePath: filename,
                firebaseStoragePath: nil,
                timestamp: timestamp,
                synced: 0
            )

            guard let sampleId = self.db.insertAudioSample(sample) else { return }

            self.db.linkAudioToDetection(detectionId: detectionId, audioSampleId: sampleId)

            var uploadSample = sample
            uploadSample.id = sampleId
            FirebaseService.shared.uploadAudio(uploadSample) { success in
                if success { let _ = self.badges.checkAfterAudioUpload() }
            }
        }
    }

    // Video Processing

    // Begins processing a video file. Sets up the scan mode and kicks off
    // the frame-by-frame analysis on a background task.
    func startVideoProcessing(url: URL) {
        cancelVideo(); resetForNewScan()
        scanMode = .video; selectedVideoURL = url; isClassifying = false
        videoTask = Task { await processVideo(url: url) }
    }

    func cancelVideo() { videoTask?.cancel(); videoTask = nil }

    // Process video with multi-frame consensus voting.
    // Scans the video in 2-second windows, classifies multiple frames per window,
    // and uses voting to find the most consistent prediction. At the end, only
    // the single best vehicle (most frequently detected, highest confidence) is kept.
    private func processVideo(url: URL) async {
        isProcessingVideo = true
        if let b = badges.award("first_video") { showToast(b) }

        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration).seconds, dur > 0 else {
            isProcessingVideo = false; statusMessage = "Could not read video."; return
        }

        let interval = 2.0
        let windowTimes = stride(from: 0, to: dur, by: interval).map { $0 }
        videoTotal = Double(windowTimes.count)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.3, preferredTimescale: 600)

        var done = 0
        // Track every valid detection across all windows to find the best one
        var allCandidates: [VideoDetection] = []
        var labelCounts: [String: Int] = [:]
        var labelBestConf: [String: Double] = [:]

        for windowStart in windowTimes {
            guard !Task.isCancelled else { isProcessingVideo = false; return }
            done += 1

            let offsets = [0.0, 0.7, 1.4].filter { windowStart + $0 < dur }
            var windowResults: [(output: ClassificationOutput, frame: UIImage)] = []

            for offset in offsets {
                guard !Task.isCancelled else { isProcessingVideo = false; return }
                let t = CMTime(seconds: windowStart + offset, preferredTimescale: 600)
                guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
                let fullFrame = UIImage(cgImage: cg)

                let frameToClassify = cropToSalientRegion(fullFrame) ?? fullFrame

                let out: ClassificationOutput?
                do {
                    out = try await withCheckedThrowingContinuation { cont in
                        if Task.isCancelled { cont.resume(throwing: CancellationError()); return }
                        var sub: AnyCancellable?
                        sub = classifier.$lastOutput.dropFirst().first().sink { r in sub?.cancel(); cont.resume(returning: r) }
                        classifier.classify(image: frameToClassify)
                    }
                } catch { isProcessingVideo = false; return }

                if let out, out.isVehicle, out.tier != .tooLow {
                    windowResults.append((output: out, frame: fullFrame))
                }
            }

            if let best = consensusResult(from: windowResults) {
                // Track how often each label appears and its best confidence
                labelCounts[best.label, default: 0] += 1
                if best.confidence > (labelBestConf[best.label] ?? 0) {
                    labelBestConf[best.label] = best.confidence
                    // Store/update the candidate for this label
                    allCandidates.removeAll { $0.label == best.label }
                    allCandidates.append(VideoDetection(
                        label: best.label,
                        confidence: max(0, min(1, best.confidence)),
                        appearedAt: windowStart,
                        thumbnail: best.frame,
                        top3: best.top3
                    ))
                }
            }

            videoProgress = Double(done)
        }

        // Pick the single best vehicle: most frequently detected, highest confidence as tiebreaker
        if let bestLabel = labelCounts.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return (labelBestConf[a.key] ?? 0) < (labelBestConf[b.key] ?? 0)
        })?.key, let bestDetection = allCandidates.first(where: { $0.label == bestLabel }) {
            videoDetections = [bestDetection]
        }

        isProcessingVideo = false
        statusMessage = videoDetections.isEmpty ? "No vehicles detected." : "Vehicle identified - review below."
    }

    // Consensus Voting

    private struct ConsensusResult {
        let label: String
        let confidence: Double
        let top3: [(label: String, confidence: Double)]
        let frame: UIImage
    }

    // Given multiple classification results from frames within the same time window,
    // pick the most consistent prediction. This filters out random misclassifications.
    private func consensusResult(from results: [(output: ClassificationOutput, frame: UIImage)]) -> ConsensusResult? {
        guard !results.isEmpty else { return nil }

        if results.count == 1 {
            let r = results[0]
            guard r.output.confidence >= 0.15 else { return nil }
            return ConsensusResult(
                label: r.output.label,
                confidence: r.output.confidence,
                top3: r.output.top3,
                frame: r.frame
            )
        }

        var labelCounts: [String: Int] = [:]
        var labelBestConf: [String: Double] = [:]
        var labelBestIdx: [String: Int] = [:]

        for (i, r) in results.enumerated() {
            let label = r.output.label
            labelCounts[label, default: 0] += 1
            if r.output.confidence > (labelBestConf[label] ?? 0) {
                labelBestConf[label] = r.output.confidence
                labelBestIdx[label] = i
            }
        }

        let sorted = labelCounts.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return (labelBestConf[a.key] ?? 0) > (labelBestConf[b.key] ?? 0)
        }

        guard let winner = sorted.first else { return nil }
        let winnerLabel = winner.key
        let idx = labelBestIdx[winnerLabel] ?? 0
        let bestResult = results[idx]

        let voteCount = winner.value
        let conf = bestResult.output.confidence
        guard voteCount >= 2 || conf >= 0.25 else { return nil }

        let boostedConf = voteCount >= 2 ? min(1.0, conf * 1.1) : conf

        return ConsensusResult(
            label: winnerLabel,
            confidence: boostedConf,
            top3: bestResult.output.top3,
            frame: bestResult.frame
        )
    }

    // Saliency Crop

    // Uses Apple's built-in objectness saliency to find the most prominent
    // object in the frame (likely the car), then crops to that region.
    // Returns nil if saliency detection fails; caller falls back to full frame.
    private func cropToSalientRegion(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let result = request.results?.first as? VNSaliencyImageObservation,
              let salientObjects = result.salientObjects,
              !salientObjects.isEmpty else {
            return nil
        }

        let largest = salientObjects.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        })!

        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)
        let box = largest.boundingBox

        let padding: CGFloat = 0.2
        let x = max(0, (box.origin.x - padding) * imgWidth)
        let y = max(0, (1 - box.origin.y - box.height - padding) * imgHeight)
        let w = min(imgWidth - x, (box.width + padding * 2) * imgWidth)
        let h = min(imgHeight - y, (box.height + padding * 2) * imgHeight)

        let cropRect = CGRect(x: x, y: y, width: w, height: h)

        let cropArea = w * h
        let totalArea = imgWidth * imgHeight
        guard cropArea > totalArea * 0.1 && cropArea < totalArea * 0.95 else { return nil }

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    // Helpers

    // Creates a new Detection record in SQLite with the current timestamp
    private func insertDetection(label: String, confidence: Double) -> Detection? {
        let ts = ISO8601DateFormatter().string(from: Date())
        let d = Detection(id: nil, vehicleLabel: label, confidence: confidence, timestamp: ts, synced: 0, audioSampleId: nil)
        guard let id = db.insertDetection(d) else { return nil }
        return Detection(id: id, vehicleLabel: label, confidence: confidence, timestamp: ts, synced: 0, audioSampleId: nil)
    }

    // Adds a badge to the display queue. Badges are shown one at a time
    // with a 2.5 second display, then a brief gap before the next one.
    func showToast(_ badge: Badge) {
        badgeQueue.append(badge)
        drainToastQueue()
    }

    // Shows the next badge in the queue, waits 2.5 seconds, then checks
    // if there are more to show.
    private func drainToastQueue() {
        guard !isShowingToast, !badgeQueue.isEmpty else { return }
        isShowingToast = true
        let badge = badgeQueue.removeFirst()
        toastBadge = badge
        showBadgeToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.showBadgeToast = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.isShowingToast = false
                self?.drainToastQueue()
            }
        }
    }

    func fmtTime(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
