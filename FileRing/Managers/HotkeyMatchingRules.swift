import CoreGraphics

/// Pure functions extracted from EventTapManager for independent testability.
/// These implement the critical hotkey matching logic with exact modifier flag matching.
enum HotkeyMatchingRules {

    /// Mask for the four standard modifier keys only (command, control, shift, option).
    /// Filters out caps lock, fn, numpad, and other non-modifier flag bits.
    nonisolated static let relevantModifierMask: UInt64 = 0x100000 | 0x40000 | 0x20000 | 0x80000

    // MARK: - parseModifiers

    /// Convert an array of modifier name strings to a CGEventFlags bitmask.
    ///
    /// Supports: "command", "control", "shift", "option", "alt" (case-insensitive).
    /// Unknown strings are silently ignored.
    nonisolated static func parseModifiers(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command":
                flags.insert(CGEventFlags(rawValue: 0x100000))
            case "control":
                flags.insert(CGEventFlags(rawValue: 0x40000))
            case "shift":
                flags.insert(CGEventFlags(rawValue: 0x20000))
            case "option", "alt":
                flags.insert(CGEventFlags(rawValue: 0x80000))
            default:
                break
            }
        }
        return flags
    }

    // MARK: - modifiersMatch

    /// Returns true if `flags` contains EXACTLY the required modifiers — no more, no less.
    ///
    /// This is the "CRITICAL FIX" behaviour: we do an exact match against the relevant
    /// modifier bits, not a subset match.  This prevents e.g. Cmd+Shift from accidentally
    /// triggering a hotkey configured for Cmd only.
    ///
    /// Non-modifier bits (caps lock, fn, etc.) are masked out before comparison.
    nonisolated static func modifiersMatch(_ flags: CGEventFlags, required modifiers: [String]) -> Bool {
        let required = parseModifiers(modifiers)
        let actual = CGEventFlags(rawValue: flags.rawValue & relevantModifierMask)
        return actual == required
    }

    // MARK: - isSingleModifierOnly

    /// Returns true if `flags` has exactly the specified single-modifier key pressed and
    /// no other relevant modifier keys.
    ///
    /// - Parameters:
    ///   - flags: The current CGEventFlags (e.g. from a flagsChanged event).
    ///   - modifiers: The expected modifier keys (should be a single element for single-modifier hotkeys).
    nonisolated static func isSingleModifierOnly(_ flags: CGEventFlags, expected modifiers: [String]) -> Bool {
        let required = parseModifiers(modifiers)
        let actual = CGEventFlags(rawValue: flags.rawValue & relevantModifierMask)
        return actual == required
    }
}
