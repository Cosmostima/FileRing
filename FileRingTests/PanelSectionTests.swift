import Testing
import Foundation
@testable import FileRing

// MARK: - normalizedDegrees (free function)

@Suite("normalizedDegrees")
struct NormalizedDegreesTests {

    @Test("zero stays zero")
    func zeroStaysZero() {
        #expect(normalizedDegrees(0) == 0.0)
    }

    @Test("360 wraps to 0")
    func threeSixtyWrapsToZero() {
        #expect(normalizedDegrees(360) == 0.0)
    }

    @Test("370 wraps to 10")
    func threeSeventy() {
        #expect(normalizedDegrees(370) == 10.0)
    }

    @Test("negative -60 wraps to 300")
    func negativeMinusSixty() {
        #expect(normalizedDegrees(-60) == 300.0)
    }

    @Test("negative -1 wraps to 359")
    func negativeMinusOne() {
        #expect(normalizedDegrees(-1) == 359.0)
    }

    @Test("720 wraps to 0")
    func sevenTwenty() {
        #expect(normalizedDegrees(720) == 0.0)
    }

    @Test("181 stays 181")
    func oneEightyOne() {
        #expect(normalizedDegrees(181) == 181.0)
    }
}

// MARK: - PanelSection

@Suite("PanelSection")
struct PanelSectionTests {

    // MARK: - centerAngle for all 6 sections
    // Formula: rawValue * 60 - 60, normalized

    @Test("fileRecentlyOpened centerAngle = 300")
    func fileRecentlyOpenedAngle() {
        #expect(PanelSection.fileRecentlyOpened.centerAngle == 300.0)
    }

    @Test("fileRecentlySaved centerAngle = 0")
    func fileRecentlySavedAngle() {
        #expect(PanelSection.fileRecentlySaved.centerAngle == 0.0)
    }

    @Test("fileFrequentlyOpened centerAngle = 60")
    func fileFrequentlyOpenedAngle() {
        #expect(PanelSection.fileFrequentlyOpened.centerAngle == 60.0)
    }

    @Test("folderRecentlyOpened centerAngle = 120")
    func folderRecentlyOpenedAngle() {
        #expect(PanelSection.folderRecentlyOpened.centerAngle == 120.0)
    }

    @Test("folderRecentlySaved centerAngle = 180")
    func folderRecentlySavedAngle() {
        #expect(PanelSection.folderRecentlySaved.centerAngle == 180.0)
    }

    @Test("folderFrequentlyOpened centerAngle = 240")
    func folderFrequentlyOpenedAngle() {
        #expect(PanelSection.folderFrequentlyOpened.centerAngle == 240.0)
    }

    // MARK: - section(for:) reverse lookup

    @Test("section(for:0) returns fileRecentlySaved")
    func sectionForZero() {
        #expect(PanelSection.section(for: 0) == .fileRecentlySaved)
    }

    @Test("section(for:60) returns fileFrequentlyOpened")
    func sectionForSixty() {
        #expect(PanelSection.section(for: 60) == .fileFrequentlyOpened)
    }

    @Test("section(for:120) returns folderRecentlyOpened")
    func sectionForOneTwenty() {
        #expect(PanelSection.section(for: 120) == .folderRecentlyOpened)
    }

    @Test("section(for:180) returns folderRecentlySaved")
    func sectionForOneEighty() {
        #expect(PanelSection.section(for: 180) == .folderRecentlySaved)
    }

    @Test("section(for:240) returns folderFrequentlyOpened")
    func sectionForTwoForty() {
        #expect(PanelSection.section(for: 240) == .folderFrequentlyOpened)
    }

    @Test("section(for:300) returns fileRecentlyOpened")
    func sectionForThreeHundred() {
        #expect(PanelSection.section(for: 300) == .fileRecentlyOpened)
    }

    @Test("section(for:359) returns fileRecentlySaved (spans 330–30°, wraps through 0)")
    func sectionForThreeFiftyNine() {
        // fileRecentlySaved: centerAngle=0°, startAngle=330°, endAngle=30°
        // 359° >= 330° → inside the wrap-around span
        #expect(PanelSection.section(for: 359) == .fileRecentlySaved)
    }

