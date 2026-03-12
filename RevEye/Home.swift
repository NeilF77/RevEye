//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//  Updated 10/03/2026 — confidence tiers, audio context sheet, improved flow

import SwiftUI
import PhotosUI
import UIKit
import AVKit
import AVFoundation
import FirebaseAuth
import Combine

private enum ActiveMode { case none, photo, video }

struct HomeView: View {

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL? = nil
    @StateObject private var classifier = CarClassifier()
    @State private var activeMode: ActiveMode = .none
    @State private var photoSaved = false
    @State private var videoTask: Task<Void, Never>? = nil
    @State private var statusMessage: String? = nil
    @State private var isProcessingVideo = false
    @State private var videoProgress: Double = 0
    @State private var videoTotal: Double = 1
    @State private var videoDetections: [(label: String, confidence: Double, appearedAt: Double)] = []
    @State private var videoDetectionIds: [Int64] = []          // row IDs for audio linking
    @State private var newBadge: Badge? = nil
    @State private var showBadgeToast = false
    @State private var showAudioSheet = false                   // audio context sheet trigger
    private let db = DatabaseManager.shared
    private let badgeService = BadgeService.shared
    @State private var savedDetections: [Detection] = []

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 20) {

                        // ── Action Buttons ──────────────────────────────
                        VStack(spacing: 12) {
                            Button("Take Photo") { showCamera = true }
                                .buttonStyle(AppButtonStyle(color: .blue))
                                .sheet(isPresented: $showCamera) {
                                    ImagePicker(sourceType: .camera) { image in handlePickedImage(image) }
                                }

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Text("Select Photo")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.green).foregroundColor(.white)
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

                        // ── Photo Result ────────────────────────────────
                        if activeMode == .photo, let data = selectedImageData,
                           let uiImage = UIImage(data: data) {
                            photoResultCard(uiImage: uiImage)
                        }

                        // ── Status Message ──────────────────────────────
                        if let msg = statusMessage {
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // ── Video Player ────────────────────────────────
                        if activeMode == .video, let videoURL = selectedVideoURL {
                            VideoPlayer(player: AVPlayer(url: videoURL))
                                .frame(height: 220).cornerRadius(10)
                        }

                        // ── Video Progress ──────────────────────────────
                        if activeMode == .video && isProcessingVideo {
                            VStack(spacing: 8) {
                                ProgressView("Scanning video for vehicles…")
                                ProgressView(value: videoProgress, total: videoTotal)
                                    .progressViewStyle(.linear)
                                Text("\(Int(videoProgress)) / \(Int(videoTotal)) frames · \(videoDetections.count) vehicle(s)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding().background(Color.yellow.opacity(0.25)).cornerRadius(10)
                        }

                        // ── Video Detections List ───────────────────────
                        if activeMode == .video && !videoDetections.isEmpty {
                            videoDetectionsList
                        }
                    }
                    .padding()
                }

                // ── Badge Toast Overlay ─────────────────────────
                if showBadgeToast, let badge = newBadge {
                    BadgeToast(badge: badge)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1).padding(.top, 8)
                }
            }
            .animation(.spring(response: 0.4), value: showBadgeToast)
            .onChange(of: selectedItem) { _, newItem in
                loadPhotoPickerImage(newItem)
            }
            .onAppear { savedDetections = db.fetchAllDetections() }
            .navigationTitle("RevEye")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink("Badges")     { BadgesView() }
                        NavigationLink("Collection")  { CollectionView(detections: $savedDetections) }
                        Button("Logout") { AuthService.shared.signOut() }
                            .foregroundStyle(.red)
                    }
                }
            }
            // Audio context sheet — presented after video scan completes
            .sheet(isPresented: $showAudioSheet) {
                if let url = selectedVideoURL, let firstDet = videoDetections.first {
                    AudioContextSheet(
                        videoURL: url,
                        vehicleLabel: firstDet.label,
                        confidence: firstDet.confidence,
                        detectionIds: videoDetectionIds
                    )
                }
            }
        }
    }

    // MARK: - Photo Result Card

    @ViewBuilder
    private func photoResultCard(uiImage: UIImage) -> some View {
        VStack(spacing: 8) {
            Image(uiImage: uiImage)
                .resizable().scaledToFit()
                .frame(maxHeight: 250).cornerRadius(10)

            // Confidence-tier-aware display
            if let output = classifier.lastOutput {
                resultView(for: output)
            } else {
                Text(classifier.result)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            // Save button — only show when we have a usable result
            if let output = classifier.lastOutput, output.isVehicle, output.tier != .tooLow {
                Button(photoSaved ? "Saved ✓" : "Save Detection") { savePhotoDetection() }
                    .buttonStyle(AppButtonStyle(color: photoSaved ? .gray : .blue))
                    .disabled(photoSaved)
            }
        }
        .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
    }

    /// Shows the prediction with appropriate styling based on confidence tier.
    @ViewBuilder
    private func resultView(for output: ClassificationOutput) -> some View {
        if !output.isVehicle {
            // OOD guard fired — no vehicle in image
            Label("No vehicle detected in this image.", systemImage: "xmark.circle")
                .font(.subheadline).foregroundColor(.orange)
        } else {
            switch output.tier {
            case .tooLow:
                Label("Could not identify a vehicle. Try a clearer photo.",
                      systemImage: "questionmark.circle")
                    .font(.subheadline).foregroundColor(.orange)

            case .low:
                VStack(spacing: 4) {
                    Text(output.label)
                        .font(.headline)
                    Text("Low confidence: \(Int(output.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                    if output.isAmbiguous, output.top3.count >= 2 {
                        Text("Also possible: \(output.top3[1].label)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Text("This result may be inaccurate.")
                        .font(.caption2).foregroundColor(.secondary)
                }

            case .high:
                VStack(spacing: 4) {
                    Text(output.label)
                        .font(.headline)
                    Text("\(Int(output.confidence * 100))% confidence")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    if output.isAmbiguous, output.top3.count >= 2 {
                        Text("Also possible: \(output.top3[1].label)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Video Detections List

    private var videoDetectionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isProcessingVideo ? "Vehicles found so far" : "Vehicles Detected")
                .font(.headline).padding(.bottom, 10)

            ForEach(Array(videoDetections.enumerated()), id: \.offset) { _, det in
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: "car.fill").foregroundColor(.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(det.label).fontWeight(.semibold)
                            .minimumScaleFactor(0.5).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Int(det.confidence * 100))% confidence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("First seen at").font(.caption2).foregroundStyle(.secondary)
                        Text(formatVideoTime(det.appearedAt))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.orange).monospacedDigit()
                    }
                }
                .padding(.vertical, 10)
                if det.label != videoDetections.last?.label { Divider() }
            }
        }
        .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
    }

    // MARK: - Photo Handling

    private func handlePickedImage(_ image: UIImage) {
        videoTask?.cancel(); videoTask = nil
        activeMode = .photo; selectedVideoURL = nil; videoDetections = []
        videoDetectionIds = []; isProcessingVideo = false; photoSaved = false
        selectedImageData = image.jpegData(compressionQuality: 0.9)
        statusMessage = nil
        classifier.classify(image: image)
        if let b = badgeService.award("first_photo") { showToast(b) }
    }

    private func loadPhotoPickerImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        videoTask?.cancel(); videoTask = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                activeMode = .photo; selectedVideoURL = nil; videoDetections = []
                videoDetectionIds = []; isProcessingVideo = false; photoSaved = false
                selectedImageData = data; statusMessage = nil
                classifier.classify(image: image)
                // Award badge on main thread to avoid threading issues
                if let b = badgeService.award("first_photo") {
                    showToast(b)
                }
            }
        }
    }

    private func savePhotoDetection() {
        guard let output = classifier.lastOutput else {
            statusMessage = "No result to save yet."; return
        }
        let confidence = max(0.0, min(1.0, output.confidence))
        if let saved = insertDetection(label: output.label, confidence: confidence) {
            FirebaseService.shared.uploadDetection(saved) { success in
                if success, let b = self.badgeService.award("first_sync") { self.showToast(b) }
            }
            savedDetections = db.fetchAllDetections()
            for badge in badgeService.checkAfterPhotoSave(confidence: confidence,
                                                           allDetections: savedDetections) {
                showToast(badge)
            }
            statusMessage = confidence < 0.30
                ? "Saved with low confidence (\(Int(confidence * 100))%) — result may be inaccurate."
                : "Saved: \(saved.vehicleLabel)"
            photoSaved = true
        }
    }

    // MARK: - Video Processing

    private func processVideo(url: URL) async {
        await MainActor.run {
            activeMode = .video; selectedImageData = nil; isProcessingVideo = true
            videoDetections = []; videoDetectionIds = []; videoProgress = 0
            videoTotal = 1; statusMessage = nil
        }
        if let b = badgeService.award("first_video") {
            await MainActor.run { showToast(b) }
        }

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            await MainActor.run { isProcessingVideo = false; statusMessage = "Could not read video." }
            return
        }
        let times = stride(from: 0.0, to: duration, by: 1.0)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }
        await MainActor.run { videoTotal = Double(times.count) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        var framesProcessed = 0
        var seenLabels = Set<String>()

        for time in times {
            guard !Task.isCancelled else {
                await MainActor.run { isProcessingVideo = false }; return
            }
            framesProcessed += 1
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                await MainActor.run { videoProgress = Double(framesProcessed) }; continue
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
                await MainActor.run { isProcessingVideo = false }; return
            }

            // Only accept results that are vehicles, above threshold, and not yet seen.
            // With 196 classes, 20% confidence is a meaningful signal.
            if let output,
               output.isVehicle,
               output.tier != .tooLow,
               max(0.0, min(1.0, output.confidence)) >= 0.15,
               !seenLabels.contains(output.label) {

                seenLabels.insert(output.label)
                let confidence = max(0.0, min(1.0, output.confidence))
                if let saved = insertDetection(label: output.label, confidence: confidence) {
                    FirebaseService.shared.uploadDetection(saved, source: .video)
                    await MainActor.run {
                        if let id = saved.id { videoDetectionIds.append(id) }
                        savedDetections = db.fetchAllDetections()
                    }
                }
                await MainActor.run {
                    videoDetections.append((label: output.label,
                                            confidence: output.confidence,
                                            appearedAt: time.seconds))
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

            for badge in badgeService.checkAfterVideoDetection(allDetections: savedDetections) {
                showToast(badge)
            }

            // Offer audio contribution if we found any vehicles
            if count > 0 {
                // Small delay so the user can see the results first
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showAudioSheet = true
                }
            }
        }
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

    private func formatVideoTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func showToast(_ badge: Badge) {
        guard !showBadgeToast else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.showToast(badge) }
            return
        }
        newBadge = badge
        withAnimation { showBadgeToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation { showBadgeToast = false }
        }
    }
}

// MARK: - Badge Toast

private struct BadgeToast: View {
    let badge: Badge
    var body: some View {
        HStack(spacing: 12) {
            Text(badge.emoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked!")
                    .font(.caption).foregroundColor(.orange).fontWeight(.semibold)
                Text(badge.title)
                    .font(.subheadline).fontWeight(.bold)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial).cornerRadius(14)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Button Style

private struct AppButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body).frame(maxWidth: .infinity).padding()
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white).cornerRadius(12)
    }
}

#Preview { HomeView() }
