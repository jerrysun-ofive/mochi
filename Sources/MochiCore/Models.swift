import Foundation
import UniformTypeIdentifiers

public struct FileFingerprint: Codable, Hashable, Sendable {
    public let size: Int64
    public let modificationDate: Date?
    public let resourceIdentifier: Data?

    public init(size: Int64, modificationDate: Date?, resourceIdentifier: Data? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.resourceIdentifier = resourceIdentifier
    }
}

public struct FileMetadata: Codable, Hashable, Sendable {
    public let url: URL
    public let filename: String
    public let fileExtension: String
    public let contentTypeIdentifier: String?
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let finderTags: Set<String>
    public let isHidden: Bool
    public let isRegularFile: Bool
    public let isSymbolicLink: Bool
    public let fingerprint: FileFingerprint

    public init(
        url: URL,
        filename: String,
        fileExtension: String,
        contentTypeIdentifier: String? = nil,
        size: Int64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        finderTags: Set<String> = [],
        isHidden: Bool = false,
        isRegularFile: Bool = true,
        isSymbolicLink: Bool = false,
        fingerprint: FileFingerprint? = nil
    ) {
        self.url = url
        self.filename = filename
        self.fileExtension = fileExtension
        self.contentTypeIdentifier = contentTypeIdentifier
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.finderTags = finderTags
        self.isHidden = isHidden
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.fingerprint = fingerprint ?? .init(size: size, modificationDate: modificationDate)
    }
}

public enum GroupOperation: String, Codable, Sendable { case all, any }
public enum TextOperation: String, Codable, Sendable { case contains, startsWith, endsWith }
public enum Comparison: String, Codable, Sendable { case lessThan, lessThanOrEqual, equal, greaterThanOrEqual, greaterThan }
public enum DateComparison: String, Codable, Sendable { case before, onOrBefore, onOrAfter, after }
public enum RuleOrigin: String, Codable, Sendable { case user, starter, aiApproved, learnedApproved }

public enum RulePredicate: Codable, Hashable, Sendable {
    case fileExtension(values: [String])
    case contentType(conformsTo: String)
    case filename(operation: TextOperation, value: String)
    case size(comparison: Comparison, bytes: Int64)
    case creationDate(comparison: DateComparison, value: Date)
    case modificationDate(comparison: DateComparison, value: Date)
    case finderTag(values: Set<String>, mode: GroupOperation)
    case isHidden(Bool)
}

public struct ConditionGroup: Codable, Hashable, Sendable {
    public var operation: GroupOperation
    public var predicates: [RulePredicate]

    public init(operation: GroupOperation, predicates: [RulePredicate]) {
        self.operation = operation
        self.predicates = predicates
    }
}

public struct DestinationReference: Codable, Hashable, Sendable {
    public let grantID: UUID
    public let relativeSubpath: String

    public init(grantID: UUID, relativeSubpath: String = "") {
        self.grantID = grantID
        self.relativeSubpath = relativeSubpath
    }
}

public enum Disposition: Codable, Hashable, Sendable {
    case move(DestinationReference)
    case leave
}

public struct RuleAction: Codable, Hashable, Sendable {
    public var disposition: Disposition
    public var renameTemplate: String?

    public init(disposition: Disposition, renameTemplate: String? = nil) {
        self.disposition = disposition
        self.renameTemplate = renameTemplate
    }
}

public struct OrganizationRule: Codable, Identifiable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var priority: Int
    public var sourceGrantIDs: Set<UUID>
    public var match: ConditionGroup
    public var action: RuleAction
    public var origin: RuleOrigin

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = false,
        priority: Int,
        sourceGrantIDs: Set<UUID> = [],
        match: ConditionGroup,
        action: RuleAction,
        origin: RuleOrigin = .user
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.sourceGrantIDs = sourceGrantIDs
        self.match = match
        self.action = action
        self.origin = origin
    }
}

public struct MatchReason: Codable, Hashable, Sendable {
    public let predicate: String
    public let matched: Bool
    public let explanation: String
}

public struct RuleEvaluation: Codable, Sendable {
    public let rule: OrganizationRule
    public let matched: Bool
    public let reasons: [MatchReason]
}

public enum OperationState: String, Codable, Sendable {
    case planned, prepared, executing, committed, failed, needsReview
    case undoing, undone, undoFailed
}

public struct OperationRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let ruleID: UUID?
    public let sourceURL: URL
    public let destinationURL: URL?
    public let sourceFingerprint: FileFingerprint
    public var destinationFingerprint: FileFingerprint?
    public var state: OperationState
    public var failureMessage: String?
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        ruleID: UUID?,
        sourceURL: URL,
        destinationURL: URL?,
        sourceFingerprint: FileFingerprint,
        state: OperationState = .planned,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ruleID = ruleID
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sourceFingerprint = sourceFingerprint
        self.state = state
        self.createdAt = createdAt
    }
}
