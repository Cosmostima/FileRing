//
//  FileSystemService.swift
//  PopUp
//
//  Spotlight-based file system service (no caching - fresh data on every panel open)
//

import Foundation
import os.log

@MainActor
class FileSystemService {
    private var spotlight: SpotlightManager
    private var appSearchService: AppSearchService
    private var config: SpotlightConfig

    init() {
        let config = SpotlightConfig.load()
        self.config = config
        self.spotlight = SpotlightManager(config: config)
        self.appSearchService = AppSearchService(config: config, spotlightManager: self.spotlight)

        // Listen for config changes
        NotificationCenter.default.addObserver(
            forName: .spotlightConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadConfig()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func reloadConfig() {
        let config = SpotlightConfig.load()
        self.config = config
        self.spotlight = SpotlightManager(config: config)
        self.appSearchService = AppSearchService(config: config, spotlightManager: self.spotlight)
    }

    // MARK: - File Operations
    func fetchRecentlyOpenedFiles(limit: Int = 10) async throws -> [FileItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchRecentFiles", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchRecentFiles", signpostID: signpostID) }

        // If app search is disabled, return files only (zero overhead)
        guard config.enableAppSearch else {
            return try await spotlight.queryRecentlyOpenedFiles(limit: limit)
        }

        // Mix apps and files, guaranteeing at least 50% files
        return try await appSearchService.fetchRecentItemsWithApps(totalLimit: limit)
    }

    func fetchRecentlySavedFiles(limit: Int = 10) async throws -> [FileItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchRecentSavedFiles", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchRecentSavedFiles", signpostID: signpostID) }

        // Recently saved only applies to files, not apps
        return try await spotlight.queryRecentlySavedFiles(limit: limit)
    }

    func fetchFrequentlyOpenedFiles(limit: Int = 10) async throws -> [FileItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchFrequentFiles", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchFrequentFiles", signpostID: signpostID) }

        // If app search is disabled, return files only (zero overhead)
        guard config.enableAppSearch else {
            return try await spotlight.queryFrequentlyOpenedFiles(limit: limit)
        }

        // Mix apps and files with adjusted app frequency (0.5x), guaranteeing at least 50% files
        return try await appSearchService.fetchFrequentItemsWithApps(totalLimit: limit)
    }

    // MARK: - Folder Operations
    func fetchRecentlyOpenedFolders(limit: Int = 10) async throws -> [FolderItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchRecentFolders", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchRecentFolders", signpostID: signpostID) }

        return try await spotlight.queryRecentlyOpenedFolders(limit: limit)
    }

    func fetchRecentlyModifiedFolders(limit: Int = 10) async throws -> [FolderItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchRecentModifiedFolders", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchRecentModifiedFolders", signpostID: signpostID) }

        return try await spotlight.queryRecentlyModifiedFolders(limit: limit)
    }

    func fetchFrequentlyOpenedFolders(limit: Int = 10) async throws -> [FolderItem] {
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "FetchFrequentFolders", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "FetchFrequentFolders", signpostID: signpostID) }

        return try await spotlight.queryFrequentlyOpenedFolders(limit: limit)
    }

    // MARK: - Open File/Folder
    func open(path: String) async throws {
        try spotlight.openFile(at: path)
    }

    func copyToClipboard(path: String, mode: ClipboardMode) async throws {
        try spotlight.copyToClipboard(path: path, mode: mode)
    }

    // MARK: - Helper Methods
    func fetchFiles(for category: CategoryType, limit: Int = 10) async throws -> [FileItem] {
        switch category {
        case .recentlyOpened:
            return try await fetchRecentlyOpenedFiles(limit: limit)
        case .recentlySaved:
            return try await fetchRecentlySavedFiles(limit: limit)
        case .frequentlyOpened:
            return try await fetchFrequentlyOpenedFiles(limit: limit)
        }
    }

    func fetchFolders(for category: CategoryType, limit: Int = 10) async throws -> [FolderItem] {
        switch category {
        case .recentlyOpened:
            return try await fetchRecentlyOpenedFolders(limit: limit)
        case .recentlySaved:
            return try await fetchRecentlyModifiedFolders(limit: limit)
        case .frequentlyOpened:
            return try await fetchFrequentlyOpenedFolders(limit: limit)
        }
    }
}

// MARK: - File System Error
enum FileSystemError: LocalizedError {
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}
