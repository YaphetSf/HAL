import AppKit
import XCTest

/// D26: importing, replacing and losing the user's artwork. Every failure here has to end
/// as "fall back to the built-in ball", never as an error the input method must handle.
final class ModeFeedbackArtworkTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HALArtworkTests-\(UUID().uuidString)")
        SettingsStore.directoryOverride = directory
    }

    override func tearDown() {
        SettingsStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ contents: String, as name: String) throws -> URL {
        let url = directory.appendingPathComponent("source-\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func svg(_ fill: String = "#3b7") -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\
        <circle cx="50" cy="50" r="40" fill="\(fill)"/></svg>
        """
    }

    private var installedFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ModeFeedbackArtwork.directory.path)) ?? [])
            .sorted()
    }

    func testInstallCopiesTheFileAndReturnsItsName() throws {
        let source = try write(svg(), as: "cat.svg")
        let name = try ModeFeedbackArtwork.install(from: source)

        XCTAssertEqual(name, "custom1.svg")
        XCTAssertEqual(installedFiles, ["custom1.svg"])
        XCTAssertNotNil(ModeFeedbackArtwork.image(for: .custom(name)))

        // The copy is the point: deleting the original must not disturb the artwork.
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(ModeFeedbackArtwork.image(for: .custom(name)))
    }

    func testEveryImportIsKeptAndNumbered() throws {
        let first = try ModeFeedbackArtwork.install(from: write(svg(), as: "first.svg"))
        let second = try ModeFeedbackArtwork.install(from: write(svg("#c33"), as: "second.SVG"))

        XCTAssertEqual(first, "custom1.svg")
        XCTAssertEqual(second, "custom2.svg", "the extension is lowercased")
        XCTAssertEqual(ModeFeedbackArtwork.installedNames, ["custom1.svg", "custom2.svg"])
    }

    func testRemovingOneFreesItsNumberForTheNextImport() throws {
        _ = try ModeFeedbackArtwork.install(from: write(svg(), as: "first.svg"))
        let second = try ModeFeedbackArtwork.install(from: write(svg(), as: "second.svg"))
        ModeFeedbackArtwork.remove(named: second)

        XCTAssertEqual(ModeFeedbackArtwork.installedNames, ["custom1.svg"])
        XCTAssertEqual(try ModeFeedbackArtwork.install(from: write(svg(), as: "third.png")),
                       "custom2.png")
    }

    func testAFileMacOSCannotReadIsRefused() throws {
        let source = try write("this is not an image", as: "notes.txt")
        XCTAssertThrowsError(try ModeFeedbackArtwork.install(from: source)) { error in
            XCTAssertEqual(error as? ModeFeedbackArtwork.ImportError, .unreadable)
        }
        XCTAssertTrue(installedFiles.isEmpty)
    }

    func testAnOversizedFileIsRefusedWithoutBeingInstalled() throws {
        let source = try write(String(repeating: "a", count: ModeFeedbackArtwork.maximumByteCount + 1),
                               as: "huge.svg")
        XCTAssertThrowsError(try ModeFeedbackArtwork.install(from: source)) { error in
            XCTAssertEqual(error as? ModeFeedbackArtwork.ImportError, .tooLarge)
        }
        XCTAssertTrue(installedFiles.isEmpty)
    }

    func testMissingOrEscapingNamesFallBackToTheBuiltInBall() throws {
        XCTAssertNil(ModeFeedbackArtwork.image(for: .custom("gone.svg")))
        XCTAssertNil(ModeFeedbackArtwork.url(named: "../../Settings.json"),
                     "a hand-edited Settings.json must not point at an arbitrary path")

        let name = try ModeFeedbackArtwork.install(from: write(svg(), as: "cat.svg"))
        XCTAssertNotNil(ModeFeedbackArtwork.image(for: .custom(name)))
        try FileManager.default.removeItem(at: XCTUnwrap(ModeFeedbackArtwork.url(named: name)))
        XCTAssertNil(ModeFeedbackArtwork.image(for: .custom(name)), "a deleted file is not an error")
    }

    func testRemovingGoesBackToNothingInstalled() throws {
        let name = try ModeFeedbackArtwork.install(from: write(svg(), as: "cat.svg"))
        ModeFeedbackArtwork.remove(named: name)
        XCTAssertTrue(installedFiles.isEmpty)
        XCTAssertNil(ModeFeedbackArtwork.image(for: .custom(name)))
    }

    func testTheChoiceRoundTripsThroughSettingsJson() throws {
        XCTAssertEqual(SettingsStore.load().modeFeedback, .miku, "the bundled artwork is the default")
        SettingsStore.saveModeFeedback(.custom("mode-feedback.svg"))
        XCTAssertEqual(SettingsStore.load().modeFeedback, .custom("mode-feedback.svg"))
        SettingsStore.saveModeFeedback(.serve)
        XCTAssertEqual(SettingsStore.load().modeFeedback, .serve)
        XCTAssertNil(ModeFeedbackArtwork.image(for: .serve), "the serve brings its own ball")
    }

    func testAnUnreadableChoiceFallsBackToTheDefault() throws {
        let json = #"{"modeFeedback":"file:"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: json).modeFeedback,
                       .custom(""), "an empty name is still a custom choice; url(named:) rejects it")
        XCTAssertNil(ModeFeedbackArtwork.url(named: ""))
        let legacy = #"{"modeFeedback":"mode-feedback.svg"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: legacy).modeFeedback,
                       .miku, "anything unrecognized is the default, never a crash")
    }

    func testImportsSurvivePickingAnotherChoice() throws {
        let name = try ModeFeedbackArtwork.install(from: write(svg(), as: "cat.svg"))
        SettingsStore.saveModeFeedback(.serve)
        XCTAssertEqual(ModeFeedbackArtwork.installedNames, [name],
                       "picking another choice must not throw the user's import away")
    }
}
