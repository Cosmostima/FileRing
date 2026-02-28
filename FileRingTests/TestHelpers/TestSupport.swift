import Foundation
@testable import FileRing

// MARK: - IsolatedUserDefaults

/// Creates a unique UserDefaults suite per test instance.
/// Automatically removes the persistent domain on deinit, preventing cross-test pollution.
final class IsolatedUserDefaults {
    let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "FileRingTest.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - TempDirectory

/// Creates a unique temporary directory for file-system tests.
/// Automatically removed on deinit.
final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - FileSystemItem Factories

extension FileSystemItem {
    static func makeFile(
        path: String = "/tmp/test/file.txt",
        name: String = "file.txt",
        lastUsed: String? = nil,
        lastModified: String? = nil,
        useCount: Int? = nil
    ) -> FileSystemItem {
        FileSystemItem(
            path: path, name: name,
            lastUsed: lastUsed, lastModified: lastModified,
            contentType: "public.plain-text",
            itemType: .file,
            bundleIdentifier: nil, version: nil,
            useCount: useCount
        )
    }

    static func makeApp(
        path: String = "/Applications/TestApp.app",
        name: String = "TestApp",
        lastUsed: String? = nil,
        useCount: Int? = nil
    ) -> FileSystemItem {
        FileSystemItem(
            path: path, name: name,
            lastUsed: lastUsed, lastModified: nil,
            contentType: "com.apple.application-bundle",
            itemType: .application,
            bundleIdentifier: "com.test.app", version: "1.0",
            useCount: useCount
        )
    }
}
