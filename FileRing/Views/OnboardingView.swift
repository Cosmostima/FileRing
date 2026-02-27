//
//  OnboardingView.swift
//  FileRing
//
//  Simplified user onboarding guide for first-time users
//

import SwiftUI
import Combine
import os.log

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var selectedModifier = "control"
    @State private var selectedKey = "x"
    @State private var authorizedFolders: [String] = []
    @State private var hasAccessibilityPermission = false
    @State private var showBookmarkError = false
    @State private var bookmarkErrorMessage = ""

    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        // Initialize state values after the struct is created
        _selectedModifier = State(initialValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.modifierKey) ?? "control")
        _selectedKey = State(initialValue: UserDefaults.standard.string(forKey: UserDefaultsKeys.keyEquivalent) ?? "x")
        _authorizedFolders = State(initialValue: BookmarkManager.shared.bookmarkKeys())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
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
                } else if currentPage == 1 {
                    setupPage
                        .frame(height: 530)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    permissionPage
                        .frame(height: 530)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                checkPermissionStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard currentPage == 2, !hasAccessibilityPermission else { return }
                if AccessibilityHelper.checkPermission() {
                    hasAccessibilityPermission = true
                    stopObservingPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        completeAndRestart()
                    }
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                guard currentPage == 2, !hasAccessibilityPermission else { return }
                if AccessibilityHelper.checkPermission() {
                    hasAccessibilityPermission = true
                    stopObservingPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        completeAndRestart()
                    }
                }
            }

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

                if currentPage < 2 {
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
                    .disabled(!hasAccessibilityPermission)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 700, height: 600)
        .alert("Folder Authorization Error", isPresented: $showBookmarkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(bookmarkErrorMessage)
        }
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
                        defaults.set(newModifier, forKey: UserDefaultsKeys.modifierKey)
                        defaults.set(newKey, forKey: UserDefaultsKeys.keyEquivalent)

                        // Auto-detect mode based on whether key is provided
                        let newMode = newKey.isEmpty ? "modifier_only" : "combination"
                        defaults.set(newMode, forKey: UserDefaultsKeys.hotkeyMode)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func folderPermissionRow(title: String, icon: String, key: String, folder: FileManager.SearchPathDirectory?) -> some View {
        FolderPermissionRow(
            title: title, icon: icon, key: key, folder: folder,
            onError: { msg in bookmarkErrorMessage = msg; showBookmarkError = true },
            onSuccess: { refreshAuthorizedFolders() }
        )
    }

    private func addCustomFolder() {
        FolderAuthorizationHelper.addCustomFolder(
            onError: { msg in bookmarkErrorMessage = msg; showBookmarkError = true },
            onSuccess: { refreshAuthorizedFolders() }
        )
    }

    private func refreshAuthorizedFolders() {
        authorizedFolders = BookmarkManager.shared.bookmarkKeys()
    }

    // MARK: - Permission Page
    private var permissionPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(hasAccessibilityPermission ? .green : .orange)
                .padding(.bottom, 8)

            // Title
            Text("Accessibility Permission")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)

            if hasAccessibilityPermission {
                // Permission granted
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 24))
                        Text("Permission Granted")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.green)
                    }

                    Text("The app can now run normally.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                // Permission needed
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 20))
                        Text("Permission Required")
                            .font(.system(size: 18, weight: .semibold))
                    }

                    Text("FileRing needs Accessibility permission to capture global hotkeys.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("To grant permission:")
                            .font(.system(size: 14, weight: .medium))

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Open System Settings > Privacy & Security > Accessibility", systemImage: "1.circle.fill")
                            Label("Click the lock icon to unlock (admin password required)", systemImage: "2.circle.fill")
                            Label("Find FileRing in the list and enable it", systemImage: "3.circle.fill")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    }

                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(spacing: 8) {
                        Text("If you just completed authorization, please restart the app to take effect.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Complete & Restart App") {
                            completeAndRestart()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
        .onChange(of: currentPage) { newPage in
            if newPage == 2 {
                checkPermissionStatus()
            } else {
                stopObservingPermission()
            }
        }
    }

    // MARK: - Permission Management

    private func checkPermissionStatus() {
        hasAccessibilityPermission = AccessibilityHelper.checkPermission()
    }

    private func stopObservingPermission() {
        // Permission observation is handled by Timer and didBecomeActive receivers;
        // this method is kept as a hook for future cleanup if needed.
    }

    private func openAccessibilitySettings() {
        // Call with prompt=true to register the app in the Accessibility list,
        // then open Settings so the user can enable the toggle.
        _ = AccessibilityHelper.requestPermission()
        AccessibilityHelper.openSystemSettings()
    }

    private func completeOnboarding() {
        AppVersion.markOnboardingCompleted()
        onComplete()
    }

    private func completeAndRestart() {
        AppVersion.markOnboardingCompleted()
        onComplete()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AccessibilityHelper.restartApp()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
