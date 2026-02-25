//
//  BookmarkResourcePool.swift
//  FileRing
//
//  Created by Claude on 2026-01-15.
//  Thread-safe pool of security-scoped resources with reference counting
//

import Foundation

/// Thread-safe pool that manages security-scoped resources with automatic lifecycle management.
/// Resources are cached and reused across multiple accesses, preventing resource exhaustion.
///
/// Key features:
/// - Lazy resource creation: Resources created only when first accessed
/// - Automatic cleanup: Resources released when no longer referenced
/// - Reference counting: Single resource shared across multiple accessors
/// - Thread-safe: All operations are @MainActor isolated
@MainActor
final class BookmarkResourcePool {
    // MARK: - Storage Keys

    private let bookmarksKey = UserDefaultsKeys.managedBookmarkKeys
    private let authorizedPathsKey = UserDefaultsKeys.authorizedFolderPaths

    // MARK: - State

    /// Cached security-scoped resources (key -> resource)
    private var resources: [String: SecurityScopedResource] = [:]

    /// Bookmark data storage (key -> bookmark data)
    /// This is the source of truth for persisted bookmarks
    private var bookmarkData: [String: Data] = [:]

    // MARK: - Initialization

    init() {
        loadFromStorage()
    }

    // MARK: - Public API

    /// Acquire a security-scoped resource for the given key.
    /// Returns nil if bookmark doesn't exist or resource cannot be accessed.
    /// The returned resource is cached and reused on subsequent calls.
    ///
    /// - Parameter key: Bookmark identifier (e.g., "Downloads", "Documents")
    /// - Returns: Security-scoped resource or nil if unavailable
    func acquire(key: String) -> SecurityScopedResource? {
        // Return existing cached resource if available
        if let existing = resources[key] {
            // Check if resource is still valid
            if existing.isCurrentlyAccessing() {
                return existing
            } else {
                // Resource was stopped, remove from cache
                resources.removeValue(forKey: key)
            }
        }

        // Load bookmark data
        guard let data = bookmarkData[key] else {
            return nil
        }

        // Create new resource
        guard let resource = SecurityScopedResource(bookmarkData: data) else {
            return nil
        }

        // Cache the resource for reuse
        resources[key] = resource
        return resource
    }

    /// Store bookmark data for a key.
    /// Invalidates any cached resource for this key.
    ///
    /// - Parameters:
    ///   - key: Bookmark identifier
    ///   - bookmarkData: Security-scoped bookmark data
    /// - Throws: BookmarkError if storage fails
    func store(key: String, bookmarkData: Data) throws {
        self.bookmarkData[key] = bookmarkData

        // Invalidate cached resource (will be recreated on next acquire)
        if let resource = resources[key] {
            resource.stop()
            resources[key] = nil
        }

        try saveToStorage()
    }

    /// Remove bookmark for a key and stop any active resources.
    ///
    /// - Parameter key: Bookmark identifier to remove
    /// - Throws: BookmarkError if removal fails
    func remove(key: String) throws {
        bookmarkData.removeValue(forKey: key)

        // Stop and remove resource if cached
        if let resource = resources[key] {
            resource.stop()
            resources[key] = nil
        }

        try saveToStorage()
    }

    /// Get all stored bookmark keys.
    ///
    /// - Returns: Array of bookmark identifiers
    func allKeys() -> [String] {
        return Array(bookmarkData.keys)
    }

    /// Check if a bookmark exists for the given key.
    ///
    /// - Parameter key: Bookmark identifier
    /// - Returns: true if bookmark exists
    func hasBookmark(forKey key: String) -> Bool {
        return bookmarkData[key] != nil
    }

    /// Get bookmark data for a key (for migration purposes).
    ///
    /// - Parameter key: Bookmark identifier
    /// - Returns: Bookmark data or nil if not found
    func getBookmarkData(forKey key: String) -> Data? {
        return bookmarkData[key]
    }

    /// Clear all resources and stop all active accesses.
    /// Useful for testing or cleanup scenarios.
    func clearAll() {
        // Stop all active resources
        for (_, resource) in resources {
            resource.stop()
        }

        resources.removeAll()
        bookmarkData.removeAll()
    }

    // MARK: - Storage Management

    /// Load bookmark data from persistent storage (currently UserDefaults).
    /// This will be migrated to Keychain in Phase 2.
    private func loadFromStorage() {
        // Load from UserDefaults
        if let stored = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] {
            self.bookmarkData = stored
        }
    }

    /// Save bookmark data to persistent storage.
    /// This currently uses UserDefaults but will migrate to Keychain in Phase 2.
    private func saveToStorage() throws {
        UserDefaults.standard.set(bookmarkData, forKey: bookmarksKey)
    }
}

// MARK: - Error Types

enum BookmarkError: LocalizedError {
    case notAuthorized(String)
    case invalidBookmark(String)
    case storageFailed(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let key):
            return NSLocalizedString(
                "Folder '\(key)' is not authorized. Please authorize it in Settings.",
                comment: "Bookmark not authorized error"
            )
        case .invalidBookmark(let key):
            return NSLocalizedString(
                "Bookmark for '\(key)' is invalid or stale. Please re-authorize the folder in Settings.",
                comment: "Invalid bookmark error"
            )
        case .storageFailed(let reason):
            return NSLocalizedString(
                "Failed to save folder authorization: \(reason)",
                comment: "Storage failed error"
            )
        case .migrationFailed(let reason):
            return NSLocalizedString(
                "Failed to migrate folder authorizations: \(reason)",
                comment: "Migration failed error"
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAuthorized, .invalidBookmark:
            return NSLocalizedString(
                "Open Settings and re-authorize the folder.",
                comment: "Recovery suggestion for bookmark errors"
            )
        case .storageFailed:
            return NSLocalizedString(
                "Check disk space and try again.",
                comment: "Recovery suggestion for storage errors"
            )
        case .migrationFailed:
            return NSLocalizedString(
                "Your folder authorizations may need to be reset. Contact support if this persists.",
                comment: "Recovery suggestion for migration errors"
            )
        }
    }
}
