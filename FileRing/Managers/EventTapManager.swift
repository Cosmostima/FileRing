//
// EventTapManager.swift
// FileRing
//
// Extended CGEventTap-based manager with hotkey support
// Provides automatic recovery mechanism with sleep/wake handling
//

import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Hotkey Types

enum HotkeyState {
    case idle
    case pressed
}

struct HotkeyConfig: Equatable {
    let modifiers: [String]
    let keyCode: UInt32?

    nonisolated var isSingleModifier: Bool {
        return modifiers.count == 1 && modifiers.allSatisfy({
            ["command", "control", "option", "alt", "shift"].contains($0.lowercased())
        }) && keyCode == nil
    }
}

// HotkeyManagerDelegate protocol is defined in HotkeyManager.swift

enum EventTapType {
    case keyboard
    case modifierFlags
}

enum EventTapResult {
    case consume
    case forward
}

class EventTapManager {

    // MARK: - Properties

    // Properties accessed from background thread (nonisolated)
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var runLoop: CFRunLoop?
    nonisolated(unsafe) private var runLoopQueue: DispatchQueue?

    nonisolated(unsafe) private var eventType: EventTapType
    nonisolated(unsafe) private var callback: (CGEvent) -> EventTapResult

    nonisolated(unsafe) private var isRunning = false
    nonisolated(unsafe) private var stopSemaphore: DispatchSemaphore?

    nonisolated(unsafe) private var currentConfig: HotkeyConfig?
    nonisolated(unsafe) private var hotkeyState: HotkeyState = .idle
    nonisolated(unsafe) private var modifierFlags: CGEventFlags = []

    // Track if we consumed the keyDown event (to ensure keyDown/keyUp pairing)
    nonisolated(unsafe) private var didConsumeKeyDown = false

    // Properties accessed from main actor
    @MainActor weak var delegate: HotkeyManagerDelegate?

    // Recording state support (like HotkeyManager)
    nonisolated(unsafe) private var isRecordingHotkey = false

    // MARK: - Initialization

    init(type: EventTapType, callback: @escaping (CGEvent) -> EventTapResult) {
        self.eventType = type
        self.callback = callback
    }

    @MainActor convenience init() {
        self.init(type: .keyboard, callback: { event in
            return .forward
        })

        setupSleepWakeNotifications()
        setupSettingsObserver()
        setupRecordingObservers()
    }

    deinit {
        // Cleanup will be called automatically when the instance is deallocated
    }

    // MARK: - HotkeyManager Compatible API

    @MainActor func updateRegistration() {
        // Read configuration from UserDefaults
        let defaults = UserDefaults.standard
        let modifierSetting = defaults.string(forKey: "FileRingModifierKey") ?? "control"
        let keySetting = defaults.string(forKey: "FileRingKeyEquivalent") ?? "x"

        // Validate configuration
        guard !keySetting.isEmpty else {
            return
        }

        guard let keyCode = keyCodeFromString(keySetting) else {
            return
        }

        // Parse modifiers
        let modifiers = modifierSetting.split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        // Update hotkey configuration
        updateHotkey(modifiers: modifiers, keyCode: keyCode)
    }

    func cleanup() {
        stopAndWait()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sleep/Wake Notifications

    private func setupSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep() {
        // System is about to sleep: stop event tap
        stop()
    }

    @objc private func handleDidWake() {
        // System woke up: restart event tap
        // Delay a bit to ensure system is stable
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            self.start()
        }
    }

