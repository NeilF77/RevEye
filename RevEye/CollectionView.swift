//
//  CollectionView.swift
//  RevEye
//
//  Created by user on 06/02/2026.
//

import SwiftUI

struct CollectionView: View {
    @State private var detections: [Detection] = []
    @State private var isSyncing = false
    private let db = DatabaseManager.shared

    var body: some View {
        List {
            ForEach(detections) { det in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(det.vehicleLabel)
                            .font(.headline)
                        Spacer()
                        // Sync status badge
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
                    // EditButton enables swipe-to-delete and the red minus buttons
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
            loadDetections()
        }
    }

    // MARK: - Private

    private func loadDetections() {
        detections = db.fetchAllDetections()
    }

    private func deleteDetections(at offsets: IndexSet) {
        for index in offsets {
            if let id = detections[index].id {
                db.deleteDetection(id: id)
            }
        }
        // Remove from local array so the list updates instantly
        detections.remove(atOffsets: offsets)
    }

    private func syncUnsynced() {
        let unsynced = db.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else {
            print("Nothing to sync")
            return
        }

        isSyncing = true

        // Upload each unsynced detection. FirebaseService.uploadDetection already calls
        // markAsSynced internally when the upload succeeds, so we just need to reload
        // the list once enough time has passed for the callbacks to complete.
        for det in unsynced {
            FirebaseService.shared.uploadDetection(det, source: .photo)
        }

        // Reload after a short delay to reflect updated synced flags from Firebase callbacks.
        // A more robust approach would be a completion-based API on FirebaseService,
        // but this covers the typical case cleanly without over-engineering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            loadDetections()
            isSyncing = false
        }
    }

    /// Converts an ISO8601 string to a readable date like "6 Feb 2026, 14:32"
    private func formatWallTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
