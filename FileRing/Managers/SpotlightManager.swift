//
//  SpotlightManager.swift
//  PopUp
//
//  Core Spotlight query manager using NSMetadataQuery
//

import Foundation
import AppKit

@MainActor
class SpotlightManager: NSObject {
    private var currentQuery: NSMetadataQuery?
    private var continuation: CheckedContinuation<[NSMetadataItem], Error>?
    private var timeoutTask: Task<Void, Never>?

    private let config: SpotlightConfig

    init(config: SpotlightConfig) {
        self.config = config
        super.init()
    }

    // MARK: - File Queries

    /// Query recently opened files - sorted by last used date (newest first)
    func queryRecentlyOpenedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.recentDays,
                       isFolder: false, sortBy: "kMDItemLastUsedDate", limit: limit)
    }

    /// Query recently saved files - sorted by modification date (newest first)
    func queryRecentlySavedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemFSContentChangeDate", daysAgo: -config.recentDays,
                       isFolder: false, sortBy: "kMDItemFSContentChangeDate", limit: limit)
    }

    /// Query frequently opened files - sorted by use count (most used first)
    func queryFrequentlyOpenedFiles(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.frequentDays,
                       isFolder: false, sortBy: "kMDItemUseCount", limit: limit)
    }

    // MARK: - Folder Queries

    /// Query recently opened folders - sorted by last used date (newest first)
    func queryRecentlyOpenedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.recentDays,
                       isFolder: true, sortBy: "kMDItemLastUsedDate", limit: limit)
    }

    /// Query recently modified folders - sorted by modification date (newest first)
    func queryRecentlyModifiedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemFSContentChangeDate", daysAgo: -config.recentDays,
                       isFolder: true, sortBy: "kMDItemFSContentChangeDate", limit: limit)
    }

    /// Query frequently opened folders - sorted by use count (most used first)
    func queryFrequentlyOpenedFolders(limit: Int) async throws -> [FileSystemItem] {
        try await query(attribute: "kMDItemLastUsedDate", daysAgo: -config.frequentDays,
                       isFolder: true, sortBy: "kMDItemUseCount", limit: limit)
    }

    // MARK: - Core Query Logic

    /// Core query method - always sorts descending (newest/highest first)
    private func query(attribute: String, daysAgo: Int, isFolder: Bool, sortBy: String, limit: Int) async throws -> [FileSystemItem] {
        // ascending: false = descending order (newest/most used first)
        let items = try await performQuery(attribute: attribute, daysAgo: daysAgo,
                                           isFolder: isFolder, sortBy: sortBy, ascending: false)

        // Get authorized paths once for the entire batch
        let authorizedPaths = BookmarkManager.shared.authorizedPaths()
        return parseItems(from: items, limit: limit, isFolder: isFolder, authorizedPaths: authorizedPaths)
    }

    private func performQuery(
        attribute: String,
        daysAgo: Int,
        isFolder: Bool,
        sortBy: String,
        ascending: Bool
    ) async throws -> [NSMetadataItem] {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let query = NSMetadataQuery()
            self.currentQuery = query

            // Set search scope
            if config.searchOnlyUserHome {
                // Use user home scope which includes ~/Library/Mobile Documents (iCloud Drive)
                query.searchScopes = [NSMetadataQueryUserHomeScope]
            } else {
                query.searchScopes = [NSMetadataQueryLocalComputerScope]
            }

            // Build predicate
            let startDate = Calendar.current.date(byAdding: .day, value: daysAgo, to: Date())!
            var predicates: [NSPredicate] = [
                NSPredicate(format: "\(attribute) >= %@", startDate as NSDate)
            ]

            // Filter by folder/file
            if isFolder {
                predicates.append(NSPredicate(format: "kMDItemContentType == %@", "public.folder"))
            } else {
                predicates.append(NSPredicate(format: "kMDItemContentTypeTree != %@", "public.folder"))

                // Exclude extensions via predicate (more efficient)
                if !config.excludedExtensions.isEmpty {
                    for ext in config.excludedExtensions {
                        predicates.append(NSPredicate(format: "NOT kMDItemFSName ENDSWITH[cd] %@", ext))
                    }
                }
            }

            query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            // Set sort descriptors
            query.sortDescriptors = [NSSortDescriptor(key: sortBy, ascending: ascending)]

            // Register notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queryDidFinishGathering),
                name: .NSMetadataQueryDidFinishGathering,
                object: query
            )

            // Start query
            query.start()

            // Setup timeout
            let timeoutSeconds = config.queryTimeoutSeconds
            self.timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    self?.handleTimeout()
                } catch {
                    // Task was cancelled, which is expected
                }
            }
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        timeoutTask?.cancel()

        guard let query = notification.object as? NSMetadataQuery else {
            continuation?.resume(throwing: SpotlightError.queryFailed("Invalid query object"))
            continuation = nil
            return
        }

        query.disableUpdates()

        var items: [NSMetadataItem] = []
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem {
                items.append(item)
            }
        }

        query.stop()
        currentQuery = nil
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        continuation?.resume(returning: items)
        continuation = nil
    }

    private func handleTimeout() {
        guard let query = currentQuery else { return }

        // Properly stop the query to free resources
        query.disableUpdates()
        query.stop()
        currentQuery = nil

        // Remove observer to prevent memory leaks
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        continuation?.resume(throwing: SpotlightError.timeout)
        continuation = nil
    }

    // MARK: - Result Parsing

    /// Fast path authorization check using pre-fetched authorized paths
    private func isPathInAuthorizedFolders(_ path: String, authorizedPaths: [String]) -> Bool {
        // If no authorized paths, allow nothing
        guard !authorizedPaths.isEmpty else { return false }

        // Check if path starts with any authorized path
        for authorizedPath in authorizedPaths {
            if path.hasPrefix(authorizedPath) {
                return true
            }
        }

        return false
    }

    private func parseItems(from items: [NSMetadataItem], limit: Int, isFolder: Bool, authorizedPaths: [String]) -> [FileSystemItem] {
        var results: [FileSystemItem] = []

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            // Check if path is in authorized folders (whitelist) - optimized batch check
            if !isPathInAuthorizedFolders(path, authorizedPaths: authorizedPaths) {
                continue
            }

            if config.isPathExcluded(path) {
                continue
            }

            let itemName = URL(fileURLWithPath: path).lastPathComponent

            // Apply extension filtering for files only
            if !isFolder && config.isExtensionExcluded(itemName) {
                continue
            }

            let displayName = item.value(forAttribute: "kMDItemDisplayName") as? String ?? itemName
            let contentType = item.value(forAttribute: "kMDItemContentType") as? String
                ?? (isFolder ? "public.folder" : "")

            let lastUsed = (item.value(forAttribute: "kMDItemLastUsedDate") as? Date).map(formatDate)
            let lastModified = (item.value(forAttribute: "kMDItemFSContentChangeDate") as? Date).map(formatDate)

            results.append(FileSystemItem(
                path: path,
                name: displayName,
                lastUsed: lastUsed,
                lastModified: lastModified,
                contentType: contentType
            ))

            if results.count >= limit {
                break
            }
        }

        return results
    }

    private func formatDate(_ date: Date) -> String {
        // Format: "2025-10-31 07:29:56 +0000"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    // MARK: - File Operations

    func openFile(at path: String) throws {
        let url = URL(fileURLWithPath: path)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(url, configuration: configuration) { _, _ in }
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

    deinit {
        currentQuery?.stop()
        NotificationCenter.default.removeObserver(self)
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
