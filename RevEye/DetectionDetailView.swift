//
//  DetectionDetailView.swift
//  RevEye
//
//  Created 14/03/2026 — full detection detail with saved image

import SwiftUI

struct DetectionDetailView: View {
    let detection: Detection
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: RE.s24) {

                    // Image
                    if let img = image {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .cornerRadius(RE.r12)
                            .padding(.horizontal, RE.s16)
                            .padding(.top, RE.s8)
                    } else {
                        // No image placeholder
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

                    // Vehicle info
                    VStack(spacing: RE.s12) {
                        // Confidence pill
                        let confColor = REColors.displayConf(detection.confidence)
                        Text("\(Int(detection.confidence * 100))% match")
                            .font(REFont.caption).foregroundColor(confColor)
                            .padding(.horizontal, RE.s12).padding(.vertical, RE.s4)
                            .background(confColor.opacity(0.1)).cornerRadius(100)

                        // Vehicle name
                        Text(detection.vehicleLabel)
                            .font(REFont.title)
                            .foregroundColor(REColors.text)
                            .multilineTextAlignment(.center)
                    }

                    // Metadata
                    VStack(spacing: 0) {
                        metaRow("calendar", "Date", fmtDate(detection.timestamp))
                        Divider().background(REColors.bgInput)
                        metaRow("clock", "Time", fmtTime(detection.timestamp))
                        Divider().background(REColors.bgInput)
                        metaRow("chart.bar", "Confidence", "\(Int(detection.confidence * 100))%")
                        Divider().background(REColors.bgInput)
                        metaRow(detection.synced == 1 ? "checkmark.icloud" : "icloud.slash",
                                "Sync Status", detection.synced == 1 ? "Synced" : "Pending")
                        if detection.audioSampleId != nil {
                            Divider().background(REColors.bgInput)
                            metaRow("waveform", "Audio", "Sample attached")
                        }
                    }
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)
                    .padding(.horizontal, RE.s16)

                    // Delete button
                    Button { showDeleteConfirm = true } label: {
                        Text("Delete Detection")
                    }
                    .buttonStyle(REDestructiveButton())
                    .padding(.horizontal, RE.s16)

                    Spacer().frame(height: RE.s48)
                }
            }
        }
        .navigationTitle("Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if let id = detection.id {
                image = ImageStore.load(for: id)
            }
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
}