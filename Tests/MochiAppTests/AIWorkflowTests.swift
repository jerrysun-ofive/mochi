import Foundation
import XCTest
@testable import MochiAI
@testable import MochiApp
@testable import MochiCore

@MainActor
final class AIWorkflowTests: XCTestCase {
    func testUnmatchedFileBecomesReviewableAISuggestionWithoutRules() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.destination.appendingPathComponent("Receipts"), withIntermediateDirectories: true)
        let file = fixture.source.appendingPathComponent("receipt.heic")
        try Data("fixture".utf8).write(to: file)

        let jev = ClosureDecisionProvider { request in
            let receipts = try XCTUnwrap(request.candidates.first { $0.displayName.hasSuffix("/Receipts") })
            return .fixture(selectedID: receipts.id.uuidString, confidence: 0.9, probabilities: [receipts.id.uuidString: 0.9, "other": 0.1])
        }
        let model = await fixture.model(orchestrator: HybridDecisionOrchestrator(decisionProvider: jev, generativeProvider: FixedGenerativeProvider(result: .noRecommendation(explanation: "unused"))))

        await model.runNow()
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(model.proposals.count, 1)
        XCTAssertNil(proposal.ruleID)
        XCTAssertNotNil(proposal.aiExplanation)
        XCTAssertEqual(proposal.destinationURL?.path, fixture.destination.appendingPathComponent("Receipts/receipt.heic").path)

        await model.approve(proposal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("Receipts/receipt.heic").path))
    }

    func testNoneOfTheseFallsBackToGenerativeNewFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("fixture".utf8).write(to: fixture.source.appendingPathComponent("2025-tax-return.pdf"))

        let jev = ClosureDecisionProvider { _ in .fixture(selectedID: DestinationDecision.noneOfTheseID, confidence: 0.95, probabilities: [DestinationDecision.noneOfTheseID: 0.95]) }
        let generative = ClosureGenerativeProvider { request in
            .proposedFolder(authorizedParentID: try XCTUnwrap(request.authorizedParentIDs.first), relativeName: "Taxes", explanation: "Tax documents")
        }
        let model = await fixture.model(orchestrator: HybridDecisionOrchestrator(decisionProvider: jev, generativeProvider: generative))

        await model.runNow()
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(proposal.destinationURL?.path, fixture.destination.appendingPathComponent("Taxes/2025-tax-return.pdf").path)
        await model.approve(proposal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("Taxes/2025-tax-return.pdf").path))
    }

    func testAICanChooseSuggestedFolderThatDoesNotExistYet() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("fixture".utf8).write(to: fixture.source.appendingPathComponent("origin-energy-sept.pdf"))

        let jev = ClosureDecisionProvider { request in
            let bills = try XCTUnwrap(request.candidates.first { $0.displayName.hasSuffix("/Utility Bills") })
            XCTAssertTrue(bills.userDescription?.contains("Electricity") == true)
            XCTAssertTrue(request.candidates.contains { $0.displayName.hasSuffix("/Work") })
            return .fixture(selectedID: bills.id.uuidString, confidence: 0.9, probabilities: [bills.id.uuidString: 0.9, "other": 0.1])
        }
        let model = await fixture.model(orchestrator: HybridDecisionOrchestrator(decisionProvider: jev, generativeProvider: FixedGenerativeProvider(result: .noRecommendation(explanation: "unused"))))

        await model.runNow()
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(proposal.destinationURL?.path, fixture.destination.appendingPathComponent("Utility Bills/origin-energy-sept.pdf").path)
        XCTAssertTrue(proposal.aiExplanation?.hasPrefix("New folder “Utility Bills”") == true)
        XCTAssertNil(model.aiProgress)
        await model.approve(proposal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("Utility Bills/origin-energy-sept.pdf").path))
    }

    func testKeywordQuickRuleMatchesFilename() throws {
        let template = try XCTUnwrap(QuickRuleTemplate.builtIns.first { $0.id == "invoices" })
        let rule = template.makeRule(sourceGrantID: nil, destinationGrantID: UUID(), priority: 0)
        XCTAssertTrue(RuleValidator().validate(rule).isEmpty)
        let engine = RuleEngine()
        let invoice = FileMetadata(url: URL(fileURLWithPath: "/tmp/Invoice-0042.pdf"), filename: "Invoice-0042.pdf", fileExtension: "pdf", size: 1)
        let other = FileMetadata(url: URL(fileURLWithPath: "/tmp/notes.pdf"), filename: "notes.pdf", fileExtension: "pdf", size: 1)
        XCTAssertTrue(engine.evaluate(file: invoice, rule: rule).matched)
        XCTAssertFalse(engine.evaluate(file: other, rule: rule).matched)
        XCTAssertNil(QuickRuleTemplate.builtIns.first { $0.id == "work" }, "AI-only folders have no Quick Rule")
    }

    func testRejectedKeyIsReportedAndNothingIsProposed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("fixture".utf8).write(to: fixture.source.appendingPathComponent("mystery.bin"))

        let jev = ClosureDecisionProvider { _ in throw AIProviderError.unavailable(statusCode: 401) }
        let model = await fixture.model(orchestrator: HybridDecisionOrchestrator(decisionProvider: jev, generativeProvider: FixedGenerativeProvider(result: .noRecommendation(explanation: "unused"))))

        await model.runNow()
        XCTAssertTrue(model.proposals.isEmpty)
        XCTAssertTrue(model.notice?.contains("typesafe: it rejected the API key (HTTP 401)") == true, model.notice ?? "")
    }

    func testRuleMatchedFilesAreNotSentToAI() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("fixture".utf8).write(to: fixture.source.appendingPathComponent("notes.txt"))

        let jev = ClosureDecisionProvider { _ in
            XCTFail("Rule-matched files must not reach the AI provider.")
            throw AIProviderError.invalidResponse
        }
        let model = await fixture.model(orchestrator: HybridDecisionOrchestrator(decisionProvider: jev, generativeProvider: FixedGenerativeProvider(result: .noRecommendation(explanation: "unused"))))
        model.addRule(.init(
            name: "Text files",
            isEnabled: true,
            priority: 0,
            match: .init(operation: .all, predicates: [.fileExtension(values: ["txt"])]),
            action: .init(disposition: .move(.init(grantID: model.destinationGrants[0].id)))
        ))

        await model.runNow()
        XCTAssertEqual(model.proposals.count, 1)
        XCTAssertNil(model.proposals.first?.aiExplanation)
    }

    func testBYOKConfigurationRequiresBothKeys() throws {
        let suite = "MochiBYOKTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(GenerativeProviderChoice.deepSeek.rawValue, forKey: "ai.generativeProvider")
        let credentials = MemoryCredentials()

        XCTAssertNil(BYOKConfiguration.makeOrchestrator(defaults: defaults, credentials: credentials))
        credentials.values[BYOKConfiguration.jevAccount] = "jev"
        XCTAssertNil(BYOKConfiguration.makeOrchestrator(defaults: defaults, credentials: credentials))
        credentials.values[BYOKConfiguration.providerAccount(for: .deepSeek)] = "deepseek"
        XCTAssertNotNil(BYOKConfiguration.makeOrchestrator(defaults: defaults, credentials: credentials))
    }

    func testCachedCredentialsReadEachKeychainItemOnce() throws {
        let base = MemoryCredentials()
        base.values["jev"] = "secret"
        let cached = CachedCredentialStore(base: base)

        for _ in 0..<5 {
            XCTAssertEqual(try cached.load(account: "jev"), "secret")
            XCTAssertNil(try cached.load(account: "missing"))
        }
        XCTAssertEqual(base.loadCount, 2)

        try cached.save("replaced", account: "jev")
        XCTAssertEqual(try cached.load(account: "jev"), "replaced")
        try cached.remove(account: "jev")
        XCTAssertNil(try cached.load(account: "jev"))
        XCTAssertEqual(base.loadCount, 2)
    }
}

