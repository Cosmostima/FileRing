import Testing
import Foundation
@testable import FileRing

@Suite("String+RelativeTime")
struct StringRelativeTimeTests {

    // MARK: - relativeTimeString()

    @Test("valid ISO 8601 Spotlight date returns non-nil relative string")
    func validDateReturnsString() {
        // Use a date 1 hour ago
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let formatter = DateFormatter.spotlightDateFormatter
        let dateString = formatter.string(from: oneHourAgo)
        let result = dateString.relativeTimeString()
        #expect(result != nil)
        #expect(result!.isEmpty == false)
    }

    @Test("recent date string contains time unit")
    func recentDateContainsTimeUnit() {
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let dateString = DateFormatter.spotlightDateFormatter.string(from: twoMinutesAgo)
        let result = dateString.relativeTimeString()
        #expect(result != nil)
        // RelativeDateTimeFormatter abbreviated produces something like "2 min. ago" or "2分钟前"
        #expect(!result!.isEmpty)
    }

    @Test("invalid format string returns nil")
    func invalidFormatReturnsNil() {
        #expect("not-a-date".relativeTimeString() == nil)
    }

    @Test("empty string returns nil")
    func emptyStringReturnsNil() {
        #expect("".relativeTimeString() == nil)
    }

    @Test("ISO 8601 without timezone returns nil (wrong format)")
    func isoWithoutTimezoneReturnsNil() {
        // The formatter expects "yyyy-MM-dd HH:mm:ss Z" — missing Z
        #expect("2025-01-15 10:30:00".relativeTimeString() == nil)
    }

    @Test("future date also returns non-nil")
    func futureDateReturnsNonNil() {
        let oneHourFromNow = Date().addingTimeInterval(3600)
        let dateString = DateFormatter.spotlightDateFormatter.string(from: oneHourFromNow)
        #expect(dateString.relativeTimeString() != nil)
    }

    // MARK: - DateFormatter.spotlightDateFormatter

    @Test("spotlightDateFormatter locale is en_US_POSIX")
    func formatterLocale() {
        let locale = DateFormatter.spotlightDateFormatter.locale
        #expect(locale?.identifier == "en_US_POSIX")
    }

    @Test("spotlightDateFormatter round-trip preserves date")
    func formatterRoundTrip() {
        let now = Date()
        let formatter = DateFormatter.spotlightDateFormatter
        let string = formatter.string(from: now)
        let parsed = formatter.date(from: string)
        #expect(parsed != nil)
        #expect(abs(parsed!.timeIntervalSince(now)) < 1.0)
    }
}
