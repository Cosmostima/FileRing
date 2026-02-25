//
//  PanelSection.swift
//  FileRing
//
//  Created by Claude on 30/10/2025.
//

import SwiftUI

enum PanelSection: Int, CaseIterable, Identifiable, Hashable {
    case fileRecentlyOpened = 0
    case fileRecentlySaved
    case fileFrequentlyOpened
    case folderRecentlyOpened
    case folderRecentlySaved
    case folderFrequentlyOpened

    enum Side {
        case left
        case right
    }

    static let angleSpan: Double = 60

    var id: Self { self }

    var contentType: ContentType {
        switch self {
        case .fileRecentlyOpened, .fileRecentlySaved, .fileFrequentlyOpened:
            return .files
        case .folderRecentlyOpened, .folderRecentlySaved, .folderFrequentlyOpened:
            return .folders
        }
    }

    var category: CategoryType {
        switch self {
        case .fileRecentlyOpened, .folderRecentlyOpened:
            return .recentlyOpened
        case .fileRecentlySaved, .folderRecentlySaved:
            return .recentlySaved
        case .fileFrequentlyOpened, .folderFrequentlyOpened:
            return .frequentlyOpened
        }
    }

    var title: String {
        switch self {
        case .fileRecentlyOpened: return "Files · Recently Opened"
        case .fileRecentlySaved: return "Files · Recently Saved"
        case .fileFrequentlyOpened: return "Files · Frequently Used"
        case .folderRecentlyOpened: return "Folders · Recently Opened"
        case .folderRecentlySaved: return "Folders · Recently Saved"
        case .folderFrequentlyOpened: return "Folders · Frequently Used"
        }
    }

    var baseColor: Color {
        contentType == .files ? .green : .blue
    }

    var symbolName: String {
        switch self {
        case .fileRecentlyOpened, .folderRecentlyOpened:
            return "clock"
        case .fileRecentlySaved, .folderRecentlySaved:
            return "arrow.down.doc"
        case .fileFrequentlyOpened, .folderFrequentlyOpened:
            return "star"
        }
    }

    var side: Side {
        let radians = centerAngle * .pi / 180.0
        return cos(radians) >= 0 ? .right : .left
    }

    var centerAngle: Double {
        normalizedDegrees(Double(rawValue) * PanelSection.angleSpan - 60.0)
    }

    var startAngle: Double {
        normalizedDegrees(centerAngle - PanelSection.angleSpan / 2)
    }

    var midAngle: Double {
        normalizedDegrees(startAngle + PanelSection.angleSpan / 2)
    }

    func contains(_ angle: Double) -> Bool {
        let normalized = normalizedDegrees(angle)
        let start = normalizedDegrees(startAngle)
        let end = normalizedDegrees(startAngle + PanelSection.angleSpan)

        if start <= end {
            return normalized >= start && normalized < end
        } else {
            return normalized >= start || normalized < end
        }
    }

    static func section(for angle: Double) -> PanelSection? {
        let normalized = normalizedDegrees(angle)
        return allCases.first { $0.contains(normalized) }
    }
}

@inline(__always)
func normalizedDegrees(_ angle: Double) -> Double {
    var result = angle.truncatingRemainder(dividingBy: 360)
    if result < 0 { result += 360 }
    return result
}
