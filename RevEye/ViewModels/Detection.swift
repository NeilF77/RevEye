import Foundation

struct Detection {
    var id: Int64?
    var localFilePath: String      // where the image is saved on device
    var vehicleLabel: String       // e.g. "BMW 3 Series"
    var confidence: Double
    var timestamp: String          // ISO8601 string
    var synced: Int                // 0 = not synced, 1 = synced
}
