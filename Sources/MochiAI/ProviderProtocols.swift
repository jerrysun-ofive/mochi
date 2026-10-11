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

extension AIProviderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingCredential: "no API key is saved"
        case .invalidEndpoint: "the endpoint URL is invalid"
        case .unsupportedCandidateCount(let maximum): "it supports at most \(maximum) destinations"
        case .invalidResponse: "it returned a response Mochi could not read"
        case .unavailable(let status?) where status == 401 || status == 403: "it rejected the API key (HTTP \(status))"
        case .unavailable(let status?): "it returned HTTP \(status)"
        case .unavailable(nil): "it could not be reached"
        case .capabilityUnavailable: "it does not support this request"
        }
    }
}
