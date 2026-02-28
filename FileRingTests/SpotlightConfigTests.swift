import Testing
import Foundation
@testable import FileRing

// .serialized prevents parallel interference on UserDefaults.standard during save/load tests
@Suite("SpotlightConfig", .serialized)
struct SpotlightConfigTests {

    // MARK: - Default Values

    @Test("default excludedFolders count")
    func defaultExcludedFoldersCount() {
        let config = SpotlightConfig()
        #expect(config.excludedFolders.count == 10)
    }

    @Test("default excludedExtensions count")
    func defaultExcludedExtensionsCount() {
        let config = SpotlightConfig()
        #expect(config.excludedExtensions.count == 8)
    }

    @Test("default recentDays is 7")
    func defaultRecentDays() {
        #expect(SpotlightConfig().recentDays == 7)
    }

    @Test("default frequentDays is 3")
    func defaultFrequentDays() {
        #expect(SpotlightConfig().frequentDays == 3)
    }

    @Test("default searchOnlyUserHome is true")
    func defaultSearchOnlyUserHome() {
        #expect(SpotlightConfig().searchOnlyUserHome == true)
    }

    @Test("default appFrequencyMultiplier is 0.5")
    func defaultAppFrequencyMultiplier() {
        #expect(SpotlightConfig().appFrequencyMultiplier == 0.5)
    }

    // MARK: - isPathExcluded (nonisolated variant with explicit homeDir)

    let homeDir = "/Users/testuser"

    @Test(".Trash is excluded")
    func trashExcluded() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/.Trash/file.txt", homeDir: homeDir))
    }

    @Test("node_modules is excluded")
    func nodeModulesExcluded() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/project/node_modules/lodash/index.js", homeDir: homeDir))
    }

    @Test(".git is excluded")
    func gitExcluded() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/repo/.git/config", homeDir: homeDir))
    }

    @Test("__pycache__ nested under Desktop is excluded")
    func pycacheNestedExcluded() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/Desktop/__pycache__/module.pyc", homeDir: homeDir))
    }

    @Test("__pycache__ deep nested is excluded")
    func pycacheDeepNested() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/project/src/__pycache__/util.cpython-39.pyc", homeDir: homeDir))
    }

    @Test("excluded folder at root is excluded")
    func excludedFolderAtRoot() {
        let config = SpotlightConfig()
        #expect(config.isPathExcluded("/Users/testuser/node_modules", homeDir: homeDir))
    }

    @Test("regular Documents path is NOT excluded")
    func regularPathNotExcluded() {
        let config = SpotlightConfig()
        #expect(!config.isPathExcluded("/Users/testuser/Documents/report.pdf", homeDir: homeDir))
    }

    @Test("swift source file is NOT excluded")
    func swiftFileNotExcluded() {
        let config = SpotlightConfig()
        #expect(!config.isPathExcluded("/Users/testuser/MyProject/AppDelegate.swift", homeDir: homeDir))
    }

    @Test("folder name that merely CONTAINS excluded word is not excluded")
    func folderContainingKeywordNotExcluded() {
        // "my_node_modules_archive" should NOT be excluded for "node_modules"
        let config = SpotlightConfig()
        #expect(!config.isPathExcluded("/Users/testuser/my_node_modules_archive/file.txt", homeDir: homeDir))
    }

    // MARK: - isExtensionExcluded

    @Test(".tmp extension is excluded")
    func tmpExtensionExcluded() {
        #expect(SpotlightConfig().isExtensionExcluded("cache.tmp"))
    }

    @Test(".DS_Store is excluded")
    func dsStoreExcluded() {
        #expect(SpotlightConfig().isExtensionExcluded(".DS_Store"))
    }

    @Test(".pyc is excluded")
    func pycExcluded() {
        #expect(SpotlightConfig().isExtensionExcluded("module.pyc"))
    }

    @Test(".swp is excluded")
    func swpExcluded() {
        #expect(SpotlightConfig().isExtensionExcluded("file.swp"))
    }

    @Test(".swift is NOT excluded")
    func swiftNotExcluded() {
        #expect(!SpotlightConfig().isExtensionExcluded("main.swift"))
    }

    @Test(".txt is NOT excluded")
    func txtNotExcluded() {
        #expect(!SpotlightConfig().isExtensionExcluded("notes.txt"))
    }

    @Test(".TMP uppercase is NOT excluded (case-sensitive match)")
    func tmpUppercaseNotExcluded() {
        // The matching is case-sensitive (hasSuffix), so .TMP != .tmp
        #expect(!SpotlightConfig().isExtensionExcluded("file.TMP"))
    }

    // MARK: - save / load / reset

    @Test("save and load round-trip preserves custom recentDays")
    func saveLoadRoundTrip() throws {
        var config = SpotlightConfig()
        config.recentDays = 14
        try config.save()
        let loaded = SpotlightConfig.load()
        SpotlightConfig.reset()  // cleanup
        #expect(loaded.recentDays == 14)
    }

    @Test("save and load preserves appFrequencyMultiplier")
    func saveLoadMultiplier() throws {
        var config = SpotlightConfig()
        config.appFrequencyMultiplier = 0.8
        try config.save()
        let loaded = SpotlightConfig.load()
        SpotlightConfig.reset()
        #expect(loaded.appFrequencyMultiplier == 0.8)
    }

    @Test("reset returns default values on next load")
    func resetRestoresDefaults() throws {
        var config = SpotlightConfig()
        config.recentDays = 30
        try config.save()
        SpotlightConfig.reset()
        let loaded = SpotlightConfig.load()
        #expect(loaded.recentDays == 7)
    }

    @Test("load with no saved data returns defaults")
    func loadNoDataReturnsDefaults() {
        SpotlightConfig.reset()
        let config = SpotlightConfig.load()
        #expect(config.recentDays == 7)
        #expect(config.frequentDays == 3)
        #expect(config.appFrequencyMultiplier == 0.5)
    }
}
