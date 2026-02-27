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
import os

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

// HotkeyManagerDelegate protocol is defined below

enum EventTapType {
    case keyboard
    case modifierFlags
}

enum EventTapResult {
    case consume
    case forward
}

class EventTapManager {

    // MARK: - Shared State (cross-thread, protected by lock)

    private struct SharedState {
        var currentConfig: HotkeyConfig?
        var isRunning: Bool = false
        var isRecordingHotkey: Bool = false
        var didConsumeKeyDown: Bool = false
        var stopSemaphore: DispatchSemaphore?
    }

    private let sharedState = OSAllocatedUnfairLock(initialState: SharedState())

    // MARK: - Background-thread-only Properties

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var runLoop: CFRunLoop?
    nonisolated(unsafe) private var runLoopQueue: DispatchQueue?
    nonisolated(unsafe) private var modifierFlags: CGEventFlags = []
    nonisolated(unsafe) private var eventType: EventTapType
    nonisolated(unsafe) private var callback: (CGEvent) -> EventTapResult

    // MARK: - MainActor-only Properties

    @MainActor weak var delegate: HotkeyManagerDelegate?
    @MainActor private var hotkeyState: HotkeyState = .idle

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
        let modifierSetting = defaults.string(forKey: UserDefaultsKeys.modifierKey) ?? "control"
        let keySetting = defaults.string(forKey: UserDefaultsKeys.keyEquivalent) ?? "x"

        // Validate configuration
        guard !keySetting.isEmpty else {
            return
        }

        guard let keyCode = KeyCodeMapping.keyCode(from: keySetting) else {
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
        sharedState.withLock { state in
            state.isRecordingHotkey = true
        }
    }

    @objc private func handleRecordingEnded() {
        sharedState.withLock { state in
            state.isRecordingHotkey = false
        }
    }

    // MARK: - Hotkey Management

    func updateHotkey(modifiers: [String], keyCode: UInt32?) {
        let newConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)

        let shouldUpdate = sharedState.withLock { state -> Bool in
            guard newConfig != state.currentConfig else {
                return false
            }
            state.currentConfig = newConfig
            return true
        }

        guard shouldUpdate else { return }

        // Reset state when changing hotkey configuration
        sharedState.withLock { $0.didConsumeKeyDown = false }
        Task { @MainActor in
            self.hotkeyState = .idle
        }

        stopAndWait()
        start()
    }

    // MARK: - Permission Handling

    func checkPermission() -> Bool {
        let hasPermission = AccessibilityHelper.checkPermission()
        Logger.main.info("Accessibility permission check: \(hasPermission ? "granted" : "denied")")
        return hasPermission
    }

    func requestPermission() async -> Bool {
        Logger.main.info("Requesting Accessibility permission via system prompt...")
        let granted = AccessibilityHelper.requestPermission()
        Logger.main.info("Permission request result: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - Public Methods

    func start() {
        let didClaim = sharedState.withLock { state -> Bool in
            guard !state.isRunning else { return false }
            state.isRunning = true
            return true
        }
        guard didClaim else { return }

        let queue = DispatchQueue(label: "com.filering.eventtap.\(UUID().uuidString)", qos: .userInteractive)
        self.runLoopQueue = queue

        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupEventTap()
        }
    }

    func stop() {
        let wasRunning = sharedState.withLock { state -> Bool in
            guard state.isRunning else { return false }
            state.isRunning = false
            return true
        }
        guard wasRunning else { return }

        // Reset state when stopping to prevent stale state issues
        sharedState.withLock { $0.didConsumeKeyDown = false }
        Task { @MainActor in
            self.hotkeyState = .idle
        }

        if let runLoop = runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as CFTypeRef) { [weak self] in
                self?.disableEventTap()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func stopAndWait() {
        let wasRunning = sharedState.withLock { $0.isRunning }
        guard wasRunning else { return }

        // Reset state when stopping
        sharedState.withLock { $0.didConsumeKeyDown = false }
        Task { @MainActor in
            self.hotkeyState = .idle
        }

        let semaphore = DispatchSemaphore(value: 0)
        sharedState.withLock { state in
            state.stopSemaphore = semaphore
            state.isRunning = false
        }

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

        sharedState.withLock { state in
            state.stopSemaphore = nil
        }
    }

    // MARK: - Private Methods

    nonisolated private func setupEventTap() {
        let eventsOfInterest: CGEventMask

        let config = sharedState.withLock { $0.currentConfig }

        if let config = config {
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
            // Use os_log (free function) to avoid @MainActor inference from Logger.main static property.
            os_log(.error, "Failed to create event tap - Accessibility permission required")
            sharedState.withLock { state in
                state.isRunning = false
                _ = state.stopSemaphore?.signal()
            }
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let currentRunLoop = CFRunLoopGetCurrent()
        self.runLoop = currentRunLoop

        CFRunLoopAddSource(currentRunLoop, source, .commonModes)

        // Check if stop() was called between start() claiming isRunning and now.
        // If so, don't enter the run loop — just clean up.
        let stillRunning = sharedState.withLock { $0.isRunning }
        guard stillRunning else {
            cleanupResources()
            sharedState.withLock { state in _ = state.stopSemaphore?.signal() }
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)

        CFRunLoopRun()

        // RunLoop exited (either via stop() or unexpectedly).
        // Ensure isRunning is false so start() can be called again.
        cleanupResources()

        sharedState.withLock { state in
            state.isRunning = false
            _ = state.stopSemaphore?.signal()
        }
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
                sharedState.withLock { $0.didConsumeKeyDown = true }
            } else if type == .keyUp {
                sharedState.withLock { $0.didConsumeKeyDown = false }
            }

            // Return nil to consume the event and prevent system beep
            return nil
        }

        let result = self.callback(event)

        switch result {
        case .consume:
            return nil
        case .forward:
            return Unmanaged.passUnretained(event)
        }
    }

    nonisolated private func isHotkeyEvent(_ event: CGEvent) -> Bool {
        guard let config = sharedState.withLock({ $0.currentConfig }) else {
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
                    return sharedState.withLock { $0.didConsumeKeyDown }
                }
                // For keyDown, check modifiers
                return modifiersMatch(event.flags, modifiers: config.modifiers)
            }
        }

        return false
    }

    nonisolated private func handleHotkeyEvent(_ event: CGEvent) {
        // Suspend hotkey handling during recording
        let isRecording = sharedState.withLock { $0.isRecordingHotkey }
        guard !isRecording else { return }

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
        let relevantMask: UInt64 = 0x100000 | 0x40000 | 0x20000 | 0x80000  // cmd|ctrl|shift|opt
        let actualFlags = CGEventFlags(rawValue: modifierFlags.rawValue & relevantMask)

        return actualFlags == requiredFlags
    }

    nonisolated private func modifiersMatch(_ flags: CGEventFlags, modifiers: [String]) -> Bool {
        // CRITICAL FIX: Use EXACT match, not subset match
        let requiredFlags = parseModifiers(modifiers)

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
        sharedState.withLock { $0.didConsumeKeyDown = false }
        Task { @MainActor in
            self.hotkeyState = .idle
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
