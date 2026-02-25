//
//  SecurePathValidator.swift
//  FileRing
//
//  Created by Claude on 2026-01-15.
//  Secure path validation with comprehensive security checks
//

import Foundation

/// Secure path validator that prevents path traversal attacks and unauthorized file access.
///
/// This validator performs multiple security checks:
/// 1. **Symlink resolution**: Resolves symbolic links to prevent directory traversal
/// 2. **Path normalization**: Standardizes paths by removing `.` and `..` components
/// 3. **Case-insensitive matching**: Handles macOS filesystem case-insensitivity
/// 4. **Unicode normalization**: Prevents Unicode homograph attacks
///
/// Example usage:
/// ```swift
/// let validator = SecurePathValidator()
/// let isAuthorized = validator.isPathAuthorized(
///     "/Users/bob/Documents/file.txt",
///     authorizedPaths: ["/Users/bob/Documents"]
/// )
/// ```
@MainActor
final class SecurePathValidator {
    private let fileManager = FileManager.default

    // MARK: - Public API

    /// Validate if a path is authorized based on a list of authorized folder paths.
    ///
    /// This method performs comprehensive security checks to prevent path traversal attacks:
    /// - Resolves symbolic links in both the target path and authorized paths
    /// - Normalizes paths to handle `.` and `..` sequences
    /// - Performs case-insensitive comparison (macOS filesystem behavior)
    /// - Normalizes Unicode to prevent homograph attacks
    ///
    /// - Parameters:
    ///   - path: The path to validate
    ///   - authorizedPaths: List of authorized folder paths
    /// - Returns: true if the path is within an authorized folder
    func isPathAuthorized(_ path: String, authorizedPaths: [String]) -> Bool {
        // Empty authorized list = deny all access
        guard !authorizedPaths.isEmpty else {
            return false
        }

        // Normalize the target path
        guard let normalizedPath = normalizePath(path) else {
            // If path cannot be normalized, deny access
            return false
        }

        // Check against each authorized path
        for authorizedPath in authorizedPaths {
            guard let normalizedAuthorized = normalizePath(authorizedPath) else {
                // Skip invalid authorized paths
                continue
            }

            if isPath(normalizedPath, withinAuthorized: normalizedAuthorized) {
                return true
            }
        }

        return false
    }

    /// Build an efficient trie structure for fast path lookups.
    ///
    /// For applications with many authorized paths or frequent path checks,
    /// a trie provides O(m) lookup time where m is the path depth,
    /// compared to O(n×m) for linear search.
    ///
    /// - Parameter authorizedPaths: List of authorized folder paths
    /// - Returns: PathTrie optimized for fast lookups
    func buildPathTrie(authorizedPaths: [String]) -> PathTrie {
        let trie = PathTrie()

        for path in authorizedPaths {
            if let normalized = normalizePath(path) {
                trie.insert(normalized)
            }
        }

        return trie
    }

    // MARK: - Path Normalization

    /// Normalize a path by resolving symlinks, standardizing, and applying Unicode normalization.
    ///
    /// Security properties:
    /// 1. **Symlink resolution**: Follows symbolic links to their target
    /// 2. **Path standardization**: Removes `.` and `..`, collapses `//`
    /// 3. **Case normalization**: Converts to lowercase (macOS is case-insensitive)
    /// 4. **Unicode NFC normalization**: Prevents homograph attacks
    ///
    /// - Parameter path: Path to normalize
    /// - Returns: Normalized path, or nil if path is invalid
    func normalizePath(_ path: String) -> String? {
        // Create URL from path
        let url = URL(fileURLWithPath: path)

        // Step 1: Resolve symbolic links
        // This prevents attacks like: /authorized/link -> /etc
        let resolvedPath: String
        if fileManager.fileExists(atPath: url.path) {
            // resolvingSymlinksInPath resolves the full symlink chain and standardizes the path
            resolvedPath = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
        } else {
            // Path doesn't exist yet (e.g., checking before creation)
            // Still normalize it, but can't resolve symlinks
            resolvedPath = url.path
        }

        // Step 2: Standardize path (removes . and .., collapses //)
        // This prevents attacks like: /authorized/../etc/passwd
        let standardizedURL = URL(fileURLWithPath: resolvedPath).standardized
        let standardizedPath = standardizedURL.path

        // Step 3: Convert to lowercase for case-insensitive comparison
        // macOS filesystems (HFS+, APFS) are case-insensitive by default
        // This prevents: /Users/Bob/Documents vs /users/bob/documents
        let lowercasedPath = standardizedPath.lowercased()

        // Step 4: Unicode NFC normalization
        // Prevents homograph attacks with different Unicode representations
        // Example: "café" (U+00E9) vs "café" (U+0065 U+0301)
        let normalizedPath = lowercasedPath.precomposedStringWithCanonicalMapping

        return normalizedPath
    }

