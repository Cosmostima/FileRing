//
//  AppSpotlightManager.swift
//  PopUp
//
//  Application-specific Spotlight query manager using NSMetadataQuery
//

import Foundation
import AppKit

@MainActor
class AppSpotlightManager: NSObject {
    private var currentQuery: NSMetadataQuery?
    private var continuation: CheckedContinuation<[NSMetadataItem], Error>?
    private var timeoutTask: Task<Void, Never>?

    // Query serialization to prevent continuation overwrites
    private var isQueryRunning = false

    private let config: SpotlightConfig

    init(config: SpotlightConfig) {
        self.config = config
        super.init()
    }

    // MARK: - Application Queries

    /// Query recently used applications - sorted by last used date (newest first)
    func queryRecentlyUsedApps(limit: Int) async throws -> [FileSystemItem] {
        try await queryApps(
            attribute: "kMDItemLastUsedDate",
            daysAgo: -config.recentDays,
            sortBy: "kMDItemLastUsedDate",
            limit: limit
        )
    }

    /// Query frequently used applications - sorted by use count (most used first)
    func queryFrequentlyUsedApps(limit: Int) async throws -> [FileSystemItem] {
        try await queryApps(
            attribute: "kMDItemLastUsedDate",
            daysAgo: -config.frequentDays,
            sortBy: "kMDItemUseCount",
            limit: limit
        )
    }

    // MARK: - Core Query Logic

    private func queryApps(
        attribute: String,
        daysAgo: Int,
        sortBy: String,
        limit: Int
    ) async throws -> [FileSystemItem] {
        // ascending: false = descending order (newest/most used first)
        let items = try await performAppQuery(
            attribute: attribute,
            daysAgo: daysAgo,
            sortBy: sortBy,
            ascending: false
        )

        return parseAppItems(from: items, limit: limit)
    }

    private func performAppQuery(
        attribute: String,
        daysAgo: Int,
        sortBy: String,
        ascending: Bool
    ) async throws -> [NSMetadataItem] {
        // Wait for any existing query to complete (reduce delay to 10ms for lower latency)
        while isQueryRunning {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        isQueryRunning = true

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let query = NSMetadataQuery()
            self.currentQuery = query

            // Set search scope - ALWAYS search entire system for apps
            // (Applications are typically in /Applications which is outside user home)
            query.searchScopes = [NSMetadataQueryLocalComputerScope]

            // Build predicate for applications
            let startDate = Calendar.current.date(byAdding: .day, value: daysAgo, to: Date())!
            var predicates: [NSPredicate] = [
                NSPredicate(format: "kMDItemContentType == %@", "com.apple.application-bundle"),
                NSPredicate(format: "\(attribute) >= %@", startDate as NSDate)
            ]

            // Optional: Exclude system applications
            if config.excludeSystemApps {
                predicates.append(NSPredicate(format: "NOT kMDItemPath BEGINSWITH %@", "/System"))
                predicates.append(NSPredicate(format: "NOT kMDItemPath BEGINSWITH %@", "/Library"))
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
        isQueryRunning = false
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
        isQueryRunning = false
    }

    // MARK: - Result Parsing

    private func parseAppItems(from items: [NSMetadataItem], limit: Int) -> [FileSystemItem] {
        var results: [FileSystemItem] = []
        let homeDir = NSHomeDirectory()
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            // IMPORTANT: Do NOT check authorized paths for applications!
            // Applications in /Applications, /System/Applications are publicly readable
            // and don't require security-scoped bookmark authorization.
            // The security-scoped bookmark system has known issues with /Applications folder.

            // Only apply exclusion filter (for DerivedData, build artifacts, etc.)
            if config.isPathExcluded(path, homeDir: homeDir) {
                continue
            }

            // Extract metadata
            let fsName = item.value(forAttribute: "kMDItemFSName") as? String ?? ""
            let displayName = item.value(forAttribute: "kMDItemDisplayName") as? String
                ?? fsName.replacingOccurrences(of: ".app", with: "")
            let bundleID = item.value(forAttribute: "kMDItemCFBundleIdentifier") as? String
            let version = item.value(forAttribute: "kMDItemVersion") as? String
            let lastUsed = (item.value(forAttribute: "kMDItemLastUsedDate") as? Date).map(formatDate)
            let useCount = item.value(forAttribute: "kMDItemUseCount") as? Int

            results.append(FileSystemItem(
                path: path,
                name: displayName,
                lastUsed: lastUsed,
                lastModified: nil,
                contentType: "com.apple.application-bundle",
                itemType: .application,
                bundleIdentifier: bundleID,
                version: version,
                useCount: useCount
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

    deinit {
        currentQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }
}
