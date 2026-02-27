//
//  SettingsView.swift
//  FileRing
//
//  Settings window UI
//

import SwiftUI
import Combine
import os

struct SettingsView: View {
    @AppStorage(UserDefaultsKeys.hotkeyMode) private var hotkeyMode = "combination"
    @AppStorage(UserDefaultsKeys.modifierKey) private var selectedModifier = "control"
    @AppStorage(UserDefaultsKeys.keyEquivalent) private var selectedKey = "x"
    @AppStorage(UserDefaultsKeys.itemsPerSection) private var itemsPerSection = 6
    @AppStorage(UserDefaultsKeys.hideDockIcon) private var hideDockIcon = false
    @AppStorage(UserDefaultsKeys.hideStatusBarIcon) private var hideStatusBarIcon = false
    @State private var authorizedFolders: [String] = BookmarkManager.shared.bookmarkKeys()
    @State private var showResetAlert = false
    @State private var showBothHiddenWarning = false

    // Spotlight filter configuration
    @State private var spotlightConfig = SpotlightConfig.load()
    @State private var showFolderFilterEditor = false
    @State private var showExtensionFilterEditor = false

    // Launch at login
    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var launchAtLogin = false
    @State private var showLaunchError = false
    @State private var launchErrorMessage = ""

    // Bookmark error alert
    @State private var showBookmarkError = false
    @State private var bookmarkErrorMessage = ""

    // Permission status
    @State private var hasAccessibilityPermission = false
    @State private var showRestartPrompt = false

    var body: some View {
        VStack(spacing: 20) {

            Form {
                HStack(spacing: 10) {
                    IconWithBackground()
                        .frame(width: 50)
                        .padding()

                    Text("FileRing Settings")
                        .font(.title)
                        .fontWeight(.bold)
                }
                hotkeySection
                if !hasAccessibilityPermission {
                    permissionSection
                }
                displaySection
                folderPermissionSection
                filterSettingsSection
                appBehaviorSection
                aboutSection
                resetSection
            }
            .formStyle(.grouped)

            Divider()
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onAppear {
            // Sync launch at login state from system
            launchAtLogin = launchAtLoginManager.isLaunchAtLoginEnabled
            // Check permission status
            checkPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let granted = AccessibilityHelper.checkPermission()
            if granted && !hasAccessibilityPermission {
                hasAccessibilityPermission = true
                stopObservingPermission()
                showRestartPrompt = true
            } else {
                hasAccessibilityPermission = granted
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !hasAccessibilityPermission else { return }
            if AccessibilityHelper.checkPermission() {
                hasAccessibilityPermission = true
                stopObservingPermission()
                showRestartPrompt = true
            }
        }
        .alert("Reset FileRing?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAndShowOnboarding()
            }
        } message: {
            Text("This will delete all folder authorizations and show the onboarding screen again. This action cannot be undone.")
        }
        .alert("Launch at Login Error", isPresented: $showLaunchError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(launchErrorMessage)
        }
        .alert("Accessibility Permission Granted", isPresented: $showRestartPrompt) {
            Button("Restart Now") { restartApplication() }
            Button("Later", role: .cancel) { }
        } message: {
            Text("FileRing needs to restart to activate the hotkey with the new permission.")
        }
        .alert("Folder Authorization Error", isPresented: $showBookmarkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(bookmarkErrorMessage)
        }
        .alert("Warning", isPresented: $showBothHiddenWarning) {
            Button("Cancel", role: .cancel) {
                // Revert the most recent change
                DispatchQueue.main.async {
                    if hideDockIcon && hideStatusBarIcon {
                        // Find which one was changed last by checking current notification
                        // Since we can't determine this easily, revert status bar icon as it's instant
                        hideStatusBarIcon = false
                        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hideStatusBarIcon)
                        NotificationCenter.default.post(name: .statusBarIconVisibilityChanged, object: nil)
                    }
                }
            }
            Button("Continue", role: .destructive) {
                // Allow both to be hidden
            }
        } message: {
            Text("Hiding both the dock icon and status bar icon will make the app only accessible through the hotkey. You can reopen settings by clicking the app in Applications folder or Spotlight.")
        }
        .sheet(isPresented: $showFolderFilterEditor) {
            FilterListEditorView(
                title: "Excluded Folders",
                placeholder: "e.g., node_modules, .git",
                itemPrefix: "",
                items: $spotlightConfig.excludedFolders
            )
            .onDisappear {
                saveSpotlightConfig()
            }
        }
        .sheet(isPresented: $showExtensionFilterEditor) {
            FilterListEditorView(
                title: "Excluded Extensions",
                placeholder: "e.g., tmp, log, cache",
                itemPrefix: ".",
                items: $spotlightConfig.excludedExtensions
            )
            .onDisappear {
                saveSpotlightConfig()
            }
        }
    }

