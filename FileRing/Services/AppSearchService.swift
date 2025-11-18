//
//  AppSearchService.swift
//  PopUp
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

    /// Merge files and apps sorted by time, guaranteeing minimum file count
    private func mergeByTime(
        files: [FileSystemItem],
        apps: [FileSystemItem],
        limit: Int,
        minFileCount: Int
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
        // If we have fewer files than minFileCount, relax the constraint and allow apps to fill
        let maxAppCount = actualFileCount >= minFileCount ? actualFileCount : limit

        // Then merge remaining items by time, respecting the app limit
        while results.count < limit && (fileIndex < files.count || (appIndex < apps.count && appIndex < maxAppCount)) {
            let fileTime = fileIndex < files.count ? parseDate(files[fileIndex].lastUsed) : nil
            let appTime = (appIndex < apps.count && appIndex < maxAppCount) ? parseDate(apps[appIndex].lastUsed) : nil

            if let fTime = fileTime, let aTime = appTime {
                // Both available: pick newer one
                if fTime > aTime {
                    results.append(files[fileIndex])
                    fileIndex += 1
                } else {
                    results.append(apps[appIndex])
                    appIndex += 1
                }
            } else if fileTime != nil {
                // Only file available
                results.append(files[fileIndex])
                fileIndex += 1
            } else if appTime != nil {
                // Only app available (within limit)
                results.append(apps[appIndex])
                appIndex += 1
            } else {
                break
            }
        }

        return results
    }

    /// Merge files and apps sorted by use count, guaranteeing minimum file count
    private func mergeByUseCount(
        files: [FileSystemItem],
        apps: [FileSystemItem],
        limit: Int,
        minFileCount: Int
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
        // If we have fewer files than minFileCount, relax the constraint and allow apps to fill
        let maxAppCount = actualFileCount >= minFileCount ? actualFileCount : limit

        // Then merge remaining items by use count (apps already have adjusted count), respecting the app limit
        while results.count < limit && (fileIndex < files.count || (appIndex < apps.count && appIndex < maxAppCount)) {
            let fileCount = fileIndex < files.count ? (files[fileIndex].useCount ?? 0) : -1
            let appCount = (appIndex < apps.count && appIndex < maxAppCount) ? (apps[appIndex].useCount ?? 0) : -1

            if fileCount >= 0 && appCount >= 0 {
                // Both available: pick higher count
                if fileCount >= appCount {
                    results.append(files[fileIndex])
                    fileIndex += 1
                } else {
                    results.append(apps[appIndex])
                    appIndex += 1
                }
            } else if fileCount >= 0 {
                // Only file available
                results.append(files[fileIndex])
                fileIndex += 1
            } else if appCount >= 0 {
                // Only app available (within limit)
                results.append(apps[appIndex])
                appIndex += 1
            } else {
                break
            }
        }

        return results
    }

    /// Parse date string to Date for comparison
    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: dateString)
    }
}
