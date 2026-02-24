//
//  CollectionView.swift
//  RevEye
//
//  Created by user on 06/02/2026.
//

import SwiftUI

struct CollectionView: View {
    // Passed in from HomeView so both views share the same source of truth.
    // When HomeView saves a detection, it updates this binding and CollectionView
    // reflects the change immediately without needing onAppear to re-fire.
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
        // Reload every time the view appears — handles the case where the user
        // navigates away, a background sync marks rows as synced, then navigates back
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

    /// Uploads each unsynced detection and reloads the list only after every
    /// upload has completed — no arbitrary delay needed.
    private func syncUnsynced() {
        let unsynced = db.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else {
            syncMessage = "Everything is synced."
            return
        }

        isSyncing = true
        syncMessage = nil

        // Use a DispatchGroup to know exactly when all uploads have finished
        let group = DispatchGroup()
        var successCount = 0

        for det in unsynced {
            group.enter()
            FirebaseService.shared.uploadDetection(det, source: .photo) { success in
                if success { successCount += 1 }
                group.leave()
            }
        }

        // This fires on the main thread once every completion handler has called leave()
        group.notify(queue: .main) {
            detections = db.fetchAllDetections()
            isSyncing = false
            syncMessage = "\(successCount) of \(unsynced.count) detection(s) synced."
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
