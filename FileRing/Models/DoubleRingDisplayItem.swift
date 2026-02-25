//
//  DoubleRingDisplayItem.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import Foundation

struct DoubleRingDisplayItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isFolder: Bool
    let isApplication: Bool
    let parentPath: String  // Two-level parent path like "Documents / Projects"
    let lastModified: String?  // ISO 8601 timestamp
}
