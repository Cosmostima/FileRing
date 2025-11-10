//
//  FileRingApp.swift
//  FileRing
//
//  Created by Cosmos on 30/10/2025.
//

import SwiftUI

@main
struct FileRingApp: App {
    @NSApplicationDelegateAdaptor(MenuBarApp.self) var appDelegate

    var body: some Scene {
        // Empty scene - we manage all windows manually in MenuBarApp
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
