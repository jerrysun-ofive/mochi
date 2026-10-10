import Foundation

public protocol DestinationDecisionProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    var capabilities: DecisionCapabilities { get }
    func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision
}

public protocol GenerativeAIProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    var generativeCapabilities: GenerativeCapabilities { get }
    func resolveDestination(_ request: DestinationGenerationRequest) async throws -> GenerativeDestinationResult
    func compileRule(_ request: NaturalLanguageRuleRequest) async throws -> RuleCompilationResult
}

public enum AIProviderError: Error, Equatable, Sendable {
    case missingCredential
    case invalidEndpoint
    case unsupportedCandidateCount(maximum: Int)
    case invalidResponse
    case unavailable(statusCode: Int?)
    case capabilityUnavailable
}
