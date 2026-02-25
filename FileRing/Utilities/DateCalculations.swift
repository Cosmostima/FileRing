//
//  DateCalculations.swift
//  FileRing
//
//  Created by Claude on 2026-01-15.
//  Safe date calculation utilities with overflow protection
//

import Foundation

extension Calendar {
    /// Safely add a time interval to a date with automatic fallback on overflow.
    ///
    /// This method prevents crashes from force unwrapping when date calculations overflow.
    /// If the calculation would result in a date beyond the calendar system's limits,
    /// it returns a boundary date (distantFuture or distantPast) instead of nil.
    ///
    /// - Parameters:
    ///   - component: The component to add (e.g., .day, .month, .year)
    ///   - value: The number of units to add (negative to subtract)
    ///   - date: The base date
    /// - Returns: The calculated date, or a boundary date if overflow occurs
    ///
    /// Example:
    /// ```swift
    /// // Instead of this (can crash):
    /// let date = Calendar.current.date(byAdding: .day, value: daysAgo, to: Date())!
    ///
    /// // Use this (safe):
    /// let date = Calendar.current.dateWithFallback(byAdding: .day, value: daysAgo, to: Date())
    /// ```
    func dateWithFallback(byAdding component: Component, value: Int, to date: Date) -> Date {
        // Attempt normal date calculation
        if let result = self.date(byAdding: component, value: value, to: date) {
            return result
        }

        // Calculation overflowed - return boundary date
        // Positive value -> future overflow, negative value -> past overflow
        if value > 0 {
            return Date.distantFuture
        } else {
            return Date.distantPast
        }
    }

    /// Safely add a time interval with optional validation of the value range.
    ///
    /// This variant clamps the value to a reasonable range before calculating,
    /// providing an additional layer of protection against extreme values.
    ///
    /// - Parameters:
    ///   - component: The component to add
    ///   - value: The number of units to add (will be clamped to ±10000)
    ///   - date: The base date
    /// - Returns: The calculated date
    func dateWithClampedValue(byAdding component: Component, value: Int, to date: Date) -> Date {
        // Clamp value to reasonable range to prevent overflow
        let clampedValue = max(-10000, min(10000, value))

        // This should never fail with clamped values, but use fallback just in case
        return dateWithFallback(byAdding: component, value: clampedValue, to: date)
    }
}
