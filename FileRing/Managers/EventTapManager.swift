//
//  EventTapManager.swift
//  PopUp
//
//  Low-level event monitoring manager based on CGEventTap
//  Provides automatic recovery mechanism, no manual handling needed for system sleep/wake
//

import Foundation
import CoreGraphics
import Carbon

/// Event type
enum EventTapType {
    case keyboard       // Keyboard events (keyDown, keyUp)
    case modifierFlags  // Modifier flag change events (flagsChanged)
}

/// Event callback result
enum EventTapResult {
    case consume    // Consume event, don't pass to other apps
    case forward    // Forward event
}

/// EventTap manager
class EventTapManager {
    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var runLoopQueue: DispatchQueue?

    private let eventType: EventTapType
    private let callback: (CGEvent) -> EventTapResult

    private var isRunning = false
    private var stopSemaphore: DispatchSemaphore?

    // MARK: - Initialization

    /// Initialize event listener
    /// - Parameters:
    ///   - type: Type of events to monitor
    ///   - callback: Event callback, returns whether to consume the event
    init(type: EventTapType, callback: @escaping (CGEvent) -> EventTapResult) {
        self.eventType = type
        self.callback = callback
    }

    deinit {
        stopAndWait()
        cleanup()
    }

    // MARK: - Public Methods

    /// Start event monitoring
    func start() {
        guard !isRunning else {
            return
        }

        // Create dedicated queue to run RunLoop
        let queue = DispatchQueue(label: "com.popup.eventtap.\(UUID().uuidString)", qos: .userInteractive)
        self.runLoopQueue = queue

        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupEventTap()
        }
    }

    /// Stop event monitoring (blocking until fully stopped)
    func stopAndWait() {
        guard isRunning else { return }

        let semaphore = DispatchSemaphore(value: 0)
        self.stopSemaphore = semaphore

        if let runLoop = runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as CFTypeRef) { [weak self] in
                self?.disableEventTap()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else {
            // If runLoop not yet created, signal immediately
            semaphore.signal()
        }

        // Wait for RunLoop to fully stop (max 1 second)
        _ = semaphore.wait(timeout: .now() + 1.0)

        isRunning = false
        self.stopSemaphore = nil
    }

    /// Non-blocking stop (for deinit and similar scenarios)
    func stop() {
        guard isRunning else { return }

        if let runLoop = runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as CFTypeRef) { [weak self] in
                self?.disableEventTap()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }

        isRunning = false
    }

    // MARK: - Private Methods

    /// Setup event tap
    private func setupEventTap() {
        // Determine which event types to monitor
        let eventsOfInterest: CGEventMask
        switch eventType {
        case .keyboard:
            eventsOfInterest = CGEventMask(
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)
            )
        case .modifierFlags:
            eventsOfInterest = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        }

        // Create event callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        // Create event tap
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: selfPtr
        ) else {
            stopSemaphore?.signal()
            return
        }

        self.eventTap = tap

        // Create RunLoop source
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        // Get current RunLoop
        let currentRunLoop = CFRunLoopGetCurrent()
        self.runLoop = currentRunLoop

        // Add to RunLoop
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)

        // Enable event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        // Run RunLoop
        CFRunLoopRun()

        // Cleanup resources after RunLoop stops
        cleanup()

        // Notify waiters
        stopSemaphore?.signal()
    }

    /// Handle event
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        // Critical: Handle case when event tap is disabled (triggered after system sleep)
        if type == .tapDisabledByTimeout {
            if let eventTap = self.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        // Call user callback
        let result = callback(event)

        switch result {
        case .consume:
            // Return null event to consume - system handles the original event properly
            // Using passUnretained on the original event signals consumption without memory leak
            return Unmanaged.passUnretained(event)
        case .forward:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Disable event tap
    private func disableEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    /// Cleanup resources
    private func cleanup() {
        if let runLoop = runLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            self.runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }

        self.runLoop = nil
        self.runLoopQueue = nil
    }
}
