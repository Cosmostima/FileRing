//
//  MenuBarApp.swift
//  PopUp
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI
import AppKit

class MenuBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popupPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var eventMonitor: Any?
    private var hostingView: NSHostingView<DoubleRingPanelView>?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureDefaultHotkeySettings()
        applyDockIconVisibility()
        setupHotkeyManager()
        setupStatusBarItem()
        setupPopupPanel()
        setupEscapeKeyMonitor()

        // Load bookmarks
        let allBookmarkKeys = BookmarkManager.shared.bookmarkKeys()
        for key in allBookmarkKeys {
            _ = BookmarkManager.shared.loadUrl(withKey: key)
        }

        // Show onboarding for first-time users
        showOnboardingIfNeeded()

        // Listen for reset notification from settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnboarding),
            name: Notification.Name("ShowOnboarding"),
            object: nil
        )
    }

    private func ensureDefaultHotkeySettings() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "FileRingHotkeyMode") == nil {
            defaults.set("combination", forKey: "FileRingHotkeyMode")
        }
        if defaults.string(forKey: "FileRingModifierKey") == nil {
            defaults.set("control", forKey: "FileRingModifierKey")
        }
        if defaults.string(forKey: "FileRingKeyEquivalent") == nil {
            defaults.set("x", forKey: "FileRingKeyEquivalent")
        }
        if defaults.integer(forKey: "FileRingItemsPerSection") == 0 {
            defaults.set(6, forKey: "FileRingItemsPerSection")
        }
    }

    private func applyDockIconVisibility() {
        let hideDockIcon = UserDefaults.standard.bool(forKey: "FileRingHideDockIcon")

        if hideDockIcon {
            // Hide dock icon - app becomes accessory (status bar only)
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Show dock icon - app is regular
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.delegate = self
        hotkeyManager?.updateRegistration()
    }

    // MARK: - Status Bar Item
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use custom icon from Assets as template image
            // Icon should be 18x18 points (36x36 @2x) for proper status bar display
            if let customImage = NSImage(named: "StatusBarIcon") {
                // Set as template - system will handle sizing and color adaptation
                customImage.isTemplate = true
                button.image = customImage
            } else {
                // Fallback to SF Symbol
                button.image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "FileRing")
            }
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About FileRing", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked() {
        // Menu shown automatically
    }

    // MARK: - Popup Panel
    private func setupPopupPanel() {
        let panelView = DoubleRingPanelView()
        hostingView = NSHostingView(rootView: panelView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 900),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        // Use .popUpMenu level to allow panel to appear above menu bar
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false

        // Prevent system from constraining panel to screen bounds
        panel.isMovableByWindowBackground = false
        panel.isMovable = false

        popupPanel = panel
    }

    @objc private func showPopupPanel() {
        guard let panel = popupPanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size

        // Always center the panel on the mouse cursor
        // Allow clipping at screen edges to keep mouse in the center
        let newOrigin = CGPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2
        )

        let newFrame = NSRect(origin: newOrigin, size: panelSize)

        // Use setFrame with display: false to prevent system from constraining the frame
        panel.setFrame(newFrame, display: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.post(name: .refreshPanel, object: nil)
    }

    private func hidePopupPanel(openSelection: Bool = true) {
        if openSelection {
            NotificationCenter.default.post(name: .triggerHoveredItem, object: nil)
        }
        NotificationCenter.default.post(name: .hidePanel, object: nil)
        popupPanel?.orderOut(nil)
    }

    // MARK: - Local Event Monitor
    private func setupEscapeKeyMonitor() {
        // Local ESC key monitor for quick panel dismissal
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 == kVK_Escape

            if self?.popupPanel?.isVisible == true {
                self?.hidePopupPanel(openSelection: false)
                return nil
            }

            return event
        }
    }

    // MARK: - Onboarding Window
    private func showOnboardingIfNeeded() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "FileRingHasSeenOnboarding")

        if !hasSeenOnboarding {
            showOnboardingWindow()
        }
    }

    @objc private func handleShowOnboarding() {
        showOnboardingWindow()
    }

    private func showOnboardingWindow() {
        let onboardingView = OnboardingView { [weak self] in
            guard let self = self else { return }

            // Post notification to stop any active hotkey recording
            NotificationCenter.default.post(name: .hotkeyRecordingEnded, object: nil)

            // Delay closing to allow SwiftUI and event monitors to complete cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Make the window resign first responder to stop any active responders
                self.onboardingWindow?.makeFirstResponder(nil)

                // Additional delay to ensure responder cleanup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // First, remove the content view controller to break the SwiftUI connection
                    self.onboardingWindow?.contentViewController = nil
                    // Then close the window
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                }
            }
        }

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to FileRing"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window
    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.title = "Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false

            // Set minimum and maximum window size
            window.minSize = NSSize(width: 400, height: 400)
            window.maxSize = NSSize(width: 800, height: 1000)

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - About
    @objc private func showAbout() {
        let modifierKey = UserDefaults.standard.string(forKey: "FileRingModifierKey") ?? "option"
        let key = UserDefaults.standard.string(forKey: "FileRingKeyEquivalent") ?? "x"
        let comboDescription = formattedHotkeyDescription(modifierKey: modifierKey, key: key)

        let alert = NSAlert()
        alert.messageText = "FileRing"
        alert.informativeText = """
        Version 1.0

        Quick access to files and folders.

        How to use:
        • Hold \(comboDescription) to show panel
        • Move mouse to select files/folders
        • Release hotkey to open selected item
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Reset
    @objc private func resetAndShowOnboarding() {
        // Delete all authorizations
        let bookmarkKeys = BookmarkManager.shared.bookmarkKeys()
        for key in bookmarkKeys {
            BookmarkManager.shared.revokeAuthorization(forKey: key)
        }

        // Reset onboarding flag
        UserDefaults.standard.removeObject(forKey: "FileRingHasSeenOnboarding")

        // Show onboarding
        showOnboardingWindow()
    }

    // MARK: - Quit
    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helper
    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyManager?.cleanup()
    }

    private func formattedHotkeyDescription(modifierKey: String, key: String) -> String {
        let modifierSymbol: String
        switch modifierKey.lowercased() {
        case "option", "alt": modifierSymbol = "⌥ Option"
        case "command": modifierSymbol = "⌘ Command"
        case "control": modifierSymbol = "⌃ Control"
        case "shift": modifierSymbol = "⇧ Shift"
        case "none": modifierSymbol = ""
        default: modifierSymbol = "⌥ Option"
        }

        let keyDescription: String
        switch key.lowercased() {
        case "space": keyDescription = "Space"
        case "escape", "esc": keyDescription = "Esc"
        default: keyDescription = key.uppercased()
        }

        if modifierSymbol.isEmpty {
            return keyDescription
        }

        return "\(modifierSymbol) + \(keyDescription)"
    }
}

// MARK: - HotkeyManagerDelegate
extension MenuBarApp: HotkeyManagerDelegate {
    func hotkeyPressed() {
        showPopupPanel()
    }

    func hotkeyReleased() {
        hidePopupPanel()
    }
}
