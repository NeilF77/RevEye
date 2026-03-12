//
//  AudioLibraryView.swift
//  RevEye
//
//  Created by user on 10/03/2026.
//
//  Browse and play back audio samples the user has contributed.
//  Accessible from a NavigationLink in HomeView toolbar or BadgesView.

import SwiftUI
import AVFoundation

struct AudioLibraryView: View {
    @State private var samples: [AudioSample] = []
    @State private var playingId: Int64? = nil
    @State private var audioPlayer: AVAudioPlayer?

    private let db = DatabaseManager.shared

    var body: some View {
        Group {
            if samples.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No audio samples yet")
                        .font(.headline).foregroundColor(.secondary)
                    Text("Upload a video with a vehicle to contribute audio to the database.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                List {
                    Section {
                        Text("\(samples.count) audio sample\(samples.count == 1 ? "" : "s") contributed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    ForEach(samples) { sample in
                        audioRow(sample)
                    }
                }
            }
        }
        .navigationTitle("Audio Library")
        .onAppear {
            samples = db.fetchAllAudioSamples()
        }
        .onDisappear {
            audioPlayer?.stop()
            playingId = nil
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func audioRow(_ sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Vehicle + confidence
            HStack {
                Text(sample.vehicleLabel)
                    .font(.headline)
                Spacer()
                Label(
                    sample.synced == 1 ? "Uploaded" : "Local",
                    systemImage: sample.synced == 1 ? "checkmark.icloud" : "icloud.slash"
                )
                .font(.caption)
                .foregroundColor(sample.synced == 1 ? .blue : .orange)
            }

            // Metadata tags
            HStack(spacing: 8) {
                metadataTag(sample.engineAudible.label, icon: "speaker.wave.2")
                metadataTag(sample.vehicleState.label, icon: "car")
                metadataTag(sample.backgroundNoise.label, icon: "waveform")
            }

            // Duration + context
            HStack {
                Text(formatDuration(sample.audioDuration))
                    .font(.caption).foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text(sample.recordingContext.label)
                    .font(.caption).foregroundColor(.secondary)
            }

            // Notes
            if !sample.userNotes.isEmpty {
                Text(sample.userNotes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Play button
            Button {
                togglePlayback(sample)
            } label: {
                HStack {
                    Image(systemName: playingId == sample.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(playingId == sample.id ? "Stop" : "Play")
                        .font(.subheadline)
                }
                .foregroundColor(.orange)
            }
            .buttonStyle(.plain)

            // Timestamp
            Text(formatWallTime(sample.timestamp))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Playback

    private func togglePlayback(_ sample: AudioSample) {
        if playingId == sample.id {
            audioPlayer?.stop()
            playingId = nil
            return
        }

        let url = URL(fileURLWithPath: sample.localFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            playingId = sample.id
        } catch {
            print("Playback error: \(error.localizedDescription)")
            playingId = nil
        }
    }

    // MARK: - Helpers

    private func metadataTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(.systemGray5))
        .cornerRadius(6)
        .foregroundColor(.secondary)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatWallTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
