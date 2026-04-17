// ScanView.swift
// RevEye
//
// The main scanning screen. Manages multiple UI states: idle (waiting for
// input), loading (classifying), photo result (showing prediction with
// save/correct options), video progress, video results, and audio prompt.
// Delegates all business logic to ScanViewModel.

import SwiftUI
import AVKit

struct ScanView: View {
    // Reference to the shared view model that handles all scan logic
    @ObservedObject var vm: ScanViewModel

    // Sheet presentation states for camera, photo library, and video picker
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var showPhotoLibrary = false
    @State private var showCorrection = false
    @State private var correctionPick: [Int: Int] = [:]  // detection index → picked option (-1 = unknown)
    @State private var showScanShareSheet = false

    // Computed property that determines which UI state to show based on
    // what the view model is currently doing
    private var state: VState {
        if vm.isClassifying { return .loading }
        if vm.scanMode == .video && vm.isProcessingVideo { return .videoProg }
        if vm.scanMode == .video && !vm.isProcessingVideo && vm.selectedVideoURL != nil { return .videoResult }
        if vm.scanMode == .photo, vm.classifier.lastOutput != nil { return .photoResult }
        return .idle
    }
    // The possible visual states of the scan screen
private enum VState { case idle, loading, photoResult, videoProg, videoResult }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    Group {
                                                // Show different content depending on what stage of scanning we're in
switch state {
                        case .idle:        idleView
                        case .loading:     loadingView
                        case .photoResult: photoResultView
                        case .videoProg:   videoProgressView
                        case .videoResult: videoResultView
                        }
                    }
                    .padding(.bottom, state == .idle ? RE.s24 : 88)
                }

                                // Show the footer bar (Scan Again + Library) when viewing results
if state == .photoResult || state == .videoResult {
                    footer
                }
            }

                        // Badge earned toast - slides up from the bottom when a badge is awarded
if vm.showBadgeToast, let b = vm.toastBadge {
                VStack {
                    Spacer()
                    toastView(b)
                        .padding(.bottom, 90)
                }
                .zIndex(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.showBadgeToast)
        .onChange(of: vm.scanMode) { _, m in if m == .idle { showCorrection = false } }
                // Camera sheet - opens the device camera for photo or video capture
.sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                onImagePicked: { showCorrection = false; vm.handlePickedImage($0) },
                onVideoPicked: { showCorrection = false; vm.startVideoProcessing(url: $0) }
            )
        }
                // Photo library sheet - opens the photo library with crop support enabled
.sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(
                sourceType: .photoLibrary,
                allowsEditing: true,
                onImagePicked: { showCorrection = false; vm.handlePickedImage($0) }
            )
        }
                // Video picker sheet - lets user select a video from their library
.sheet(isPresented: $showVideoPicker) {
            VideoPicker { showCorrection = false; vm.startVideoProcessing(url: $0) }
        }
                // Audio context prompt - shown after saving a video detection
    // to collect metadata about the engine sound
.sheet(isPresented: $vm.showAudioContextPrompt, onDismiss: {
            vm.returnToScan()
        }) {
            AudioContextSheet(
                vehicleLabel: vm.pendingAudioLabel ?? "Vehicle",
                onSubmit: { engine, context, state, noise in
                    vm.submitAudioContext(engineAudible: engine, recordingContext: context,
                                         vehicleState: state, backgroundNoise: noise)
                },
                onSkip: {
                    vm.showAudioContextPrompt = false
                }
            )
            .presentationDetents([.medium])
        }
        .onAppear { vm.refreshDetections() }
    }

    // IDLE — even bigger ring

    // Idle state - shown when no scan is in progress. Shows the app name,
    // a large tap-to-scan button, and smaller photo/video options below.
    private var idleView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: RE.s32)

            Text("RevEye")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(REColors.text)
                .padding(.bottom, RE.s4)
            Text("Vehicle Identifier")
                .font(REFont.caption).foregroundColor(REColors.textSec)

            Spacer().frame(height: RE.s48)

                        // Tap-to-scan ring button - opens the camera

