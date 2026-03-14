//
//  ScanView.swift
//  RevEye
//
//  UI overhaul v8 — bigger ring, toast at bottom, softer Scan Again

import SwiftUI
import PhotosUI
import AVKit

struct ScanView: View {
    @ObservedObject var vm: ScanViewModel

    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showAudioSheet = false
    @State private var showCorrection = false

    private var state: VState {
        if vm.isClassifying { return .loading }
        if vm.scanMode == .video && vm.isProcessingVideo { return .videoProg }
        if vm.scanMode == .video && !vm.isProcessingVideo && vm.selectedVideoURL != nil { return .videoResult }
        if vm.scanMode == .photo, vm.classifier.lastOutput != nil { return .photoResult }
        return .idle
    }
    private enum VState { case idle, loading, photoResult, videoProg, videoResult }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    Group {
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

                if state == .photoResult || state == .videoResult {
                    footer
                }
            }

            // Badge toast — bottom of screen, above tab bar
            if vm.showBadgeToast, let b = vm.toastBadge {
                VStack {
                    Spacer()
                    toastView(b)
                        .padding(.bottom, 90) // above tab bar
                }
                .zIndex(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: photoItem) { _, v in showCorrection = false; vm.handlePhotoPickerItem(v) }
        .onChange(of: vm.scanMode) { _, m in if m == .idle { showCorrection = false } }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                sourceType: .camera,
                onImagePicked: { showCorrection = false; vm.handlePickedImage($0) },
                onVideoPicked: { showCorrection = false; vm.startVideoProcessing(url: $0) }
            )
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { showCorrection = false; vm.startVideoProcessing(url: $0) }
        }
        .sheet(isPresented: $showAudioSheet) {
            if let u = vm.selectedVideoURL, let d = vm.videoDetections.first(where: { $0.saved }) {
                AudioContextSheet(videoURL: u, vehicleLabel: d.label,
                                  confidence: d.confidence, detectionIds: vm.videoDetectionIds)
            }
        }
        .onAppear { vm.refreshDetections() }
    }

    // ═══════════════════════════════════════════════════
    // MARK: - IDLE — even bigger ring
    // ═══════════════════════════════════════════════════

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

            // Ring — 250pt to fill the screen
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

            HStack(spacing: RE.s48) {
                PhotosPicker(selection: $photoItem, matching: .images) {
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
        }
    }

    // ═══════════════════════════════════════════════════
    // MARK: - LOADING
    // ═══════════════════════════════════════════════════

    private var loadingView: some View {
        VStack(spacing: RE.s24) {
            if let img = vm.capturedImage {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 320).cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16).padding(.top, RE.s16)
            }
            ProgressView().tint(REColors.blue)
            Text("Identifying…").font(REFont.label).foregroundColor(REColors.textSec)
        }
    }

    // ═══════════════════════════════════════════════════
    // MARK: - PHOTO RESULT
    // ═══════════════════════════════════════════════════

    private var photoResultView: some View {
        VStack(spacing: RE.s16) {
            if let img = vm.capturedImage {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 320).cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16).padding(.top, RE.s8)
            }
            if let output = vm.classifier.lastOutput {
                resultSection(output).padding(.horizontal, RE.s16)
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ output: ClassificationOutput) -> some View {
        if showCorrection {
            SuggestionPickerView(
                output: output, headerText: "What is the correct vehicle?",
                onSelect: { l, c in vm.saveDetectionWithLabel(l, confidence: c) },
                onSaveUnknown: { vm.saveAsUnknown() },
                onSkip: { vm.skipDetection() }
            ).reCard()
        } else if !output.isVehicle || output.tier == .tooLow || output.tier == .low || output.isAmbiguous {
            SuggestionPickerView(
                output: usableOutput(output), headerText: headerFor(output),
                onSelect: { l, c in vm.saveDetectionWithLabel(l, confidence: c) },
                onSaveUnknown: { vm.saveAsUnknown() },
                onSkip: { vm.skipDetection() }
            ).reCard()
        } else {
            confidentCard(output)
        }
    }

    private func usableOutput(_ o: ClassificationOutput) -> ClassificationOutput {
        guard !o.top3.isEmpty else { return o }
        return ClassificationOutput(label: o.top3[0].label, confidence: o.top3[0].confidence,
                                    tier: o.tier, top3: o.top3, isAmbiguous: o.isAmbiguous, isVehicle: true)
    }

    private func headerFor(_ o: ClassificationOutput) -> String {
        if !o.isVehicle { return "Not sure there's a vehicle — but could it be:" }
        if o.tier == .tooLow { return "Tough one — our best guesses:" }
        return "We think it might be:"
    }

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
                    Button("Save Detection") { vm.savePhotoDetection() }.buttonStyle(REPrimaryButton())
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
                    Text("Saved").font(REFont.label).foregroundColor(REColors.success)
                }
            }
            if vm.photoSkipped {
                Text("Not saved").font(REFont.caption).foregroundColor(REColors.textDim)
            }
        }
        .padding(.vertical, RE.s8)
    }

    // ═══════════════════════════════════════════════════
    // MARK: - VIDEO PROGRESS
    // ═══════════════════════════════════════════════════

    private var videoProgressView: some View {
        VStack(spacing: RE.s16) {
            if let u = vm.selectedVideoURL {
                VideoPlayer(player: AVPlayer(url: u))
                    .frame(height: 180).cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16).padding(.top, RE.s8)
            }
            VStack(spacing: RE.s12) {
                ProgressView(value: vm.videoProgress, total: vm.videoTotal).tint(REColors.accent)
                HStack {
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

    // ═══════════════════════════════════════════════════
    // MARK: - VIDEO RESULT
    // ═══════════════════════════════════════════════════

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
                    Text("\(vm.videoDetections.count) Vehicle\(vm.videoDetections.count == 1 ? "" : "s") Found")
                        .font(REFont.title).foregroundColor(REColors.text)
                    Text("Review each detection below")
                        .font(REFont.caption).foregroundColor(REColors.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RE.s16).padding(.top, RE.s8)

                ForEach(Array(vm.videoDetections.enumerated()), id: \.element.id) { index, det in
                    videoDetCard(det, index: index).padding(.horizontal, RE.s16)
                }

                let unhandled = vm.videoDetections.filter { !$0.handled }.count
                if unhandled > 1 {
                    HStack(spacing: RE.s8) {
                        Button("Save All (\(unhandled))") { vm.saveAllVideoDetections() }
                            .buttonStyle(REPrimaryButton())
                        Button("Don't Save All") { vm.skipAllVideoDetections() }
                            .buttonStyle(REDestructiveButton())
                    }.padding(.horizontal, RE.s16)
                }

                if vm.showAudioPrompt {
                    audioCard.padding(.horizontal, RE.s16)
                }
            }
        }
    }

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
            } else {
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
            }
        }
        .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r12)
    }

    // ═══════════════════════════════════════════════════
    // MARK: - FOOTER
    // ═══════════════════════════════════════════════════

    private var footer: some View {
        HStack(spacing: RE.s12) {
            Button {
                showCorrection = false; vm.returnToScan(); showCamera = true
            } label: {
                HStack(spacing: RE.s8) { Image(systemName: "viewfinder"); Text("Scan Again") }
            }
            .buttonStyle(REPrimaryButton(color: Color(hex: "2D6FD9")))

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: RE.s8) { Image(systemName: "photo"); Text("Library") }
                    .font(REFont.heading)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(REColors.bgInput).foregroundColor(REColors.textSec)
                    .cornerRadius(RE.r12)
            }
        }
        .padding(.horizontal, RE.s16).padding(.vertical, RE.s8).background(REColors.bg)
    }

    // ═══════════════════════════════════════════════════
    // MARK: - SMALL COMPONENTS
    // ═══════════════════════════════════════════════════

    private var audioCard: some View {
        Button { showAudioSheet = true } label: {
            HStack(spacing: RE.s12) {
                Image(systemName: "waveform").foregroundColor(REColors.blueLight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contribute audio data").font(REFont.label).foregroundColor(REColors.textSec)
                    Text("Help improve vehicle identification").font(REFont.small).foregroundColor(REColors.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(REColors.textDim)
            }
            .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r12)
        }
    }

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