    @Test("section(for:-60) = section(for:300) = fileRecentlyOpened")
    func sectionForNegative() {
        #expect(PanelSection.section(for: -60) == .fileRecentlyOpened)
    }

    // MARK: - contains boundary conditions

    @Test("section contains its exact center angle")
    func containsCenterAngle() {
        for section in PanelSection.allCases {
            #expect(section.contains(section.centerAngle), "Section \(section) should contain its centerAngle")
        }
    }

    @Test("section contains its startAngle (inclusive)")
    func containsStartAngle() {
        for section in PanelSection.allCases {
            #expect(section.contains(section.startAngle), "Section \(section) should include startAngle")
        }
    }

    @Test("section does NOT contain the next section's startAngle")
    func doesNotContainNextSectionStart() {
        for section in PanelSection.allCases {
            let nextRawValue = (section.rawValue + 1) % PanelSection.allCases.count
            if let next = PanelSection(rawValue: nextRawValue) {
                #expect(!section.contains(next.startAngle), "\(section) should not contain \(next).startAngle")
            }
        }
    }

    // MARK: - all sections partition 360°

    @Test("every integer degree 0-359 belongs to exactly one section")
    func fullCoverageWithoutOverlap() {
        for angle in 0..<360 {
            let matches = PanelSection.allCases.filter { $0.contains(Double(angle)) }
            #expect(matches.count == 1, "Angle \(angle)° should belong to exactly 1 section, got \(matches.count)")
        }
    }

    // MARK: - contentType and category

    @Test("file sections map to .files contentType")
    func fileSectionContentType() {
        #expect(PanelSection.fileRecentlyOpened.contentType == .files)
        #expect(PanelSection.fileRecentlySaved.contentType == .files)
        #expect(PanelSection.fileFrequentlyOpened.contentType == .files)
    }

    @Test("folder sections map to .folders contentType")
    func folderSectionContentType() {
        #expect(PanelSection.folderRecentlyOpened.contentType == .folders)
        #expect(PanelSection.folderRecentlySaved.contentType == .folders)
        #expect(PanelSection.folderFrequentlyOpened.contentType == .folders)
    }

    @Test("recentlyOpened sections have .recentlyOpened category")
    func recentlyOpenedCategory() {
        #expect(PanelSection.fileRecentlyOpened.category == .recentlyOpened)
        #expect(PanelSection.folderRecentlyOpened.category == .recentlyOpened)
    }

    @Test("recentlySaved sections have .recentlySaved category")
    func recentlySavedCategory() {
        #expect(PanelSection.fileRecentlySaved.category == .recentlySaved)
        #expect(PanelSection.folderRecentlySaved.category == .recentlySaved)
    }

    @Test("frequentlyOpened sections have .frequentlyOpened category")
    func frequentlyOpenedCategory() {
        #expect(PanelSection.fileFrequentlyOpened.category == .frequentlyOpened)
        #expect(PanelSection.folderFrequentlyOpened.category == .frequentlyOpened)
    }

    // MARK: - side

    @Test("fileRecentlySaved (0°) side is right")
    func fileRecentlySavedSideRight() {
        #expect(PanelSection.fileRecentlySaved.side == .right)
    }

    @Test("fileFrequentlyOpened (60°) side is right")
    func fileFrequentlyOpenedSideRight() {
        #expect(PanelSection.fileFrequentlyOpened.side == .right)
    }

    @Test("folderRecentlyOpened (120°) side is left")
    func folderRecentlyOpenedSideLeft() {
        #expect(PanelSection.folderRecentlyOpened.side == .left)
    }

    @Test("folderRecentlySaved (180°) side is left")
    func folderRecentlySavedSideLeft() {
        #expect(PanelSection.folderRecentlySaved.side == .left)
    }

    @Test("folderFrequentlyOpened (240°) side is left")
    func folderFrequentlyOpenedSideLeft() {
        #expect(PanelSection.folderFrequentlyOpened.side == .left)
    }

    @Test("fileRecentlyOpened (300°) side is right")
    func fileRecentlyOpenedSideRight() {
        #expect(PanelSection.fileRecentlyOpened.side == .right)
    }

    // MARK: - allCases count

    @Test("allCases has 6 sections")
    func allCasesCount() {
        #expect(PanelSection.allCases.count == 6)
    }
}
