import Foundation
@testable import FileRing

/// Mock implementation of FileSystemServiceProtocol for unit testing DoubleRingViewModel
/// without any live Spotlight or file system queries.
@MainActor
final class MockFileSystemService: FileSystemServiceProtocol {

    // MARK: - Configurable Responses

    var filesByCategory: [CategoryType: [FileSystemItem]] = [:]
    var foldersByCategory: [CategoryType: [FileSystemItem]] = [:]
    var fetchError: Error?

    // MARK: - Call Recording

    var openedPaths: [String] = []
    var copiedPaths: [(path: String, mode: ClipboardMode)] = []
    var fetchFileCallCount = 0
    var fetchFolderCallCount = 0

    // MARK: - FileSystemServiceProtocol

    func fetchFiles(for category: CategoryType, limit: Int) async throws -> [FileSystemItem] {
        fetchFileCallCount += 1
        if let err = fetchError { throw err }
        return Array((filesByCategory[category] ?? []).prefix(limit))
    }

    func fetchFolders(for category: CategoryType, limit: Int) async throws -> [FileSystemItem] {
        fetchFolderCallCount += 1
        if let err = fetchError { throw err }
        return Array((foldersByCategory[category] ?? []).prefix(limit))
    }

    func open(path: String) async throws {
        openedPaths.append(path)
    }

    func copyToClipboard(path: String, mode: ClipboardMode) async throws {
        copiedPaths.append((path: path, mode: mode))
    }

    // MARK: - Convenience Factories

    /// Populate all file categories with the given items.
    func setFiles(_ items: [FileSystemItem]) {
        for category in CategoryType.allCases {
            filesByCategory[category] = items
        }
    }

    /// Populate all folder categories with the given items.
    func setFolders(_ items: [FileSystemItem]) {
        for category in CategoryType.allCases {
            foldersByCategory[category] = items
        }
    }
}
