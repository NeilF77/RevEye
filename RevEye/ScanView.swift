//
//  ScanView.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Fixed 12/03/2026 — proper state clearing between scans, cleaner layout

import SwiftUI
import PhotosUI
import AVKit

struct ScanView: View {
    @ObservedObject var vm: ScanViewModel

    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showAudioSheet = false
    @State private var showCorrectionPicker = false

    /// Determines what the main content area shows
    private var viewState: ViewState {
        if vm.isClassifying { return .loading }
        if vm.scanMode == .video && vm.isProcessingVideo { return .videoProcessing }
        if vm.scanMode == .video && !vm.videoDetections.isEmpty { return .videoResult }
        if vm.scanMode == .photo, vm.classifier.lastOutput != nil { return .photoResult }
        return .idle
    }

    private enum ViewState {
        case idle, loading, photoResult, videoProcessing, videoResult
    }

    var body: some View {
        ZStack {
            REColors.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: RESpacing.lg) {
                    topBar
                        .padding(.horizontal, RESpacing.lg)

                    switch viewState {
                    case .idle:       idleContent
                    case .loading:    loadingContent
                    case .photoResult: photoResultContent
                    case .videoProcessing: videoProcessingContent
                    case .videoResult: videoResultContent
                    }
                }
                .padding(.top, RESpacing.sm)
                .padding(.bottom, RESpacing.xxxl)
            }

