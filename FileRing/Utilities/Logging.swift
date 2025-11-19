//
//  Logging.swift
//  FileRing
//
//  Created by Gemini on 2025/11/18.
//

import Foundation
import os.log

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!

    /// The main log for general app information.
    static let main = OSLog(subsystem: subsystem, category: "Main")

    /// The log for performance-related measurements, intended for use with Instruments.
    static let pointsOfInterest = OSLog(subsystem: subsystem, category: .pointsOfInterest)
}
