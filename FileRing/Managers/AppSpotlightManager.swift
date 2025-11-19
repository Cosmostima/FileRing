//
//  AppSpotlightManager.swift
//  PopUp
//
//  Application-specific Spotlight query manager using NSMetadataQuery
//

import Foundation
import AppKit

private final class AppQueryContext {
    let query: NSMetadataQuery
    let continuation: CheckedContinuation<[NSMetadataItem], Error>
    var timeoutTask: Task<Void, Never>?

    init(query: NSMetadataQuery, continuation: CheckedContinuation<[NSMetadataItem], Error>) {
        self.query = query
        self.continuation = continuation
    }
}

private final class CancellationToken: @unchecked Sendable {
    var identifier: ObjectIdentifier?
}

@MainActor
class AppSpotlightManager: NSObject {
    private var activeQueries: [ObjectIdentifier: AppQueryContext] = [:]

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
        let cancellationToken = CancellationToken()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = NSMetadataQuery()
                let identifier = ObjectIdentifier(query)

                let context = AppQueryContext(query: query, continuation: continuation)
                activeQueries[identifier] = context
                cancellationToken.identifier = identifier

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
                context.timeoutTask = Task { [weak self, weak query] in
                    guard let query = query else { return }
                    guard let self = self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                        if Task.isCancelled { return }
                        await self.handleTimeout(for: query)
                    } catch {
                        // Task cancelled, ignore
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let id = cancellationToken.identifier else { return }
                self.cancelQuery(with: id, error: CancellationError())
            }
        }
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
        cancelQuery(with: ObjectIdentifier(query), error: error)
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
