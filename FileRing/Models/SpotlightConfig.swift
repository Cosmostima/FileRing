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
        "Library",  // Exclude entire Library folder
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

    // MARK: - File Management

    private static let configDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let popUpDir = appSupport.appendingPathComponent("FileRing", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: popUpDir, withIntermediateDirectories: true)

        return popUpDir
    }()

    private static let configFile: URL = {
        return configDirectory.appendingPathComponent("spotlight-config.json")
    }()

    // MARK: - Loading & Saving

    /// Load configuration from disk, or return default if not found
    static func load() -> SpotlightConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(SpotlightConfig.self, from: data) else {
            return SpotlightConfig()
        }
        return config
    }

    /// Save configuration to disk
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.configFile)
    }

    // MARK: - Filtering Helpers

    /// Check if a file path should be excluded based on excluded folders
    func isPathExcluded(_ path: String) -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // IMPORTANT: Allow iCloud Drive files
        if path.contains("/Library/Mobile Documents/com~apple~CloudDocs/") {
            return false
        }

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
            // Check if path starts with excluded folder
            if relativePath.hasPrefix(excluded + "/") || relativePath == excluded {
                return true
            }
            // Check if excluded folder is in the middle of the path
            if relativePath.contains("/" + excluded + "/") {
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
