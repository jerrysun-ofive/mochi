import Foundation
import UniformTypeIdentifiers

public struct RuleEngine: Sendable {
    public init() {}

    public func firstMatch(
        file: FileMetadata,
        sourceGrantID: UUID,
        rules: [OrganizationRule]
    ) -> RuleEvaluation? {
        rules
            .filter(\.isEnabled)
            .filter { $0.sourceGrantIDs.isEmpty || $0.sourceGrantIDs.contains(sourceGrantID) }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id.uuidString < rhs.id.uuidString : lhs.priority < rhs.priority
            }
            .lazy
            .map { evaluate(file: file, rule: $0) }
            .first(where: \.matched)
    }

    public func evaluate(file: FileMetadata, rule: OrganizationRule) -> RuleEvaluation {
        let reasons = rule.match.predicates.map { evaluate(file: file, predicate: $0) }
        let matched: Bool
        switch rule.match.operation {
        case .all: matched = !reasons.isEmpty && reasons.allSatisfy(\.matched)
        case .any: matched = reasons.contains(where: \.matched)
        }
        return RuleEvaluation(rule: rule, matched: matched, reasons: reasons)
    }

    private func evaluate(file: FileMetadata, predicate: RulePredicate) -> MatchReason {
        switch predicate {
        case .fileExtension(let values):
            let normalized = file.fileExtension.lowercased(with: Locale(identifier: "en_US_POSIX"))
            let matched = values.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased(with: Locale(identifier: "en_US_POSIX")) }.contains(normalized)
            return .init(predicate: "extension", matched: matched, explanation: matched ? "Extension is \(normalized)." : "Extension \(normalized) is not in the rule.")
        case .contentType(let identifier):
            guard let actualID = file.contentTypeIdentifier, let actual = UTType(actualID), let expected = UTType(identifier) else {
                return .init(predicate: "contentType", matched: false, explanation: "Content type is unavailable.")
            }
            let matched = actual.conforms(to: expected)
            return .init(predicate: "contentType", matched: matched, explanation: "\(actualID) \(matched ? "conforms" : "does not conform") to \(identifier).")
        case .filename(let operation, let value):
            let name = normalize(file.filename)
            let needle = normalize(value)
            let matched: Bool
            switch operation {
            case .contains: matched = name.contains(needle)
            case .startsWith: matched = name.hasPrefix(needle)
            case .endsWith: matched = name.hasSuffix(needle)
            }
            return .init(predicate: "filename", matched: matched, explanation: "Filename \(matched ? "matches" : "does not match") \(operation.rawValue) ‘\(value)’.")
        case .size(let comparison, let bytes):
            let matched = compare(file.size, bytes, comparison)
            return .init(predicate: "size", matched: matched, explanation: "File size is \(file.size) bytes.")
        case .creationDate(let comparison, let value):
            return compareDate(file.creationDate, value, comparison, label: "creationDate")
        case .modificationDate(let comparison, let value):
            return compareDate(file.modificationDate, value, comparison, label: "modificationDate")
        case .finderTag(let values, let mode):
            let tags = Set(file.finderTags.map(normalize))
            let wanted = Set(values.map(normalize))
            let matched = mode == .all ? wanted.isSubset(of: tags) : !tags.isDisjoint(with: wanted)
            return .init(predicate: "finderTag", matched: matched, explanation: matched ? "Finder tags match." : "Finder tags do not match.")
        case .isHidden(let expected):
            return .init(predicate: "isHidden", matched: file.isHidden == expected, explanation: "Hidden state is \(file.isHidden).")
        }
    }

    private func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func compare(_ lhs: Int64, _ rhs: Int64, _ comparison: Comparison) -> Bool {
        switch comparison {
        case .lessThan: lhs < rhs
        case .lessThanOrEqual: lhs <= rhs
        case .equal: lhs == rhs
        case .greaterThanOrEqual: lhs >= rhs
        case .greaterThan: lhs > rhs
        }
    }

    private func compareDate(_ actual: Date?, _ target: Date, _ comparison: DateComparison, label: String) -> MatchReason {
        guard let actual else { return .init(predicate: label, matched: false, explanation: "Date metadata is unavailable.") }
        let matched: Bool
        switch comparison {
        case .before: matched = actual < target
        case .onOrBefore: matched = actual <= target
        case .onOrAfter: matched = actual >= target
        case .after: matched = actual > target
        }
        return .init(predicate: label, matched: matched, explanation: "Date comparison \(matched ? "matches" : "does not match").")
    }
}
