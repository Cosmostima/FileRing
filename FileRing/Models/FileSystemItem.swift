//
//  FileSystemItem.swift
//  PopUp
//
//  Created by Claude on 30/10/2025.
//

import Foundation

// MARK: - File System Item (unified model for files and folders)
struct FileSystemItem: Codable, Identifiable, Sendable {
    let path: String
    let name: String
    let lastUsed: String?
    let lastModified: String?
    let contentType: String

    var id: String { path }
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || Self.looksLikeTimestamp(trimmed) {
            return fallbackName()
        }
        return trimmed
    }

    /// Returns the timestamp to display (lastModified or lastUsed, whichever is available)
    var timestamp: String? {
        return lastModified ?? lastUsed
    }

    enum CodingKeys: String, CodingKey {
        case path, name
        case lastUsed = "last_used"
        case lastModified = "last_modified"
        case contentType = "content_type"
    }

    private func fallbackName() -> String {
        let url = URL(fileURLWithPath: path)
        let candidate = url.lastPathComponent
        if !candidate.isEmpty {
            return candidate
        }
        return path
    }

    private static func looksLikeTimestamp(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
    }
}

// MARK: - Type Aliases for backward compatibility
typealias FileItem = FileSystemItem
typealias FolderItem = FileSystemItem