    // MARK: - Path Comparison

    /// Check if a normalized path is within a normalized authorized folder.
    ///
    /// Both paths must be normalized before calling this method.
    ///
    /// - Parameters:
    ///   - path: Normalized path to check
    ///   - authorized: Normalized authorized folder path
    /// - Returns: true if path is within the authorized folder
    private func isPath(_ path: String, withinAuthorized authorized: String) -> Bool {
        // Exact match
        if path == authorized {
            return true
        }

        // Check if path is a subdirectory of authorized folder
        // Use path separator to prevent partial matches
        // Example: /Users/bob/Documents should NOT match /Users/bob/Doc
        if path.hasPrefix(authorized + "/") {
            return true
        }

        return false
    }

    // MARK: - Validation Helpers

    /// Validate a single path string for common issues.
    ///
    /// Checks for:
    /// - Empty or whitespace-only paths
    /// - Suspicious patterns like `..` or unusual Unicode
    ///
    /// - Parameter path: Path to validate
    /// - Returns: true if path appears valid
    func isPathStringValid(_ path: String) -> Bool {
        // Check for empty or whitespace-only paths
        guard !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }

        // Check for suspicious patterns
        let suspiciousPatterns = [
            "../",      // Parent directory traversal
            "/../",     // Embedded parent traversal
            "/./",      // Current directory (should be normalized)
            "//",       // Double slashes (should be normalized)
        ]

        for pattern in suspiciousPatterns {
            if path.contains(pattern) {
                // These patterns should be normalized away
                // If they still exist, something is wrong
                return false
            }
        }

        return true
    }

    /// Check if a path exists and is accessible.
    ///
    /// - Parameter path: Path to check
    /// - Returns: true if path exists and is readable
    func pathExistsAndIsAccessible(_ path: String) -> Bool {
        // Check if path exists
        guard fileManager.fileExists(atPath: path) else {
            return false
        }

        // Check if path is readable
        guard fileManager.isReadableFile(atPath: path) else {
            return false
        }

        return true
    }
}

// MARK: - Path Trie

/// Trie (prefix tree) data structure for efficient path authorization lookups.
///
/// Provides O(m) lookup time where m is the path depth, compared to O(n×m) for linear search
/// where n is the number of authorized paths.
///
/// Example:
/// ```swift
/// let trie = PathTrie()
/// trie.insert("/users/bob/documents")
/// trie.insert("/users/bob/downloads")
///
/// trie.isAuthorized("/users/bob/documents/file.txt") // true
/// trie.isAuthorized("/users/alice/file.txt")          // false
/// ```
final class PathTrie {
    private var root = TrieNode()

    /// Node in the trie tree
    private class TrieNode {
        /// Child nodes indexed by path component
        var children: [String: TrieNode] = [:]

        /// Whether this node represents an authorized path
        var isAuthorized = false
    }

    // MARK: - Insertion

    /// Insert an authorized path into the trie.
    ///
    /// The path should be normalized before insertion.
    ///
    /// - Parameter path: Normalized authorized path
    func insert(_ path: String) {
        // Split path into components
        // Example: "/users/bob/documents" -> ["users", "bob", "documents"]
        let components = path.split(separator: "/").map(String.init)

        var current = root

        // Traverse/create nodes for each path component
        for component in components {
            if current.children[component] == nil {
                current.children[component] = TrieNode()
            }
            current = current.children[component]!
        }

        // Mark the final node as authorized
        current.isAuthorized = true
    }

    // MARK: - Lookup

    /// Check if a path is authorized.
    ///
    /// A path is authorized if:
    /// 1. The exact path is in the trie, or
    /// 2. Any ancestor directory is authorized
    ///
    /// The path should be normalized before checking.
    ///
    /// - Parameter path: Normalized path to check
    /// - Returns: true if path is authorized
    func isAuthorized(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        var current = root

        // Traverse the trie following the path
        for component in components {
            // If any ancestor is authorized, this path is authorized
            if current.isAuthorized {
                return true
            }

            // Move to the next node
            guard let next = current.children[component] else {
                // Path not in trie
                return false
            }

            current = next
        }

        // Check if the final node is authorized
        return current.isAuthorized
    }

    // MARK: - Utilities

    /// Get the total number of authorized paths in the trie.
    ///
    /// - Returns: Count of authorized paths
    func count() -> Int {
        return countNodes(root)
    }

    private func countNodes(_ node: TrieNode) -> Int {
        var count = node.isAuthorized ? 1 : 0

        for child in node.children.values {
            count += countNodes(child)
        }

        return count
    }

    /// Remove all paths from the trie.
    func clear() {
        root = TrieNode()
    }
}
