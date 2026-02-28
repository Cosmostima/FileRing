import Testing
import Foundation
import AppKit
import Carbon.HIToolbox
@testable import FileRing

@Suite("KeyCodeMapping")
struct KeyCodeMappingTests {

    // MARK: - keyCode(from:)

    @Test("keyCode for 'a' is kVK_ANSI_A")
    func keyCodeForA() {
        #expect(KeyCodeMapping.keyCode(from: "a") == UInt32(kVK_ANSI_A))
    }

    @Test("keyCode for 'z' is kVK_ANSI_Z")
    func keyCodeForZ() {
        #expect(KeyCodeMapping.keyCode(from: "z") == UInt32(kVK_ANSI_Z))
    }

    @Test("keyCode for 'space' is kVK_Space")
    func keyCodeForSpace() {
        #expect(KeyCodeMapping.keyCode(from: "space") == UInt32(kVK_Space))
    }

    @Test("keyCode for 'esc' is kVK_Escape")
    func keyCodeForEsc() {
        #expect(KeyCodeMapping.keyCode(from: "esc") == UInt32(kVK_Escape))
    }

    @Test("keyCode for 'escape' is kVK_Escape")
    func keyCodeForEscape() {
        #expect(KeyCodeMapping.keyCode(from: "escape") == UInt32(kVK_Escape))
    }

    @Test("keyCode for digits 0-9 is non-nil")
    func keyCodeForDigits() {
        for d in 0...9 {
            #expect(KeyCodeMapping.keyCode(from: "\(d)") != nil, "digit \(d) should have a keyCode")
        }
    }

    @Test("keyCode for invalid string returns nil")
    func keyCodeForInvalid() {
        #expect(KeyCodeMapping.keyCode(from: "INVALID") == nil)
        #expect(KeyCodeMapping.keyCode(from: "F1") == nil)
        #expect(KeyCodeMapping.keyCode(from: "") == nil)
    }

    @Test("keyCode is case-insensitive (uppercase A maps same as lowercase a)")
    func keyCodeCaseInsensitive() {
        #expect(KeyCodeMapping.keyCode(from: "A") == KeyCodeMapping.keyCode(from: "a"))
    }

    // MARK: - keyString(from:) — bidirectional round-trip

    @Test("keyString(from keyCode) returns original key for all letters")
    func keyStringRoundTripLetters() {
        for ch in "abcdefghijklmnopqrstuvwxyz" {
            let s = String(ch)
            if let code = KeyCodeMapping.keyCode(from: s),
               let back = KeyCodeMapping.keyString(from: UInt16(code)) {
                #expect(back == s, "Round-trip failed for '\(s)': got '\(back)'")
            }
        }
    }

    @Test("keyString(from keyCode) returns original key for digits")
    func keyStringRoundTripDigits() {
        for d in 0...9 {
            let s = "\(d)"
            if let code = KeyCodeMapping.keyCode(from: s),
               let back = KeyCodeMapping.keyString(from: UInt16(code)) {
                #expect(back == s, "Round-trip failed for '\(s)'")
            }
        }
    }

    @Test("keyString for unknown keyCode returns nil")
    func keyStringForUnknownCode() {
        // 0xFFFF is not a valid key code
        #expect(KeyCodeMapping.keyString(from: UInt16(0xFFFF)) == nil)
    }

    // MARK: - modifierSymbol(for:)

    @Test("modifierSymbol for 'command' is ⌘")
    func modifierSymbolCommand() {
        #expect(KeyCodeMapping.modifierSymbol(for: "command") == "⌘")
    }

    @Test("modifierSymbol for 'control' is ⌃")
    func modifierSymbolControl() {
        #expect(KeyCodeMapping.modifierSymbol(for: "control") == "⌃")
    }

    @Test("modifierSymbol for 'option' is ⌥")
    func modifierSymbolOption() {
        #expect(KeyCodeMapping.modifierSymbol(for: "option") == "⌥")
    }

    @Test("modifierSymbol for 'alt' is ⌥ (alias)")
    func modifierSymbolAlt() {
        #expect(KeyCodeMapping.modifierSymbol(for: "alt") == "⌥")
    }

    @Test("modifierSymbol for 'shift' is ⇧")
    func modifierSymbolShift() {
        #expect(KeyCodeMapping.modifierSymbol(for: "shift") == "⇧")
    }

    @Test("modifierSymbol is case-insensitive")
    func modifierSymbolCaseInsensitive() {
        #expect(KeyCodeMapping.modifierSymbol(for: "COMMAND") == "⌘")
        #expect(KeyCodeMapping.modifierSymbol(for: "Control") == "⌃")
    }

    // MARK: - modifierString(from:)

    @Test("modifierString with .command flag returns 'command'")
    func modifierStringCommand() {
        let flags: NSEvent.ModifierFlags = [.command]
        #expect(KeyCodeMapping.modifierString(from: flags) == "command")
    }

    @Test("modifierString with .command + .shift returns 'command+shift'")
    func modifierStringCommandShift() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let result = KeyCodeMapping.modifierString(from: flags)
        #expect(result == "command+shift")
    }

    @Test("modifierString with .control + .option returns 'control+option'")
    func modifierStringControlOption() {
        let flags: NSEvent.ModifierFlags = [.control, .option]
        let result = KeyCodeMapping.modifierString(from: flags)
        #expect(result == "control+option")
    }

    @Test("modifierString with empty flags returns empty string")
    func modifierStringEmpty() {
        #expect(KeyCodeMapping.modifierString(from: []) == "")
    }

    // MARK: - modifierSettingParts(from:)

    @Test("modifierSettingParts from empty string returns []")
    func settingPartsEmpty() {
        #expect(KeyCodeMapping.modifierSettingParts(from: "") == [])
    }

    @Test("modifierSettingParts from 'none' returns []")
    func settingPartsNone() {
        #expect(KeyCodeMapping.modifierSettingParts(from: "none") == [])
    }

    @Test("modifierSettingParts from 'command' returns ['command']")
    func settingPartsSingle() {
        #expect(KeyCodeMapping.modifierSettingParts(from: "command") == ["command"])
    }

    @Test("modifierSettingParts from 'command+control' returns two parts")
    func settingPartsTwo() {
        let parts = KeyCodeMapping.modifierSettingParts(from: "command+control")
        #expect(parts == ["command", "control"])
    }

    // MARK: - formattedHotkeyDescription

    @Test("formatted description with modifier and key")
    func formattedDescriptionWithModifierAndKey() {
        let result = KeyCodeMapping.formattedHotkeyDescription(modifierKey: "command", key: "space")
        #expect(result.contains("⌘") || result.contains("Command"))
        #expect(result.contains("Space"))
    }

    @Test("formatted description with 'none' modifier returns only key")
    func formattedDescriptionNoneModifier() {
        let result = KeyCodeMapping.formattedHotkeyDescription(modifierKey: "none", key: "a")
        #expect(result == "A")
    }

    @Test("keyDescription for 'space' returns 'Space'")
    func keyDescriptionSpace() {
        #expect(KeyCodeMapping.keyDescription(for: "space") == "Space")
    }

    @Test("keyDescription for 'a' returns 'A'")
    func keyDescriptionLetter() {
        #expect(KeyCodeMapping.keyDescription(for: "a") == "A")
    }

    @Test("keyDescription for empty returns empty")
    func keyDescriptionEmpty() {
        #expect(KeyCodeMapping.keyDescription(for: "") == "")
    }
}
