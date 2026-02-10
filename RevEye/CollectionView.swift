import SwiftUI

struct CollectionView: View {
    @State private var detections: [Detection] = []
    private let db = DatabaseManager.shared

    var body: some View {
        List(detections) { det in
            VStack(alignment: .leading) {
                Text(det.vehicleLabel)
                    .font(.headline)
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
        .onAppear {
            detections = db.fetchAllDetections()
        }
    }
}
