//
//  LaunchAtLoginManager.swift
//  FileRing
//
//  Created on 2025-11-16.
//

import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager {

    /// Returns the current launch at login status from the system
    /// This reads directly from SMAppService to ensure accuracy with system state
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enable or disable launch at login
    /// - Parameter enabled: Whether to enable launch at login
    /// - Throws: Error if registration/unregistration fails
    func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .enabled {
                // Already enabled, nothing to do
                return
            }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered {
                // Already disabled, nothing to do
                return
            }
            try SMAppService.mainApp.unregister()
        }
    }
}
