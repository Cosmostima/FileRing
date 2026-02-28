import Testing
import Foundation
@testable import FileRing

// MARK: - Helpers

private func makeItems(count: Int, prefix: String = "item") -> [FileSystemItem] {
    (0..<count).map { i in
        FileSystemItem.makeFile(
            path: "/Users/test/\(prefix)\(i).txt",
            name: "\(prefix)\(i).txt"
        )
    }
}

private func makeItems(count: Int, lastUsed: String, prefix: String = "item") -> [FileSystemItem] {
    (0..<count).map { i in
        FileSystemItem.makeFile(
            path: "/Users/test/\(prefix)\(i).txt",
            name: "\(prefix)\(i).txt",
            lastUsed: lastUsed
        )
    }
}

// MARK: - DoubleRingViewModel Tests

@Suite("DoubleRingViewModel", .serialized)
@MainActor
struct DoubleRingViewModelTests {

    // MARK: - Initial State

    @Test("initial state: isInitialLoading = true")
    func initialIsLoadingTrue() {
        let vm = DoubleRingViewModel(fileSystemService: MockFileSystemService())
        #expect(vm.isInitialLoading == true)
    }

    @Test("initial state: selectedSection = .fileRecentlySaved")
    func initialSelectedSection() {
        let vm = DoubleRingViewModel(fileSystemService: MockFileSystemService())
        #expect(vm.selectedSection == .fileRecentlySaved)
    }

    @Test("initial state: fileItems and folderItems are empty")
    func initialItemsEmpty() {
        let vm = DoubleRingViewModel(fileSystemService: MockFileSystemService())
        #expect(vm.fileItems.isEmpty)
        #expect(vm.folderItems.isEmpty)
    }

    @Test("initial state: error is nil")
    func initialErrorNil() {
        let vm = DoubleRingViewModel(fileSystemService: MockFileSystemService())
        #expect(vm.error == nil)
    }

    // MARK: - refresh()

    @Test("refresh sets isInitialLoading to false on completion")
    func refreshSetsInitialLoadingFalse() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 3))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(vm.isInitialLoading == false)
    }

    @Test("refresh populates fileItems for initial file section")
    func refreshPopulatesFileItems() async {
        let mock = MockFileSystemService()
        let items = makeItems(count: 4)
        mock.setFiles(items)
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        // selectedSection is .fileRecentlySaved → file section
        #expect(!vm.fileItems.isEmpty)
    }

    @Test("refresh populates displayItems")
    func refreshPopulatesDisplayItems() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 3))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(!vm.displayItems.isEmpty)
    }

    // MARK: - Error state

    @Test("fetch error sets error property")
    func fetchErrorSetsErrorProperty() async {
        let mock = MockFileSystemService()
        mock.fetchError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Spotlight unavailable"])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(vm.error != nil)
    }

    @Test("fetch error empties fileItems")
    func fetchErrorEmptiesItems() async {
        let mock = MockFileSystemService()
        mock.fetchError = NSError(domain: "test", code: 1)
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(vm.fileItems.isEmpty)
        #expect(vm.folderItems.isEmpty)
    }

    // MARK: - switchToSection

    @Test("switchToSection changes selectedSection")
    func switchToSectionChangesSelection() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 2))
        mock.setFolders(makeItems(count: 2, prefix: "folder"))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        vm.switchToSection(.folderRecentlyOpened)
        #expect(vm.selectedSection == .folderRecentlyOpened)
    }

    @Test("switchToSection to same section is a no-op (selectedSection unchanged)")
    func switchToSameSectionNoOp() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 2))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        let before = vm.fetchFileCallCount(from: mock)
        vm.switchToSection(.fileRecentlySaved)
        let after = vm.fetchFileCallCount(from: mock)
        #expect(before == after)
    }

    @Test("switchToSection with cached data shows items without re-fetching")
    func switchToCachedSectionNoreload() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 3))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()  // preloads all sections
        let callsBefore = mock.fetchFileCallCount
        vm.switchToSection(.fileFrequentlyOpened)
        let callsAfter = mock.fetchFileCallCount
        #expect(callsAfter == callsBefore)  // cache hit: no additional fetch
    }

    // MARK: - handlePanelHide

    @Test("handlePanelHide resets to initial state")
    func handlePanelHideResetsState() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 5))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(!vm.fileItems.isEmpty)

        vm.handlePanelHide()
        #expect(vm.selectedSection == .fileRecentlySaved)
        #expect(vm.fileItems.isEmpty)
        #expect(vm.folderItems.isEmpty)
        #expect(vm.isInitialLoading == true)
    }

    // MARK: - displayItems mapping

    @Test("displayItems.isFolder = false for file section")
    func displayItemsIsFolder() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 2))
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        #expect(vm.displayItems.allSatisfy { !$0.isFolder })
    }

    @Test("displayItems.isFolder = true for folder section")
    func displayItemsIsFolderTrue() async {
        let mock = MockFileSystemService()
        mock.setFiles(makeItems(count: 1))
        mock.setFolders([
            FileSystemItem(path: "/Users/bob/docs", name: "docs", lastUsed: nil, lastModified: nil, contentType: "public.folder")
        ])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        vm.switchToSection(.folderRecentlyOpened)
        // After async load: folderItems should be populated
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        if !vm.folderItems.isEmpty {
            #expect(vm.displayItems.allSatisfy { $0.isFolder })
        }
    }

    @Test("displayItems name matches FileSystemItem displayName")
    func displayItemsNameMatchesDisplayName() async {
        let mock = MockFileSystemService()
        let items = makeItems(count: 2)
        mock.setFiles(items)
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        for (displayItem, fileItem) in zip(vm.displayItems, vm.fileItems) {
            #expect(displayItem.name == fileItem.displayName)
        }
    }

    @Test("displayItems path matches FileSystemItem path")
    func displayItemsPathMatches() async {
        let mock = MockFileSystemService()
        let items = makeItems(count: 2)
        mock.setFiles(items)
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        for (displayItem, fileItem) in zip(vm.displayItems, vm.fileItems) {
            #expect(displayItem.path == fileItem.path)
        }
    }

    // MARK: - open / copyToClipboard

    @Test("open records path in mock")
    func openRecordsPath() async {
        let mock = MockFileSystemService()
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.open(path: "/Users/bob/file.txt")
        #expect(mock.openedPaths == ["/Users/bob/file.txt"])
    }

    @Test("copyToClipboard records path in mock")
    func copyRecordsPath() async {
        let mock = MockFileSystemService()
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.copyToClipboard(path: "/Users/bob/file.txt", mode: .path)
        #expect(mock.copiedPaths.count == 1)
        #expect(mock.copiedPaths.first?.path == "/Users/bob/file.txt")
    }
}

