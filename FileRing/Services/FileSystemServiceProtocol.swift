import Foundation

/// Abstracts file system queries so DoubleRingViewModel can be unit-tested
/// without depending on live Spotlight queries.
@MainActor
protocol FileSystemServiceProtocol: AnyObject {
    func fetchFiles(for category: CategoryType, limit: Int) async throws -> [FileSystemItem]
    func fetchFolders(for category: CategoryType, limit: Int) async throws -> [FileSystemItem]
    func open(path: String) async throws
    func copyToClipboard(path: String, mode: ClipboardMode) async throws
}
