import Foundation
import MochiCore

public struct DestinationCandidate: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let userDescription: String?
    public let examples: [String]

    public init(id: UUID, displayName: String, userDescription: String? = nil, examples: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.userDescription = userDescription
        self.examples = examples
    }
}

public enum ExtractionLevel: Int, Codable, Sendable { case metadata = 0, boundedText = 1, localOCR = 2 }

public struct MinimalFileEnvelope: Codable, Hashable, Sendable {
    public let filename: String
    public let fileExtension: String
    public let contentTypeIdentifier: String?
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let finderTags: Set<String>
    public let boundedText: String?
    public let extractionLevel: ExtractionLevel
    public let fingerprint: FileFingerprint

    public init(metadata: FileMetadata, boundedText: String? = nil, extractionLevel: ExtractionLevel = .metadata) {
        self.filename = metadata.filename
        self.fileExtension = metadata.fileExtension
        self.contentTypeIdentifier = metadata.contentTypeIdentifier
        self.size = metadata.size
        self.creationDate = metadata.creationDate
        self.modificationDate = metadata.modificationDate
        self.finderTags = metadata.finderTags
        self.boundedText = boundedText.map { String($0.prefix(2_000)) }
        self.extractionLevel = extractionLevel
        self.fingerprint = metadata.fingerprint
    }
}

public struct AIProviderDescriptor: Codable, Hashable, Sendable {
    public let providerID: String
    public let modelID: String
    public let modelVersion: String?

    public init(providerID: String, modelID: String, modelVersion: String? = nil) {
        self.providerID = providerID
        self.modelID = modelID
        self.modelVersion = modelVersion
    }
}

public struct DecisionCapabilities: Codable, Hashable, Sendable {
    public let maximumCandidates: Int?
    public let supportsBatch: Bool
    public let supportsModelPinning: Bool
    public let reportsUsage: Bool

    public init(maximumCandidates: Int? = nil, supportsBatch: Bool = false, supportsModelPinning: Bool = true, reportsUsage: Bool = true) {
        self.maximumCandidates = maximumCandidates
        self.supportsBatch = supportsBatch
        self.supportsModelPinning = supportsModelPinning
        self.reportsUsage = reportsUsage
    }
}

public struct GenerativeCapabilities: Codable, Hashable, Sendable {
    public let structuredOutputs: Bool
    public let supportsBatch: Bool
    public let supportsCachedInput: Bool

    public init(structuredOutputs: Bool, supportsBatch: Bool = false, supportsCachedInput: Bool = false) {
        self.structuredOutputs = structuredOutputs
        self.supportsBatch = supportsBatch
        self.supportsCachedInput = supportsCachedInput
    }
}

public struct AIUsage: Codable, Hashable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let billedCostUSD: Decimal?

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cachedInputTokens: Int = 0, billedCostUSD: Decimal? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.billedCostUSD = billedCostUSD
    }
}

public struct DestinationDecisionRequest: Codable, Sendable {
    public let file: MinimalFileEnvelope
    public let candidates: [DestinationCandidate]
    public let candidateSetHash: String
    public let schemaVersion: Int

    public init(file: MinimalFileEnvelope, candidates: [DestinationCandidate], candidateSetHash: String, schemaVersion: Int = 1) {
        self.file = file
        self.candidates = candidates
        self.candidateSetHash = candidateSetHash
        self.schemaVersion = schemaVersion
    }
}

public struct DestinationDecision: Codable, Sendable {
    public static let noneOfTheseID = "none_of_these"

    public let selectedID: String
    public let probabilities: [String: Double]
    public let confidence: Double
    public let provider: AIProviderDescriptor
    public let latencyMilliseconds: Int
    public let usage: AIUsage

    public var margin: Double {
        let sorted = probabilities.values.sorted(by: >)
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        return sorted[0] - sorted[1]
    }
}

public struct DestinationGenerationRequest: Codable, Sendable {
    public let file: MinimalFileEnvelope
    public let candidates: [DestinationCandidate]
    public let decision: DestinationDecision?
    public let authorizedParentIDs: [UUID]
}

public enum GenerativeDestinationResult: Codable, Sendable, Equatable {
    case existingDestination(candidateID: UUID, explanation: String)
    case proposedFolder(authorizedParentID: UUID, relativeName: String, explanation: String)
    case needsClarification(question: String)
    case noRecommendation(explanation: String)
}

public struct NaturalLanguageRuleRequest: Codable, Sendable {
    public let instruction: String
    public let supportedDestinationIDs: [UUID]
}

public enum RuleCompilationResult: Codable, Sendable {
    case draft(OrganizationRule)
    case clarification(String)
    case unsupported(String)
}

public enum AIReviewReason: String, Codable, Sendable {
    case reviewByDefault, lowConfidence, narrowMargin, newFolder, needsClarification
    case providerUnavailable, invalidResponse, unsupportedCandidateSet, modelNotApproved
}

public enum HybridDecisionOutcome: Sendable {
    case existingDestination(UUID, automatic: Bool, explanation: String?)
    case proposedFolder(parentID: UUID, relativeName: String, explanation: String)
    case review(AIReviewReason, explanation: String?)
}

public struct AIAutomationPolicy: Codable, Sendable {
    public let allowsExistingFolderAutomation: Bool
    public let approvedModels: Set<AIProviderDescriptor>
    public let minimumConfidence: Double
    public let minimumMargin: Double

    public init(
        allowsExistingFolderAutomation: Bool = false,
        approvedModels: Set<AIProviderDescriptor> = [],
        minimumConfidence: Double = 1,
        minimumMargin: Double = 1
    ) {
        self.allowsExistingFolderAutomation = allowsExistingFolderAutomation
        self.approvedModels = approvedModels
        self.minimumConfidence = minimumConfidence
        self.minimumMargin = minimumMargin
    }
}
