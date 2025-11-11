//
//  Notifications.swift
//  PopUp
//
//  Created by Claude on 30/10/2025.
//

import Foundation

// MARK: - Notification Names
extension Notification.Name {
    static let refreshPanel = Notification.Name("refreshPanel")
    static let triggerHoveredItem = Notification.Name("triggerHoveredItem")
    static let hidePanel = Notification.Name("hidePanel")
    static let hotkeySettingChanged = Notification.Name("hotkeySettingChanged")
    static let hotkeyRecordingStarted = Notification.Name("hotkeyRecordingStarted")
    static let hotkeyRecordingEnded = Notification.Name("hotkeyRecordingEnded")
    static let spotlightConfigChanged = Notification.Name("spotlightConfigChanged")
}
