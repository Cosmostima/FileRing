//
//  UserDefaultsKeys.swift
//  FileRing
//
//  Centralized UserDefaults keys to avoid magic strings
//

import Foundation

enum UserDefaultsKeys {
    static let hotkeyMode = "FileRingHotkeyMode"
    static let modifierKey = "FileRingModifierKey"
    static let keyEquivalent = "FileRingKeyEquivalent"
    static let itemsPerSection = "FileRingItemsPerSection"
    static let hideDockIcon = "FileRingHideDockIcon"
    static let onboardingCompletedVersion = "FileRingOnboardingCompletedVersion"
}
