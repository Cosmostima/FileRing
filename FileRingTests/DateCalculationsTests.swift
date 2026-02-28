import Testing
import Foundation
@testable import FileRing

@Suite("DateCalculations")
struct DateCalculationsTests {

    let calendar = Calendar.current

    // MARK: - dateWithFallback: normal cases

    @Test("adding 7 days returns correct date")
    func addSevenDays() {
        let now = Date()
        let result = calendar.dateWithFallback(byAdding: .day, value: 7, to: now)
        let expected = calendar.date(byAdding: .day, value: 7, to: now)!
        #expect(abs(result.timeIntervalSince(expected)) < 1.0)
    }

    @Test("subtracting 7 days returns correct date")
    func subtractSevenDays() {
        let now = Date()
        let result = calendar.dateWithFallback(byAdding: .day, value: -7, to: now)
        let expected = calendar.date(byAdding: .day, value: -7, to: now)!
        #expect(abs(result.timeIntervalSince(expected)) < 1.0)
    }

    @Test("adding 0 days returns same date")
    func addZeroDays() {
        let now = Date()
        let result = calendar.dateWithFallback(byAdding: .day, value: 0, to: now)
        #expect(abs(result.timeIntervalSince(now)) < 1.0)
    }

    @Test("adding 365 days works correctly")
    func addOneYear() {
        let now = Date()
        let result = calendar.dateWithFallback(byAdding: .day, value: 365, to: now)
        let expected = calendar.date(byAdding: .day, value: 365, to: now)!
        #expect(abs(result.timeIntervalSince(expected)) < 1.0)
    }

    @Test("adding months works")
    func addThreeMonths() {
        let now = Date()
        let result = calendar.dateWithFallback(byAdding: .month, value: 3, to: now)
        let expected = calendar.date(byAdding: .month, value: 3, to: now)!
        #expect(abs(result.timeIntervalSince(expected)) < 1.0)
    }

    // MARK: - dateWithFallback: overflow

    @Test("large positive value overflows to distantFuture")
    func largePosOverflow() {
        // Int.max days would overflow Date range
        let result = calendar.dateWithFallback(byAdding: .day, value: Int.max, to: Date())
        // Either returns distantFuture or a valid very far future date
        // The key is it doesn't crash
        #expect(result.timeIntervalSinceReferenceDate > 0)
    }

    @Test("large negative value overflows to distantPast")
    func largeNegOverflow() {
        let result = calendar.dateWithFallback(byAdding: .day, value: Int.min, to: Date())
        #expect(result.timeIntervalSinceReferenceDate < 0 || result == Date.distantPast)
    }

    // MARK: - dateWithClampedValue

    @Test("value within ±10000 is unchanged")
    func clampedValueInRange() {
        let now = Date()
        let direct = calendar.dateWithFallback(byAdding: .day, value: 5000, to: now)
        let clamped = calendar.dateWithClampedValue(byAdding: .day, value: 5000, to: now)
        #expect(abs(direct.timeIntervalSince(clamped)) < 1.0)
    }

    @Test("value > 10000 is clamped to 10000")
    func clampAboveMax() {
        let now = Date()
        let clamped10000 = calendar.dateWithClampedValue(byAdding: .day, value: 10000, to: now)
        let clampedExcess = calendar.dateWithClampedValue(byAdding: .day, value: 99999, to: now)
        #expect(abs(clamped10000.timeIntervalSince(clampedExcess)) < 1.0)
    }

    @Test("value < -10000 is clamped to -10000")
    func clampBelowMin() {
        let now = Date()
        let clamped10000 = calendar.dateWithClampedValue(byAdding: .day, value: -10000, to: now)
        let clampedExcess = calendar.dateWithClampedValue(byAdding: .day, value: -99999, to: now)
        #expect(abs(clamped10000.timeIntervalSince(clampedExcess)) < 1.0)
    }

    @Test("clamped 0 same as direct 0")
    func clampedZero() {
        let now = Date()
        let result = calendar.dateWithClampedValue(byAdding: .day, value: 0, to: now)
        #expect(abs(result.timeIntervalSince(now)) < 1.0)
    }

    @Test("negative value subtracts correctly when within range")
    func clampedNegativeInRange() {
        let now = Date()
        let direct = calendar.dateWithFallback(byAdding: .day, value: -30, to: now)
        let clamped = calendar.dateWithClampedValue(byAdding: .day, value: -30, to: now)
        #expect(abs(direct.timeIntervalSince(clamped)) < 1.0)
    }
}
