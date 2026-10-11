import Foundation

public enum PlanningWarning: String, Codable, Sendable {
    case sourceNotRegularFile
    case sourceIsSymbolicLink
    case destinationUnavailable
    case crossVolumeMoveUnsupported
    case filenameConflict
}

public struct ProposedOperation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let source: FileMetadata
    public let ruleID: UUID?
    public let destinationURL: URL?
    public let reasons: [MatchReason]
    public let warnings: [PlanningWarning]
    public var isExcluded: Bool

    public init(
        id: UUID = UUID(),
        source: FileMetadata,
        ruleID: UUID?,
        destinationURL: URL?,
        reasons: [MatchReason],
        warnings: [PlanningWarning] = [],
        isExcluded: Bool = false
    ) {
        self.id = id
        self.source = source
        self.ruleID = ruleID
        self.destinationURL = destinationURL
        self.reasons = reasons
        self.warnings = warnings
        self.isExcluded = isExcluded
    }
}

public struct OperationPlanner: Sendable {
    public typealias GrantResolver = @Sendable (UUID) -> URL?

    private let resolveGrant: GrantResolver

    public init(resolveGrant: @escaping GrantResolver) {
        self.resolveGrant = resolveGrant
    }

    public func plan(file: FileMetadata, evaluation: RuleEvaluation) -> ProposedOperation {
        guard case .move(let reference) = evaluation.rule.action.disposition else {
            return ProposedOperation(source: file, ruleID: evaluation.rule.id, destinationURL: nil, reasons: evaluation.reasons, warnings: sourceWarnings(file))
        }
        return plan(file: file, reference: reference, renameTemplate: evaluation.rule.action.renameTemplate, ruleID: evaluation.rule.id, reasons: evaluation.reasons)
    }

    public func plan(file: FileMetadata, destination reference: DestinationReference, reasons: [MatchReason]) -> ProposedOperation {
        plan(file: file, reference: reference, renameTemplate: nil, ruleID: nil, reasons: reasons)
    }

    private func plan(file: FileMetadata, reference: DestinationReference, renameTemplate: String?, ruleID: UUID?, reasons: [MatchReason]) -> ProposedOperation {
        var warnings = sourceWarnings(file)
        guard let root = resolveGrant(reference.grantID),
              let folder = PathSafety.containedURL(root: root, relativePath: reference.relativeSubpath) else {
            warnings.append(.destinationUnavailable)
            return ProposedOperation(source: file, ruleID: ruleID, destinationURL: nil, reasons: reasons, warnings: warnings)
        }

        let name = renderedName(template: renameTemplate, metadata: file)
        let destination = folder.appendingPathComponent(name)
        if destination.filePath == file.url.filePath { warnings.append(.destinationUnavailable) }
        if !Self.sameVolume(file.url, folder) { warnings.append(.crossVolumeMoveUnsupported) }
        if FileManager.default.fileExists(atPath: destination.path) { warnings.append(.filenameConflict) }
        return ProposedOperation(source: file, ruleID: ruleID, destinationURL: destination, reasons: reasons, warnings: warnings)
    }

    private func sourceWarnings(_ file: FileMetadata) -> [PlanningWarning] {
        var warnings: [PlanningWarning] = []
        if !file.isRegularFile { warnings.append(.sourceNotRegularFile) }
        if file.isSymbolicLink { warnings.append(.sourceIsSymbolicLink) }
        return warnings
    }

    private func renderedName(template: String?, metadata: FileMetadata) -> String {
        guard var result = template else { return metadata.filename }
        let original = metadata.url.deletingPathExtension().lastPathComponent
        result = result.replacingOccurrences(of: "{name}", with: original)
        result = result.replacingOccurrences(of: "{ext}", with: metadata.fileExtension)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{created:yyyy-MM-dd}", with: metadata.creationDate.map(formatter.string) ?? "unknown")
        result = result.replacingOccurrences(of: "{modified:yyyy-MM-dd}", with: metadata.modificationDate.map(formatter.string) ?? "unknown")
        return result
    }

    private static func sameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = volumeIdentifier(for: lhs)
        let right = volumeIdentifier(for: rhs)
        guard let left, let right else { return false }
        return String(describing: left) == String(describing: right)
    }

    private static func volumeIdentifier(for url: URL) -> Any? {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
        return try? candidate.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
    }
}

private extension URL {
    var filePath: String { standardizedFileURL.path }
}
