//
//  AppSearchService.swift
//  FileRing
//
//  Service for merging application and file search results
//

import Foundation

@MainActor
class AppSearchService {
    private let appSpotlightManager: AppSpotlightManager
    private let spotlightManager: SpotlightManager
    private let config: SpotlightConfig

    init(config: SpotlightConfig, spotlightManager: SpotlightManager) {
        self.config = config
        self.spotlightManager = spotlightManager
        self.appSpotlightManager = AppSpotlightManager(config: config)
    }

    // MARK: - Mixed Search Methods

    /// Fetch recently used items (files + apps) sorted by time
    /// Guarantees at least 50% files in the result
    func fetchRecentItemsWithApps(totalLimit: Int) async throws -> [FileSystemItem] {
        // Calculate limits: guarantee at least 50% files
        let minFileCount = totalLimit / 2
        let appLimit = totalLimit - minFileCount

        // Query files and apps IN PARALLEL to avoid delay
        async let fileItems = spotlightManager.queryRecentlyOpenedFiles(limit: totalLimit)
        async let appItems = appSpotlightManager.queryRecentlyUsedApps(limit: appLimit * 2)

        let (files, apps) = try await (fileItems, appItems)

        // Merge and sort by time - pass all apps, let merge function decide how many to use
        let mergedItems = mergeByTime(files: files, apps: Array(apps), limit: totalLimit, minFileCount: minFileCount)

        return mergedItems
    }

    /// Fetch frequently used items (files + apps) sorted by use count
    /// Apps' use count is multiplied by config.appFrequencyMultiplier (default 0.5)
    /// Guarantees at least 50% files in the result
    func fetchFrequentItemsWithApps(totalLimit: Int) async throws -> [FileSystemItem] {
        // Calculate limits: guarantee at least 50% files
        let minFileCount = totalLimit / 2
        let appLimit = totalLimit - minFileCount

        // Query files and apps IN PARALLEL
        async let fileItems = spotlightManager.queryFrequentlyOpenedFiles(limit: totalLimit)
        async let appItems = appSpotlightManager.queryFrequentlyUsedApps(limit: appLimit * 2)

        let (files, apps) = try await (fileItems, appItems)

        // Adjust app use counts with multiplier - adjust all apps, let merge function decide how many to use
        let adjustedApps = apps.map { app -> FileSystemItem in
            let adjustedCount = Int(Double(app.useCount ?? 0) * config.appFrequencyMultiplier)
            return FileSystemItem(
                path: app.path,
                name: app.name,
                lastUsed: app.lastUsed,
                lastModified: app.lastModified,
                contentType: app.contentType,
                itemType: app.itemType,
                bundleIdentifier: app.bundleIdentifier,
                version: app.version,
                useCount: adjustedCount
            )
        }

        // Merge and sort by use count
        let mergedItems = mergeByUseCount(files: files, apps: adjustedApps, limit: totalLimit, minFileCount: minFileCount)

        return mergedItems
    }

    // MARK: - Private Helpers

    /// Generic merge of files and apps, guaranteeing minimum file count.
    /// Items are compared using the provided `value` closures and `isHigherPriority` comparator.
    private func mergeItems<V>(
        files: [FileSystemItem],
        apps: [FileSystemItem],
        limit: Int,
        minFileCount: Int,
        fileValue: (FileSystemItem) -> V?,
        appValue: (FileSystemItem) -> V?,
        isHigherPriority: (V, V) -> Bool
    ) -> [FileSystemItem] {
        var results: [FileSystemItem] = []
        var fileIndex = 0
        var appIndex = 0

        // First, add all available files up to minFileCount
        while results.count < minFileCount && fileIndex < files.count {
            results.append(files[fileIndex])
            fileIndex += 1
        }

        // Calculate how many apps we can actually add while maintaining 50% file ratio
        let actualFileCount = fileIndex
        let maxAppCount = actualFileCount >= minFileCount ? actualFileCount : limit

        // Then merge remaining items by priority, respecting the app limit
        while results.count < limit && (fileIndex < files.count || (appIndex < apps.count && appIndex < maxAppCount)) {
            let fVal = fileIndex < files.count ? fileValue(files[fileIndex]) : nil
            let aVal = (appIndex < apps.count && appIndex < maxAppCount) ? appValue(apps[appIndex]) : nil

            if let f = fVal, let a = aVal {
                if isHigherPriority(f, a) {
                    results.append(files[fileIndex])
                    fileIndex += 1
                } else {
                    results.append(apps[appIndex])
                    appIndex += 1
                }
            } else if fVal != nil {
                results.append(files[fileIndex])
                fileIndex += 1
            } else if aVal != nil {
                results.append(apps[appIndex])
                appIndex += 1
            } else {
                break
            }
        }

        return results
    }

    /// Merge files and apps sorted by time, guaranteeing minimum file count
    private func mergeByTime(
        files: [FileSystemItem],
        apps: [FileSystemItem],
        limit: Int,
        minFileCount: Int
    ) -> [FileSystemItem] {
        mergeItems(
            files: files, apps: apps, limit: limit, minFileCount: minFileCount,
            fileValue: { self.parseDate($0.lastUsed) },
            appValue: { self.parseDate($0.lastUsed) },
            isHigherPriority: { $0 > $1 }
        )
    }

    /// Merge files and apps sorted by use count, guaranteeing minimum file count
    private func mergeByUseCount(
        files: [FileSystemItem],
        apps: [FileSystemItem],
        limit: Int,
        minFileCount: Int
    ) -> [FileSystemItem] {
        mergeItems(
            files: files, apps: apps, limit: limit, minFileCount: minFileCount,
            fileValue: { $0.useCount ?? 0 },
            appValue: { $0.useCount ?? 0 },
            isHigherPriority: { $0 >= $1 }
        )
    }

    /// Parse date string to Date for comparison
    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        return DateFormatter.spotlightDateFormatter.date(from: dateString)
    }
}
