//
//  ThumbnailService.swift
//  FileRing
//
//  Created by Claude on 07/11/2025.
//

import Foundation
import AppKit
import QuickLookThumbnailing

/// Actor-based service for generating file thumbnails with automatic caching
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let generator = QLThumbnailGenerator.shared
    private let cache = NSCache<NSString, NSImage>()

    // File extensions that benefit from content thumbnails
    private let thumbnailExtensions: Set<String> = [
        // Images
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
        // Documents
        "pdf", "pages", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "key", "numbers", "rtf", "txt",
        // Videos
        "mp4", "mov", "m4v", "avi", "mkv",
        // 3D
        "usdz", "obj", "dae"
    ]

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    /// Generate thumbnail for file at path
    /// - Parameters:
    ///   - path: File path
    ///   - size: Desired thumbnail size
    /// - Returns: Thumbnail image or generic icon
    func thumbnail(for path: String, size: CGSize) async -> NSImage {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            // Always use generic icon for folders
            return NSWorkspace.shared.icon(forFile: path)
        }

        // Use generic icon for non-previewable files
        guard thumbnailExtensions.contains(ext) else {
            return NSWorkspace.shared.icon(forFile: path)
        }

        // Check in-memory cache
        let cacheKey = "\(path)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Generate thumbnail (will use system cache if available)
        return await generateAndCache(url: url, size: size, cacheKey: cacheKey)
    }

    private func generateAndCache(url: URL, size: CGSize, cacheKey: NSString) async -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .lowQualityThumbnail // Fast version - uses cache or embedded previews
        )

        do {
            let representation = try await generator.generateBestRepresentation(for: request)
            let image = representation.nsImage

            // Cache in memory
            cache.setObject(image, forKey: cacheKey)

            return image
        } catch {
            // Fallback to generic icon on error
            let fallback = NSWorkspace.shared.icon(forFile: url.path)
            cache.setObject(fallback, forKey: cacheKey)
            return fallback
        }
    }

    /// Clear in-memory cache
    func clearCache() {
        cache.removeAllObjects()
    }

    /// Preload thumbnails for multiple paths (optional optimization)
    func preloadThumbnails(for paths: [String], size: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                group.addTask {
                    _ = await self.thumbnail(for: path, size: size)
                }
            }
        }
    }
}
