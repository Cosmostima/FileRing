//
//  DoubleRingViewModel.swift
//  PopUp
//
//  Created by Cosmos on 30/10/2025.
//

import Foundation
import Combine

@MainActor
final class DoubleRingViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .fileRecentlySaved
    @Published private(set) var isInitialLoading = true
    @Published private(set) var isLoadingSection = false
    @Published private(set) var error: String?
    @Published private(set) var fileItems: [FileItem] = []
    @Published private(set) var folderItems: [FolderItem] = []

    private let fileSystemService: FileSystemService
    private var cachedFiles: [PanelSection: [FileItem]] = [:]
    private var cachedFolders: [PanelSection: [FolderItem]] = [:]
    private var preloadTask: Task<Void, Never>?

    init(fileSystemService: FileSystemService? = nil) {
        self.fileSystemService = fileSystemService ?? FileSystemService()
    }

    private var itemsLimit: Int {
        let limit = UserDefaults.standard.integer(forKey: UserDefaultsKeys.itemsPerSection)
        return limit > 0 ? limit : 6
    }

    var currentItemCount: Int {
        selectedSection.contentType == .files ? fileItems.count : folderItems.count
    }

    func refresh() async {
        startNewSession()
        await loadInitialSection()
        await preloadRemainingSections()
    }

    func switchToSection(_ section: PanelSection) {
        guard selectedSection != section else { return }
        selectedSection = section

        if applyCachedData(for: section) {
            error = nil
            isLoadingSection = false
        } else {
            Task { await load(section: section, updateUI: true) }
        }
    }

    func open(path: String) async throws {
        try await fileSystemService.open(path: path)
    }

    func copyToClipboard(path: String, mode: ClipboardMode) async {
        do {
            try await fileSystemService.copyToClipboard(path: path, mode: mode)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func handlePanelHide() {
        startNewSession()
    }
}

// MARK: - Session Management
private extension DoubleRingViewModel {
    func startNewSession() {
        cancelPreload()
        cachedFiles.removeAll()
        cachedFolders.removeAll()
        selectedSection = .fileRecentlySaved
        error = nil
        fileItems = []
        folderItems = []
        isInitialLoading = true
        isLoadingSection = false
    }

    func loadInitialSection() async {
        await load(section: selectedSection, updateUI: true)
        isInitialLoading = false
    }

    func preloadRemainingSections() async {
        cancelPreload()
        preloadTask = Task {
            let sections = PanelSection.allCases.filter { $0 != selectedSection }
            for section in sections {
                if Task.isCancelled { return }
                if cachedSnapshot(for: section) != nil { continue }
                await load(section: section, updateUI: false)
            }
        }
    }

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
    }
}

// MARK: - Loading Helpers
private extension DoubleRingViewModel {
    func load(section: PanelSection, updateUI: Bool) async {
        if updateUI {
            isLoadingSection = true
            error = nil
        }

        do {
            let shouldUpdateUI = section == selectedSection
            switch section.contentType {
            case .files:
                let items = try await fileSystemService.fetchFiles(for: section.category, limit: itemsLimit)
                cachedFiles[section] = items
                if shouldUpdateUI {
                    fileItems = items
                    folderItems = []
                    isLoadingSection = false
                }
            case .folders:
                let items = try await fileSystemService.fetchFolders(for: section.category, limit: itemsLimit)
                cachedFolders[section] = items
                if shouldUpdateUI {
                    folderItems = items
                    fileItems = []
                    isLoadingSection = false
                }
            }
        } catch {
            if section == selectedSection {
                self.error = error.localizedDescription
                fileItems = []
                folderItems = []
                isLoadingSection = false
            }
        }
    }

    func cachedSnapshot(for section: PanelSection) -> ([FileItem], [FolderItem])? {
        if let files = cachedFiles[section] {
            return (files, [])
        }
        if let folders = cachedFolders[section] {
            return ([], folders)
        }
        return nil
    }

    func applyCachedData(for section: PanelSection) -> Bool {
        guard let snapshot = cachedSnapshot(for: section) else { return false }
        if section.contentType == .files {
            fileItems = snapshot.0
            folderItems = []
        } else {
            folderItems = snapshot.1
            fileItems = []
        }
        return true
    }
}
