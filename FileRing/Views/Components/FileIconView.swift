//
//  FileIconView.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI
import AppKit

struct FileIconView: View {
    let path: String
    let isFolder: Bool

    @State private var image: NSImage?

    private let iconSize: CGFloat = 52 // Match layout iconSize

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                // Instant placeholder while loading
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: path) {
            // Load thumbnail asynchronously
            // Use 2x size for retina displays
            let size = CGSize(width: iconSize * 2, height: iconSize * 2)
            image = await ThumbnailService.shared.thumbnail(for: path, size: size)
        }
    }
}
