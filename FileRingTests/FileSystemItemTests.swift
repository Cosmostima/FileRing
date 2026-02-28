import Testing
import Foundation
@testable import FileRing

@Suite("FileSystemItem")
struct FileSystemItemTests {

    // MARK: - displayName

    @Test("normal name is returned as-is")
    func normalNameReturnedAsIs() {
        let item = FileSystemItem.makeFile(path: "/tmp/README.md", name: "README.md")
        #expect(item.displayName == "README.md")
    }

    @Test("empty name falls back to path's lastPathComponent")
    func emptyNameFallsBack() {
        let item = FileSystemItem.makeFile(path: "/Users/bob/report.pdf", name: "")
        #expect(item.displayName == "report.pdf")
    }

    @Test("whitespace-only name falls back to path's lastPathComponent")
    func whitespaceNameFallsBack() {
        let item = FileSystemItem.makeFile(path: "/Users/bob/report.pdf", name: "   ")
        #expect(item.displayName == "report.pdf")
    }

    @Test("timestamp-like name falls back to path's lastPathComponent")
    func timestampNameFallsBack() {
        // Names that look like ISO 8601 dates (from Spotlight metadata) should not be displayed
        let item = FileSystemItem.makeFile(path: "/Users/bob/notes.txt", name: "2025-01-15 10:30:00")
        #expect(item.displayName == "notes.txt")
    }

    @Test("date-only name falls back")
    func dateOnlyNameFallsBack() {
        let item = FileSystemItem.makeFile(path: "/Users/bob/notes.txt", name: "2025-01-01")
        #expect(item.displayName == "notes.txt")
    }

    @Test("non-timestamp text name is kept")
    func nonTimestampNameKept() {
        // e.g. "2025 Annual Report" starts with digits but is not a timestamp
        // The regex requires yyyy-mm-dd prefix, "2025 Annual" doesn't match
        let item = FileSystemItem.makeFile(path: "/tmp/x.txt", name: "2025 Annual Report")
        #expect(item.displayName == "2025 Annual Report")
    }

    @Test("path with no file name returns path itself")
    func pathWithNoFileName() {
        // When lastPathComponent is empty or just /
        let item = FileSystemItem.makeFile(path: "/", name: "")
        // URL("/").lastPathComponent == "" so fallback is "/" itself
        #expect(!item.displayName.isEmpty)
    }

    // MARK: - timestamp priority

    @Test("timestamp prefers lastModified over lastUsed")
    func timestampPrefersLastModified() {
        let item = FileSystemItem(
            path: "/tmp/f.txt", name: "f.txt",
            lastUsed: "2024-01-01 00:00:00 +0000",
            lastModified: "2025-06-15 12:00:00 +0000",
            contentType: "public.plain-text"
        )
        #expect(item.timestamp == "2025-06-15 12:00:00 +0000")
    }

    @Test("timestamp falls back to lastUsed when lastModified is nil")
    func timestampFallsBackToLastUsed() {
        let item = FileSystemItem(
            path: "/tmp/f.txt", name: "f.txt",
            lastUsed: "2024-12-01 08:00:00 +0000",
            lastModified: nil,
            contentType: "public.plain-text"
        )
        #expect(item.timestamp == "2024-12-01 08:00:00 +0000")
    }

    @Test("timestamp is nil when both dates are nil")
    func timestampNilWhenBothNil() {
        let item = FileSystemItem.makeFile(path: "/tmp/f.txt", name: "f.txt")
        #expect(item.timestamp == nil)
    }

    // MARK: - id

    @Test("id equals path")
    func idEqualsPath() {
        let path = "/Users/bob/Documents/test.txt"
        let item = FileSystemItem.makeFile(path: path, name: "test.txt")
        #expect(item.id == path)
    }

    // MARK: - convenience initializer

    @Test("convenience init infers .folder itemType for public.folder")
    func convenienceInitFolderType() {
        let item = FileSystemItem(
            path: "/Users/bob/docs", name: "docs",
            lastUsed: nil, lastModified: nil,
            contentType: "public.folder"
        )
        #expect(item.itemType == .folder)
    }

    @Test("convenience init infers .file itemType for plain text")
    func convenienceInitFileType() {
        let item = FileSystemItem(
            path: "/tmp/a.txt", name: "a.txt",
            lastUsed: nil, lastModified: nil,
            contentType: "public.plain-text"
        )
        #expect(item.itemType == .file)
    }

    @Test("full initializer preserves all fields")
    func fullInitializerPreservesFields() {
        let item = FileSystemItem(
            path: "/Applications/Xcode.app",
            name: "Xcode",
            lastUsed: "2025-01-01 00:00:00 +0000",
            lastModified: nil,
            contentType: "com.apple.application-bundle",
            itemType: .application,
            bundleIdentifier: "com.apple.dt.Xcode",
            version: "16.0",
            useCount: 42
        )
        #expect(item.itemType == .application)
        #expect(item.bundleIdentifier == "com.apple.dt.Xcode")
        #expect(item.version == "16.0")
        #expect(item.useCount == 42)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = FileSystemItem(
            path: "/Users/bob/file.txt",
            name: "file.txt",
            lastUsed: "2025-03-15 10:00:00 +0000",
            lastModified: "2025-03-16 11:00:00 +0000",
            contentType: "public.plain-text",
            itemType: .file,
            bundleIdentifier: nil,
            version: nil,
            useCount: 7
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileSystemItem.self, from: data)

        #expect(decoded.path == original.path)
        #expect(decoded.name == original.name)
        #expect(decoded.lastUsed == original.lastUsed)
        #expect(decoded.lastModified == original.lastModified)
        #expect(decoded.contentType == original.contentType)
        #expect(decoded.itemType == original.itemType)
        #expect(decoded.useCount == original.useCount)
    }

    @Test("Codable with nil optional fields round-trips correctly")
    func codableNilFields() throws {
        let original = FileSystemItem.makeFile(path: "/tmp/a.txt", name: "a.txt")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileSystemItem.self, from: data)
        #expect(decoded.lastUsed == nil)
        #expect(decoded.lastModified == nil)
        #expect(decoded.bundleIdentifier == nil)
    }

    // MARK: - ItemType

    @Test("ItemType rawValues are stable")
    func itemTypeRawValues() {
        #expect(ItemType.file.rawValue == "file")
        #expect(ItemType.folder.rawValue == "folder")
        #expect(ItemType.application.rawValue == "application")
    }
}
