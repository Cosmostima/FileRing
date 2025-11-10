//
//  HoverState.swift
//  PopUp
//
//  Created by Claude on 30/10/2025.
//

import Foundation

// MARK: - Hover State
struct HoverState {
    var openFilePath: String?
    var copyFilePath: String?
    var copyMode: ClipboardMode?

    mutating func clear() {
        openFilePath = nil
        copyFilePath = nil
        copyMode = nil
    }

    mutating func setOpen(_ path: String) {
        openFilePath = path
        copyFilePath = nil
        copyMode = nil
    }

    mutating func setCopy(_ path: String, mode: ClipboardMode) {
        openFilePath = nil
        copyFilePath = path
        copyMode = mode
    }
}
