import Testing
import Foundation
@testable import FileRing

// MARK: - SecurePathValidator Tests

@Suite("SecurePathValidator")
@MainActor
struct SecurePathValidatorTests {

    let validator = SecurePathValidator()

    // MARK: - isPathAuthorized

    @Test("exact match is authorized")
    func exactMatch() {
        #expect(validator.isPathAuthorized("/Users/bob/Documents", authorizedPaths: ["/Users/bob/Documents"]))
    }

    @Test("subdirectory is authorized")
    func subdirectoryAuthorized() {
        #expect(validator.isPathAuthorized("/Users/bob/Documents/report.pdf", authorizedPaths: ["/Users/bob/Documents"]))
    }

    @Test("deep subdirectory is authorized")
    func deepSubdirectory() {
        #expect(validator.isPathAuthorized("/Users/bob/Documents/2025/Q1/report.pdf", authorizedPaths: ["/Users/bob/Documents"]))
    }

    @Test("partial prefix does NOT authorize — critical security check")
    func partialPrefixDenied() {
        // /Users/bob/Doc should NOT grant access to /Users/bob/Documents
        #expect(!validator.isPathAuthorized("/Users/bob/Documents/file.txt", authorizedPaths: ["/Users/bob/Doc"]))
    }

    @Test("sibling directory is denied")
    func siblingDenied() {
        #expect(!validator.isPathAuthorized("/Users/alice/file.txt", authorizedPaths: ["/Users/bob"]))
    }

    @Test("empty authorized list denies all")
    func emptyAuthorizedList() {
        #expect(!validator.isPathAuthorized("/Users/bob/file.txt", authorizedPaths: []))
    }

    @Test("multiple authorized paths — first matches")
    func multipleAuthsFirstMatch() {
        #expect(validator.isPathAuthorized(
            "/Users/bob/Downloads/x.zip",
            authorizedPaths: ["/Users/bob/Downloads", "/Users/bob/Documents"]
        ))
    }

    @Test("multiple authorized paths — second matches")
    func multipleAuthsSecondMatch() {
        #expect(validator.isPathAuthorized(
            "/Users/bob/Documents/y.pdf",
            authorizedPaths: ["/Users/bob/Downloads", "/Users/bob/Documents"]
        ))
    }

    @Test("multiple authorized paths — none match")
    func multipleAuthsNoMatch() {
        #expect(!validator.isPathAuthorized(
            "/Users/alice/secret.txt",
            authorizedPaths: ["/Users/bob/Downloads", "/Users/bob/Documents"]
        ))
    }

    // MARK: - normalizePath

    @Test("normalizes double-slash — result contains no //")
    func normalizeDoubleSlash() {
        let result = validator.normalizePath("/private//tmp")
        #expect(result?.contains("//") == false)
        #expect(result != nil)
    }

    @Test("normalizes dot-dot sequences — result contains no ..")
    func normalizeDotDot() throws {
        // Use real paths we can control via TempDirectory
        let tmp = try TempDirectory()
        let sub = tmp.url.appendingPathComponent("a").appendingPathComponent("b")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        // Navigate out of sub via ../..
        let traversalPath = sub.path + "/../../.."
        let result = validator.normalizePath(traversalPath)
        #expect(result?.contains("..") == false)
    }

    @Test("normalizes embedded dot-dot — path does not contain ..")
    func normalizeEmbeddedDotDot() throws {
        let tmp = try TempDirectory()
        let sub = tmp.url.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let path = sub.path + "/../sub"
        let result = validator.normalizePath(path)
        #expect(result?.contains("..") == false)
        // Should resolve to sub itself
        let directResult = validator.normalizePath(sub.path)
        #expect(result == directResult)
    }

    @Test("normalizes single dot — result contains no /./")
    func normalizeSingleDot() {
        let result = validator.normalizePath("/private/./tmp")
        #expect(result?.contains("/./") == false)
        #expect(result != nil)
    }

    @Test("Unicode NFC normalization applied")
    func unicodeNFCNormalization() throws {
        // café composed (U+00E9) vs decomposed (e + combining accent U+0301)
        let decomposed = "caf\u{0065}\u{0301}"   // e + combining accent = NFD
        let composed = "caf\u{00E9}"              // é precomposed = NFC
        let basePath = "/Users/\(decomposed)"
        let result = validator.normalizePath(basePath)
        // After NFC normalization both forms should produce the same result
        #expect(result?.contains(composed) == true || result?.contains(decomposed) == true)
        // Both paths should normalize to the same value
        let resultComposed = validator.normalizePath("/Users/\(composed)")
        #expect(result == resultComposed)
    }

    // MARK: - isPathStringValid

    @Test("valid path is valid")
    func validPath() {
        #expect(validator.isPathStringValid("/Users/bob/file.txt"))
    }

    @Test("empty string is invalid")
    func emptyStringInvalid() {
        #expect(!validator.isPathStringValid(""))
    }

    @Test("whitespace-only is invalid")
    func whitespaceInvalid() {
        #expect(!validator.isPathStringValid("   "))
    }

    @Test("path with ../ is invalid")
    func pathWithDotDotSlash() {
        #expect(!validator.isPathStringValid("/Users/../etc/passwd"))
    }

    @Test("path with // is invalid")
    func pathWithDoubleSlash() {
        #expect(!validator.isPathStringValid("/Users//bob"))
    }

    @Test("path with /./ is invalid")
    func pathWithDotSegment() {
        #expect(!validator.isPathStringValid("/Users/./bob"))
    }

    // MARK: - pathExistsAndIsAccessible

    @Test("existing temp directory is accessible")
    func tempDirAccessible() throws {
        let tmp = try TempDirectory()
        #expect(validator.pathExistsAndIsAccessible(tmp.url.path))
    }

    @Test("nonexistent path is not accessible")
    func nonExistentNotAccessible() {
        #expect(!validator.pathExistsAndIsAccessible("/nonexistent/path/\(UUID().uuidString)"))
    }
}