Button { showCamera = true } label: {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(colors: [REColors.blue, REColors.accent],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 4
                        )
                        .frame(width: 250, height: 250)
                    Circle().fill(REColors.bgCard).frame(width: 236, height: 236)
                    VStack(spacing: RE.s8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(REColors.blue)
                        Text("Tap to scan")
                            .font(REFont.small)
                            .foregroundColor(REColors.textDim)
                    }
                }
            }

            Spacer().frame(height: RE.s48)

            Text("Point your camera at any vehicle")
                .font(REFont.body).foregroundColor(REColors.textSec)
            Text("or choose from your library")
                .font(REFont.caption).foregroundColor(REColors.textDim)
                .padding(.top, RE.s4)

            Spacer().frame(height: RE.s32)

                        // Photo and Video shortcut buttons below the scan ring

HStack(spacing: RE.s48) {
                Button { showPhotoLibrary = true } label: {
                    VStack(spacing: RE.s8) {
                        Image(systemName: "photo").font(.system(size: 22, weight: .light)).foregroundColor(REColors.textSec)
                        Text("Photos").font(REFont.small).foregroundColor(REColors.textDim)
                    }
                }
                Button { showVideoPicker = true } label: {
                    VStack(spacing: RE.s8) {
                        Image(systemName: "video").font(.system(size: 22, weight: .light)).foregroundColor(REColors.textSec)
                        Text("Video").font(REFont.small).foregroundColor(REColors.textDim)
                    }
                }
            }

            Spacer().frame(height: RE.s16)

            Text("Videos identify one vehicle per clip")
                .font(REFont.small).foregroundColor(REColors.textDim)
        }
    }

    // LOADING

    // Loading state - shown while the ML model is classifying an image
    private var loadingView: some View {
        VStack(spacing: RE.s24) {
            if let img = vm.capturedImage {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 320).cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16).padding(.top, RE.s16)
            }
                        // Spinner shown while the ML model is processing
ProgressView().tint(REColors.blue)
                        // Status label during classification
