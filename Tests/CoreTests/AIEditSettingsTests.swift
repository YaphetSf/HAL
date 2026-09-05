import XCTest

final class AIEditSettingsTests: XCTestCase {
    func testDefaultsDecodeFromEmptyObject() throws {
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.aiEdit, AIEditSettings())
        XCTAssertEqual(settings.aiEdit.provider, .appleOnDevice)
        XCTAssertTrue(settings.aiEdit.isEndpointConfigured == false)
    }

    func testProviderOrderMatchesProductPriority() {
        XCTAssertEqual(AIEditProvider.allCases, [.appleOnDevice, .openAICompatible])
    }

    func testRephrasePromptDefaultsToTheShippingContract() {
        let aiEdit = AIEditSettings()
        XCTAssertEqual(aiEdit.rephrasePrompt, AIEditSettings.defaultRephrasePrompt)
        XCTAssertFalse(aiEdit.rephrasePrompt.isEmpty)
    }

    func testLegacyFileWithoutAIEditDecodes() throws {
        // A pre-D28 Settings.json has no aiEdit key and still decodes with defaults.
        let legacy = """
        {"fuzzyDinToDing": false}
        """
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.aiEdit, AIEditSettings())
    }

    func testRoundTripPreservesEndpointAndPromptConfiguration() throws {
        var aiEdit = AIEditSettings()
        aiEdit.provider = .openAICompatible
        aiEdit.endpointURL = "http://192.168.1.10:8901/v1/chat/completions"
        aiEdit.timeout = 30
        aiEdit.rephrasePrompt = "Rewrite this in my house style."

        let settings = UserSettings(aiEdit: aiEdit)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded.aiEdit, aiEdit)
    }

    func testEndpointConfiguredValidatesScheme() {
        var aiEdit = AIEditSettings()
        XCTAssertFalse(aiEdit.isEndpointConfigured)

        aiEdit.endpointURL = "ftp://example.com/v1/chat/completions"
        XCTAssertFalse(aiEdit.isEndpointConfigured)

        aiEdit.endpointURL = "http://127.0.0.1:8901/v1/chat/completions"
        XCTAssertTrue(aiEdit.isEndpointConfigured)

        aiEdit.endpointURL = "https://api.example.com/v1/chat/completions"
        XCTAssertTrue(aiEdit.isEndpointConfigured)
    }
}
