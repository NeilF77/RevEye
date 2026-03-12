//
//  CollectionView.swift
//  RevEye
//
//  Created by user on 06/02/2026.
//  Updated 10/03/2026 — added audio indicator icon

import SwiftUI

struct CollectionView: View {
    @Binding var detections: [Detection]

    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    private let db = DatabaseManager.shared

    var body: some View {
        List {
            ForEach(detections) { det in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(det.vehicleLabel)
                            .font(.headline)

                        // Audio indicator — shows if this detection has an audio sample
                        if det.audioSampleId != nil {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Label(
                            det.synced == 1 ? "Synced" : "Local",
                            systemImage: det.synced == 1 ? "checkmark.icloud" : "icloud.slash"
                        )
                        .font(.caption)
                        .foregroundColor(det.synced == 1 ? .blue : .orange)
                    }

                    Text(String(format: "Confidence: %.0f%%", det.confidence * 100))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(formatWallTime(det.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteDetections)
        }
        .navigationTitle("My Collection")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    EditButton()
                    Button {
                        syncUnsynced()
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Text("Sync")
                        }
                    }
                    .disabled(isSyncing)
                }
            }
        }
        .onAppear {
            detections = db.fetchAllDetections()
        }
        if let msg = syncMessage {
            Text(msg)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Private

    private func deleteDetections(at offsets: IndexSet) {
        for index in offsets {
            if let id = detections[index].id {
                db.deleteDetection(id: id)
            }
        }
        detections.remove(atOffsets: offsets)
    }

    private func syncUnsynced() {
        let unsynced = db.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else {
            syncMessage = "Everything is synced."
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
            syncMessage = "\(successCount) of \(unsynced.count) detection(s) synced."
        }
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