Text("Identifying…").font(REFont.label).foregroundColor(REColors.textSec)
        }
    }

    // PHOTO RESULT

    // Photo result state - shows the scanned image with a share icon overlay
    // (appears after save) and the classification result below
    private var photoResultView: some View {
        VStack(spacing: RE.s16) {
            if let img = vm.capturedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipped()
                        .cornerRadius(RE.r12)

                    
            // After saving - show confirmation with share icon on the photo

if vm.photoSaved {
                        Button { showScanShareSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .cornerRadius(RE.r8)
                        }
                        .padding(RE.s8)
                        .sheet(isPresented: $showScanShareSheet) {
                            if let output = vm.classifier.lastOutput {
                                let text = "I spotted a \(output.label) with \(Int(output.confidence * 100))% confidence using RevEye! 🚗"
                                ShareSheet(items: [text, img]) {
                                    let earned = BadgeService.shared.checkAfterShare()
                                    for b in earned { vm.showToast(b) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, RE.s16).padding(.top, RE.s8)
            }
            if let output = vm.classifier.lastOutput {
                resultSection(output).padding(.horizontal, RE.s16)
            }
        }
    }

    @ViewBuilder
    // Decides which result UI to show based on confidence level.
    // High confidence = simple card with save/skip buttons.
    // Low/ambiguous confidence = suggestion picker with top 3 predictions.
    private func resultSection(_ output: ClassificationOutput) -> some View {
        if showCorrection {
            SuggestionView(
                output: output, headerText: "What is the correct vehicle?",
                onSelect: { l, c in vm.saveDetectionWithLabel(l, confidence: c) },
                onSaveUnknown: { vm.saveAsUnknown() },
                onSkip: { vm.skipDetection() }
            ).reCard()
        } else if !output.isVehicle || output.tier == .tooLow || output.tier == .low || output.isAmbiguous {
            SuggestionView(
                output: usableOutput(output), headerText: headerFor(output),
                onSelect: { l, c in vm.saveDetectionWithLabel(l, confidence: c) },
                onSaveUnknown: { vm.saveAsUnknown() },
                onSkip: { vm.skipDetection() }
            ).reCard()
        } else {
            confidentCard(output)
        }
    }

    // If the raw output is unusable (not a vehicle or too low confidence),
    // restructure it so the suggestion picker can still show the top 3 guesses
    private func usableOutput(_ o: ClassificationOutput) -> ClassificationOutput {
        guard !o.top3.isEmpty else { return o }
        return ClassificationOutput(label: o.top3[0].label, confidence: o.top3[0].confidence,
                                    tier: o.tier, top3: o.top3, isAmbiguous: o.isAmbiguous, isVehicle: true)
    }

    // Picks the right heading text based on why we're showing suggestions
    private func headerFor(_ o: ClassificationOutput) -> String {
        if !o.isVehicle { return "Not sure there's a vehicle — but could it be:" }
        if o.tier == .tooLow { return "Tough one — our best guesses:" }
        return "We think it might be:"
    }

    // Result card shown when the model is confident in its prediction.
    // Shows the confidence percentage, vehicle name, and save/skip/correct buttons.
    private func confidentCard(_ output: ClassificationOutput) -> some View {
        let confColor = REColors.displayConf(output.confidence)
        return VStack(spacing: RE.s16) {
            Text("\(Int(output.confidence * 100))% match")
                .font(REFont.caption).foregroundColor(confColor)
                .padding(.horizontal, RE.s12).padding(.vertical, RE.s4)
                .background(confColor.opacity(0.1)).cornerRadius(100)

            Text(output.label).font(REFont.title).foregroundColor(REColors.text).multilineTextAlignment(.center)

            if output.isAmbiguous, output.top3.count >= 2 {
                Text("or \(output.top3[1].label)").font(REFont.caption).foregroundColor(REColors.textDim)
            }

            if !vm.photoSaved && !vm.photoSkipped {
                VStack(spacing: RE.s8) {
                                        // Main save button - stores the detection and triggers badge checks
Button("Save Detection") { vm.savePhotoDetection() }.buttonStyle(REPrimaryButton())
                                        // Skip button - discard this result without saving
Button("Don't Save") { vm.skipDetection() }.buttonStyle(REDestructiveButton())
                    Button { showCorrection = true } label: {
                        HStack(spacing: RE.s8) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12))
                            Text("Not right? Tap to correct").font(REFont.label)
                        }
                        .foregroundColor(REColors.accent)
                        .padding(.horizontal, RE.s16).padding(.vertical, RE.s8)
                        .background(REColors.accent.opacity(0.1)).cornerRadius(100)
                    }.padding(.top, RE.s4)
                }
            }

            

if vm.photoSaved {
                HStack(spacing: RE.s8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(REColors.success)
                    Text("Saved to Garage").font(REFont.label).foregroundColor(REColors.success)
                }
            }
            if vm.photoSkipped {
                Text("Not saved").font(REFont.caption).foregroundColor(REColors.textDim)
            }
        }
        .padding(.vertical, RE.s8)
    }

    // VIDEO PROGRESS

    // Video scanning progress view - shows the video player, a progress bar,
    // and a live count of vehicles found so far
    private var videoProgressView: some View {
        VStack(spacing: RE.s16) {
            if let u = vm.selectedVideoURL {
                VideoPlayer(player: AVPlayer(url: u))
                    .frame(height: 180).cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16).padding(.top, RE.s8)
            }
            VStack(spacing: RE.s12) {
                                // Progress bar showing how far through the video we are
ProgressView(value: vm.videoProgress, total: vm.videoTotal).tint(REColors.accent)
                HStack {
                                        // Status text during video scan
Text("Scanning for vehicles…").font(REFont.label).foregroundColor(REColors.textSec)
                    Spacer()
                    Text("\(Int(vm.videoProgress)) of \(Int(vm.videoTotal))").font(REFont.small).foregroundColor(REColors.textDim)
                }
                if !vm.videoDetections.isEmpty {
                    HStack(spacing: RE.s8) {
                        Image(systemName: "car.fill").font(.system(size: 12)).foregroundColor(REColors.accent)
                        Text("\(vm.videoDetections.count) found so far").font(REFont.label).foregroundColor(REColors.accent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, RE.s16)

            if !vm.videoDetections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RE.s8) {
                                                // List each vehicle found in the video with save/skip buttons
ForEach(vm.videoDetections) { det in
                            if let thumb = det.thumbnail {
                                Image(uiImage: thumb)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 50).cornerRadius(RE.r8).clipped()
                            }
                        }
                    }.padding(.horizontal, RE.s16)
                }
            }
        }
    }

    // VIDEO RESULT

    // Video result view - shows the single best vehicle detected in the video.
    private var videoResultView: some View {
        VStack(spacing: RE.s16) {
            if vm.videoDetections.isEmpty {
                VStack(spacing: RE.s16) {
                    Spacer().frame(height: RE.s32)
                    Image(systemName: "car.circle")
                        .font(.system(size: 40, weight: .ultraLight)).foregroundColor(REColors.textDim)
                    Text(vm.statusMessage ?? "No vehicles detected.")
                        .font(REFont.body).foregroundColor(REColors.textSec).multilineTextAlignment(.center)
                }.padding(.horizontal, RE.s16)
            } else {
                VStack(alignment: .leading, spacing: RE.s4) {
                    Text("Vehicle Identified")
                        .font(REFont.title).foregroundColor(REColors.text)
                    Text("Save or skip this detection")
                        .font(REFont.caption).foregroundColor(REColors.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RE.s16).padding(.top, RE.s8)

                ForEach(Array(vm.videoDetections.enumerated()), id: \.element.id) { index, det in
                    videoDetCard(det, index: index).padding(.horizontal, RE.s16)
                }
            }
        }
    }

    // AUDIO CONTEXT PROMPT (2-3 taps)

    private func videoDetCard(_ det: VideoDetection, index: Int) -> some View {
        let confColor = REColors.displayConf(det.confidence)
        return VStack(spacing: RE.s12) {

            HStack(alignment: .top, spacing: RE.s12) {
                if let thumb = det.thumbnail {
                    Image(uiImage: thumb)
                        .resizable().scaledToFill()
                        .frame(width: 100, height: 70).cornerRadius(RE.r8).clipped()
                }
                VStack(alignment: .leading, spacing: RE.s4) {
                    Text(det.label).font(REFont.heading).foregroundColor(REColors.text).lineLimit(2)
                    HStack(spacing: RE.s8) {
                        Text("\(Int(det.confidence * 100))%").font(REFont.label).foregroundColor(confColor)
                        Text("·").foregroundColor(REColors.textDim)
                        Text("at \(vm.fmtTime(det.appearedAt))").font(REFont.caption).foregroundColor(REColors.textDim)
                    }
                }
                Spacer()
            }

            if det.correcting && !det.handled {
                videoDetCorrectionView(det, index: index)
            }

            if det.handled {
                HStack(spacing: RE.s8) {
                    if det.saved {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(REColors.success)
                        Text("Saved").font(REFont.caption).foregroundColor(REColors.success)
                    } else {
                        Text("Not saved").font(REFont.caption).foregroundColor(REColors.textDim)
                    }
                    Spacer()
                }
            } else if !det.correcting {
                VStack(spacing: RE.s8) {
                    HStack(spacing: RE.s8) {
                        Button("Save") { vm.saveVideoDetection(at: index) }
                            .font(REFont.label).foregroundColor(.white)
                            .padding(.horizontal, RE.s16).padding(.vertical, RE.s8)
                            .background(REColors.blue).cornerRadius(RE.r8)
                        Button("Don't Save") { vm.skipVideoDetection(at: index) }
                            .font(REFont.label).foregroundColor(.white)
                            .padding(.horizontal, RE.s16).padding(.vertical, RE.s8)
                            .background(REColors.destructive).cornerRadius(RE.r8)
                    }

                    if !det.top3.isEmpty {
                        Button { vm.toggleVideoCorrection(at: index) } label: {
                            HStack(spacing: RE.s4) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                                Text("Not right? Tap to correct").font(REFont.small)
                            }
                            .foregroundColor(REColors.accent)
                            .padding(.horizontal, RE.s12).padding(.vertical, RE.s4)
                            .background(REColors.accent.opacity(0.1)).cornerRadius(100)
                        }
                    }
                }
            }
        }
        .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r12)
    }

    // Inline correction picker — radio-select then Save (mirrors photo SuggestionPicker)
    private func videoDetCorrectionView(_ det: VideoDetection, index: Int) -> some View {
        let pick = correctionPick[index]

        return VStack(alignment: .leading, spacing: RE.s8) {
            VStack(alignment: .leading, spacing: RE.s4) {
                Text("Select the correct vehicle:")
                    .font(REFont.label).foregroundColor(REColors.textSec)
                Text("Pick the closest match, or choose 'Unknown' if none are right.")
                    .font(REFont.small).foregroundColor(REColors.textDim)
            }

            ForEach(Array(det.top3.prefix(3).enumerated()), id: \.offset) { i, pred in
                let selected = pick == i
                Button { correctionPick[index] = i } label: {
                    HStack(spacing: RE.s12) {
                        Circle()
                            .stroke(selected ? REColors.accent : REColors.textDim, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().fill(selected ? REColors.accent : Color.clear).frame(width: 10, height: 10))

                        Text(pred.label)
                            .font(REFont.body).foregroundColor(REColors.text)
                            .lineLimit(2).multilineTextAlignment(.leading)

                        Spacer()

                        Text("\(Int(pred.confidence * 100))%")
                            .font(REFont.label)
                            .foregroundColor(REColors.displayConf(pred.confidence))
                            .monospacedDigit()
                    }
                    .padding(.vertical, RE.s8).padding(.horizontal, RE.s12)
                    .background(selected ? REColors.accent.opacity(0.06) : Color.clear)
                    .cornerRadius(RE.r8)
                }
            }

            let unknownSelected = pick == -1
            Button { correctionPick[index] = -1 } label: {
                HStack(spacing: RE.s12) {
                    Circle()
                        .stroke(unknownSelected ? REColors.confNone : REColors.textDim, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().fill(unknownSelected ? REColors.confNone : Color.clear).frame(width: 10, height: 10))

                    Text("None of these / Unknown")
                        .font(REFont.body).foregroundColor(REColors.textSec)
                    Spacer()
                }
                .padding(.vertical, RE.s8).padding(.horizontal, RE.s12)
            }

            HStack(spacing: RE.s8) {
                if pick != nil {
                    Button {
                        if let p = pick {
                            if p == -1 {
                                vm.saveVideoDetectionAsUnknown(at: index)
                            } else if p < det.top3.count {
                                let pred = det.top3[p]
                                vm.saveVideoDetectionWithLabel(at: index, label: pred.label, confidence: pred.confidence)
                            }
                            correctionPick.removeValue(forKey: index)
                        }
                    } label: {
                        Text(pick == -1 ? "Save as Unknown" : "Save Selection")
                            .font(REFont.label).foregroundColor(.white)
                            .padding(.horizontal, RE.s16).padding(.vertical, RE.s8)
                            .background(REColors.blue).cornerRadius(RE.r8)
                    }
                }

                Spacer()

                Button {
                    correctionPick.removeValue(forKey: index)
                    vm.toggleVideoCorrection(at: index)
                } label: {
                    Text("Cancel")
                        .font(REFont.label).foregroundColor(.white)
                        .padding(.horizontal, RE.s16).padding(.vertical, RE.s8)
                        .background(REColors.destructive).cornerRadius(RE.r8)
                }
            }
            .padding(.top, RE.s4)
        }
        .padding(RE.s12)
        .background(REColors.bgInput)
        .cornerRadius(RE.r8)
    }

    // FOOTER

    // Bottom toolbar shown during results - Scan Again and Library buttons
    private var footer: some View {
        HStack(spacing: RE.s12) {
            Button {
                showCorrection = false; vm.returnToScan(); showCamera = true
            } label: {
                HStack(spacing: RE.s8) { Image(systemName: "viewfinder"); Text("Scan Again") }
            }
            .buttonStyle(REPrimaryButton(color: Color(hex: "2D6FD9")))

            Button {
                showCorrection = false; vm.returnToScan(); showPhotoLibrary = true
            } label: {
                HStack(spacing: RE.s8) { Image(systemName: "photo"); Text("Library") }
                    .font(REFont.heading)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(REColors.bgInput).foregroundColor(REColors.textSec)
                    .cornerRadius(RE.r12)
            }
        }
        .padding(.horizontal, RE.s16).padding(.vertical, RE.s8).background(REColors.bg)
    }

    // SMALL COMPONENTS

    // Badge earned notification that slides up from the bottom of the screen
    private func toastView(_ b: Badge) -> some View {
        HStack(spacing: RE.s12) {
            Text(b.emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked!").font(REFont.small).foregroundColor(REColors.accent)
                Text(b.title).font(REFont.heading).foregroundColor(REColors.text)
            }
            Spacer()
        }
        .padding(RE.s12).background(.ultraThinMaterial).cornerRadius(RE.r12)
        .padding(.horizontal, RE.s16)
    }
}
