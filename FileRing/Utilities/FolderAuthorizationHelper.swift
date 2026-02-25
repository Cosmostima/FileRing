//
//  FolderAuthorizationHelper.swift
//  FileRing
//
//  Shared folder authorization logic for SettingsView and OnboardingView
//

import Foundation
import AppKit

@MainActor
enum FolderAuthorizationHelper {

    /// Present an open panel to select iCloud Drive folder and save a bookmark.
    static func selectICloudDrive(
        onError: @escaping (String) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.message = "Select iCloud Drive folder to grant access"
        openPanel.prompt = "Select"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.showsHiddenFiles = true

        if let homeURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let mobileDocsURL = homeURL.appendingPathComponent("Mobile Documents")
            openPanel.directoryURL = mobileDocsURL
        }

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    try BookmarkManager.shared.saveBookmark(for: url, withKey: "iCloudDrive")
                    onSuccess()
                } catch {
                    onError("Failed to save iCloud Drive bookmark: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Present an open panel to select a standard folder and save a bookmark.
    static func selectFolder(
        key: String,
        defaultDirectory: FileManager.SearchPathDirectory,
        onError: @escaping (String) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.message = "Select \(key) folder to grant access"
        openPanel.prompt = "Select"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false

        if let defaultURL = FileManager.default.urls(for: defaultDirectory, in: .userDomainMask).first {
            openPanel.directoryURL = defaultURL
        }

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    try BookmarkManager.shared.saveBookmark(for: url, withKey: key)
                    onSuccess()
                } catch {
                    onError("Failed to save \(key) bookmark: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Present an open panel to select a custom folder and save a bookmark with a unique key.
    static func addCustomFolder(
        onError: @escaping (String) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.message = "Select a folder to authorize"
        openPanel.prompt = "Authorize"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                let folderName = url.lastPathComponent
                var key = "Custom_\(folderName)"
                var counter = 1

                while BookmarkManager.shared.isAuthorized(forKey: key) {
                    counter += 1
                    key = "Custom_\(folderName)_\(counter)"
                }

                do {
                    try BookmarkManager.shared.saveBookmark(for: url, withKey: key)
                    onSuccess()
                } catch {
                    onError("Failed to save custom folder bookmark: \(error.localizedDescription)")
                }
            }
        }
    }
}
