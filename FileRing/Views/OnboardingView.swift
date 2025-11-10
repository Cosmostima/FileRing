//
//  OnboardingView.swift
//  FileRing
//
//  Simplified user onboarding guide for first-time users
//

import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var selectedModifier = "control"
    @State private var selectedKey = "x"
    @State private var authorizedFolders: [String] = []

    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        // Initialize state values after the struct is created
        _selectedModifier = State(initialValue: UserDefaults.standard.string(forKey: "FileRingModifierKey") ?? "control")
        _selectedKey = State(initialValue: UserDefaults.standard.string(forKey: "FileRingKeyEquivalent") ?? "x")
        _authorizedFolders = State(initialValue: BookmarkManager.shared.bookmarkKeys())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(height: 10)

            // Content
            Group {
                if currentPage == 0 {
                    welcomePage
                        .frame(height: 530)
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                } else {
                    setupPage
                        .frame(height: 530)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                if currentPage < 1 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 700, height: 600)
    }

    // MARK: - Welcome Page
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            IconWithBackground()
                .frame(width: 100, height: 100)
                .foregroundStyle(.blue)
                .padding(.bottom, 8)

            // Title
            Text("Welcome to FileRing!")
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)

            // Description
            Text("Quick access to your files and folders.")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Divider()
                .padding(.vertical, 20)

            // Six sections explanation with icons
            VStack(spacing: 16) {
                Text("Six Sections")
                    .font(.system(size: 20, weight: .semibold))

                HStack(spacing: 40) {
                    // Files column
                    VStack(alignment: .leading, spacing: 12) {
                        sectionItem(icon: "clock", color: .green, title: "Recently Opened Files")
                        sectionItem(icon: "arrow.down.doc", color: .green, title: "Recently Saved Files")
                        sectionItem(icon: "star", color: .green, title: "Frequently Used Files (3 days)")
                    }

                    // Folders column
                    VStack(alignment: .leading, spacing: 12) {
                        sectionItem(icon: "clock", color: .blue, title: "Recently Opened Folders")
                        sectionItem(icon: "arrow.down.doc", color: .blue, title: "Recently Saved Folders")
                        sectionItem(icon: "star", color: .blue, title: "Frequently Used Folders (3 days)")
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Setup Page
    private var setupPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    // Hotkey Settings
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.green)
                            Text("Hotkey Settings")
                                .font(.system(size: 20, weight: .semibold))
                        }

                        Text("Click the field and press your desired shortcut. Must combine modifier keys with a regular key (e.g., ⌃X, ⌥Space).")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        HotkeyCaptureField(
                            modifierSetting: $selectedModifier,
                            keySetting: $selectedKey
                        ) { newModifier, newKey in
                            let defaults = UserDefaults.standard
                            defaults.set(newModifier, forKey: "FileRingModifierKey")
                            defaults.set(newKey, forKey: "FileRingKeyEquivalent")

                            // Auto-detect mode based on whether key is provided
                            let newMode = newKey.isEmpty ? "modifier_only" : "combination"
                            defaults.set(newMode, forKey: "FileRingHotkeyMode")

                            NotificationCenter.default.post(name: .hotkeySettingChanged, object: nil)
                        }
                        .frame(height: 32)
                        .padding(.vertical, 4)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)

                    Divider()

                    // Folder Authorization
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 24))
                                .foregroundStyle(.orange)
                            Text("Authorize Folders")
                                .font(.system(size: 20, weight: .semibold))
                        }

                        Text("Grant access to folders you want FileRing to search. This is required for FileRing to work.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        // Common folders
                        VStack(spacing: 8) {
                            folderPermissionRow(title: "iCloud Drive", icon: "icloud.fill", key: "iCloudDrive", folder: nil)
                            folderPermissionRow(title: "Desktop", icon: "macwindow", key: "Desktop", folder: .desktopDirectory)
                            folderPermissionRow(title: "Downloads", icon: "arrow.down.circle.fill", key: "Downloads", folder: .downloadsDirectory)
                            folderPermissionRow(title: "Documents", icon: "doc.fill", key: "Documents", folder: .documentDirectory)
                            folderPermissionRow(title: "Applications", icon: "app.fill", key: "Applications", folder: .applicationDirectory)
                        }

                        // Custom folder button
                        Button(action: addCustomFolder) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Custom Folder")
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)

                        // Authorized count
                        Text("\(authorizedFolders.count) folder(s) authorized")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    // MARK: - Helper Views
    private func sectionItem(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(5)
                .padding(.horizontal,3)
                .background(RoundedRectangle(cornerRadius: 10).fill(color))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14))
        }
    }

    @ViewBuilder
    private func folderPermissionRow(title: String, icon: String, key: String, folder: FileManager.SearchPathDirectory?) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(key == "iCloudDrive" ? .blue : .secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14))
            Spacer()
            if BookmarkManager.shared.isAuthorized(forKey: key) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
            } else {
                Button("Authorize") {
                    if key == "iCloudDrive" {
                        selectICloudDrive()
                    } else if let folder = folder {
                        selectFolder(key: key, defaultDirectory: folder)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Folder Selection
    private func selectICloudDrive() {
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
                BookmarkManager.shared.saveBookmark(for: url, withKey: "iCloudDrive")
                refreshAuthorizedFolders()
            }
        }
    }

    private func selectFolder(key: String, defaultDirectory: FileManager.SearchPathDirectory) {
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
                BookmarkManager.shared.saveBookmark(for: url, withKey: key)
                refreshAuthorizedFolders()
            }
        }
    }

    private func addCustomFolder() {
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

                BookmarkManager.shared.saveBookmark(for: url, withKey: key)
                refreshAuthorizedFolders()
            }
        }
    }

    private func refreshAuthorizedFolders() {
        authorizedFolders = BookmarkManager.shared.bookmarkKeys()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "FileRingHasSeenOnboarding")
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
