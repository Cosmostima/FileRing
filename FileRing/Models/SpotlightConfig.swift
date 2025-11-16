//
//  SpotlightConfig.swift
//  PopUp
//
//  Configuration for Spotlight queries with filtering support
//

import Foundation

struct SpotlightConfig: Codable {
    // MARK: - Filtering

    /// Folders to exclude from search results (relative to home directory)
    var excludedFolders: [String] = [
        ".Trash",
        "node_modules",
        ".git",
        ".vscode",
        ".idea",
        "__pycache__",
        ".npm",
        ".gradle",
        ".cargo",
        ".rustup"
    ]

    /// File extensions to exclude from search results
    var excludedExtensions: [String] = [
        ".tmp",
        ".cache",
        ".log",
        ".DS_Store",
        ".localized",
        ".pyc",
        ".swp",
        ".swo"
    ]

    // MARK: - Time Ranges

    /// Days to look back for recently opened/saved files and folders
    var recentDays: Int = 7

    /// Days to look back for frequently opened files and folders (shorter for "frequent" = more meaningful)
    var frequentDays: Int = 3

    // MARK: - Search Scope

    /// If true, only search within user's home directory
    var searchOnlyUserHome: Bool = true

    // MARK: - Performance

    /// Cache duration in seconds
    var cacheSeconds: Int = 60

    /// Query timeout in seconds
    var queryTimeoutSeconds: Int = 10

    // MARK: - UserDefaults Keys

    private static let excludedFoldersKey = "FileRingExcludedFolders"
    private static let excludedExtensionsKey = "FileRingExcludedExtensions"
    private static let recentDaysKey = "FileRingRecentDays"
    private static let frequentDaysKey = "FileRingFrequentDays"
    private static let searchOnlyUserHomeKey = "FileRingSearchOnlyUserHome"
    private static let cacheSecondsKey = "FileRingCacheSeconds"
    private static let queryTimeoutSecondsKey = "FileRingQueryTimeoutSeconds"

    // MARK: - Loading & Saving

    /// Load configuration from UserDefaults, or return default if not found
    static func load() -> SpotlightConfig {
        let defaults = UserDefaults.standard

        var config = SpotlightConfig()

        // Load arrays if they exist
        if let folders = defaults.array(forKey: excludedFoldersKey) as? [String] {
            config.excludedFolders = folders
        }

        if let extensions = defaults.array(forKey: excludedExtensionsKey) as? [String] {
            config.excludedExtensions = extensions
        }

        // Load integers if they exist (check if > 0 to distinguish from unset)
        let recentDays = defaults.integer(forKey: recentDaysKey)
        if recentDays > 0 {
            config.recentDays = recentDays
        }

        let frequentDays = defaults.integer(forKey: frequentDaysKey)
        if frequentDays > 0 {
            config.frequentDays = frequentDays
        }

        let cacheSeconds = defaults.integer(forKey: cacheSecondsKey)
        if cacheSeconds > 0 {
            config.cacheSeconds = cacheSeconds
        }

        let queryTimeout = defaults.integer(forKey: queryTimeoutSecondsKey)
        if queryTimeout > 0 {
            config.queryTimeoutSeconds = queryTimeout
        }

        // Load boolean if it exists
        if defaults.object(forKey: searchOnlyUserHomeKey) != nil {
            config.searchOnlyUserHome = defaults.bool(forKey: searchOnlyUserHomeKey)
        }

        return config
    }

    /// Save configuration to UserDefaults
    func save() throws {
        let defaults = UserDefaults.standard

        defaults.set(excludedFolders, forKey: Self.excludedFoldersKey)
        defaults.set(excludedExtensions, forKey: Self.excludedExtensionsKey)
        defaults.set(recentDays, forKey: Self.recentDaysKey)
        defaults.set(frequentDays, forKey: Self.frequentDaysKey)
        defaults.set(searchOnlyUserHome, forKey: Self.searchOnlyUserHomeKey)
        defaults.set(cacheSeconds, forKey: Self.cacheSecondsKey)
        defaults.set(queryTimeoutSeconds, forKey: Self.queryTimeoutSecondsKey)
    }

    /// Reset configuration to defaults
    static func reset() {
        let defaults = UserDefaults.standard

        defaults.removeObject(forKey: excludedFoldersKey)
        defaults.removeObject(forKey: excludedExtensionsKey)
        defaults.removeObject(forKey: recentDaysKey)
        defaults.removeObject(forKey: frequentDaysKey)
        defaults.removeObject(forKey: searchOnlyUserHomeKey)
        defaults.removeObject(forKey: cacheSecondsKey)
        defaults.removeObject(forKey: queryTimeoutSecondsKey)
    }

    // MARK: - Filtering Helpers

    /// Check if a file path should be excluded based on excluded folders
    func isPathExcluded(_ path: String) -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Get relative path
        var relativePath = path
        if path.hasPrefix(homeDir + "/") {
            relativePath = String(path.dropFirst((homeDir + "/").count))
        } else if path.hasPrefix(homeDir) {
            relativePath = String(path.dropFirst(homeDir.count))
            if relativePath.hasPrefix("/") {
                relativePath = String(relativePath.dropFirst())
            }
        }

        // Check against excluded folders
        for excluded in excludedFolders {
            // Check if path equals excluded folder
            if relativePath == excluded {
                return true
            }

            // Check if path starts with excluded folder (e.g., "__pycache__/something")
            if relativePath.hasPrefix(excluded + "/") {
                return true
            }

            // Check if excluded folder is anywhere in the path (e.g., "Desktop/__pycache__" or "Desktop/__pycache__/file")
            if relativePath.contains("/" + excluded + "/") || relativePath.hasSuffix("/" + excluded) {
                return true
            }
        }

        return false
    }

    /// Check if a file extension should be excluded
    func isExtensionExcluded(_ fileName: String) -> Bool {
        for ext in excludedExtensions {
            if fileName.hasSuffix(ext) {
                return true
            }
        }
        return false
    }
}
