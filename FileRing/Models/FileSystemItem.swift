//
//  FileSystemItem.swift
//  FileRing
//
//  Created by Claude on 30/10/2025.
//

import Foundation

// MARK: - Item Type
enum ItemType: String, Codable, Sendable {
    case file
    case folder
    case application
}

// MARK: - File System Item (unified model for files, folders, and applications)
struct FileSystemItem: Codable, Identifiable, Sendable {
    let path: String
    let name: String
    let lastUsed: String?
    let lastModified: String?
    let contentType: String
    let itemType: ItemType?
    let bundleIdentifier: String?
    let version: String?
    let useCount: Int?

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
        case itemType = "item_type"
        case bundleIdentifier = "bundle_identifier"
        case version
        case useCount = "use_count"
    }

    /// Convenience initializer for files/folders (backward compatibility)
    init(path: String, name: String, lastUsed: String?, lastModified: String?, contentType: String) {
        self.path = path
        self.name = name
        self.lastUsed = lastUsed
        self.lastModified = lastModified
        self.contentType = contentType
        self.itemType = contentType == "public.folder" ? .folder : .file
        self.bundleIdentifier = nil
        self.version = nil
        self.useCount = nil
    }

    /// Full initializer for all types including applications
    init(path: String, name: String, lastUsed: String?, lastModified: String?, contentType: String,
         itemType: ItemType?, bundleIdentifier: String?, version: String?, useCount: Int?) {
        self.path = path
        self.name = name
        self.lastUsed = lastUsed
        self.lastModified = lastModified
        self.contentType = contentType
        self.itemType = itemType
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.useCount = useCount
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