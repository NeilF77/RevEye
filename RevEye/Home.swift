//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//

import SwiftUI
import PhotosUI
import UIKit
import AVKit
import AVFoundation
import FirebaseAuth
import Combine

// Tracks which input the user most recently used so only one result is shown at a time.
// Switching to photo clears video state; switching to video clears photo state.
private enum ActiveMode {
    case none, photo, video
}

struct HomeView: View {

    // MARK: - State

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL? = nil

    @StateObject private var classifier = CarClassifier()

    // Controls which result card is visible — only one is ever shown at a time
    @State private var activeMode: ActiveMode = .none

    // Prevents the Save button being tapped twice on the same photo
    @State private var photoSaved = false

    // Held so we can cancel video processing if the user switches to a photo mid-scan
    @State private var videoTask: Task<Void, Never>? = nil

    @State private var statusMessage: String? = nil
    @State private var isProcessingVideo = false
    @State private var videoProgress: Double = 0
    @State private var videoTotal: Double = 1

    // Each entry is a unique vehicle: (label, confidence, seconds into video)
    @State private var videoDetections: [(label: String, confidence: Double, appearedAt: Double)] = []

    private let db = DatabaseManager.shared

    // Shared source of truth for saved detections — passed as a binding to CollectionView
    // so both views stay in sync without needing onAppear to reload from the DB
    @State private var savedDetections: [Detection] = []

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Input Buttons
                    VStack(spacing: 12) {
                        Button("Take Photo") { showCamera = true }
                            .buttonStyle(AppButtonStyle(color: .blue))
                            .sheet(isPresented: $showCamera) {
                                ImagePicker(sourceType: .camera) { image in
                                    handlePickedImage(image)
                                }
                            }

                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Select Photo")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }

                        Button("Upload Video") { showVideoPicker = true }
                            .buttonStyle(AppButtonStyle(color: .orange))
                            .sheet(isPresented: $showVideoPicker) {
                                VideoPicker { url in
                                    selectedVideoURL = url
                                    videoTask?.cancel()
                                    videoTask = Task { await processVideo(url: url) }
                                }
                            }
                    }

                    // MARK: Photo Result — only shown when the user's last action was a photo
                    if activeMode == .photo, let data = selectedImageData, let uiImage = UIImage(data: data) {
                        VStack(spacing: 8) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 250)
                                .cornerRadius(10)

                            Text(classifier.result)
                                .font(.headline)
                                .multilineTextAlignment(.center)

                            if classifier.lastOutput != nil {
                                Button(photoSaved ? "Saved ✓" : "Save Detection") {
                                    savePhotoDetection()
                                }
                                .buttonStyle(AppButtonStyle(color: photoSaved ? .gray : .blue))
                                .disabled(photoSaved)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // MARK: Status Message
                    if let msg = statusMessage {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // MARK: Video Player — only shown when the user's last action was a video
                    if activeMode == .video, let videoURL = selectedVideoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 220)
                            .cornerRadius(10)
                    }

                    // MARK: Video Scan Progress
                    if activeMode == .video && isProcessingVideo {
                        VStack(spacing: 8) {
                            ProgressView("Scanning video for vehicles…")
                            ProgressView(value: videoProgress, total: videoTotal)
                                .progressViewStyle(.linear)
                            Text("\(Int(videoProgress)) / \(Int(videoTotal)) frames · \(videoDetections.count) unique vehicle(s) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.25))
                        .cornerRadius(10)
                    }

                    // MARK: Video Detection Results
                    if activeMode == .video && !videoDetections.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(isProcessingVideo ? "Vehicles found so far" : "Vehicles Detected")
                                .font(.headline)
                                .padding(.bottom, 10)

                            ForEach(Array(videoDetections.enumerated()), id: \.offset) { _, det in
                                HStack(spacing: 14) {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "car.fill")
                                            .foregroundColor(.orange)
                                    }

                                    // Label + confidence
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(det.label)
                                            .fontWeight(.semibold)
                                        Text("\(Int(det.confidence * 100))% confidence")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // "First seen at X:XX" badge
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("First seen at")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(formatVideoTime(det.appearedAt))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.orange)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.vertical, 10)

