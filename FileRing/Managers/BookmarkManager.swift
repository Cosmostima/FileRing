
import Foundation

class BookmarkManager {
    static let shared = BookmarkManager()

    private let bookmarksKey = "managedBookmarkKeys"
    private let authorizedPathsKey = "authorizedFolderPaths" // Persistent cache

    // In-memory cache for fast access (loaded on init)
    private var authorizedPathsCache: [String] = []

    private init() {
        loadAuthorizedPathsCache()
    }

    /// Check if specific folder is authorized
    func isAuthorized(forKey key: String) -> Bool {
        return loadUrl(withKey: key) != nil
    }

    /// Save folder access bookmark
    /// - Parameters:
    ///   - url: User-selected folder URL
    ///   - key: Unique identifier for the folder (e.g., "Downloads")
    func saveBookmark(for url: URL, withKey key: String) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[key] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)

            addPathToCache(url.path)
        } catch {
            // Silently fail
        }
    }

    /// Load and restore folder access permissions
    /// - Parameter key: Unique identifier for the folder
    /// - Returns: Folder URL if bookmark is valid (access already started)
    /// - Note: Access permissions persist for the app lifecycle
    func loadUrl(withKey key: String) -> URL? {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data],
              let bookmarkData = bookmarks[key] else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

            if url.startAccessingSecurityScopedResource() {
                return url
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    /// Get all saved bookmark keys
    func bookmarkKeys() -> [String] {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] else {
            return []
        }
        return Array(bookmarks.keys)
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
            if let url = loadUrl(withKey: key) {
                paths.append(url.path)
            }
        }

        authorizedPathsCache = paths
        UserDefaults.standard.set(paths, forKey: authorizedPathsKey)
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
        }
    }

    /// Remove a path from the cache (called when bookmark is revoked)
    private func removePathFromCache(_ path: String) {
        authorizedPathsCache.removeAll { $0 == path }
        UserDefaults.standard.set(authorizedPathsCache, forKey: authorizedPathsKey)
    }

    /// Revoke folder authorization
    func revokeAuthorization(forKey key: String) {
        let pathToRemove = loadUrl(withKey: key)?.path

        guard var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] else {
            return
        }

        bookmarks.removeValue(forKey: key)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)

        if let path = pathToRemove {
            removePathFromCache(path)
        }
    }

    /// Check if path is in authorized folders
    func isPathAuthorized(_ path: String) -> Bool {
        for authorizedPath in authorizedPathsCache {
            if path.hasPrefix(authorizedPath) {
                return true
            }
        }
        return false
    }
}
