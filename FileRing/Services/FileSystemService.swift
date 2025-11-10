//
//  FileSystemService.swift
//  PopUp
//
//  Spotlight-based file system service (no caching - fresh data on every panel open)
//

import Foundation

@MainActor
class FileSystemService {
    private let spotlight: SpotlightManager

    init() {
        let config = SpotlightConfig.load()
        self.spotlight = SpotlightManager(config: config)
    }

    // MARK: - File Operations
    func fetchRecentlyOpenedFiles(limit: Int = 10) async throws -> [FileItem] {
        return try await spotlight.queryRecentlyOpenedFiles(limit: limit)
    }

    func fetchRecentlySavedFiles(limit: Int = 10) async throws -> [FileItem] {
        return try await spotlight.queryRecentlySavedFiles(limit: limit)
    }

    func fetchFrequentlyOpenedFiles(limit: Int = 10) async throws -> [FileItem] {
        return try await spotlight.queryFrequentlyOpenedFiles(limit: limit)
    }

    // MARK: - Folder Operations
    func fetchRecentlyOpenedFolders(limit: Int = 10) async throws -> [FolderItem] {
        return try await spotlight.queryRecentlyOpenedFolders(limit: limit)
    }

    func fetchRecentlyModifiedFolders(limit: Int = 10) async throws -> [FolderItem] {
        return try await spotlight.queryRecentlyModifiedFolders(limit: limit)
    }

    func fetchFrequentlyOpenedFolders(limit: Int = 10) async throws -> [FolderItem] {
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
