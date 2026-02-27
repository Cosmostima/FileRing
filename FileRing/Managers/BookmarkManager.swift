
import Foundation

@MainActor
class BookmarkManager {
    static let shared = BookmarkManager()

    private let resourcePool: BookmarkResourcePool
    private let pathValidator = SecurePathValidator()
    private let authorizedPathsKey = UserDefaultsKeys.authorizedFolderPaths // Persistent cache

    // In-memory cache for fast access (loaded on init)
    private var authorizedPathsCache: [String] = []

    // Optimized trie for fast path lookups
    private var pathTrie: PathTrie?

    private init() {
        self.resourcePool = BookmarkResourcePool()
        loadAuthorizedPathsCache()
        rebuildPathTrie()
    }

    /// Check if specific folder is authorized
    /// - Parameter key: Unique identifier for the folder (e.g., "Downloads")
    /// - Returns: true if folder is authorized and accessible
    func isAuthorized(forKey key: String) -> Bool {
        return resourcePool.acquire(key: key) != nil
    }

    /// Save folder access bookmark
    /// - Parameters:
    ///   - url: User-selected folder URL
    ///   - key: Unique identifier for the folder (e.g., "Downloads")
    /// - Throws: BookmarkError if bookmark creation or storage fails
    func saveBookmark(for url: URL, withKey key: String) throws {
        // Create security-scoped bookmark
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Store in resource pool (handles caching and persistence)
        try resourcePool.store(key: key, bookmarkData: bookmarkData)

        // Update path cache for fast path authorization checks
        addPathToCache(url.path)
    }

    /// Execute an operation with authorized URL access.
    /// The security-scoped resource is automatically managed and released after the operation.
    ///
    /// - Parameters:
    ///   - key: Bookmark identifier
    ///   - operation: Closure to execute with the authorized URL
    /// - Returns: Result of the operation
    /// - Throws: BookmarkError if folder is not authorized or operation fails
    func withAuthorizedURL<T>(key: String, perform operation: (URL) throws -> T) throws -> T {
        guard let resource = resourcePool.acquire(key: key) else {
            throw BookmarkError.notAuthorized(key)
        }

        return try operation(resource.getURL())
    }

    /// Get all saved bookmark keys
    /// - Returns: Array of bookmark identifiers
    func bookmarkKeys() -> [String] {
        return resourcePool.allKeys()
    }

    /// Load authorized paths from persistent storage on init
    private func loadAuthorizedPathsCache() {
        if let savedPaths = UserDefaults.standard.array(forKey: authorizedPathsKey) as? [String] {
            authorizedPathsCache = savedPaths
        } else {
            rebuildAndSavePathsCache()
        }
    }

    /// Rebuild paths cache from bookmarks and save to persistent storage
    private func rebuildAndSavePathsCache() {
        let keys = bookmarkKeys()
        var paths: [String] = []

        for key in keys {
            // Safely acquire resource to get URL path
            if let resource = resourcePool.acquire(key: key) {
                paths.append(resource.getURL().path)
            }
        }

        authorizedPathsCache = paths
        UserDefaults.standard.set(paths, forKey: authorizedPathsKey)

        // Rebuild trie with new paths
        rebuildPathTrie()
    }

    /// Get all authorized paths (fast - from in-memory cache)
    func authorizedPaths() -> [String] {
        return authorizedPathsCache
    }

    /// Add a path to the cache (called when bookmark is saved)
    private func addPathToCache(_ path: String) {
        if !authorizedPathsCache.contains(path) {
            authorizedPathsCache.append(path)
            UserDefaults.standard.set(authorizedPathsCache, forKey: authorizedPathsKey)

            // Rebuild trie to include new path
            rebuildPathTrie()
        }
    }

    /// Remove a path from the cache (called when bookmark is revoked)
    private func removePathFromCache(_ path: String) {
        authorizedPathsCache.removeAll { $0 == path }
        UserDefaults.standard.set(authorizedPathsCache, forKey: authorizedPathsKey)

        // Rebuild trie to exclude removed path
        rebuildPathTrie()
    }

    /// Revoke folder authorization
    /// - Parameter key: Bookmark identifier to revoke
    /// - Throws: BookmarkError if revocation fails
    func revokeAuthorization(forKey key: String) throws {
        // Remove from resource pool (stops resource and removes from storage)
        try resourcePool.remove(key: key)

        // Rebuild paths cache from remaining bookmarks to ensure consistency
        rebuildAndSavePathsCache()
    }

    /// Check if path is in authorized folders (SECURE VERSION).
    ///
    /// This method performs comprehensive security checks:
    /// - Resolves symbolic links to prevent directory traversal attacks
    /// - Normalizes paths to handle `.` and `..` sequences
    /// - Performs case-insensitive matching (macOS filesystem behavior)
    /// - Uses Unicode normalization to prevent homograph attacks
    ///
    /// For performance, uses a trie structure for O(m) lookups where m is path depth.
    ///
    /// - Parameter path: Path to validate
    /// - Returns: true if path is within an authorized folder
    func isPathAuthorized(_ path: String) -> Bool {
        // Use cached trie for performance (O(m) lookup)
        if let trie = pathTrie {
            // Normalize the path before checking
            guard let normalized = pathValidator.normalizePath(path) else {
                // Path cannot be normalized - deny access
                return false
            }
            return trie.isAuthorized(normalized)
        }

        // Fallback to validator (O(n×m) lookup, but with full security checks)
        return pathValidator.isPathAuthorized(path, authorizedPaths: authorizedPathsCache)
    }

    // MARK: - Path Trie Management

    /// Rebuild the path trie from current authorized paths.
    /// This is called after paths change to keep the trie in sync.
    private func rebuildPathTrie() {
        pathTrie = pathValidator.buildPathTrie(authorizedPaths: authorizedPathsCache)
    }
}