    // MARK: - Sections
    private var hotkeySection: some View {
        Section("Hotkey Settings") {
            HotkeyCaptureField(
                modifierSetting: $selectedModifier,
                keySetting: $selectedKey
            ) { newModifier, newKey in
                let defaults = UserDefaults.standard
                defaults.set(newModifier, forKey: UserDefaultsKeys.modifierKey)
                defaults.set(newKey, forKey: UserDefaultsKeys.keyEquivalent)

                // Auto-detect mode based on whether key is provided
                let newMode = newKey.isEmpty ? "modifier_only" : "combination"
                if newMode != hotkeyMode {
                    hotkeyMode = newMode
                    defaults.set(newMode, forKey: UserDefaultsKeys.hotkeyMode)
                }

                NotificationCenter.default.post(name: .hotkeySettingChanged, object: nil)
            }
            .frame(height: 32)
            .padding(.vertical, 4)

            Text(hotkeyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionSection: some View {
        Section("Accessibility Permission") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasAccessibilityPermission ? .green : .orange)
                        Text(hasAccessibilityPermission ? "Permission Granted" : "Permission Required")
                            .font(.body)
                    }

                    if !hasAccessibilityPermission {
                        Text("FileRing needs Accessibility permission to capture global hotkeys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !hasAccessibilityPermission {
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Refresh") {
                        checkPermissionStatus()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)

            if !hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To grant permission:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Open System Settings > Privacy & Security > Accessibility", systemImage: "1.circle.fill")
                        Label("Click the lock icon to unlock (admin password required)", systemImage: "2.circle.fill")
                        Label("Find FileRing in the list and enable it", systemImage: "3.circle.fill")
                        Label("Restart FileRing if needed", systemImage: "4.circle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var displaySection: some View {
        Section("Display Settings") {
            Picker("Items per section", selection: $itemsPerSection) {
                ForEach(4...10, id: \.self) { num in
                    Text("\(num)").tag(num)
                }
            }
            // @AppStorage automatically persists changes

            Text("Default: 6, Maximum: 10")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filterSettingsSection: some View {
        Section("Filter Settings") {
            Text("Exclude specific folders and file extensions from search results.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Excluded Folders
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Excluded Folders")
                        .font(.body)
                    Text("\(spotlightConfig.excludedFolders.count) folders excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage") {
                    showFolderFilterEditor = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

            // Excluded Extensions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Excluded Extensions")
                        .font(.body)
                    Text("\(spotlightConfig.excludedExtensions.count) extensions excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage") {
                    showExtensionFilterEditor = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
            
            // Application Search
            Toggle("Include Applications in Search", isOn: $spotlightConfig.enableAppSearch)
                .onChange(of: spotlightConfig.enableAppSearch) { _ in
                    saveSpotlightConfig()
                }

            Text("When enabled, applications will be mixed with files in \"Recently Used\" and \"Most Used\" sections. At least 50% of results will always be files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appBehaviorSection: some View {
        Section("App Behavior") {
            Toggle("Launch at Startup", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        try launchAtLoginManager.setLaunchAtLogin(enabled: newValue)
                        // Update state to reflect actual system state
                        launchAtLogin = launchAtLoginManager.isLaunchAtLoginEnabled
                    } catch {
                        // Revert toggle on error
                        launchAtLogin = launchAtLoginManager.isLaunchAtLoginEnabled
                        launchErrorMessage = "Failed to update launch at login: \(error.localizedDescription)"
                        showLaunchError = true
                    }
                }

            Text("Launch FileRing automatically when you log in to your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Hide Dock icon", isOn: $hideDockIcon)
                .onChange(of: hideDockIcon) { newValue in
                    if newValue && hideStatusBarIcon {
                        showBothHiddenWarning = true
                    }
                    // Note: Dock icon visibility is applied on app restart
                    // Implementation is in MenuBarApp.applicationDidFinishLaunching
                }

            Text("When enabled, app appears only in status bar. Requires restart to take effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Hide Status Bar icon", isOn: $hideStatusBarIcon)
                .onChange(of: hideStatusBarIcon) { newValue in
                    if newValue && hideDockIcon {
                        showBothHiddenWarning = true
                    }
                    // Notify MenuBarApp to update status bar icon visibility
                    NotificationCenter.default.post(name: .statusBarIconVisibilityChanged, object: nil)
                }

            Text("When enabled, status bar icon will be hidden. App can still be accessed via hotkey or dock icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderPermissionSection: some View {
        Section("Folder Permissions") {
            Text("Only authorized folders will be searchable. Grant access to folders you want FileRing to manage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick access common folders
            VStack(alignment: .leading, spacing: 4) {
                Text("Common Folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                folderPermissionRow(title: "iCloud Drive", icon: "icloud.fill", key: "iCloudDrive", folder: nil)
                folderPermissionRow(title: "Desktop", icon: "macwindow", key: "Desktop", folder: .desktopDirectory)
                folderPermissionRow(title: "Downloads", icon: "arrow.down.circle.fill", key: "Downloads", folder: .downloadsDirectory)
                folderPermissionRow(title: "Documents", icon: "doc.fill", key: "Documents", folder: .documentDirectory)
            }

            // Authorized folders list
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Authorized Folders (\(authorizedFolders.count))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add",systemImage: "plus") {
                        addCustomFolder()
                    }
                    .buttonStyle(.borderless)
                }

                if authorizedFolders.isEmpty {
                    Text("No folders authorized yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(authorizedFolders, id: \.self) { key in
                        authorizedFolderRow(key: key)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(AppVersion.current)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Created by")
                Spacer()
                Text("Cosmos")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resetSection: some View {
        Section{
            Button("Reset") {
                showResetAlert = true
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Reset
    private func resetAndShowOnboarding() {
        let bookmarkKeys = BookmarkManager.shared.bookmarkKeys()
        for key in bookmarkKeys {
            do {
                try BookmarkManager.shared.revokeAuthorization(forKey: key)
            } catch {
                Logger.main.error("Failed to revoke authorization for \(key): \(error.localizedDescription)")
            }
        }
        AppVersion.completedOnboardingVersion = nil

        // Reset spotlight config to defaults
        resetSpotlightConfig()

        refreshAuthorizedFolders()
        NotificationCenter.default.post(name: Notification.Name("ShowOnboarding"), object: nil)
    }

    // MARK: - Spotlight Config Management
    private func saveSpotlightConfig() {
        do {
            try spotlightConfig.save()
            // Notify that config has changed so FileSystemService reloads it
            NotificationCenter.default.post(name: .spotlightConfigChanged, object: nil)
        } catch {
            Logger.main.error("Failed to save spotlight config: \(String(describing: error))")
        }
    }

    private func resetSpotlightConfig() {
        // Reset UserDefaults to restore defaults
        SpotlightConfig.reset()

        // Reload default config
        spotlightConfig = SpotlightConfig.load()

        // Notify that config has changed
        NotificationCenter.default.post(name: .spotlightConfigChanged, object: nil)
    }

    // MARK: - Helpers
    private var hotkeyDescription: String {
        return "Click the field and press your desired shortcut. Must combine modifier keys with a regular key (e.g., ⌃X, ⌥Space)."
    }

    private func folderPermissionRow(title: String, icon: String, key: String, folder: FileManager.SearchPathDirectory?) -> some View {
        FolderPermissionRow(
            title: title, icon: icon, key: key, folder: folder,
            onError: { msg in bookmarkErrorMessage = msg; showBookmarkError = true },
            onSuccess: { refreshAuthorizedFolders() }
        )
    }

    @ViewBuilder
    private func authorizedFolderRow(key: String) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Use new safe API to get folder information
                let folderInfo = try? BookmarkManager.shared.withAuthorizedURL(key: key) { url in
                    (name: url.lastPathComponent, path: url.path)
                }

                if let info = folderInfo {
                    Text(info.name)
                        .font(.system(size: 13))
                    Text(info.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                revokeAuthorization(forKey: key)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Custom Folder Management
    private func addCustomFolder() {
        FolderAuthorizationHelper.addCustomFolder(
            onError: { msg in bookmarkErrorMessage = msg; showBookmarkError = true },
            onSuccess: { refreshAuthorizedFolders() }
        )
    }

    private func revokeAuthorization(forKey key: String) {
        do {
            try BookmarkManager.shared.revokeAuthorization(forKey: key)
            self.refreshAuthorizedFolders()
        } catch {
            bookmarkErrorMessage = "Failed to revoke authorization for \(key): \(error.localizedDescription)"
            showBookmarkError = true
        }
    }

    private func refreshAuthorizedFolders() {
        authorizedFolders = BookmarkManager.shared.bookmarkKeys()
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

    private func restartApplication() {
        AccessibilityHelper.restartApp()
    }
}
