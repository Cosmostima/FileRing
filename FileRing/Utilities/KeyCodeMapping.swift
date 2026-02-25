//
//  KeyCodeMapping.swift
//  FileRing
//
//  Shared key code mapping and modifier symbol utilities
//

import Foundation
import Carbon.HIToolbox
import AppKit

enum KeyCodeMapping {

    // MARK: - Key String to Key Code

    /// Convert a key string (e.g., "a", "space") to a Carbon virtual key code.
    static func keyCode(from key: String) -> UInt32? {
        let lowercased = key.trimmingCharacters(in: .whitespaces).lowercased()
        return stringToKeyCode[lowercased]
    }

    /// Convert an NSEvent key code to a key string.
    static func keyString(from keyCode: UInt16) -> String? {
        return keyCodeToString[keyCode]
    }

    /// Convert an NSEvent to a key string (tries characters first, then keyCode fallback).
    static func keyString(from event: NSEvent) -> String? {
        if let characters = event.charactersIgnoringModifiers,
           !characters.isEmpty {
            let char = characters.lowercased()
            if char.range(of: "^[a-z0-9]$", options: .regularExpression) != nil {
                return char
            }
        }
        return keyString(from: event.keyCode)
    }

    // MARK: - Modifier Symbols

    /// Convert a modifier name string (e.g., "command") to its symbol (e.g., "⌘").
    static func modifierSymbol(for modifier: String) -> String {
        switch modifier.lowercased() {
        case "command": return "⌘"
        case "control": return "⌃"
        case "option", "alt": return "⌥"
        case "shift": return "⇧"
        default: return modifier.capitalized
        }
    }

    /// Convert a modifier name to a human-readable label (e.g., "⌥ Option").
    static func modifierLabel(for modifier: String) -> String {
        switch modifier.lowercased() {
        case "option", "alt": return "⌥ Option"
        case "command": return "⌘ Command"
        case "control": return "⌃ Control"
        case "shift": return "⇧ Shift"
        case "none": return ""
        default: return "⌥ Option"
        }
    }

    /// Format a human-readable key description (e.g., "space" -> "Space", "a" -> "A").
    static func keyDescription(for key: String) -> String {
        switch key.lowercased() {
        case "", " ": return ""
        case "space": return "Space"
        case "escape", "esc": return "Esc"
        default: return key.uppercased()
        }
    }

    /// Format a full hotkey description (e.g., "⌃ Control + X").
    static func formattedHotkeyDescription(modifierKey: String, key: String) -> String {
        let modifierLabel = modifierLabel(for: modifierKey)
        let keyDesc = keyDescription(for: key)

        if modifierLabel.isEmpty {
            return keyDesc
        }
        return "\(modifierLabel) + \(keyDesc)"
    }

    /// Extract modifier symbols from NSEvent.ModifierFlags.
    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// Convert NSEvent.ModifierFlags to a modifier string (e.g., "command+control").
    static func modifierString(from flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.command) { parts.append("command") }
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        return parts.joined(separator: "+")
    }

    /// Split a modifier setting string (e.g., "command+control") into parts.
    static func modifierSettingParts(from setting: String) -> [String] {
        guard !setting.isEmpty, setting != "none" else { return [] }
        return setting.split(separator: "+").map { String($0) }
    }

    // MARK: - Private Mappings

    private static let stringToKeyCode: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
    ]

    private static let keyCodeToString: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (key, code) in stringToKeyCode where key != "esc" {
            map[UInt16(code)] = key
        }
        return map
    }()
}
