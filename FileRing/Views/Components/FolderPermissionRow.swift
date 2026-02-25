//
//  FolderPermissionRow.swift
//  FileRing
//
//  Shared folder permission row component used in SettingsView and OnboardingView
//

import SwiftUI

struct FolderPermissionRow: View {
    let title: String
    let icon: String
    let key: String
    let folder: FileManager.SearchPathDirectory?
    let onError: (String) -> Void
    let onSuccess: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(key == "iCloudDrive" ? .blue : .secondary)
                .frame(width: 20)
            Text(title)
            Spacer()
            if BookmarkManager.shared.isAuthorized(forKey: key) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Authorize") {
                    if key == "iCloudDrive" {
                        FolderAuthorizationHelper.selectICloudDrive(onError: onError, onSuccess: onSuccess)
                    } else if let folder = folder {
                        FolderAuthorizationHelper.selectFolder(key: key, defaultDirectory: folder, onError: onError, onSuccess: onSuccess)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}