// MARK: - PathTrie Tests

@Suite("PathTrie")
struct PathTrieTests {

    // MARK: - Basic insert + lookup

    @Test("exact path is authorized")
    func exactPathAuthorized() {
        let trie = PathTrie()
        trie.insert("/users/bob/documents")
        #expect(trie.isAuthorized("/users/bob/documents"))
    }

    @Test("child of authorized path is authorized")
    func childAuthorized() {
        let trie = PathTrie()
        trie.insert("/users/bob")
        #expect(trie.isAuthorized("/users/bob/documents/file.txt"))
    }

    @Test("ancestor does NOT inherit authorization from descendant")
    func ancestorNotAuthorized() {
        let trie = PathTrie()
        trie.insert("/users/bob/documents")
        #expect(!trie.isAuthorized("/users/bob"))
    }

    @Test("unrelated path is denied")
    func unrelatedPathDenied() {
        let trie = PathTrie()
        trie.insert("/users/bob")
        #expect(!trie.isAuthorized("/users/alice/file.txt"))
    }

    @Test("sibling directory is denied")
    func siblingDenied() {
        let trie = PathTrie()
        trie.insert("/users/bob/documents")
        #expect(!trie.isAuthorized("/users/bob/downloads/file.txt"))
    }

    // MARK: - Multiple inserts

    @Test("multiple paths - first matches")
    func multiplePathsFirstMatch() {
        let trie = PathTrie()
        trie.insert("/users/bob/documents")
        trie.insert("/users/bob/downloads")
        #expect(trie.isAuthorized("/users/bob/documents/report.pdf"))
    }

    @Test("multiple paths - second matches")
    func multiplePathsSecondMatch() {
        let trie = PathTrie()
        trie.insert("/users/bob/documents")
        trie.insert("/users/bob/downloads")
        #expect(trie.isAuthorized("/users/bob/downloads/archive.zip"))
    }

    // MARK: - count

    @Test("count reflects number of inserted paths")
    func countAfterInserts() {
        let trie = PathTrie()
        trie.insert("/a/b")
        trie.insert("/a/c")
        trie.insert("/x/y/z")
        #expect(trie.count() == 3)
    }

    @Test("duplicate insert does not inflate count")
    func duplicateInsert() {
        let trie = PathTrie()
        trie.insert("/a/b")
        trie.insert("/a/b")
        #expect(trie.count() == 1)
    }

    // MARK: - clear

    @Test("clear removes all paths")
    func clearRemovesAll() {
        let trie = PathTrie()
        trie.insert("/a/b")
        trie.insert("/c/d")
        trie.clear()
        #expect(trie.count() == 0)
        #expect(!trie.isAuthorized("/a/b"))
    }

    @Test("empty trie denies everything")
    func emptyTrieDeniesAll() {
        let trie = PathTrie()
        #expect(!trie.isAuthorized("/any/path"))
    }
}
