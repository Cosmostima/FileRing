//
//  AccessibilityHelper.swift
//  FileRing
//
//  Shared accessibility permission and app lifecycle utilities
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum AccessibilityHelper {

    /// Set once when permission is confirmed during this app session. Never reset.
    /// All views read this flag to skip redundant re-checks.
    private(set) static var permissionConfirmedThisSession = false

    /// Mark accessibility permission as confirmed for the lifetime of this process.
    static func markPermissionConfirmed() {
        permissionConfirmedThisSession = true
    }

    /// Check current accessibility permission status without prompting.
    /// Uses AXIsProcessTrustedWithOptions — kept for requestPermission() triggering only.
    static func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Check accessibility permission using CGEvent.tapCreate as the authoritative test.
    /// More reliable than AXIsProcessTrustedWithOptions for sandboxed apps where TCC
    /// may not reflect the granted state until the next app launch.
    /// Uses .defaultTap (same mode as the real EventTap) to probe Accessibility permission —
    /// NOT .listenOnly, which would probe Input Monitoring instead (a different TCC category).
    /// The tap is immediately invalidated and never enabled, so no events are intercepted.
    nonisolated static func checkPermissionViaTap() -> Bool {
        let callback: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
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
