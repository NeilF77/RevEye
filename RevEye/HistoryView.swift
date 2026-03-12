//
//  HistoryView.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Replaces CollectionView. Card-based detection history with themed styling.
//  Accessible from the History tab in MainTabView.

import SwiftUI

struct HistoryView: View {
    @Binding var detections: [Detection]

    @State private var isSyncing = false
    @State private var syncMessage: String?
    private let db = DatabaseManager.shared

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bgPrimary.ignoresSafeArea()

                if detections.isEmpty {
                    emptyState
                } else {
                    detectionsList
                }
            }
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: RESpacing.md) {
                        Button {
                            syncUnsynced()
                        } label: {
                            if isSyncing {
                                ProgressView().tint(REColors.accent)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(REColors.accent)
                            }
                        }
                        .disabled(isSyncing)
                    }
                }
            }
            .onAppear {
                detections = db.fetchAllDetections()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RESpacing.lg) {
            Image(systemName: "car.circle")
                .font(.system(size: 56))
                .foregroundColor(REColors.textMuted)
            Text("No detections yet")
                .font(REFonts.headline)
                .foregroundColor(REColors.textSecondary)
            Text("Identified vehicles will appear here.\nHead to Scan to get started.")
                .font(REFonts.caption)
                .foregroundColor(REColors.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Detections List

    private var detectionsList: some View {
        ScrollView {
            LazyVStack(spacing: RESpacing.sm) {
                // Summary
                HStack {
                    Text("\(detections.count) detection\(detections.count == 1 ? "" : "s")")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.textMuted)
                    Spacer()
                    if let msg = syncMessage {
                        Text(msg)
                            .font(REFonts.caption2)
                            .foregroundColor(REColors.textMuted)
                    }
                }
                .padding(.horizontal, RESpacing.lg)
                .padding(.top, RESpacing.sm)

                ForEach(detections) { det in
                    detectionCard(det)
                        .padding(.horizontal, RESpacing.lg)
                }
            }
            .padding(.bottom, RESpacing.xl)
        }
    }

    // MARK: - Detection Card

    private func detectionCard(_ det: Detection) -> some View {
        HStack(spacing: RESpacing.md) {
            // Vehicle icon with confidence colour
            ZStack {
                Circle()
                    .fill(REColors.forTier(ConfidenceTier.tier(for: det.confidence)).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "car.fill")
                    .foregroundColor(REColors.forTier(ConfidenceTier.tier(for: det.confidence)))
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(det.vehicleLabel)
                        .font(REFonts.headline)
                        .foregroundColor(REColors.textPrimary)
                        .lineLimit(2)

                    if det.audioSampleId != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(REColors.brandBlue)
                    }
                }

                Text("\(Int(det.confidence * 100))% confidence")
                    .font(REFonts.caption)
                    .foregroundColor(REColors.forTier(ConfidenceTier.tier(for: det.confidence)))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                // Sync status
                Image(systemName: det.synced == 1 ? "checkmark.icloud" : "icloud.slash")
                    .font(.system(size: 12))
                    .foregroundColor(det.synced == 1 ? REColors.brandBlue : REColors.accent)

                Text(formatWallTime(det.timestamp))
                    .font(REFonts.caption2)
                    .foregroundColor(REColors.textMuted)
            }
        }
        .padding(RESpacing.md)
        .background(REColors.bgSecondary)
        .cornerRadius(RERadius.md)
        .contextMenu {
            Button(role: .destructive) {
                if let id = det.id {
                    db.deleteDetection(id: id)
                    detections = db.fetchAllDetections()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Sync

    private func syncUnsynced() {
        let unsynced = db.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else {
            syncMessage = "All synced"
            return
        }
        isSyncing = true
        syncMessage = nil

        let group = DispatchGroup()
        var successCount = 0

        for det in unsynced {
            group.enter()
            FirebaseService.shared.uploadDetection(det, source: .photo) { success in
                if success { successCount += 1 }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            detections = db.fetchAllDetections()
            isSyncing = false
            syncMessage = "\(successCount)/\(unsynced.count) synced"
        }
    }

    // MARK: - Helpers

    private func formatWallTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
