//
//  SpotlightConfig.swift
//  FileRing
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

    // MARK: - Application Search

    /// If true, include applications in search results
    var enableAppSearch: Bool = false

    /// If true, exclude system applications from search results
    var excludeSystemApps: Bool = false

    /// Multiplier for application use count when mixing with files (default 0.5)
    var appFrequencyMultiplier: Double = 0.5

    // MARK: - Performance

    /// Cache duration in seconds
    var cacheSeconds: Int = 60

    /// Query timeout in seconds
    var queryTimeoutSeconds: Int = 10

    // MARK: - Storage Key

    private static let storageKey = "FileRingSpotlightConfig"

    // MARK: - Loading & Saving

    /// Load configuration from UserDefaults, or return default if not found
    static func load() -> SpotlightConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(SpotlightConfig.self, from: data) else {
            return SpotlightConfig()
        }
        return config
    }

    /// Save configuration to UserDefaults
    func save() throws {
        let data = try JSONEncoder().encode(self)
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Reset configuration to defaults
    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Filtering Helpers

    /// Check if a file path should be excluded based on excluded folders
    func isPathExcluded(_ path: String) -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return isPathExcluded(path, homeDir: homeDir)
    }

    /// Check if a file path should be excluded (nonisolated version with explicit homeDir)
    nonisolated func isPathExcluded(_ path: String, homeDir: String) -> Bool {

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
