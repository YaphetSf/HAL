import XCTest

private struct FixtureExtractor: HALInputPayloadExtracting {
    let fixtureURL: URL

    func extract(archiveURL: URL, to directoryURL: URL) throws -> URL {
        let destination = directoryURL.appendingPathComponent(
            HALInstallationContext.inputMethodName, isDirectory: true)
        try FileManager.default.copyItem(at: fixtureURL, to: destination)
        return destination
    }
}

final class HALInstallerTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HALInstallerTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testReleaseAppWithoutExistingInstallRequiresInstall() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        try makeApp(at: source, version: "1.0", build: "1", withPayload: true)

        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)

        XCTAssertEqual(context.requirement, .install)
    }

    func testCurrentInstalledBundlesOpenExistingInstall() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        try makeApp(at: source, version: "1.0", build: "2", withPayload: true)
        let installedApp = home.appendingPathComponent("Applications/HAL.app", isDirectory: true)
        let installedInput = home
            .appendingPathComponent("Library/Input Methods/HAL_input.app", isDirectory: true)
        try makeApp(at: installedApp, version: "1.0", build: "2", withPayload: true)
        try makeApp(at: installedInput, version: "1.0", build: "2")

        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)

        XCTAssertEqual(context.requirement, .openInstalled)
    }

    func testOlderInstalledAppRequiresUpdate() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        try makeApp(at: source, version: "2.0", build: "1", withPayload: true)
        let installedApp = home.appendingPathComponent("Applications/HAL.app", isDirectory: true)
        try makeApp(at: installedApp, version: "1.0", build: "9", withPayload: true)

        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)

        XCTAssertEqual(context.requirement, .update)
    }

    func testCurrentAppWithMissingInputMethodRequiresRepair() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        try makeApp(at: source, version: "2.0", build: "1", withPayload: true)
        let installedApp = home.appendingPathComponent("Applications/HAL.app", isDirectory: true)
        try makeApp(at: installedApp, version: "2.0", build: "1", withPayload: true)

        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)

        XCTAssertEqual(context.requirement, .repair)
    }

    func testInstalledAppRepairsMissingInputMethod() throws {
        let installedApp = home.appendingPathComponent("Applications/HAL.app", isDirectory: true)
        try makeApp(at: installedApp, version: "1.0", build: "1", withPayload: true)

        let context = HALInstallationContext(sourceAppURL: installedApp, homeDirectoryURL: home)

        XCTAssertEqual(context.requirement, .repair)
    }

    func testDeployCopiesControlCenterAndExtractedInputMethod() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        let inputFixture = root.appendingPathComponent("Fixture/HAL_input.app", isDirectory: true)
        try makeApp(at: source, version: "1.2", build: "3", withPayload: true)
        try makeApp(at: inputFixture, version: "1.2", build: "3")
        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)

        try HALBundleDeployer.deploy(context: context,
                                     extractor: FixtureExtractor(fixtureURL: inputFixture))

        XCTAssertEqual(HALBundleVersion.read(from: context.installedAppURL),
                       HALBundleVersion(shortVersion: "1.2", build: "3"))
        XCTAssertEqual(HALBundleVersion.read(from: context.installedInputURL),
                       HALBundleVersion(shortVersion: "1.2", build: "3"))
    }

    func testDeployReplacesOlderBundles() throws {
        let source = root.appendingPathComponent("HAL.app", isDirectory: true)
        let inputFixture = root.appendingPathComponent("Fixture/HAL_input.app", isDirectory: true)
        try makeApp(at: source, version: "2.0", build: "1", withPayload: true)
        try makeApp(at: inputFixture, version: "2.0", build: "1")
        let context = HALInstallationContext(sourceAppURL: source, homeDirectoryURL: home)
        try makeApp(at: context.installedAppURL, version: "1.0", build: "1", withPayload: true)
        try makeApp(at: context.installedInputURL, version: "1.0", build: "1")

        try HALBundleDeployer.deploy(context: context,
                                     extractor: FixtureExtractor(fixtureURL: inputFixture))

        XCTAssertEqual(HALBundleVersion.read(from: context.installedAppURL)?.shortVersion, "2.0")
        XCTAssertEqual(HALBundleVersion.read(from: context.installedInputURL)?.shortVersion, "2.0")
    }

    func testLaunchServicesDumpParserFindsUniqueBundlePaths() {
        let dump = """
        path: /Applications/HAL.app (0x123)
        identifier: com.hal.inputmethod.HALSettings
        path: /Volumes/HAL/HAL.app (0x456)
        identifier: com.hal.inputmethod.HALSettings
        path: /Applications/Other.app (0x789)
        identifier: com.example.Other
        """

        XCTAssertEqual(
            HALLaunchServicesParser.registeredPaths(
                in: dump, bundleID: HALInstallationContext.controlCenterBundleID),
            ["/Applications/HAL.app", "/Volumes/HAL/HAL.app"]
        )
    }

    private func makeApp(at url: URL, version: String, build: String,
                         withPayload: Bool = false) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info,
                                                      format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if withPayload {
            try Data("payload".utf8).write(
                to: resources.appendingPathComponent(HALInstallationContext.payloadName))
        }
    }
}
