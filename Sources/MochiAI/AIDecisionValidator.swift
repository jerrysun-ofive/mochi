import Foundation
import MochiCore

public struct AIDecisionValidator: Sendable {
    public init() {}

    public func candidateID(from value: String, candidates: [DestinationCandidate]) -> UUID? {
        guard let id = UUID(uuidString: value), candidates.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    public func validate(_ result: GenerativeDestinationResult, candidates: [DestinationCandidate], authorizedParents: Set<UUID>) -> Bool {
        switch result {
        case .existingDestination(let id, _):
            return candidates.contains { $0.id == id }
        case .proposedFolder(let parent, let relativeName, _):
            return authorizedParents.contains(parent) && validFolderName(relativeName)
        case .needsClarification, .noRecommendation:
            return true
        }
    }

    public func validFolderName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return false }
        guard !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.contains("\0") else { return false }
        return !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
