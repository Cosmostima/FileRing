//
//  CategoryType.swift
//  PopUp
//
//  Created by Claude on 30/10/2025.
//

import Foundation

// MARK: - Category Types
enum CategoryType: String, CaseIterable {
    case recentlyOpened = "Recently Opened"
    case recentlySaved = "Recently Saved"
    case frequentlyOpened = "Frequently Used"

    var fileEndpoint: String {
        switch self {
        case .recentlyOpened: return "/recently-opened"
        case .recentlySaved: return "/recently-saved"
        case .frequentlyOpened: return "/frequently-opened"
        }
    }

    var folderEndpoint: String {
        switch self {
        case .recentlyOpened: return "/folders/recently-opened"
        case .recentlySaved: return "/folders/recently-modified"
        case .frequentlyOpened: return "/folders/frequently-opened"
        }
    }
}
