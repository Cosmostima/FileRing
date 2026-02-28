import Testing
import CoreGraphics
@testable import FileRing

// Helper raw-value flag constructors to avoid CGEventFlags name ambiguity
private extension CGEventFlags {
    static let testMaskCommand  = CGEventFlags(rawValue: 0x100000)
    static let testMaskControl  = CGEventFlags(rawValue: 0x40000)
    static let testMaskShift    = CGEventFlags(rawValue: 0x20000)
    static let testMaskOption   = CGEventFlags(rawValue: 0x80000)
    static let testMaskCapsLock = CGEventFlags(rawValue: 0x10000)   // non-modifier
    static let testMaskFn       = CGEventFlags(rawValue: 0x800000)  // non-modifier
}

@Suite("HotkeyMatchingRules")
struct HotkeyMatchingTests {

    // MARK: - parseModifiers

    @Test("parseModifiers(['command']) returns command mask")
    func parseCommand() {
        #expect(HotkeyMatchingRules.parseModifiers(["command"]) == .testMaskCommand)
    }

    @Test("parseModifiers(['control']) returns control mask")
    func parseControl() {
        #expect(HotkeyMatchingRules.parseModifiers(["control"]) == .testMaskControl)
    }

    @Test("parseModifiers(['shift']) returns shift mask")
    func parseShift() {
        #expect(HotkeyMatchingRules.parseModifiers(["shift"]) == .testMaskShift)
    }

    @Test("parseModifiers(['option']) returns option mask")
    func parseOption() {
        #expect(HotkeyMatchingRules.parseModifiers(["option"]) == .testMaskOption)
    }

    @Test("parseModifiers(['alt']) returns option mask (alias)")
    func parseAlt() {
        #expect(HotkeyMatchingRules.parseModifiers(["alt"]) == .testMaskOption)
    }

    @Test("parseModifiers is case-insensitive")
    func parseCaseInsensitive() {
        #expect(HotkeyMatchingRules.parseModifiers(["COMMAND"]) == .testMaskCommand)
        #expect(HotkeyMatchingRules.parseModifiers(["Control"]) == .testMaskControl)
    }

    @Test("parseModifiers(['command','control']) returns combined mask")
    func parseCommandControl() {
        let result = HotkeyMatchingRules.parseModifiers(["command", "control"])
        let expected = CGEventFlags(rawValue: 0x100000 | 0x40000)
        #expect(result == expected)
    }

    @Test("parseModifiers(['command','shift']) returns combined mask")
    func parseCommandShift() {
        let result = HotkeyMatchingRules.parseModifiers(["command", "shift"])
        let expected = CGEventFlags(rawValue: 0x100000 | 0x20000)
        #expect(result == expected)
    }

    @Test("parseModifiers([]) returns empty flags")
    func parseEmpty() {
        #expect(HotkeyMatchingRules.parseModifiers([]) == CGEventFlags(rawValue: 0))
    }

    @Test("parseModifiers with unknown string returns empty")
    func parseUnknown() {
        #expect(HotkeyMatchingRules.parseModifiers(["unknown", "fn"]) == CGEventFlags(rawValue: 0))
    }

    // MARK: - modifiersMatch

    @Test("exact command match returns true")
    func exactCommandMatch() {
        #expect(HotkeyMatchingRules.modifiersMatch(.testMaskCommand, required: ["command"]))
    }

    @Test("exact control match returns true")
    func exactControlMatch() {
        #expect(HotkeyMatchingRules.modifiersMatch(.testMaskControl, required: ["control"]))
    }

    @Test("command+shift when only command required — false (exact match enforced)")
    func commandShiftWhenOnlyCommandRequired() {
        let flags = CGEventFlags(rawValue: 0x100000 | 0x20000) // command + shift
        #expect(!HotkeyMatchingRules.modifiersMatch(flags, required: ["command"]))
    }

    @Test("command+shift when command+shift required — true")
    func commandShiftBothRequired() {
        let flags = CGEventFlags(rawValue: 0x100000 | 0x20000)
        #expect(HotkeyMatchingRules.modifiersMatch(flags, required: ["command", "shift"]))
    }

    @Test("caps lock bit is filtered — does not affect command match")
    func capsLockFiltered() {
        // caps lock = 0x10000 (outside relevantModifierMask 0x1E0000)
        let flags = CGEventFlags(rawValue: 0x100000 | 0x10000) // command + caps lock
        #expect(HotkeyMatchingRules.modifiersMatch(flags, required: ["command"]))
    }

    @Test("fn key bit is filtered — does not affect control match")
    func fnFiltered() {
        let flags = CGEventFlags(rawValue: 0x40000 | 0x800000) // control + fn
        #expect(HotkeyMatchingRules.modifiersMatch(flags, required: ["control"]))
    }

    @Test("empty flags with empty required — true")
    func emptyFlagsEmptyRequired() {
        #expect(HotkeyMatchingRules.modifiersMatch(CGEventFlags(rawValue: 0), required: []))
    }

    @Test("command pressed but empty required — false")
    func commandPressedButNoneRequired() {
        #expect(!HotkeyMatchingRules.modifiersMatch(.testMaskCommand, required: []))
    }

    @Test("option match with 'option' key name")
    func optionMatch() {
        #expect(HotkeyMatchingRules.modifiersMatch(.testMaskOption, required: ["option"]))
    }

    @Test("option match with 'alt' key alias")
    func optionAltAlias() {
        #expect(HotkeyMatchingRules.modifiersMatch(.testMaskOption, required: ["alt"]))
    }

    // MARK: - isSingleModifierOnly

    @Test("only command pressed for command expected — true")
    func singleCommandOnly() {
        #expect(HotkeyMatchingRules.isSingleModifierOnly(.testMaskCommand, expected: ["command"]))
    }

    @Test("command+shift when only command expected — false")
    func commandShiftNotSingleCommand() {
        let flags = CGEventFlags(rawValue: 0x100000 | 0x20000)
        #expect(!HotkeyMatchingRules.isSingleModifierOnly(flags, expected: ["command"]))
    }

    @Test("option pressed for option expected — true")
    func singleOptionOnly() {
        #expect(HotkeyMatchingRules.isSingleModifierOnly(.testMaskOption, expected: ["option"]))
    }

    @Test("empty flags for empty expected — true")
    func emptyFlagsEmptyExpected() {
        #expect(HotkeyMatchingRules.isSingleModifierOnly(CGEventFlags(rawValue: 0), expected: []))
    }

    @Test("command pressed for empty expected — false")
    func commandPressedEmptyExpected() {
        #expect(!HotkeyMatchingRules.isSingleModifierOnly(.testMaskCommand, expected: []))
    }

    @Test("caps lock ignored for single modifier check")
    func capsLockIgnoredForSingleModifier() {
        let flags = CGEventFlags(rawValue: 0x100000 | 0x10000) // command + caps lock
        #expect(HotkeyMatchingRules.isSingleModifierOnly(flags, expected: ["command"]))
    }

    // MARK: - relevantModifierMask covers cmd, ctrl, shift, opt only

    @Test("relevantModifierMask equals union of four standard modifier raw values")
    func relevantMaskValue() {
        let expected: UInt64 = 0x100000 | 0x40000 | 0x20000 | 0x80000
        #expect(HotkeyMatchingRules.relevantModifierMask == expected)
    }
}
