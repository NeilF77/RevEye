//
//  Item.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//

import Foundation
import SwiftData

// SwiftData model for storing item timestamps
// @Model macro makes this class compatible with SwiftData persistence
@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