                                if det.label != videoDetections.last?.label {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                }
                .padding()
            }
            .onChange(of: selectedItem) { newItem in
                loadPhotoPickerImage(newItem)
            }
            .onAppear {
                savedDetections = db.fetchAllDetections()
            }
            .navigationTitle("RevEye")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink("Collection") {
                            CollectionView(detections: $savedDetections)
                        }
                        Button("Logout") {
                            try? Auth.auth().signOut()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Photo Handling

    private func handlePickedImage(_ image: UIImage) {
        // Cancel any in-progress video scan before switching to photo mode
        videoTask?.cancel()
        videoTask = nil

        activeMode = .photo
        selectedVideoURL = nil
        videoDetections = []
        isProcessingVideo = false
        photoSaved = false  // reset so Save button is available for the new photo

        selectedImageData = image.jpegData(compressionQuality: 0.9)
        statusMessage = nil
        classifier.classify(image: image)
    }

    private func loadPhotoPickerImage(_ item: PhotosPickerItem?) {
        guard let item else { return }

        // Cancel any in-progress video scan before switching to photo mode
        videoTask?.cancel()
        videoTask = nil

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                activeMode = .photo
                selectedVideoURL = nil
                videoDetections = []
                isProcessingVideo = false
                photoSaved = false  // reset so Save button is available for the new photo

                selectedImageData = data
                statusMessage = nil
            }
            classifier.classify(image: image)
        }
    }

    private func savePhotoDetection() {
        guard let output = classifier.lastOutput else {
            statusMessage = "No result to save yet."
            return
        }
        if let saved = insertDetection(label: output.label, confidence: output.confidence) {
            FirebaseService.shared.uploadDetection(saved)
            if output.confidence < 0.7 {
                statusMessage = "Saved with low confidence (\(Int(output.confidence * 100))%) — result may be inaccurate."
            } else {
                statusMessage = "Saved: \(saved.vehicleLabel)"
            }
            photoSaved = true
            savedDetections = db.fetchAllDetections()
        }
    }

    // MARK: - Video Processing

    /// Samples one frame per second, runs the ML classifier on each frame, and saves
    /// the first confident detection of each unique vehicle label.
    ///
    /// DEDUPLICATION: `seenLabels` is a Set that accumulates label strings as we scan.
    /// When a label is already in the set, that vehicle has already been recorded and
    /// the frame is skipped — so each vehicle appears exactly once in the results.
    ///
    /// VIDEO TIMESTAMP: We record `time.seconds` (position in the video) not wall-clock
    /// time, so the user can see "first seen at 0:14" rather than a date string.
    ///
    /// AWAITING THE CLASSIFIER: CarClassifier.classify() dispatches internally via
    /// DispatchQueue and publishes via @Published. We subscribe to $lastOutput with a
    /// Combine continuation so we always wait for the result of the *current* frame
    /// before moving on — avoiding a race condition on lastOutput.
    private func processVideo(url: URL) async {
        await MainActor.run {
            // Switch to video mode — clears any photo result from the screen
            activeMode = .video
            selectedImageData = nil

            isProcessingVideo = true
            videoDetections = []
            videoProgress = 0
            videoTotal = 1
            statusMessage = nil
        }

        let asset = AVURLAsset(url: url)

        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            await MainActor.run {
                isProcessingVideo = false
                statusMessage = "Could not read video."
            }
            return
        }

        // One frame per second. Increase interval (e.g. 2.0) to scan faster on long videos.
        let interval: Double = 1.0
        let times = stride(from: 0.0, to: duration, by: interval).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }

        await MainActor.run { videoTotal = Double(times.count) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        var framesProcessed = 0
        var seenLabels = Set<String>()  // prevents the same vehicle being shown twice

        for time in times {
            // Stop immediately if the user has switched to a photo
            guard !Task.isCancelled else {
                await MainActor.run { isProcessingVideo = false }
                return
            }

            framesProcessed += 1

            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                await MainActor.run { videoProgress = Double(framesProcessed) }
                continue
            }

            // Await the classifier result for this specific frame.
            // We use a throwing continuation so that Swift cooperative cancellation
            // (triggered when the user picks a photo mid-scan) immediately throws
            // CancellationError, which we catch to exit the loop cleanly.
            // Without this, the continuation would hang indefinitely waiting for
            // $lastOutput to emit if the task is cancelled between frames.
            let output: ClassificationOutput?
            do {
                output = try await withCheckedThrowingContinuation { continuation in
                    // Register cancellation handler BEFORE subscribing, so if the task
                    // is already cancelled this path is taken immediately.
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    var cancellable: AnyCancellable?
                    cancellable = classifier.$lastOutput
                        .dropFirst()
                        .first()
                        .sink { result in
                            cancellable?.cancel()
                            continuation.resume(returning: result)
                        }
                    classifier.classify(image: UIImage(cgImage: cgImage))
                }
            } catch {
                // CancellationError (or any Vision error propagated up) — stop processing
                await MainActor.run { isProcessingVideo = false }
                return
            }

            // Only record if confident and not seen before
            if let output, output.confidence >= 0.6, !seenLabels.contains(output.label) {
                seenLabels.insert(output.label)
                let appearedAt = time.seconds

                // Save to SQLite + queue Firebase sync
                if let saved = insertDetection(label: output.label, confidence: output.confidence) {
                    FirebaseService.shared.uploadDetection(saved, source: .video)
                    await MainActor.run { savedDetections = db.fetchAllDetections() }
                }

                await MainActor.run {
                    videoDetections.append((
                        label: output.label,
                        confidence: output.confidence,
                        appearedAt: appearedAt
                    ))
                }
            }

            await MainActor.run { videoProgress = Double(framesProcessed) }
        }

        await MainActor.run {
            isProcessingVideo = false
            let count = videoDetections.count
            statusMessage = count == 0
                ? "No vehicles detected. Try a clearer video."
                : "Found \(count) unique vehicle\(count == 1 ? "" : "s")."
        }
    }

    // MARK: - Helpers

    /// Inserts a detection into SQLite and returns the saved record with its new ID.
    private func insertDetection(label: String, confidence: Double) -> Detection? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let toInsert = Detection(id: nil, vehicleLabel: label, confidence: confidence,
                                 timestamp: timestamp, synced: 0)
        guard let newId = db.insertDetection(toInsert) else { return nil }
        return Detection(id: newId, vehicleLabel: label, confidence: confidence,
                         timestamp: timestamp, synced: 0)
    }

    /// Converts raw seconds to a "m:ss" display string  e.g. 75.0 → "1:15"
    private func formatVideoTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Button Style

private struct AppButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}

#Preview {
    HomeView()
}
