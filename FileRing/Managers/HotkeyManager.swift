//
//  HotkeyManager.swift
//  PopUp
//
//  Manages global hotkey registration and monitoring for FileRing
//

import AppKit
import Carbon

private let popupHotKeySignature: UInt32 = 0x504f5055 // 'POPU'

@MainActor
class HotkeyManager {
    // MARK: - Properties
    weak var delegate: HotkeyManagerDelegate?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?

    private var appliedConfiguration: HotkeyConfiguration?
    private var isRecordingHotkey = false

    // MARK: - Initialization
    init() {
        setupHotkeyChangeObserver()
        setupRecordingObservers()
    }

    // MARK: - Public Methods
    func updateRegistration() {
        let defaults = UserDefaults.standard
        var modifierSetting = defaults.string(forKey: UserDefaultsKeys.modifierKey) ?? "control"
        var keySetting = defaults.string(forKey: UserDefaultsKeys.keyEquivalent) ?? "x"

        // Always require valid key
        if keySetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keySetting = "x"
            defaults.set(keySetting, forKey: UserDefaultsKeys.keyEquivalent)
        } else if keyCode(for: keySetting) == nil {
            keySetting = "x"
            defaults.set(keySetting, forKey: UserDefaultsKeys.keyEquivalent)
        }

        // Ensure valid modifier
        if modifierSetting == "none" || modifierSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modifierSetting = "control"
            defaults.set(modifierSetting, forKey: UserDefaultsKeys.modifierKey)
        }

        let configuration = HotkeyConfiguration(
            modifier: modifierSetting,
            key: keySetting
        )

        guard configuration != appliedConfiguration else {
            return
        }

        appliedConfiguration = configuration

        unregisterCombinationHotkey()
        registerCombinationHotkey(modifier: configuration.modifier, key: configuration.key)
    }

    func cleanup() {
        unregisterCombinationHotkey()
        if let handler = hotKeyEventHandlerRef {
            RemoveEventHandler(handler)
            hotKeyEventHandlerRef = nil
        }
        appliedConfiguration = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup Helpers
    private func setupHotkeyChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChange),
            name: .hotkeySettingChanged,
            object: nil
        )
    }

    private func setupRecordingObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStarted),
            name: .hotkeyRecordingStarted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingEnded),
            name: .hotkeyRecordingEnded,
            object: nil
        )
    }

    @objc private func handleHotkeyChange() {
        updateRegistration()
    }

    @objc private func handleRecordingStarted() {
        isRecordingHotkey = true
    }

    @objc private func handleRecordingEnded() {
        isRecordingHotkey = false
    }

    // MARK: - Combination Mode (Carbon)
    private func registerCombinationHotkey(modifier: String, key: String) {
        guard let keyCode = keyCode(for: key) else {
            return
        }

        installHotKeyHandlerIfNeeded()

        let modifiers = carbonModifierFlags(from: modifier)
        let hotKeyID = EventHotKeyID(signature: popupHotKeySignature, id: 1)
        _ = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterCombinationHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyEventHandlerRef == nil else { return }

        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            // Suspend hotkey handling during recording
            guard !manager.isRecordingHotkey else { return noErr }

            let kind = UInt32(GetEventKind(event))

            if kind == UInt32(kEventHotKeyPressed) {
                Task { @MainActor in
                    manager.delegate?.hotkeyPressed()
                }
            } else if kind == UInt32(kEventHotKeyReleased) {
                Task { @MainActor in
                    manager.delegate?.hotkeyReleased()
                }
            }

            return noErr
        }

        _ = eventTypes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }

            return InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                Int(buffer.count),
                baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &hotKeyEventHandlerRef
            )
        }
    }

    // MARK: - Helpers

    private func carbonModifierFlags(from setting: String) -> UInt32 {
        if setting == "none" {
            return 0
        }

        let parts = setting
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        var flags: UInt32 = 0

        for part in parts {
            switch part {
            case "command":
                flags |= UInt32(cmdKey)
            case "control":
                flags |= UInt32(controlKey)
            case "shift":
                flags |= UInt32(shiftKey)
            case "option", "alt":
                flags |= UInt32(optionKey)
            default:
                break
            }
        }

        if flags == 0 {
            flags = UInt32(optionKey)
        }

        return flags
    }

    private func keyCode(for key: String) -> UInt32? {
        let lowercased = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch lowercased {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "space": return UInt32(kVK_Space)
        case "escape", "esc": return UInt32(kVK_Escape)
        default: return nil
        }
    }

    private func modifierDescription(modifier: String, key: String) -> String {
        let symbol: String
        switch modifier.lowercased() {
        case "command": symbol = "⌘"
        case "control": symbol = "⌃"
        case "shift": symbol = "⇧"
        case "option", "alt": symbol = "⌥"
        case "none": symbol = ""
        default: symbol = modifier
        }

        let keyDescription: String
        switch key.lowercased() {
        case "space": keyDescription = "Space"
        case "escape", "esc": keyDescription = "Esc"
        default: keyDescription = key.uppercased()
        }

        return symbol.isEmpty ? keyDescription : "\(symbol)+\(keyDescription)"
    }
}

// MARK: - Supporting Types
private struct HotkeyConfiguration: Equatable {
    let modifier: String
    let key: String
}

// MARK: - Delegate Protocol
@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
    func hotkeyReleased()
}
