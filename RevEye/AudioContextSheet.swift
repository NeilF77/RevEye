//
//  AudioContextSheet.swift
//  RevEye
//
//  Created by user on 10/03/2026.
//

import SwiftUI
import AVFoundation

/// Presented as a sheet after video processing completes.
/// Lets the user provide context about the audio in their video
/// before extracting and uploading it to the audio database.
struct AudioContextSheet: View {

    // Input from the parent
    let videoURL: URL
    let vehicleLabel: String
    let confidence: Double
    let detectionIds: [Int64]           // detection row IDs from this video scan

    // Dismiss
    @Environment(\.dismiss) private var dismiss

    // Audio metadata form state
    @State private var engineAudible: EngineAudible = .unsure
    @State private var recordingContext: RecordingContext = .outsideNear
    @State private var vehicleState: VehicleState = .unknown
    @State private var backgroundNoise: NoiseLevel = .moderate
    @State private var userNotes: String = ""

    // Processing state
    @State private var isExtracting = false
    @State private var isUploading = false
    @State private var resultMessage: String?
    @State private var didSubmit = false

    private let db = DatabaseManager.shared
    private let badgeService = BadgeService.shared

    var body: some View {
        NavigationView {
            Form {
                // MARK: Vehicle Info
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "car.fill")
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicleLabel)
                                .fontWeight(.semibold)
                            Text("\(Int(confidence * 100))% confidence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Vehicle Detected")
                }

                // MARK: Audio Context
                Section {
                    Picker("Can you hear the engine?", selection: $engineAudible) {
                        ForEach(EngineAudible.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("How was this recorded?", selection: $recordingContext) {
                        ForEach(RecordingContext.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("What was the vehicle doing?", selection: $vehicleState) {
                        ForEach(VehicleState.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("Background noise level", selection: $backgroundNoise) {
                        ForEach(NoiseLevel.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } header: {
                    Text("Audio Context")
                } footer: {
                    Text("This information helps researchers filter audio samples by quality and context.")
                }

                // MARK: Notes
                Section {
                    TextField("Optional notes (e.g., \"recorded at car meet\")", text: $userNotes)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Notes")
                }

                // MARK: Submit
                Section {
                    if let msg = resultMessage {
                        Label(msg, systemImage: didSubmit ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(didSubmit ? .green : .orange)
                            .font(.subheadline)
                    }

                    Button {
                        extractAndUpload()
                    } label: {
                        HStack {
                            if isExtracting || isUploading {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(statusLabel)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isExtracting || isUploading || didSubmit)
                } footer: {
                    Text("The audio track will be extracted from your video and uploaded to the RevEye audio database.")
                }
            }
            .navigationTitle("Contribute Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .disabled(isExtracting || isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if didSubmit {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Computed

    private var statusLabel: String {
        if isExtracting { return "Extracting audio…" }
        if isUploading  { return "Uploading…" }
        if didSubmit    { return "Submitted ✓" }
        return "Extract & Submit Audio"
    }

    // MARK: - Actions

    private func extractAndUpload() {
        isExtracting = true
        resultMessage = nil

        AudioExtractor.extract(from: videoURL) { audioURL in
            DispatchQueue.main.async {
                isExtracting = false

                guard let audioURL else {
                    resultMessage = "Could not extract audio from this video."
                    return
                }

                // Get audio duration
                let asset = AVURLAsset(url: audioURL)
                let duration = CMTimeGetSeconds(asset.duration)

                // Build the AudioSample
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let sample = AudioSample(
                    id: nil,
                    vehicleLabel:        vehicleLabel,
                    confidence:          confidence,
                    audioDuration:       duration > 0 ? duration : 0,
                    engineAudible:       engineAudible,
                    recordingContext:    recordingContext,
                    vehicleState:        vehicleState,
                    backgroundNoise:     backgroundNoise,
                    userNotes:           userNotes,
                    localFilePath:       audioURL.path,
                    firebaseStoragePath: nil,
                    timestamp:           timestamp,
                    synced:              0
                )

                // Save locally
                guard let sampleId = db.insertAudioSample(sample) else {
                    resultMessage = "Could not save audio sample."
                    return
                }

                // Link audio to the detection(s) from this video
                for detId in detectionIds {
                    db.linkAudioToDetection(detectionId: detId, audioSampleId: sampleId)
                }

                // Upload to Firebase
                isUploading = true
                var uploadSample = sample
                uploadSample.id = sampleId

                FirebaseService.shared.uploadAudio(uploadSample) { success in
                    isUploading = false
                    if success {
                        didSubmit = true
                        resultMessage = "Audio contributed successfully!"

                        // Check audio badges
                        let newBadges = badgeService.checkAfterAudioUpload()
                        if !newBadges.isEmpty {
                            resultMessage = "Audio contributed! Badge earned: \(newBadges.first?.title ?? "")"
                        }
                    } else {
                        resultMessage = "Saved locally. Will upload when online."
                        didSubmit = true  // Still count as submitted locally
                    }
                }
            }
        }
    }
}
