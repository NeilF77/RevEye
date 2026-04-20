// DatabaseInspector.swift
// RevEye
//
// Debug view accessible from Settings that shows the raw contents of the
// local SQLite database. Three tabs: Detections, Badges, and Audio Samples.

import SwiftUI

struct DatabaseInspector: View {
    private let db = DatabaseManager.shared
    @State private var detections: [Detection] = []
    @State private var badges: [Badge] = []
    @State private var audioSamples: [AudioSample] = []
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Table", selection: $selectedTab) {
                    Text("Detections (\(detections.count))").tag(0)
                    Text("Badges (\(badges.filter { $0.earned }.count)/\(badges.count))").tag(1)
                    Text("Audio (\(audioSamples.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(RE.s16)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: RE.s8) {
                        switch selectedTab {
                        case 0: detectionsTab
                        case 1: badgesTab
                        case 2: audioTab
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, RE.s16)
                    .padding(.bottom, RE.s48)
                }
            }
        }
        .navigationTitle("Local Database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { refresh() }
    }

    private func refresh() {
        detections = db.fetchAllDetections()
        badges = db.fetchAllBadges()
        audioSamples = db.fetchAllAudioSamples()
    }

    // Detections

    @ViewBuilder
    private var detectionsTab: some View {
        if detections.isEmpty {
            emptyLabel("No detections stored locally")
        } else {
            ForEach(detections) { det in
                VStack(alignment: .leading, spacing: RE.s4) {
                    HStack {
                        Text(det.vehicleLabel).font(REFont.body).foregroundColor(REColors.text)
                        Spacer()
                        Text("id: \(det.id ?? -1)").font(REFont.mono).foregroundColor(REColors.textDim)
                    }
                    HStack(spacing: RE.s12) {
                        dbChip("conf: \(Int(det.confidence * 100))%")
                        dbChip(det.synced == 1 ? "synced" : "pending")
                        if let aid = det.audioSampleId { dbChip("audio: \(aid)") }
                    }
                    Text(det.timestamp).font(REFont.small).foregroundColor(REColors.textDim)
                }
                .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r8)
            }
        }
    }

    // Badges

    @ViewBuilder
    private var badgesTab: some View {
        ForEach(badges) { badge in
            HStack(spacing: RE.s12) {
                Text(badge.emoji).font(.system(size: 20))
                    .grayscale(badge.earned ? 0 : 0.8)
                    .opacity(badge.earned ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(badge.title).font(REFont.body).foregroundColor(REColors.text)
                        Spacer()
                        Text(badge.id).font(REFont.mono).foregroundColor(REColors.textDim)
                    }
                    if badge.earned, let at = badge.earnedAt {
                        Text("Earned: \(at)").font(REFont.small).foregroundColor(REColors.confGreen)
                    } else {
                        Text("Locked").font(REFont.small).foregroundColor(REColors.textDim)
                    }
                }
            }
            .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r8)
        }
    }

    // Audio

    @ViewBuilder
    private var audioTab: some View {
        if audioSamples.isEmpty {
            emptyLabel("No audio samples stored locally")
        } else {
            ForEach(audioSamples) { sample in
                VStack(alignment: .leading, spacing: RE.s4) {
                    HStack {
                        Text(sample.vehicleLabel).font(REFont.body).foregroundColor(REColors.text)
                        Spacer()
                        Text("id: \(sample.id ?? -1)").font(REFont.mono).foregroundColor(REColors.textDim)
                    }
                    HStack(spacing: RE.s8) {
                        dbChip("\(String(format: "%.1f", sample.audioDuration))s")
                        dbChip(sample.synced == 1 ? "uploaded" : "local")
                        dbChip(sample.engineAudible.label)
                        dbChip(sample.vehicleState.label)
                    }
                    Text(sample.localFilePath).font(.system(size: 10)).foregroundColor(REColors.textDim).lineLimit(1)
                    let exists = FileManager.default.fileExists(
                        atPath: AudioExtractor.resolvedURL(for: sample.localFilePath).path
                    )
                    Text(exists ? "File exists on disk" : "FILE MISSING").font(REFont.small)
                        .foregroundColor(exists ? REColors.confGreen : REColors.error)
                }
                .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r8)
            }
        }
    }

    // Helpers

    private func emptyLabel(_ text: String) -> some View {
        Text(text).font(REFont.caption).foregroundColor(REColors.textDim)
            .frame(maxWidth: .infinity).padding(.top, RE.s48)
    }

    private func dbChip(_ text: String) -> some View {
        Text(text).font(.system(size: 10, design: .monospaced))
            .foregroundColor(REColors.textSec)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(REColors.bgInput).cornerRadius(4)
    }
}
