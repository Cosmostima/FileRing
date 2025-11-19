//
//  DoubleRingViewModel.swift
//  PopUp
//
//  Created by Cosmos on 30/10/2025.
//

import Foundation
import Combine
import os.log

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
    private var loadingSections = Set<PanelSection>()

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
        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "TotalLoadAndPreload", signpostID: signpostID)
        defer { os_signpost(.end, log: .pointsOfInterest, name: "TotalLoadAndPreload", signpostID: signpostID) }

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
        } else if loadingSections.contains(section) {
            error = nil
            isLoadingSection = true
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
        loadingSections.removeAll()
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

        let sections = PanelSection.allCases
        guard !sections.isEmpty else { return }

        preloadTask = Task { [weak self] in
            guard let self = self else { return }
            await withTaskGroup(of: Void.self) { group in
                for section in sections {
                    if section == self.selectedSection { continue }
                    if self.cachedSnapshot(for: section) != nil { continue }
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        if Task.isCancelled { return }
                        await self.load(section: section, updateUI: false)
                    }
                }
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
        if Task.isCancelled { return }

        loadingSections.insert(section)
        defer { loadingSections.remove(section) }

        if updateUI || section == selectedSection {
            isLoadingSection = true
            error = nil
        }

        do {
            switch section.contentType {
            case .files:
                let items = try await fileSystemService.fetchFiles(for: section.category, limit: itemsLimit)
                guard !Task.isCancelled else { return }
                cachedFiles[section] = items
                if section == selectedSection {
                    fileItems = items
                    folderItems = []
                    isLoadingSection = false
                }
            case .folders:
                let items = try await fileSystemService.fetchFolders(for: section.category, limit: itemsLimit)
                guard !Task.isCancelled else { return }
                cachedFolders[section] = items
                if section == selectedSection {
                    folderItems = items
                    fileItems = []
                    isLoadingSection = false
                }
            }
        } catch {
            if error is CancellationError { return }
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
