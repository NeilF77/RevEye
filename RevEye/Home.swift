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

struct HomeView: View {

    // MARK: - State

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL? = nil

    @StateObject private var classifier = CarClassifier()

    @State private var statusMessage: String? = nil
    @State private var isProcessingVideo = false
    @State private var videoProgress: Double = 0      // frames done
    @State private var videoTotal: Double = 1         // total frames
    @State private var videoDetections: [Detection] = []

    private let db = DatabaseManager.shared

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Input Buttons
                    VStack(spacing: 12) {
                        // Camera
                        Button("Take Photo") { showCamera = true }
                            .buttonStyle(AppButtonStyle(color: .blue))
                            .sheet(isPresented: $showCamera) {
                                ImagePicker(sourceType: .camera) { image in
                                    handlePickedImage(image)
                                }
                            }

                        // Photo library
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Select Photo")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }

                        // Video
                        Button("Upload Video") { showVideoPicker = true }
                            .buttonStyle(AppButtonStyle(color: .orange))
                            .sheet(isPresented: $showVideoPicker) {
                                VideoPicker { url in
                                    selectedVideoURL = url
                                    videoDetections = []
                                    Task { await processVideo(url: url) }
                                }
                            }
                    }

                    // MARK: Photo result
                    if let data = selectedImageData, let uiImage = UIImage(data: data) {
                        VStack(spacing: 8) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 250)
                                .cornerRadius(10)

                            Text(classifier.result)
                                .font(.headline)
                                .multilineTextAlignment(.center)

                            // Only show Save once the classifier has a result
                            if classifier.lastOutput != nil {
                                Button("Save Detection") { savePhotoDetection() }
                                    .buttonStyle(AppButtonStyle(color: .blue))
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // MARK: Status message
                    if let msg = statusMessage {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // MARK: Video player
                    if let videoURL = selectedVideoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 220)
                            .cornerRadius(10)
                    }

                    // MARK: Video processing progress
                    if isProcessingVideo {
                        VStack(spacing: 8) {
                            ProgressView("Scanning video for vehicles…")
                            ProgressView(value: videoProgress, total: videoTotal)
                                .progressViewStyle(.linear)
                            Text("\(Int(videoProgress)) / \(Int(videoTotal)) frames · \(videoDetections.count) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.25))
                        .cornerRadius(10)
                    }

                    // MARK: Video detections list
                    if !videoDetections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isProcessingVideo ? "Detections so far" : "Video Detections (\(videoDetections.count))")
                                .font(.headline)

                            ForEach(videoDetections) { detection in
                                HStack {
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 36)
                                    VStack(alignment: .leading) {
                                        Text(detection.vehicleLabel)
                                            .fontWeight(.semibold)
                                        Text("\(Int(detection.confidence * 100))% confidence")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    }

                }
                .padding()
            }
            .onChange(of: selectedItem) { newItem in
                loadPhotoPickerImage(newItem)
            }
            .navigationTitle("RevEye")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink("Collection") { CollectionView() }
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
        selectedImageData = image.jpegData(compressionQuality: 0.9)
        statusMessage = nil
        classifier.classify(image: image)
    }

    private func loadPhotoPickerImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
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
        guard output.confidence >= 0.7 else {
            statusMessage = "Confidence too low (<70%). Try a clearer photo."
            return
        }
        if let saved = insertDetection(label: output.label, confidence: output.confidence) {
            FirebaseService.shared.uploadDetection(saved)
            statusMessage = "Saved: \(saved.vehicleLabel)"
        }
    }

    // MARK: - Video Processing

    /// Samples one frame per second, classifies each with the ML model, and saves hits.
    ///
    /// WHY we use a Combine continuation here:
    /// CarClassifier.classify() dispatches work onto a background DispatchQueue and publishes
    /// the result via @Published on the main thread. If we just call classify() and immediately
    /// read lastOutput, we'll always get the *previous* frame's result — a race condition.
    /// By subscribing to $lastOutput and awaiting the *next* emission, we guarantee we have
    /// the correct result for the current frame before moving on.
    private func processVideo(url: URL) async {
        await MainActor.run {
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

        // Sample every 1 second. Raise this (e.g. 2.0) to go faster on long videos.
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
        var detectionsFound = 0

        for time in times {
            framesProcessed += 1

            // Extract the frame — skip if extraction fails
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                await MainActor.run { videoProgress = Double(framesProcessed) }
                continue
            }

            let uiImage = UIImage(cgImage: cgImage)

            // Await the real classification result using a Combine subscription.
            // dropFirst() skips the current stale value; first() completes after one new value.
            let output: ClassificationOutput? = await withCheckedContinuation { continuation in
                var cancellable: AnyCancellable?
                cancellable = classifier.$lastOutput
                    .dropFirst()
                    .first()
                    .sink { result in
                        cancellable?.cancel()
                        continuation.resume(returning: result)
                    }
                classifier.classify(image: uiImage)
            }

            if let output, output.confidence >= 0.6 {
                if let saved = insertDetection(label: output.label, confidence: output.confidence) {
                    detectionsFound += 1
                    FirebaseService.shared.uploadDetection(saved)
                    await MainActor.run { videoDetections.append(saved) }
                }
            }

            await MainActor.run { videoProgress = Double(framesProcessed) }
        }

        await MainActor.run {
            isProcessingVideo = false
            statusMessage = "Done — \(framesProcessed) frames scanned, \(detectionsFound) vehicle(s) detected"
        }
    }

    // MARK: - Helpers

    /// Creates a Detection, saves it to SQLite, and returns the saved copy with its new ID.
    private func insertDetection(label: String, confidence: Double) -> Detection? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let toInsert = Detection(id: nil, vehicleLabel: label, confidence: confidence,
                                 timestamp: timestamp, synced: 0)
        guard let newId = db.insertDetection(toInsert) else { return nil }
        return Detection(id: newId, vehicleLabel: label, confidence: confidence,
                         timestamp: timestamp, synced: 0)
    }
}

// MARK: - Reusable Button Style

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
