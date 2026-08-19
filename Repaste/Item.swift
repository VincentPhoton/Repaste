//
//  Item.swift
//  Repaste
//
//  Created by 陈晓峰 on 2026/8/19.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