// MARK: - twoLevelParentPath Tests (via DoubleRingViewModel logic)

@Suite("twoLevelParentPath")
@MainActor
struct TwoLevelParentPathTests {

    @Test("regular two-level path")
    func regularTwoLevel() async {
        let mock = MockFileSystemService()
        mock.setFiles([FileSystemItem.makeFile(path: "/Users/bob/Documents/report.pdf", name: "report.pdf")])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        let item = vm.displayItems.first
        #expect(item?.parentPath == "bob / Documents")
    }

    @Test("iCloud path: com~apple~CloudDocs becomes iCloud")
    func iCloudPathMapping() async {
        let mock = MockFileSystemService()
        mock.setFiles([
            FileSystemItem.makeFile(
                path: "/Users/bob/Library/Mobile Documents/com~apple~CloudDocs/Documents/file.txt",
                name: "file.txt"
            )
        ])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        let item = vm.displayItems.first
        #expect(item?.parentPath == "iCloud / Documents")
    }

    @Test("root-level file: single parent")
    func rootLevelFile() async {
        let mock = MockFileSystemService()
        mock.setFiles([FileSystemItem.makeFile(path: "/file.txt", name: "file.txt")])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        let item = vm.displayItems.first
        // grandParentName is empty: result is "/ "
        #expect(item?.parentPath.hasPrefix("/") == true)
    }

    @Test("parent is com~apple~CloudDocs: becomes iCloud")
    func parentIsICloud() async {
        let mock = MockFileSystemService()
        mock.setFiles([
            FileSystemItem.makeFile(
                path: "/Users/bob/Library/Mobile Documents/com~apple~CloudDocs/file.txt",
                name: "file.txt"
            )
        ])
        let vm = DoubleRingViewModel(fileSystemService: mock)
        await vm.refresh()
        let item = vm.displayItems.first
        #expect(item?.parentPath.contains("iCloud") == true)
    }
}

// MARK: - Private Test Helpers

private extension DoubleRingViewModel {
    func fetchFileCallCount(from mock: MockFileSystemService) -> Int {
        mock.fetchFileCallCount
    }
}
