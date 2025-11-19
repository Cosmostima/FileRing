//
//  SpotlightManager.swift
//  PopUp
//
//  Core Spotlight query manager using NSMetadataQuery
//

import Foundation
import AppKit
import os.log

private final class SpotlightQueryContext {
    let query: NSMetadataQuery
    let continuation: CheckedContinuation<[NSMetadataItem], Error>
    var timeoutTask: Task<Void, Never>?

    init(query: NSMetadataQuery, continuation: CheckedContinuation<[NSMetadataItem], Error>) {
        self.query = query
        self.continuation = continuation
    }
}

private final class SpotlightCancellationToken: @unchecked Sendable {
    var identifier: ObjectIdentifier?
}

@MainActor
class SpotlightManager: NSObject {
    private var activeQueries: [ObjectIdentifier: SpotlightQueryContext] = [:]

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

    /// Core query method - always sorts descending (newest/highest first)
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
        let authorizedPaths = BookmarkManager.shared.authorizedPaths()

        for days in uniqueWindows {
            if results.count >= limit { break }

            let remainingLimit = limit - results.count
            let items = try await performQuery(attribute: attribute,
                                               daysAgo: -days,
                                               isFolder: isFolder,
                                               sortBy: sortBy,
                                               ascending: false)

            let parsed = parseItems(from: items,
                                    limit: remainingLimit,
                                    isFolder: isFolder,
                                    authorizedPaths: authorizedPaths,
                                    seenPaths: &seenPaths)
            results.append(contentsOf: parsed)
        }

        return results
    }

    private func performQuery(
        attribute: String,
        daysAgo: Int,
        isFolder: Bool,
        sortBy: String,
        ascending: Bool
    ) async throws -> [NSMetadataItem] {
        let cancellationToken = SpotlightCancellationToken()

        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "SpotlightQuery", signpostID: signpostID, "Attribute: %{public}s, SortBy: %{public}s", attribute, sortBy)

        let items = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = NSMetadataQuery()
                let identifier = ObjectIdentifier(query)

                let context = SpotlightQueryContext(query: query, continuation: continuation)
                activeQueries[identifier] = context
                cancellationToken.identifier = identifier

                // Set search scope
                // Prefer user-authorized folders as the Spotlight scope to avoid scanning the whole home
                let authorizedSearchPaths = BookmarkManager.shared.authorizedPaths()
                if !authorizedSearchPaths.isEmpty {
                    query.searchScopes = authorizedSearchPaths.map { URL(fileURLWithPath: $0) }
                } else if config.searchOnlyUserHome {
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
                context.timeoutTask = Task { [weak self, weak query] in
                    guard let query = query else { return }
                    guard let self = self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                        if Task.isCancelled { return }
                        await self.handleTimeout(for: query)
                    } catch {
                        // Task cancelled, no-op
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let id = cancellationToken.identifier else { return }
                self.cancelQuery(with: id, error: CancellationError())
            }
        }

        os_signpost(.end, log: .pointsOfInterest, name: "SpotlightQuery", signpostID: signpostID, "Found %d raw items", items.count)
        return items
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else {
            return
        }

        let identifier = ObjectIdentifier(query)
        guard let context = activeQueries.removeValue(forKey: identifier) else {
            return
        }

        context.timeoutTask?.cancel()

        query.disableUpdates()

        var items: [NSMetadataItem] = []
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem {
                items.append(item)
            }
        }

        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        context.continuation.resume(returning: items)
    }

    private func handleTimeout(for query: NSMetadataQuery) async {
        cancelQuery(for: query, error: SpotlightError.timeout)
    }

    private func cancelQuery(for query: NSMetadataQuery, error: Error) {
        let identifier = ObjectIdentifier(query)
        cancelQuery(with: identifier, error: error)
    }

    private func cancelQuery(with identifier: ObjectIdentifier, error: Error) {
        guard let context = activeQueries.removeValue(forKey: identifier) else {
            return
        }

        context.timeoutTask?.cancel()

        let query = context.query
        query.disableUpdates()
        query.stop()

        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        context.continuation.resume(throwing: error)
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

    private func parseItems(from items: [NSMetadataItem], limit: Int, isFolder: Bool, authorizedPaths: [String], seenPaths: inout Set<String>) -> [FileSystemItem] {
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

            if seenPaths.contains(path) {
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

        // Check if this is an application bundle
        let isApp = path.hasSuffix(".app") || url.pathExtension == "app"

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if isApp {
            // For applications, use openApplication to launch them
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        } else {
            // For regular files and folders, use open
            NSWorkspace.shared.open(url, configuration: configuration) { _, _ in }
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

    @MainActor deinit {
        for (_, context) in activeQueries {
            context.timeoutTask?.cancel()
            context.query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: context.query)
            context.continuation.resume(throwing: SpotlightError.queryFailed("Deinit before completion"))
        }
        activeQueries.removeAll()
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
