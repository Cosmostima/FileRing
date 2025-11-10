//
//  String+RelativeTime.swift
//  PopUp
//
//  Created by Cosmos on 30/10/2025.
//

import Foundation

// MARK: - Time Formatting Utilities
extension String {
    func relativeTimeString() -> String? {
        // Parse format: "2025-10-31 07:29:56 +0000"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        guard let date = formatter.date(from: self) else {
            return nil
        }

        return Self.formatRelativeTime(from: date)
    }

    private static func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(date))

        if seconds < 0 {
            return "Just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else if seconds < 2592000 {  // 30 days
            let days = seconds / 86400
            return "\(days)d ago"
        } else if seconds < 31536000 {  // 365 days
            let months = seconds / 2592000
            return "\(months)mo ago"
        } else {
            let years = seconds / 31536000
            return "\(years)y ago"
        }
    }
}
