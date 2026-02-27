//
//  Logging.swift
//  FileRing
//
//  Created by Gemini on 2025/11/18.
//

import Foundation
import os.log
import os

extension OSLog {
    /// Subsystem identifier for logging.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.filering.FileRing"

    /// The main log for general app information.
    static let main = OSLog(subsystem: subsystem, category: "Main")

    /// The log for performance-related measurements, intended for use with Instruments.
    static let pointsOfInterest = OSLog(subsystem: subsystem, category: .pointsOfInterest)
}

extension Logger {
    /// The main logger for general app information.
    /// Uses a string literal (not Bundle.main) so it is never inferred as @MainActor,
    /// making it safe to call from nonisolated contexts such as background event-tap threads.
    static let main = Logger(subsystem: "com.cosmos.FileRing", category: "Main")
}
