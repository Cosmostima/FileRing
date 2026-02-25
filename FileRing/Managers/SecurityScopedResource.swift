//
//  SecurityScopedResource.swift
//  FileRing
//
//  Created by Claude on 2026-01-15.
//  RAII wrapper for security-scoped resource access
//

import Foundation

/// RAII (Resource Acquisition Is Initialization) wrapper for security-scoped resource access.
/// Automatically calls stopAccessingSecurityScopedResource() when deallocated,
/// preventing resource leaks.
///
/// Usage:
/// ```swift
/// guard let resource = SecurityScopedResource(bookmarkData: data) else {
///     throw BookmarkError.invalidBookmark
/// }
/// let url = resource.getURL()
/// // Use url...
/// // Resource automatically released when resource goes out of scope
/// ```
final class SecurityScopedResource: @unchecked Sendable {
    private let url: URL
    private var isAccessing: Bool = false
    private let lock = NSLock()

    /// Initialize a security-scoped resource from bookmark data
    /// - Parameter bookmarkData: Security-scoped bookmark data from URL.bookmarkData()
    /// - Returns: nil if bookmark cannot be resolved or security scope cannot be started
    init?(bookmarkData: Data) {
        do {
            var isStale = false
            self.url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Immediately start accessing security-scoped resource
            lock.lock()
            defer { lock.unlock() }

            if url.startAccessingSecurityScopedResource() {
                self.isAccessing = true
            } else {
                // Failed to start accessing - initialization failed
                return nil
            }
        } catch {
            // Failed to resolve bookmark
            return nil
        }
    }

    deinit {
        // Automatic cleanup when resource is deallocated
        stop()
    }

    /// Get the URL for this security-scoped resource
    /// - Returns: URL that has active security-scoped access
    func getURL() -> URL {
        return url
    }

    /// Manually stop accessing the security-scoped resource
    /// This is called automatically by deinit, but can be called manually for early release
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isAccessing else { return }

        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }

    /// Check if the resource URL still exists and is accessible
    /// - Returns: true if the URL no longer exists or is inaccessible
    func isStale() -> Bool {
        // Check if URL still exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if !exists {
            return true
        }

        // Check if URL is still readable
        let isReadable = FileManager.default.isReadableFile(atPath: url.path)
        return !isReadable
    }

    /// Check if the resource is currently accessing (not yet stopped)
    func isCurrentlyAccessing() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAccessing
    }
}

// MARK: - CustomStringConvertible

extension SecurityScopedResource: CustomStringConvertible {
    var description: String {
        return "SecurityScopedResource(url: \(url.path), isAccessing: \(isCurrentlyAccessing()))"
    }
}
