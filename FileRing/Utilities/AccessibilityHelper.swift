//
//  AccessibilityHelper.swift
//  FileRing
//
//  Shared accessibility permission and app lifecycle utilities
//

import Foundation
import AppKit
import ApplicationServices

@MainActor
enum AccessibilityHelper {

    /// Check current accessibility permission status without prompting.
    /// Uses AXIsProcessTrustedWithOptions which is more reliable than
    /// CGPreflightPostEventAccess for reflecting post-grant state on macOS 13+.
    static func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility permission, prompting the user via system dialog.
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to the Accessibility privacy pane.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Restart the application by launching a new instance and terminating the current one.
    static func restartApp() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
