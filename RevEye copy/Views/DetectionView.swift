// DetectionView.swift
// RevEye
//
// Detail view for a single saved detection. Shows the full image, vehicle
// name with confidence, metadata (date, time, sync status), audio playback
// if an audio sample is linked, and share/delete options.

import SwiftUI
import AVFoundation

struct DetectionView: View {
    // The detection to display (passed in from GarageView)
    let detection: Detection
    // Callback to run when the user confirms deletion
    let onDelete: () -> Void

    // The detection image loaded from disk
    @State private var image: UIImage?
    @State private var showDeleteConfirm = false
    @State private var audioSample: AudioSample?
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showShareSheet = false
    @State private var shareBadge: Badge?
    @State private var showShareBadgeToast = false

    private let db = DatabaseManager.shared
    // Badge service for tracking share badges
    private let badges = BadgeService.shared

    
    // The main layout - scrollable content with image, info card, metadata,
    // audio section (if present), and delete button. Share icon overlays the image.
    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: RE.s24) {

                    
                    // Vehicle image with share icon overlay (appears when saved)
if let img = image {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .cornerRadius(RE.r12)
                            .padding(.horizontal, RE.s16)
                            .padding(.top, RE.s8)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: RE.r12)
                                .fill(REColors.bgCard)
                                .frame(height: 200)
                            VStack(spacing: RE.s8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 32, weight: .ultraLight))
                                    .foregroundColor(REColors.textDim)
                                Text("No image saved")
                                    .font(REFont.caption)
                                    .foregroundColor(REColors.textDim)
                            }
                        }
                        .padding(.horizontal, RE.s16)
                        .padding(.top, RE.s8)
                    }

                    
                    // Vehicle name and confidence badge
VStack(spacing: RE.s12) {
                        let confColor = REColors.displayConf(detection.confidence)
                        if detection.vehicleLabel != "Unknown Vehicle" {
                            Text("\(Int(detection.confidence * 100))% match")
                                .font(REFont.caption).foregroundColor(confColor)
                                .padding(.horizontal, RE.s12).padding(.vertical, RE.s4)
                                .background(confColor.opacity(0.1)).cornerRadius(100)
                        }

                        Text(detection.vehicleLabel)
                            .font(REFont.title)
                            .foregroundColor(REColors.text)
                            .multilineTextAlignment(.center)
                    }

                    
                    // Metadata card showing date, time, confidence, and sync status
VStack(spacing: 0) {
                        metaRow("calendar", "Date", fmtDate(detection.timestamp))
                        Divider().background(REColors.bgInput)
                        metaRow("clock", "Time", fmtTime(detection.timestamp))
                        Divider().background(REColors.bgInput)
                        metaRow("chart.bar", "Confidence", "\(Int(detection.confidence * 100))%")
                        Divider().background(REColors.bgInput)
                        metaRow(detection.synced == 1 ? "checkmark.icloud" : "icloud.slash",
                                "Sync Status", detection.synced == 1 ? "Synced" : "Pending")
                    }
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16)

                    
                    // Audio section - only shown if this detection has a linked audio sample
