//
//  AppSpotlightManager.swift
//  FileRing
//
//  Application-specific Spotlight query manager, using SpotlightQueryEngine
//

import Foundation
import AppKit

@MainActor
class AppSpotlightManager: NSObject {
    private let engine = SpotlightQueryEngine()
    private let config: SpotlightConfig

    init(config: SpotlightConfig) {
        self.config = config
        super.init()
    }

    // MARK: - Application Queries

    /// Query recently used applications - sorted by last used date (newest first)
    func queryRecentlyUsedApps(limit: Int) async throws -> [FileSystemItem] {
        let descriptor = buildDescriptor(
            attribute: "kMDItemLastUsedDate",
            daysAgo: -config.recentDays,
            sortBy: "kMDItemLastUsedDate"
        )
        let items = try await engine.execute(descriptor)
        return parseAppItems(from: items, limit: limit)
    }

    /// Query frequently used applications - sorted by use count (most used first)
    func queryFrequentlyUsedApps(limit: Int) async throws -> [FileSystemItem] {
        let descriptor = buildDescriptor(
            attribute: "kMDItemLastUsedDate",
            daysAgo: -config.frequentDays,
            sortBy: "kMDItemUseCount"
        )
        let items = try await engine.execute(descriptor)
        return parseAppItems(from: items, limit: limit)
    }

    // MARK: - Descriptor Building

    private func buildDescriptor(attribute: String, daysAgo: Int, sortBy: String) -> SpotlightQueryDescriptor {
        let startDate = Calendar.current.dateWithFallback(byAdding: .day, value: daysAgo, to: Date())
        var predicates: [NSPredicate] = [
            NSPredicate(format: "kMDItemContentType == %@", "com.apple.application-bundle"),
            NSPredicate(format: "\(attribute) >= %@", startDate as NSDate)
        ]

        if config.excludeSystemApps {
            predicates.append(NSPredicate(format: "NOT kMDItemPath BEGINSWITH %@", "/System"))
            predicates.append(NSPredicate(format: "NOT kMDItemPath BEGINSWITH %@", "/Library"))
        }

        return SpotlightQueryDescriptor(
            searchScopes: [NSMetadataQueryLocalComputerScope],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            sortDescriptors: [NSSortDescriptor(key: sortBy, ascending: false)],
            timeoutSeconds: config.queryTimeoutSeconds
        )
    }

    // MARK: - Result Parsing

    private func parseAppItems(from items: [NSMetadataItem], limit: Int) -> [FileSystemItem] {
        var results: [FileSystemItem] = []
        let homeDir = NSHomeDirectory()

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            if config.isPathExcluded(path, homeDir: homeDir) { continue }

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

            if results.count >= limit { break }
        }

        return results
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.spotlightDateFormatter.string(from: date)
    }
}
