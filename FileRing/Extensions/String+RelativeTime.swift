//
//  String+RelativeTime.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import Foundation

// MARK: - Shared DateFormatter

extension DateFormatter {
    /// Thread-safe cached formatter for Spotlight date strings (macOS 10.9+).
    static let spotlightDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()
}

// MARK: - Shared RelativeDateTimeFormatter

extension RelativeDateTimeFormatter {
    /// Thread-safe cached formatter for abbreviated relative times.
    static let abbreviated: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Time Formatting Utilities
extension String {
    func relativeTimeString() -> String? {
        guard let date = DateFormatter.spotlightDateFormatter.date(from: self) else {
            return nil
        }
        return RelativeDateTimeFormatter.abbreviated.localizedString(for: date, relativeTo: Date())
    }
}