if let sample = audioSample {
                        audioSection(sample)
                            .padding(.horizontal, RE.s16)
                    } else if detection.audioSampleId != nil {
                        
                    // Audio sample linked placeholder
HStack(spacing: RE.s12) {
                            Image(systemName: "waveform")
                                .foregroundColor(REColors.textDim)
                            Text("Audio sample linked")
                                .font(REFont.caption).foregroundColor(REColors.textDim)
                        }
                        .padding(RE.s16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(REColors.bgCard)
                        .cornerRadius(RE.r12)
                        .padding(.horizontal, RE.s16)
                    }

                    
                    // Share button
if let img = image {
                        Button {
                            showShareSheet = true
                        } label: {
                            HStack(spacing: RE.s8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Detection")
                            }
                        }
                        .buttonStyle(REPrimaryButton(color: REColors.blue))
                        .padding(.horizontal, RE.s16)
                        .sheet(isPresented: $showShareSheet) {
                            let shareText = "I spotted a \(detection.vehicleLabel) with \(Int(detection.confidence * 100))% confidence using RevEye! 🚗"
                            ShareSheet(items: [shareText, img]) {
                                let earned = badges.checkAfterShare()
                                if let first = earned.first {
                                    shareBadge = first
                                    withAnimation { showShareBadgeToast = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        withAnimation { showShareBadgeToast = false }
                                    }
                                }
                            }
                        }
                    }

                    
                    // Delete button with confirmation alert
Button { showDeleteConfirm = true } label: {
                        Text("Delete Detection")
                    }
                    .buttonStyle(REDestructiveButton())
                    .padding(.horizontal, RE.s16)

                    Spacer().frame(height: RE.s48)
                }
            }

            if showShareBadgeToast, let badge = shareBadge {
                VStack {
                    Spacer()
                    HStack(spacing: RE.s12) {
                        Text(badge.emoji).font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Badge Earned!").font(REFont.label).foregroundColor(REColors.accent)
                            Text(badge.title).font(REFont.body).foregroundColor(REColors.text)
                        }
                        Spacer()
                    }
                    .padding(RE.s16)
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)
                    .overlay(RoundedRectangle(cornerRadius: RE.r12).stroke(REColors.accent.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, RE.s16)
                    .padding(.bottom, RE.s32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .navigationTitle("Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
                // Load the image and audio sample when the view appears
.onAppear {
            if let id = detection.id {
                image = ImageStore.load(for: id)
            }
            if let audioId = detection.audioSampleId {
                audioSample = loadAudioSample(id: audioId)
            }
        }
        .onDisappear {
            audioPlayer?.stop()
        }
        .alert("Delete Detection?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = detection.id {
                    ImageStore.delete(for: id)
                }
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this detection and its image.")
        }
    }

    // Audio Section

    // Audio playback section - shown when this detection has a linked audio sample.
    // Includes play/stop button, waveform visualisation, duration, and metadata chips.
    private func audioSection(_ sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: RE.s12) {

            HStack(spacing: RE.s8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(REColors.blueLight)
                Text("Audio Sample")
                    .font(REFont.heading)
                    .foregroundColor(REColors.text)
                Spacer()
                HStack(spacing: RE.s4) {
                    Image(systemName: sample.synced == 1 ? "checkmark.icloud" : "icloud.slash")
                        .font(.system(size: 10))
                    Text(sample.synced == 1 ? "Uploaded" : "Local")
                        .font(REFont.small)
                }
                .foregroundColor(sample.synced == 1 ? REColors.blueLight : REColors.accent)
            }

            HStack(spacing: RE.s16) {
                Button { togglePlayback(sample) } label: {
                    ZStack {
                        Circle()
                            .fill(REColors.accent.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(REColors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: RE.s4) {
                    HStack(spacing: 2) {
                        ForEach(0..<20, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isPlaying ? REColors.accent : REColors.textDim.opacity(0.4))
                                .frame(width: 3, height: CGFloat.random(in: 6...20))
                        }
                    }
                    .frame(height: 20)

                    Text(formatDuration(sample.audioDuration))
                        .font(REFont.small)
                        .foregroundColor(REColors.textDim)
                }

                Spacer()
            }

            HStack(spacing: RE.s8) {
                audioChip(sample.engineAudible.label, icon: "speaker.wave.2")
                audioChip(sample.vehicleState.label, icon: "car")
                audioChip(sample.backgroundNoise.label, icon: "waveform")
            }

            HStack(spacing: RE.s8) {
                Text(sample.recordingContext.label)
                    .font(REFont.small).foregroundColor(REColors.textDim)
                Text("·").foregroundColor(REColors.textDim)
                Text(formatWallTime(sample.timestamp))
                    .font(REFont.small).foregroundColor(REColors.textDim)
            }
        }
        .padding(RE.s16)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }

    // Small rounded chip showing an audio metadata value (e.g. "Idling", "Quiet")
    private func audioChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(REColors.bgInput)
        .cornerRadius(100)
        .foregroundColor(REColors.textSec)
    }

    // Playback

    // Plays or stops the audio sample. Configures the audio session for
    // playback mode so sound works even when the iPhone silent switch is on.
    private func togglePlayback(_ sample: AudioSample) {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            return
        }
        let url = URL(fileURLWithPath: sample.localFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true

            let duration = sample.audioDuration > 0 ? sample.audioDuration : 10
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) { [self] in
                if self.isPlaying {
                    self.isPlaying = false
                }
            }
        } catch {
            print("Playback error: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    // Load Audio Sample

    // Loads the audio sample linked to this detection from the database
    private func loadAudioSample(id: Int64) -> AudioSample? {
        let allSamples = db.fetchAllAudioSamples()
        return allSamples.first(where: { $0.id == id })
    }

    // Metadata Row

    // A row in the metadata card showing an icon, label, and value
    private func metaRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(REColors.textDim)
                .frame(width: 20)
            Text(label)
                .font(REFont.body)
                .foregroundColor(REColors.textSec)
            Spacer()
            Text(value)
                .font(REFont.body)
                .foregroundColor(REColors.text)
        }
        .padding(.horizontal, RE.s16)
        .padding(.vertical, RE.s12)
    }

    // Formatting

    // Date and time formatting helpers for the metadata card
    private func fmtDate(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .long
        return f.string(from: d)
    }

    private func fmtTime(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: d)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatWallTime(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let date = p.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
}

// ShareSheet (wraps UIActivityViewController with completion tracking)
// Wraps UIActivityViewController for sharing. Tracks completion so we can
// award sharing badges when the user actually completes a share.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activity, completed, _, _ in
            if completed { onComplete?() }
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
