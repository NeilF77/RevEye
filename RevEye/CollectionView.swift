//
//  CollectionView.swift
//  RevEye
//
//  Created by user on 06/02/2026.
//


import SwiftUI

struct CollectionView: View {
    @State private var detections: [Detection] = []
    private let db = DatabaseManager.shared
    
    var body: some View {
           List(detections, id: \.id) { det in
               VStack(alignment: .leading) {
                   HStack {
                       Text(det.vehicleLabel)
                           .font(.headline)

                       if det.synced == 1 {
                           Text("(cloud)")
                               .font(.caption)
                               .foregroundColor(.blue)
                       } else {
                           Text("(local)")
                               .font(.caption)
                               .foregroundColor(.orange)
                       }
                   }

                   Text(String(format: "Confidence: %.0f%%", det.confidence * 100))
                       .font(.subheadline)
                       .foregroundColor(.secondary)

                   Text(det.timestamp)
                       .font(.caption)
                       .foregroundColor(.secondary)
               }
               .padding(.vertical, 4)
           }
           .navigationTitle("My Collection")
           .toolbar {
               Button("Sync") {
                   syncUnsynced()
               }
           }
           .onAppear {
               loadDetections()
           }
       }

       private func loadDetections() {
           detections = db.fetchAllDetections()
       }

       private func syncUnsynced() {
           let unsynced = db.fetchUnsyncedDetections()
           guard !unsynced.isEmpty else {
               print("No unsynced detections to upload")
               return
           }

           for det in unsynced {
               FirebaseService.shared.uploadDetection(det)
           }

           // Reload list to reflect updated synced flags
           detections = db.fetchAllDetections()
       }
   }