    // MARK: - Settings Observer

    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: Notification.Name("hotkeySettingChanged"),
            object: nil
        )
    }

    @MainActor @objc private func handleSettingsChanged() {
        updateRegistration()
    }

    // MARK: - Recording Observers

    private func setupRecordingObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStarted),
            name: Notification.Name("hotkeyRecordingStarted"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingEnded),
            name: Notification.Name("hotkeyRecordingEnded"),
            object: nil
        )
    }

    @objc private func handleRecordingStarted() {
        isRecordingHotkey = true
    }

    @objc private func handleRecordingEnded() {
        isRecordingHotkey = false
    }

    // MARK: - Hotkey Management

    func updateHotkey(modifiers: [String], keyCode: UInt32?) {
        let newConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)

        guard newConfig != currentConfig else {
            return
        }

        currentConfig = newConfig

        // Reset state when changing hotkey configuration
        didConsumeKeyDown = false
        hotkeyState = .idle  // CRITICAL: Reset to prevent hotkey from being stuck in .pressed state

        stop()
        start()
    }

    // MARK: - Permission Handling

    func checkPermission() -> Bool {
        let hasPermission = CGPreflightPostEventAccess()
        print("[EventTapManager] Post Event permission check: \(hasPermission)")
        return hasPermission
    }

    func requestPermission() async -> Bool {
        print("[EventTapManager] Requesting Post Event permission...")
        let granted = CGRequestPostEventAccess()
        print("[EventTapManager] Permission request result: \(granted)")
        return granted
    }

    // MARK: - Public Methods

    func start() {
        guard !isRunning else { return }

        let queue = DispatchQueue(label: "com.filering.eventtap.\(UUID().uuidString)", qos: .userInteractive)
        self.runLoopQueue = queue

        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupEventTap()
        }
    }

    func stop() {
        guard isRunning else { return }

        // Reset state when stopping to prevent stale state issues
        // E.g., if user is holding hotkey when stop() is called, and then start() is called later
        didConsumeKeyDown = false
        hotkeyState = .idle  // CRITICAL: Reset to prevent hotkey from being stuck in .pressed state

        if let runLoop = runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as CFTypeRef) { [weak self] in
                self?.disableEventTap()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }

        isRunning = false
    }

    func stopAndWait() {
        guard isRunning else { return }

        // Reset state when stopping (same reason as stop())
        didConsumeKeyDown = false
        hotkeyState = .idle  // CRITICAL: Reset to prevent hotkey from being stuck in .pressed state

        let semaphore = DispatchSemaphore(value: 0)
        self.stopSemaphore = semaphore

        if let runLoop = runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as CFTypeRef) { [weak self] in
                self?.disableEventTap()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else {
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 1.0)

        isRunning = false
        self.stopSemaphore = nil
    }

    // MARK: - Private Methods

    nonisolated private func setupEventTap() {
        let eventsOfInterest: CGEventMask

        if let config = currentConfig {
            if config.isSingleModifier {
                eventsOfInterest = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            } else {
                eventsOfInterest = CGEventMask(
                    (1 << CGEventType.keyDown.rawValue) |
                    (1 << CGEventType.keyUp.rawValue) |
                    (1 << CGEventType.flagsChanged.rawValue)
                )
            }
        } else {
            eventsOfInterest = CGEventMask(
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)
            )
        }

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[EventTapManager] Failed to create event tap - Post Event permission required (Accessibility)")
            stopSemaphore?.signal()
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let currentRunLoop = CFRunLoopGetCurrent()
        self.runLoop = currentRunLoop

        CFRunLoopAddSource(currentRunLoop, source, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        CFRunLoopRun()

        cleanupResources()

        stopSemaphore?.signal()
    }

    nonisolated private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let eventTap = self.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        // Update modifier flags when they change
        if type == .flagsChanged {
            modifierFlags = event.flags
        }

        if isHotkeyEvent(event) {
            handleHotkeyEvent(event)

            // Track keyDown/keyUp state to ensure proper event pairing
            if type == .keyDown {
                didConsumeKeyDown = true
            } else if type == .keyUp {
                didConsumeKeyDown = false
            }

            // Return nil to consume the event and prevent system beep
            return nil
        }

        let result = callback(event)

        switch result {
        case .consume:
            return nil
        case .forward:
            return Unmanaged.passUnretained(event)
        }
    }

    nonisolated private func isHotkeyEvent(_ event: CGEvent) -> Bool {
        guard let config = currentConfig else {
            return false
        }

        let eventType = event.type

        if config.isSingleModifier {
            return eventType == .flagsChanged && isSingleModifierPressed(modifiers: config.modifiers)
        }

        // Check for both keyDown and keyUp events
        if eventType == .keyDown || eventType == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Int(config.keyCode ?? 0) {
                if eventType == .keyUp {
                    // CRITICAL FIX: Only consume keyUp if we consumed the corresponding keyDown
                    // This prevents intercepting keyUp events for keys we didn't intercept keyDown for
                    // Without this check, pressing 'x' (without control) would have keyUp consumed
                    // even though keyDown was not, breaking keyboard input in other apps
                    return didConsumeKeyDown
                }
                // For keyDown, check modifiers
                return modifiersMatch(event.flags, modifiers: config.modifiers)
            }
        }

        return false
    }

    nonisolated private func handleHotkeyEvent(_ event: CGEvent) {
        // Suspend hotkey handling during recording (like HotkeyManager)
        guard !isRecordingHotkey else { return }

        let eventType = event.type

        if eventType == .keyDown || eventType == .flagsChanged {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only trigger if state is idle (prevent key repeat from triggering multiple times)
                guard self.hotkeyState == .idle else { return }
                self.hotkeyState = .pressed
                self.delegate?.hotkeyPressed()
            }
        } else if eventType == .keyUp {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.hotkeyState == .pressed else { return }
                self.hotkeyState = .idle
                self.delegate?.hotkeyReleased()
            }
        }
    }

    nonisolated private func isSingleModifierPressed(modifiers: [String]) -> Bool {
        let requiredFlags = parseModifiers(modifiers)

        // CRITICAL FIX: Filter out non-modifier flags (caps lock, fn, etc.)
        // Same logic as modifiersMatch to ensure consistency
        // Otherwise, Caps Lock would prevent single modifier hotkeys from working
        let relevantMask: UInt64 = 0x100000 | 0x40000 | 0x20000 | 0x80000  // cmd|ctrl|shift|opt
        let actualFlags = CGEventFlags(rawValue: modifierFlags.rawValue & relevantMask)

        return actualFlags == requiredFlags
    }

    nonisolated private func modifiersMatch(_ flags: CGEventFlags, modifiers: [String]) -> Bool {
        // CRITICAL FIX: Use EXACT match, not subset match
        // We must ensure ONLY the specified modifiers are pressed, no more, no less
        // Otherwise, hotkey like "control+x" would also trigger on "control+shift+x"
        // which could interfere with other apps' shortcuts

        let requiredFlags = parseModifiers(modifiers)

        // Extract only the modifier flags we care about (command, control, shift, option)
        // Ignore other flags like caps lock, function key, etc.
        let relevantMask: UInt64 = 0x100000 | 0x40000 | 0x20000 | 0x80000  // cmd|ctrl|shift|opt
        let actualFlags = CGEventFlags(rawValue: flags.rawValue & relevantMask)

        // Exact match required
        return actualFlags == requiredFlags
    }

    nonisolated private func parseModifiers(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []

        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command":
                flags.insert(.maskCommand)
            case "control":
                flags.insert(.maskControl)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            default:
                break
            }
        }

        return flags
    }

    nonisolated private func disableEventTap() {
        if let eventTap = self.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    nonisolated private func cleanupResources() {
        if let runLoop = runLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            self.runLoopSource = nil
        }

        if let tap = self.eventTap {
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }

        self.runLoop = nil
        self.runLoopQueue = nil

        // Reset state flags
        didConsumeKeyDown = false
        hotkeyState = .idle  // CRITICAL: Reset to prevent hotkey from being stuck in .pressed state
    }

    // MARK: - Key Code Helper

    nonisolated private func keyCodeFromString(_ key: String) -> UInt32? {
        let lowercased = key.trimmingCharacters(in: .whitespaces).lowercased()

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
}

// MARK: - CGEventFlags Extensions

extension CGEventFlags {
    nonisolated static var maskCommand: CGEventFlags { CGEventFlags(rawValue: 0x100000) }
    nonisolated static var maskControl: CGEventFlags { CGEventFlags(rawValue: 0x40000) }
    nonisolated static var maskShift: CGEventFlags { CGEventFlags(rawValue: 0x20000) }
    nonisolated static var maskAlternate: CGEventFlags { CGEventFlags(rawValue: 0x80000) }
}

// MARK: - Delegate Protocol

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
    func hotkeyReleased()
}
