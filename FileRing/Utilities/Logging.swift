//
//  Logging.swift
//  FileRing
//
//  Created by Gemini on 2025/11/18.
//

import Foundation
import os.log

extension OSLog {
    /// Subsystem identifier for logging.
    /// Falls back to a default if bundle identifier is unavailable (e.g., in test environments).
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.filering.FileRing"

    /// The main log for general app information.
    static let main = OSLog(subsystem: subsystem, category: "Main")

    /// The log for performance-related measurements, intended for use with Instruments.
    static let pointsOfInterest = OSLog(subsystem: subsystem, category: .pointsOfInterest)
}
