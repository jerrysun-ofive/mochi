import Foundation
import XCTest
@testable import MochiApp

@MainActor
final class AISettingsModelTests: XCTestCase {
    func testBYOKConfigurationStoresSecretsOutsideDefaultsAndRestoresMetadata() throws {
        let suite = "MochiAISettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let model = AISettingsModel(defaults: defaults, credentials: credentials)

        model.jevKeyEntry = "jev-secret"
        model.provider = .gemini
        model.providerChanged()
        model.providerKeyEntry = "gemini-secret"
        model.model = "gemini-test-model"
        XCTAssertTrue(model.configurationIsComplete)
        model.save()

        XCTAssertEqual(credentials.values["typesafe-jev-api-key"], "jev-secret")
        XCTAssertEqual(credentials.values["gemini-api-key"], "gemini-secret")
        XCTAssertNil(defaults.string(forKey: "typesafe-jev-api-key"))
        XCTAssertNil(defaults.string(forKey: "gemini-api-key"))

        let restored = AISettingsModel(defaults: defaults, credentials: credentials)
        XCTAssertEqual(restored.provider, .gemini)
        XCTAssertEqual(restored.model, "gemini-test-model")
        XCTAssertTrue(restored.hasJevKey)
        XCTAssertTrue(restored.hasProviderKey)
        XCTAssertTrue(restored.configurationIsComplete)
    }

    func testOllamaStillRequiresJevButNotASecondAPIKey() {
        let defaults = UserDefaults(suiteName: "MochiAISettingsTests.\(UUID().uuidString)")!
        let credentials = MemoryCredentialStore()
        let model = AISettingsModel(defaults: defaults, credentials: credentials)
        model.provider = .ollama
        model.providerChanged()
        XCTAssertFalse(model.configurationIsComplete)
        model.jevKeyEntry = "jev-secret"
        XCTAssertTrue(model.configurationIsComplete)
    }
}

private final class MemoryCredentialStore: AICredentialStoring {
    var values: [String: String] = [:]
    func save(_ secret: String, account: String) throws { values[account] = secret }
    func load(account: String) throws -> String? { values[account] }
    func remove(account: String) throws { values.removeValue(forKey: account) }
}