private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var source: URL { root.appendingPathComponent("source") }
    var destination: URL { root.appendingPathComponent("destination") }

    init() throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    @MainActor
    func model(orchestrator: HybridDecisionOrchestrator) async -> AppModel {
        let model = AppModel(supportRoot: root.appendingPathComponent("state"), securityScopedBookmarks: false, aiOrchestrator: { orchestrator })
        await model.authorizeFolder(url: source, role: .source)
        await model.authorizeFolder(url: destination, role: .destination)
        return model
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private extension DestinationDecision {
    static func fixture(selectedID: String, confidence: Double, probabilities: [String: Double]) -> Self {
        .init(selectedID: selectedID, probabilities: probabilities, confidence: confidence, provider: .init(providerID: "typesafe", modelID: "test"), latencyMilliseconds: 1, usage: .init())
    }
}

private struct ClosureDecisionProvider: DestinationDecisionProvider {
    let choose: @Sendable (DestinationDecisionRequest) throws -> DestinationDecision
    let descriptor = AIProviderDescriptor(providerID: "typesafe", modelID: "test")
    let capabilities = DecisionCapabilities()
    func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision { try choose(request) }
}

private struct ClosureGenerativeProvider: GenerativeAIProvider {
    let resolve: @Sendable (DestinationGenerationRequest) throws -> GenerativeDestinationResult
    let descriptor = AIProviderDescriptor(providerID: "deepseek", modelID: "test")
    let generativeCapabilities = GenerativeCapabilities(structuredOutputs: true)
    func resolveDestination(_ request: DestinationGenerationRequest) async throws -> GenerativeDestinationResult { try resolve(request) }
    func compileRule(_ request: NaturalLanguageRuleRequest) async throws -> RuleCompilationResult { .unsupported("unused") }
}

private struct FixedGenerativeProvider: GenerativeAIProvider {
    let result: GenerativeDestinationResult
    let descriptor = AIProviderDescriptor(providerID: "deepseek", modelID: "test")
    let generativeCapabilities = GenerativeCapabilities(structuredOutputs: true)
    func resolveDestination(_ request: DestinationGenerationRequest) async throws -> GenerativeDestinationResult { result }
    func compileRule(_ request: NaturalLanguageRuleRequest) async throws -> RuleCompilationResult { .unsupported("unused") }
}

private final class MemoryCredentials: AICredentialStoring {
    var values: [String: String] = [:]
    var loadCount = 0
    func save(_ secret: String, account: String) throws { values[account] = secret }
    func load(account: String) throws -> String? { loadCount += 1; return values[account] }
    func remove(account: String) throws { values.removeValue(forKey: account) }
}
