//
//  SpotlightManager.swift
//  FileRing
//
//  Core Spotlight query manager for files and folders, using SpotlightQueryEngine
//

import Foundation
import AppKit
import os.log

@MainActor
class SpotlightManager: NSObject {
    private let engine = SpotlightQueryEngine()
    private let config: SpotlightConfig

    init(config: SpotlightConfig) {
        self.config = config
        super.init()
    }

    // MARK: - File Queries

    private func recentProgressiveWindows() -> [Int] {
        let sameDayWindow = 1
        let extended = max(sameDayWindow, config.recentDays)
        if extended == sameDayWindow {
            return [sameDayWindow]
        }
        return [sameDayWindow, extended]
    }

    /// Query recently opened files - sorted by last used date (newest first)
    func queryRecentlyOpenedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate",
                        dayWindows: recentProgressiveWindows(),
                        isFolder: false,
                        sortBy: "kMDItemLastUsedDate",
                        limit: limit)
    }

    /// Query recently saved files - sorted by modification date (newest first)
    func queryRecentlySavedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemFSContentChangeDate",
                        dayWindows: recentProgressiveWindows(),
                        isFolder: false,
                        sortBy: "kMDItemFSContentChangeDate",
                        limit: limit)
    }

    /// Query frequently opened files - sorted by use count (most used first)
    func queryFrequentlyOpenedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.frequentDays,
                       isFolder: false, sortBy: "kMDItemUseCount", limit: limit)
    }

    // MARK: - Folder Queries

    /// Query recently opened folders - sorted by last used date (newest first)
    func queryRecentlyOpenedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate",
                        dayWindows: recentProgressiveWindows(),
                        isFolder: true,
                        sortBy: "kMDItemLastUsedDate",
                        limit: limit)
    }

    /// Query recently modified folders - sorted by modification date (newest first)
    func queryRecentlyModifiedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemFSContentChangeDate",
                        dayWindows: recentProgressiveWindows(),
                        isFolder: true,
                        sortBy: "kMDItemFSContentChangeDate",
                        limit: limit)
    }

    /// Query frequently opened folders - sorted by use count (most used first)
    func queryFrequentlyOpenedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.frequentDays,
                       isFolder: true, sortBy: "kMDItemUseCount", limit: limit)
    }

    // MARK: - Core Query Logic

    private func query(attribute: String, daysAgo: Int, isFolder: Bool, sortBy: String, limit: Int) async throws -> [FileSystemItem] {
        let window = max(1, abs(daysAgo))
        return try await query(attribute: attribute,
                               dayWindows: [window],
                               isFolder: isFolder,
                               sortBy: sortBy,
                               limit: limit)
    }

    private func query(attribute: String, dayWindows: [Int], isFolder: Bool, sortBy: String, limit: Int) async throws -> [FileSystemItem] {
        let uniqueWindows = dayWindows.reduce(into: [Int]()) { acc, value in
            let normalized = max(1, value)
            if !acc.contains(normalized) {
                acc.append(normalized)
            }
        }

        var results: [FileSystemItem] = []
        var seenPaths = Set<String>()

        for days in uniqueWindows {
            if results.count >= limit { break }

            let descriptor = buildDescriptor(attribute: attribute, daysAgo: -days, isFolder: isFolder, sortBy: sortBy)
            let items = try await engine.execute(descriptor)

            let parsed = parseItems(from: items,
                                    limit: limit - results.count,
                                    isFolder: isFolder,
                                    seenPaths: &seenPaths)
            results.append(contentsOf: parsed)
        }

        return results
    }

    private func buildDescriptor(attribute: String, daysAgo: Int, isFolder: Bool, sortBy: String) -> SpotlightQueryDescriptor {
        // Search scope
        let authorizedSearchPaths = BookmarkManager.shared.authorizedPaths()
        let searchScopes: [Any]
        if !authorizedSearchPaths.isEmpty {
            searchScopes = authorizedSearchPaths.map { URL(fileURLWithPath: $0) }
        } else if config.searchOnlyUserHome {
            searchScopes = [NSMetadataQueryUserHomeScope]
        } else {
            searchScopes = [NSMetadataQueryLocalComputerScope]
        }

        // Predicate
        let startDate = Calendar.current.dateWithFallback(byAdding: .day, value: daysAgo, to: Date())
        var predicates: [NSPredicate] = [
            NSPredicate(format: "\(attribute) >= %@", startDate as NSDate)
        ]

        if isFolder {
            predicates.append(NSPredicate(format: "kMDItemContentType == %@", "public.folder"))
        } else {
            predicates.append(NSPredicate(format: "kMDItemContentTypeTree != %@", "public.folder"))
            for ext in config.excludedExtensions {
                predicates.append(NSPredicate(format: "NOT kMDItemFSName ENDSWITH[cd] %@", ext))
            }
        }

        return SpotlightQueryDescriptor(
            searchScopes: searchScopes,
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            sortDescriptors: [NSSortDescriptor(key: sortBy, ascending: false)],
            timeoutSeconds: config.queryTimeoutSeconds
        )
    }

    // MARK: - Result Parsing

    private func parseItems(from items: [NSMetadataItem], limit: Int, isFolder: Bool, seenPaths: inout Set<String>) -> [FileSystemItem] {
        var results: [FileSystemItem] = []

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            if !BookmarkManager.shared.isPathAuthorized(path) { continue }
            if config.isPathExcluded(path) { continue }
            if seenPaths.contains(path) { continue }

            let itemName = URL(fileURLWithPath: path).lastPathComponent

            if !isFolder && config.isExtensionExcluded(itemName) { continue }

            let displayName = item.value(forAttribute: "kMDItemDisplayName") as? String ?? itemName
            let contentType = item.value(forAttribute: "kMDItemContentType") as? String
                ?? (isFolder ? "public.folder" : "")

            let lastUsed = (item.value(forAttribute: "kMDItemLastUsedDate") as? Date).map(formatDate)
            let lastModified = (item.value(forAttribute: "kMDItemFSContentChangeDate") as? Date).map(formatDate)
            let useCount = item.value(forAttribute: "kMDItemUseCount") as? Int

            results.append(FileSystemItem(
                path: path,
                name: displayName,
                lastUsed: lastUsed,
                lastModified: lastModified,
                contentType: contentType,
                itemType: isFolder ? .folder : .file,
                bundleIdentifier: nil,
                version: nil,
                useCount: useCount
            ))
            seenPaths.insert(path)

            if results.count >= limit { break }
        }

        return results
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.spotlightDateFormatter.string(from: date)
    }

    // MARK: - File Operations

    func openFile(at path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if url.pathExtension == "app" {
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            try await NSWorkspace.shared.open(url, configuration: configuration)
        }
    }

    func copyToClipboard(path: String, mode: ClipboardMode) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch mode {
        case .file:
            let url = URL(fileURLWithPath: path)
            pasteboard.writeObjects([url as NSPasteboardWriting])
        case .path:
            pasteboard.setString(path, forType: .string)
        }
    }
}

// MARK: - Errors

enum SpotlightError: LocalizedError {
    case timeout
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Query timeout"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}
