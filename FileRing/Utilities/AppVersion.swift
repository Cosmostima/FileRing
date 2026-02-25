//
//  AppVersion.swift
//  FileRing
//
//  Version management and onboarding tracking
//

import Foundation

struct AppVersion {
    /// Current app version read from Bundle
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.7"
    }

    /// Version when user completed onboarding (nil if never completed)
    static var completedOnboardingVersion: String? {
        get {
            UserDefaults.standard.string(forKey: UserDefaultsKeys.onboardingCompletedVersion)
        }
        set {
            if let version = newValue {
                UserDefaults.standard.set(version, forKey: UserDefaultsKeys.onboardingCompletedVersion)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.onboardingCompletedVersion)
            }
        }
    }

    /// Check if onboarding should be shown
    /// Returns true if user has never completed onboarding OR if app version has changed
    static func shouldShowOnboarding() -> Bool {
        guard let completedVersion = completedOnboardingVersion else {
            return true // First time user
        }
        return completedVersion != current // Different version
    }

    /// Mark onboarding as completed for current version
    static func markOnboardingCompleted() {
        completedOnboardingVersion = current
    }
}
