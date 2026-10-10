import Foundation

public actor HybridDecisionOrchestrator {
    private let decisionProvider: any DestinationDecisionProvider
    private let generativeProvider: any GenerativeAIProvider
    private let validator: AIDecisionValidator
    private let cache: DecisionCache?
    private let cacheAuthenticationKey: Data?

    public init(
        decisionProvider: any DestinationDecisionProvider,
        generativeProvider: any GenerativeAIProvider,
        cache: DecisionCache? = nil,
        cacheAuthenticationKey: Data? = nil
    ) {
        self.decisionProvider = decisionProvider
        self.generativeProvider = generativeProvider
        self.validator = AIDecisionValidator()
        self.cache = cache
        self.cacheAuthenticationKey = cacheAuthenticationKey
    }

    public func decide(
        request: DestinationDecisionRequest,
        authorizedParentIDs: Set<UUID>,
        policy: AIAutomationPolicy,
        allowProviderFailover: Bool = false
    ) async -> HybridDecisionOutcome {
        if let maximum = decisionProvider.capabilities.maximumCandidates, request.candidates.count > maximum {
            return await useGenerativeFallback(request: request, decision: nil, parents: authorizedParentIDs, reason: .unsupportedCandidateSet)
        }
        let cacheKey = try? cacheAuthenticationKey.map {
            try DecisionCache.key(request: request, provider: decisionProvider.descriptor, authenticationKey: $0)
        }
        let decision: DestinationDecision
        if let cache, let cacheKey, let cached = await cache.value(for: cacheKey) {
            decision = cached
        } else {
            do {
                decision = try await decisionProvider.chooseDestination(request)
                if let cache, let cacheKey { await cache.insert(decision, for: cacheKey) }
            } catch {
                guard allowProviderFailover else { return .review(.providerUnavailable, explanation: String(describing: error)) }
                return await useGenerativeFallback(request: request, decision: nil, parents: authorizedParentIDs, reason: .providerUnavailable)
            }
        }

        if decision.selectedID == DestinationDecision.noneOfTheseID {
            return await useGenerativeFallback(request: request, decision: decision, parents: authorizedParentIDs, reason: .newFolder)
        }
        guard let candidateID = validator.candidateID(from: decision.selectedID, candidates: request.candidates) else {
            return .review(.invalidResponse, explanation: "The provider selected an unknown destination.")
        }
        let isAmbiguous = decision.confidence < policy.minimumConfidence || decision.margin < policy.minimumMargin
        if isAmbiguous {
            return await useGenerativeFallback(request: request, decision: decision, parents: authorizedParentIDs, reason: .lowConfidence)
        }
        let automatic = policy.allowsExistingFolderAutomation && policy.approvedModels.contains(decision.provider)
        return .existingDestination(candidateID, automatic: automatic, explanation: automatic ? nil : "AI decisions require review by default.")
    }

    private func useGenerativeFallback(
        request: DestinationDecisionRequest,
        decision: DestinationDecision?,
        parents: Set<UUID>,
        reason: AIReviewReason
    ) async -> HybridDecisionOutcome {
        do {
            let generated = try await generativeProvider.resolveDestination(.init(
                file: request.file,
                candidates: request.candidates,
                decision: decision,
                authorizedParentIDs: Array(parents)
            ))
            guard validator.validate(generated, candidates: request.candidates, authorizedParents: parents) else {
                return .review(.invalidResponse, explanation: "The generative result failed local validation.")
            }
            switch generated {
            case .existingDestination(let id, let explanation):
                return .existingDestination(id, automatic: false, explanation: explanation)
            case .proposedFolder(let parent, let name, let explanation):
                return .proposedFolder(parentID: parent, relativeName: name, explanation: explanation)
            case .needsClarification(let question):
                return .review(.needsClarification, explanation: question)
            case .noRecommendation(let explanation):
                return .review(reason, explanation: explanation)
            }
        } catch {
            return .review(.providerUnavailable, explanation: String(describing: error))
        }
    }
}