            // Badge toast
            if vm.showBadgeToast, let badge = vm.toastBadge {
                VStack {
                    BadgeToastView(badge: badge)
                        .padding(.top, RESpacing.lg)
                    Spacer()
                }
                .zIndex(10)
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            showCorrectionPicker = false
            vm.handlePhotoPickerItem(newItem)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                onImagePicked: { image in
                    showCorrectionPicker = false
                    vm.handlePickedImage(image)
                },
                onVideoPicked: { url in
                    showCorrectionPicker = false
                    vm.startVideoProcessing(url: url)
                }
            )
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { url in
                showCorrectionPicker = false
                vm.startVideoProcessing(url: url)
            }
        }
        .sheet(isPresented: $showAudioSheet) {
            if let url = vm.selectedVideoURL, let firstDet = vm.videoDetections.first {
                AudioContextSheet(
                    videoURL: url,
                    vehicleLabel: firstDet.label,
                    confidence: firstDet.confidence,
                    detectionIds: vm.videoDetectionIds
                )
            }
        }
        .onAppear { vm.refreshDetections() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - TOP BAR
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var topBar: some View {
        HStack {
            Text("RevEye")
                .font(REFonts.title)
                .foregroundColor(REColors.textPrimary)
            Spacer()
            HStack(spacing: RESpacing.xs) {
                Image(systemName: "car.fill")
                    .font(.system(size: 11))
                Text("\(vm.savedDetections.count)")
                    .font(REFonts.mono)
            }
            .foregroundColor(REColors.accent)
            .padding(.horizontal, RESpacing.md)
            .padding(.vertical, RESpacing.sm)
            .background(REColors.accentSubtle)
            .cornerRadius(RERadius.pill)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IDLE (scan home)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var idleContent: some View {
        VStack(spacing: RESpacing.lg) {
            // Stats
            statsRow
                .padding(.horizontal, RESpacing.lg)

            // Recent scans
            if !vm.savedDetections.isEmpty {
                recentScansStrip
            }

            Spacer().frame(height: RESpacing.lg)

            // Scan ring
            scanRing

            Text("Tap to open camera for photo or video")
                .font(REFonts.caption)
                .foregroundColor(REColors.textMuted)

            Spacer().frame(height: RESpacing.lg)

            // Library buttons
            libraryButtons
                .padding(.horizontal, RESpacing.lg)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LOADING
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var loadingContent: some View {
        VStack(spacing: RESpacing.lg) {
            // Show the image being analysed
            if let image = vm.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .cornerRadius(RERadius.md)
                    .padding(.horizontal, RESpacing.lg)
            }

            VStack(spacing: RESpacing.md) {
                ProgressView()
                    .tint(REColors.brandBlue)
                    .scaleEffect(1.2)
                Text("Identifying vehicle…")
                    .font(REFonts.callout)
                    .foregroundColor(REColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .reCard()
            .padding(.horizontal, RESpacing.lg)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - PHOTO RESULT
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var photoResultContent: some View {
        VStack(spacing: RESpacing.lg) {
            // Image
            if let image = vm.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .cornerRadius(RERadius.md)
                    .padding(.horizontal, RESpacing.lg)
            }

            // Result card
            if let output = vm.classifier.lastOutput {
                resultCard(output)
                    .padding(.horizontal, RESpacing.lg)
            }

            // Status message
            if let msg = vm.statusMessage {
                Text(msg)
                    .font(REFonts.caption)
                    .foregroundColor(REColors.textMuted)
                    .padding(.horizontal, RESpacing.lg)
            }

            // Bottom actions
            bottomActions
                .padding(.horizontal, RESpacing.lg)
        }
    }

    @ViewBuilder
    private func resultCard(_ output: ClassificationOutput) -> some View {
        if showCorrectionPicker {
            // Correction mode — show top 3
            SuggestionPickerView(
                output: output,
                headerText: "What is the correct vehicle?",
                onSelect: { label, confidence in
                    vm.saveDetectionWithLabel(label, confidence: confidence)
                    showCorrectionPicker = false
                },
                onSkip: {
                    vm.skipDetection()
                    showCorrectionPicker = false
                }
            )
            .reCard()
        } else if !output.isVehicle || output.tier == .tooLow || output.tier == .low || output.isAmbiguous {
            // Low confidence / uncertain — always show top 3
            SuggestionPickerView(
                output: buildPickerOutput(output),
                headerText: suggestionHeaderText(output),
                onSelect: { label, confidence in
                    vm.saveDetectionWithLabel(label, confidence: confidence)
                },
                onSkip: {
                    vm.skipDetection()
                }
            )
            .reCard()
        } else {
            // High confidence — clean display
            highConfidenceCard(output)
        }
    }

    /// Build a usable output for the picker even when isVehicle is false
    private func buildPickerOutput(_ output: ClassificationOutput) -> ClassificationOutput {
        if output.top3.isEmpty { return output }
        return ClassificationOutput(
            label: output.top3[0].label,
            confidence: output.top3[0].confidence,
            tier: output.tier,
            top3: output.top3,
            isAmbiguous: output.isAmbiguous,
            isVehicle: true
        )
    }

    private func suggestionHeaderText(_ output: ClassificationOutput) -> String {
        if !output.isVehicle {
            return "We're not sure there's a vehicle here — but could it be one of these?"
        }
        if output.tier == .tooLow {
            return "This was a tough one — here are our best guesses:"
        }
        return "We think it might be one of these:"
    }

    private func highConfidenceCard(_ output: ClassificationOutput) -> some View {
        VStack(spacing: RESpacing.md) {
            // Confidence
            HStack(spacing: RESpacing.sm) {
                Circle().fill(REColors.confHigh).frame(width: 10, height: 10)
                Text("\(Int(output.confidence * 100))% confidence")
                    .font(REFonts.caption)
                    .foregroundColor(REColors.confHigh)
            }

            // Vehicle name
            Text(output.label)
                .font(REFonts.title)
                .foregroundColor(REColors.textPrimary)
                .multilineTextAlignment(.center)

            if output.isAmbiguous, output.top3.count >= 2 {
                Text("Also possible: \(output.top3[1].label)")
                    .font(REFonts.caption)
                    .foregroundColor(REColors.textMuted)
            }

            // Action buttons
            if !vm.photoSaved && !vm.photoSkipped {
                HStack(spacing: RESpacing.md) {
                    Button("Don't Save") {
                        vm.skipDetection()
                    }
                    .buttonStyle(RESecondaryButton())

                    Button("Save") {
                        vm.savePhotoDetection()
                    }
                    .buttonStyle(REPrimaryButton(color: REColors.brandBlue))
                }

                Button("Not right? Tap to correct") {
                    showCorrectionPicker = true
                }
                .font(REFonts.caption)
                .foregroundColor(REColors.accent)
                .padding(.top, RESpacing.xs)
            }

            if vm.photoSaved {
                HStack(spacing: RESpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(REColors.success)
                    Text("Saved")
                        .font(REFonts.callout)
                        .foregroundColor(REColors.success)
                }
            }

            if vm.photoSkipped {
                Text("Skipped")
                    .font(REFonts.caption)
                    .foregroundColor(REColors.textMuted)
            }
        }
        .reCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - VIDEO PROCESSING
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var videoProcessingContent: some View {
        VStack(spacing: RESpacing.lg) {
            if let url = vm.selectedVideoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .cornerRadius(RERadius.md)
                    .padding(.horizontal, RESpacing.lg)
            }

            VStack(spacing: RESpacing.sm) {
                HStack {
                    Text("Scanning video…")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.textSecondary)
                    Spacer()
                    Text("\(Int(vm.videoProgress))/\(Int(vm.videoTotal))")
                        .font(REFonts.mono)
                        .foregroundColor(REColors.textMuted)
                }
                ProgressView(value: vm.videoProgress, total: vm.videoTotal)
                    .tint(REColors.accent)

                if !vm.videoDetections.isEmpty {
                    Text("\(vm.videoDetections.count) vehicle\(vm.videoDetections.count == 1 ? "" : "s") found")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .reCard()
            .padding(.horizontal, RESpacing.lg)

            // Live detections
            ForEach(Array(vm.videoDetections.enumerated()), id: \.offset) { _, det in
                videoRow(det)
                    .padding(.horizontal, RESpacing.lg)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - VIDEO RESULT
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var videoResultContent: some View {
        VStack(spacing: RESpacing.lg) {
            if let url = vm.selectedVideoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .cornerRadius(RERadius.md)
                    .padding(.horizontal, RESpacing.lg)
            }

            VStack(alignment: .leading, spacing: RESpacing.sm) {
                Text("Vehicles Detected")
                    .font(REFonts.headline)
                    .foregroundColor(REColors.textPrimary)

                ForEach(Array(vm.videoDetections.enumerated()), id: \.offset) { _, det in
                    videoRow(det)
                }
            }
            .padding(.horizontal, RESpacing.lg)

            if let msg = vm.statusMessage {
                Text(msg)
                    .font(REFonts.caption)
                    .foregroundColor(REColors.textMuted)
                    .padding(.horizontal, RESpacing.lg)
            }

            if vm.showAudioPrompt {
                audioCard
                    .padding(.horizontal, RESpacing.lg)
            }

            bottomActions
                .padding(.horizontal, RESpacing.lg)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - SHARED COMPONENTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var scanRing: some View {
        Button { showCamera = true } label: {
            ZStack {
                Circle()
                    .stroke(REColors.brandBlue.opacity(0.15), lineWidth: 2)
                    .frame(width: 170, height: 170)
                Circle()
                    .stroke(
                        LinearGradient(colors: [REColors.brandBlue, REColors.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 4
                    )
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(REColors.bgSecondary)
                    .frame(width: 138, height: 138)
                VStack(spacing: RESpacing.sm) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(REColors.brandBlue)
                    Text("Tap to Scan")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.textSecondary)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: RESpacing.sm) {
            statPill("checkmark.circle", "\(vm.savedDetections.filter { $0.synced == 1 }.count)", "synced")
            statPill("icloud.slash", "\(vm.savedDetections.filter { $0.synced == 0 }.count)", "pending")
            statPill("trophy", "\(BadgeService.shared.badges.filter { $0.earned }.count)", "badges")
        }
    }

    private func statPill(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: RESpacing.xs) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(REColors.brandBlueLight)
            Text(value).font(REFonts.caption).foregroundColor(REColors.textPrimary).fontWeight(.semibold)
            Text(label).font(REFonts.caption2).foregroundColor(REColors.textMuted)
        }
        .padding(.horizontal, RESpacing.sm)
        .padding(.vertical, RESpacing.sm)
        .frame(maxWidth: .infinity)
        .background(REColors.bgSecondary)
        .cornerRadius(RERadius.sm)
    }

    private var recentScansStrip: some View {
        VStack(alignment: .leading, spacing: RESpacing.sm) {
            Text("Recent")
                .font(REFonts.caption)
                .foregroundColor(REColors.textMuted)
                .padding(.horizontal, RESpacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RESpacing.sm) {
                    ForEach(vm.savedDetections.prefix(5)) { det in
                        HStack(spacing: RESpacing.xs) {
                            Circle()
                                .fill(REColors.forTier(ConfidenceTier.tier(for: det.confidence)))
                                .frame(width: 6, height: 6)
                            Text(det.vehicleLabel)
                                .font(REFonts.caption2)
                                .foregroundColor(REColors.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, RESpacing.md)
                        .padding(.vertical, RESpacing.sm)
                        .background(REColors.bgSecondary)
                        .cornerRadius(RERadius.pill)
                    }
                }
                .padding(.horizontal, RESpacing.lg)
            }
        }
    }

    private var libraryButtons: some View {
        HStack(spacing: RESpacing.md) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                libLabel("photo.on.rectangle", "Photo Library")
            }
            Button { showVideoPicker = true } label: {
                libLabel("film.stack", "Video Library")
            }
        }
    }

    private func libLabel(_ icon: String, _ text: String) -> some View {
        HStack(spacing: RESpacing.sm) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(REColors.brandBlueLight)
            Text(text).font(REFonts.caption).foregroundColor(REColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RESpacing.md)
        .background(REColors.bgElevated)
        .cornerRadius(RERadius.md)
    }

    private var bottomActions: some View {
        HStack(spacing: RESpacing.md) {
            Button {
                showCorrectionPicker = false
                vm.returnToScan()
                showCamera = true
            } label: {
                HStack(spacing: RESpacing.sm) {
                    Image(systemName: "viewfinder")
                    Text("Scan Again")
                }
            }
            .buttonStyle(REPrimaryButton(color: REColors.brandBlue))

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                HStack(spacing: RESpacing.sm) {
                    Image(systemName: "photo")
                    Text("Library")
                }
                .font(REFonts.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, RESpacing.md)
                .background(REColors.bgElevated)
                .foregroundColor(REColors.textPrimary)
                .cornerRadius(RERadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: RERadius.md)
                        .stroke(REColors.brandBlueDark, lineWidth: 1)
                )
            }
        }
    }

    private func videoRow(_ det: (label: String, confidence: Double, appearedAt: Double)) -> some View {
        HStack(spacing: RESpacing.md) {
            ZStack {
                Circle().fill(REColors.accentSubtle).frame(width: 36, height: 36)
                Image(systemName: "car.fill").foregroundColor(REColors.accent).font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(det.label)
                    .font(REFonts.body).fontWeight(.semibold)
                    .foregroundColor(REColors.textPrimary).lineLimit(2)
                Text("\(Int(det.confidence * 100))%")
                    .font(REFonts.caption)
                    .foregroundColor(REColors.forTier(ConfidenceTier.tier(for: det.confidence)))
            }
            Spacer()
            Text(vm.formatVideoTime(det.appearedAt))
                .font(REFonts.mono)
                .foregroundColor(REColors.accent)
        }
        .padding(RESpacing.md)
        .background(REColors.bgSecondary)
        .cornerRadius(RERadius.md)
    }

    private var audioCard: some View {
        Button { showAudioSheet = true } label: {
            HStack(spacing: RESpacing.md) {
                Image(systemName: "waveform")
                    .foregroundColor(REColors.brandBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Contribute audio data")
                        .font(REFonts.callout).foregroundColor(REColors.textPrimary)
                    Text("Help improve RevEye's accuracy")
                        .font(REFonts.caption).foregroundColor(REColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundColor(REColors.textMuted)
            }
            .padding(RESpacing.md)
            .background(REColors.bgSecondary)
            .cornerRadius(RERadius.md)
        }
    }
}

// MARK: - Badge Toast

struct BadgeToastView: View {
    let badge: Badge
    var body: some View {
        HStack(spacing: RESpacing.md) {
            Text(badge.emoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 1) {
                Text("Badge Unlocked!")
                    .font(REFonts.caption).foregroundColor(REColors.accent).fontWeight(.semibold)
                Text(badge.title)
                    .font(REFonts.callout).foregroundColor(REColors.textPrimary).fontWeight(.bold)
            }
            Spacer()
        }
        .padding(RESpacing.md)
        .background(REColors.bgSecondary)
        .cornerRadius(RERadius.lg)
        .overlay(RoundedRectangle(cornerRadius: RERadius.lg).stroke(REColors.accent.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, RESpacing.lg)
    }
}
