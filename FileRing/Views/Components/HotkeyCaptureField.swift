//
//  HotkeyCaptureField.swift
//  FileRing
//
//  SwiftUI bridge for capturing keyboard shortcuts (modifier-only or modifier+key)
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyCaptureField: NSViewRepresentable {
    @Binding var modifierSetting: String
    @Binding var keySetting: String

    var onHotkeyChange: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = nsView
        nsView.displayText = context.coordinator.displayText()
    }

    static func dismantleNSView(_ nsView: HotkeyRecorderView, coordinator: Coordinator) {
        // Ensure recording is stopped when the view is being dismantled
        if coordinator.isCapturing {
            coordinator.stopCapturing()
        }
        nsView.window?.makeFirstResponder(nil)
    }

    // MARK: - Custom View
    final class HotkeyRecorderView: NSView {
        weak var coordinator: Coordinator?
        var displayText: String = "Click to record shortcut" {
            didSet {
                needsDisplay = true
            }
        }

        private var isRecording = false
        private var trackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupView()
        }

        private func setupView() {
            wantsLayer = true
            layer?.cornerRadius = 6.0
            layer?.borderWidth = 1.0
            layer?.borderColor = NSColor.separatorColor.cgColor
            updateTrackingAreas()
        }

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result {
                isRecording = true
                updateAppearance()
                coordinator?.startCapturing()
            }
            return result
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            updateAppearance()
            coordinator?.stopCapturing()
            return super.resignFirstResponder()
        }

        override func mouseDown(with event: NSEvent) {
            // Click animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                self.alphaValue = 0.7
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.1
                    self.alphaValue = 1.0
                })
            })

            window?.makeFirstResponder(self)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            // Draw background
            let backgroundColor = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor
            backgroundColor.setFill()
            bounds.fill()

            // Draw text
            let textColor = isRecording ? NSColor.controlAccentColor : NSColor.labelColor
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]

            let textSize = displayText.size(withAttributes: attributes)
            let textRect = NSRect(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            displayText.draw(in: textRect, withAttributes: attributes)
        }

        private func updateAppearance() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                layer?.borderWidth = isRecording ? 2.0 : 1.0
                layer?.borderColor = isRecording
                    ? NSColor.controlAccentColor.cgColor
                    : NSColor.separatorColor.cgColor
            }
            needsDisplay = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            let newTrackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            trackingArea = newTrackingArea
            addTrackingArea(newTrackingArea)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            if !isRecording {
                NSCursor.pointingHand.push()
            }
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            NSCursor.pop()
        }
    }

    // MARK: - Coordinator
    class Coordinator {
        var parent: HotkeyCaptureField
        weak var view: HotkeyRecorderView?
        var isCapturing = false
        private var eventMonitor: Any?
        private var currentModifiers: NSEvent.ModifierFlags = []
        private var lastModifierFlags: NSEvent.ModifierFlags = []
        private var capturedKeys: Set<String> = []  // Track all pressed keys
        private var maxKeyCombo: (modifiers: NSEvent.ModifierFlags, keys: Set<String>)?  // Peak combination

        init(parent: HotkeyCaptureField) {
            self.parent = parent
        }

        deinit {
            // Ensure we clean up the event monitor if the coordinator is deallocated
            stopCapturing()
        }

        func startCapturing() {
            isCapturing = true
            currentModifiers = []
            lastModifierFlags = []
            capturedKeys = []
            maxKeyCombo = nil
            NotificationCenter.default.post(name: .hotkeyRecordingStarted, object: nil)

            // Start local event monitor - now also monitor keyUp
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self = self, self.isCapturing else { return event }

                if event.type == .keyDown {
                    return self.handleKeyDown(event)
                } else if event.type == .keyUp {
                    return self.handleKeyUp(event)
                } else if event.type == .flagsChanged {
                    return self.handleFlagsChanged(event)
                }

                return event
            }

            triggerUIUpdate()
        }

        func stopCapturing() {
            isCapturing = false
            currentModifiers = []
            lastModifierFlags = []
            capturedKeys = []
            maxKeyCombo = nil

            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }

            NotificationCenter.default.post(name: .hotkeyRecordingEnded, object: nil)
            triggerUIUpdate()
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            // Allow Escape to cancel recording
            if event.keyCode == UInt16(kVK_Escape) {
                currentModifiers = []
                capturedKeys = []
                triggerUIUpdate()
                // Exit recording mode on Escape
                DispatchQueue.main.async {
                    self.view?.window?.makeFirstResponder(nil)
                }
                return nil
            }

            let modifiers = sanitizedModifiers(from: event.modifierFlags)

            guard let keyString = keyString(from: event) else {
                NSSound.beep()
                return nil
            }

            // Require at least one modifier for safety
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }

            // Add to captured keys
            capturedKeys.insert(keyString)
            currentModifiers = modifiers

            // Update the max combo (peak)
            updateMaxCombo()

            // Update display immediately
            triggerUIUpdateImmediate()

            return nil
        }

        private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
            guard let keyString = keyString(from: event) else {
                return nil
            }

            // Remove from captured keys
            let wasPresent = capturedKeys.remove(keyString) != nil

            // Detect key reduction - user is releasing keys
            if wasPresent && shouldCommit() {
                commitMaxCombo()
            }

            return nil
        }

        private func updateMaxCombo() {
            let totalKeys = capturedKeys.count + currentModifiers.rawValue.nonzeroBitCount

            let currentTotal: Int
            if let max = maxKeyCombo {
                currentTotal = max.keys.count + max.modifiers.rawValue.nonzeroBitCount
            } else {
                currentTotal = 0
            }

            // Update if current combo has more keys
            if totalKeys > currentTotal {
                maxKeyCombo = (modifiers: currentModifiers, keys: capturedKeys)
            }
        }

        private func shouldCommit() -> Bool {
            // Commit if all regular keys are released and we have captured something
            return capturedKeys.isEmpty && maxKeyCombo != nil
        }

        private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
            let modifiers = sanitizedModifiers(from: event.modifierFlags)

            let oldModifiers = currentModifiers
            currentModifiers = modifiers

            // Update UI immediately when modifiers change
            if oldModifiers != currentModifiers {
                updateMaxCombo()
                triggerUIUpdateImmediate()
            }

            // Detect if modifiers reduced (user releasing modifier keys)
            if modifiers.rawValue < oldModifiers.rawValue && shouldCommit() {
                commitMaxCombo()
            }

            return nil
        }

        private func commitMaxCombo() {
            guard isCapturing, let combo = maxKeyCombo else { return }

            // Validate: must have at least one modifier AND at least one regular key
            if combo.modifiers.isEmpty {
                NSSound.beep()
                showErrorAndRestore(message: "⚠️ Need modifier key")
                return
            }

            if combo.keys.isEmpty {
                NSSound.beep()
                showErrorAndRestore(message: "⚠️ Need a key (not just modifiers)")
                return
            }

            let modifierString = modifierString(from: combo.modifiers)

            // Join all captured keys (support multiple keys like ⌘CV)
            // Sort keys alphabetically for consistency
            let keysString = combo.keys.sorted().joined()

            applyHotkey(modifier: modifierString, key: keysString)

            // Exit recording mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.view?.window?.makeFirstResponder(nil)
            }
        }

        private func showErrorAndRestore(message: String) {
            // Flash error message
            view?.displayText = message

            // Restore after 1 second and exit recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.view?.displayText = self.displayText()
                self.view?.window?.makeFirstResponder(nil)
            }
        }

        private func applyHotkey(modifier: String, key: String) {
            DispatchQueue.main.async {
                self.parent.modifierSetting = modifier.isEmpty ? "none" : modifier
                self.parent.keySetting = key
                self.parent.onHotkeyChange(self.parent.modifierSetting, self.parent.keySetting)
            }
        }

        func displayText() -> String {
            // When actively capturing, show current state in real-time
            if isCapturing {
                let modSymbols = modifierSymbolsFromFlags(currentModifiers)

                // Show all currently pressed keys
                if !capturedKeys.isEmpty {
                    let keysDisplay = capturedKeys.sorted().map { keyDescription(for: $0) }.joined()
                    if !modSymbols.isEmpty {
                        return modSymbols.joined() + keysDisplay
                    }
                    return keysDisplay
                }

                // Otherwise just show current modifiers
                if !modSymbols.isEmpty {
                    return modSymbols.joined()
                }

                return "Recording..."
            }

            // Otherwise show the saved setting
            let modifierParts = modifierSettingParts(from: parent.modifierSetting)
            let modifierSymbols = modifierParts.map(symbol(for:))
            let keyDisplay = keyDescription(for: parent.keySetting)

            if modifierSymbols.isEmpty && keyDisplay.isEmpty {
                return "Click to record shortcut"
            }

            if modifierSymbols.isEmpty {
                return keyDisplay
            }

            if keyDisplay.isEmpty {
                return modifierSymbols.joined()
            }

            return modifierSymbols.joined() + keyDisplay
        }

        private func triggerUIUpdate() {
            // Direct immediate update to view
            view?.displayText = displayText()
        }

        private func triggerUIUpdateImmediate() {
            // Direct immediate update to view - no delay!
            view?.displayText = displayText()
        }

        private func modifierSymbolsFromFlags(_ flags: NSEvent.ModifierFlags) -> [String] {
            KeyCodeMapping.modifierSymbols(from: flags)
        }

        // MARK: - Helpers
        private func sanitizedModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
            var result: NSEvent.ModifierFlags = []
            if flags.contains(.command) { result.insert(.command) }
            if flags.contains(.control) { result.insert(.control) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.shift) { result.insert(.shift) }
            return result
        }

        private func modifierString(from flags: NSEvent.ModifierFlags) -> String {
            KeyCodeMapping.modifierString(from: flags)
        }

        private func modifierSettingParts(from setting: String) -> [String] {
            KeyCodeMapping.modifierSettingParts(from: setting)
        }

        private func symbol(for modifier: String) -> String {
            KeyCodeMapping.modifierSymbol(for: modifier)
        }

        private func keyDescription(for key: String) -> String {
            KeyCodeMapping.keyDescription(for: key)
        }

        private func keyString(from event: NSEvent) -> String? {
            KeyCodeMapping.keyString(from: event)
        }
    }
}
