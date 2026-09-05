import XCTest

/// The Settings.json store: cache validity, loud failure, and the save path (the
/// settings app's own writer, compiled into this target).
final class SettingsStoreTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL { directory.appendingPathComponent("Settings.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hal-settings-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SettingsStore.directoryOverride = directory
    }

    override func tearDown() {
        SettingsStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileYieldsDefaults() {
        XCTAssertEqual(SettingsStore.load(), UserSettings())
    }

    func testSaveThenLoadReadsTheWrittenValue() {
        SettingsStore.saveCandidatePageSize(7)

        XCTAssertEqual(SettingsStore.load().candidatePageSize, 7)
    }

    func testUnchangedFileIsServedFromCache() throws {
        SettingsStore.saveCandidatePageSize(7)
        XCTAssertEqual(SettingsStore.load().candidatePageSize, 7)

        // Stat-preserving proof that the cached value is used: with read permission
        // gone, a re-read would fail; only a valid cache can still answer 7.
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: settingsURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: settingsURL.path)
        }
        XCTAssertEqual(SettingsStore.load().candidatePageSize, 7,
                       "an unchanged stat must be answered from the cache")
    }

    func testCorruptFileFallsBackToDefaultsAndRecovers() throws {
        SettingsStore.saveCandidatePageSize(7)

        try Data("not json".utf8).write(to: settingsURL)
        XCTAssertEqual(SettingsStore.load(), UserSettings(),
                       "a hand-edited invalid file must not look like the saved settings")

        // The next real write (different size, so a different stat) must be picked up.
        SettingsStore.saveCandidatePageSize(5)
        XCTAssertEqual(SettingsStore.load().candidatePageSize, 5)
    }

    func testDirectoryOverrideSwitchDropsTheCache() {
        SettingsStore.saveCandidatePageSize(7)
        XCTAssertEqual(SettingsStore.load().candidatePageSize, 7)

        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("hal-settings-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        SettingsStore.directoryOverride = other

        XCTAssertEqual(SettingsStore.load(), UserSettings(),
                       "the override switch must not serve the previous directory's cache")
    }
}
