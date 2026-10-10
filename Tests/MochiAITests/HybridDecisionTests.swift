import Foundation
import XCTest
@testable import MochiAI
@testable import MochiCore

final class HybridDecisionTests: XCTestCase {
    func testConfidentApprovedExistingFolderCanBeAutomatic() async {
        let candidate = DestinationCandidate(id: UUID(), displayName: "Invoices")
        let descriptor = AIProviderDescriptor(providerID: "test", modelID: "v1", modelVersion: "1")
        let decision = DestinationDecision(selectedID: candidate.id.uuidString, probabilities: [candidate.id.uuidString: 0.99, DestinationDecision.noneOfTheseID: 0.01], confidence: 0.99, provider: descriptor, latencyMilliseconds: 10, usage: .init())
        let orchestrator = HybridDecisionOrchestrator(decisionProvider: MockDecisionProvider(decision: decision), generativeProvider: MockGenerativeProvider(result: .noRecommendation(explanation: "unused")))
        let outcome = await orchestrator.decide(request: request(candidates: [candidate]), authorizedParentIDs: [], policy: .init(allowsExistingFolderAutomation: true, approvedModels: [descriptor], minimumConfidence: 0.95, minimumMargin: 0.5))
        guard case .existingDestination(let id, let automatic, _) = outcome else { return XCTFail("Unexpected outcome") }
        XCTAssertEqual(id, candidate.id)
        XCTAssertTrue(automatic)
    }

    func testNoneFallsBackAndNewFolderRequiresReview() async {
        let parent = UUID()
        let descriptor = AIProviderDescriptor(providerID: "test", modelID: "v1")
        let decision = DestinationDecision(selectedID: DestinationDecision.noneOfTheseID, probabilities: [DestinationDecision.noneOfTheseID: 1], confidence: 1, provider: descriptor, latencyMilliseconds: 1, usage: .init())
        let result = GenerativeDestinationResult.proposedFolder(authorizedParentID: parent, relativeName: "Receipts", explanation: "New category")
        let orchestrator = HybridDecisionOrchestrator(decisionProvider: MockDecisionProvider(decision: decision), generativeProvider: MockGenerativeProvider(result: result))
        let outcome = await orchestrator.decide(request: request(candidates: []), authorizedParentIDs: [parent], policy: .init())
        guard case .proposedFolder(let id, let name, _) = outcome else { return XCTFail("Unexpected outcome") }
        XCTAssertEqual(id, parent)
        XCTAssertEqual(name, "Receipts")
    }

    func testValidatorRejectsPathLikeFolderName() {
        let parent = UUID()
        let result = GenerativeDestinationResult.proposedFolder(authorizedParentID: parent, relativeName: "../Secrets", explanation: "bad")
        XCTAssertFalse(AIDecisionValidator().validate(result, candidates: [], authorizedParents: [parent]))
    }

    private func request(candidates: [DestinationCandidate]) -> DestinationDecisionRequest {
        let metadata = FileMetadata(url: URL(fileURLWithPath: "/tmp/invoice.pdf"), filename: "invoice.pdf", fileExtension: "pdf", size: 42)
        return .init(file: .init(metadata: metadata), candidates: candidates, candidateSetHash: "fixture")
    }
}

private struct MockDecisionProvider: DestinationDecisionProvider {
    let decision: DestinationDecision
    var descriptor: AIProviderDescriptor { decision.provider }
    let capabilities = DecisionCapabilities()
    func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision { decision }
}

private struct MockGenerativeProvider: GenerativeAIProvider {
    let result: GenerativeDestinationResult
    let descriptor = AIProviderDescriptor(providerID: "mock", modelID: "mock")
        let generativeCapabilities = GenerativeCapabilities(structuredOutputs: true)
    func resolveDestination(_ request: DestinationGenerationRequest) async throws -> GenerativeDestinationResult { result }
    func compileRule(_ request: NaturalLanguageRuleRequest) async throws -> RuleCompilationResult { .unsupported("unused") }
}
