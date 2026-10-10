import Foundation
import XCTest
@testable import MochiCore

final class RuleEngineTests: XCTestCase {
    private let source = UUID()
    private let destination = UUID()

    func testFirstEnabledRuleWinsByPriority() {
        let lowPriority = rule(name: "Second", priority: 20, predicate: .fileExtension(values: ["pdf"]))
        let highPriority = rule(name: "First", priority: 10, predicate: .filename(operation: .contains, value: "invoice"))
        let result = RuleEngine().firstMatch(file: file(name: "Invoice.PDF"), sourceGrantID: source, rules: [lowPriority, highPriority])
        XCTAssertEqual(result?.rule.name, "First")
    }

    func testAllRequiresEveryPredicate() {
        var value = rule(name: "Invoice", priority: 0, predicate: .fileExtension(values: ["pdf"]))
        value.match.predicates.append(.filename(operation: .contains, value: "invoice"))
        XCTAssertTrue(RuleEngine().evaluate(file: file(name: "invoice.pdf"), rule: value).matched)
        XCTAssertFalse(RuleEngine().evaluate(file: file(name: "notes.pdf"), rule: value).matched)
    }

    func testMissingDateDoesNotMatch() {
        let value = rule(name: "Old", priority: 0, predicate: .creationDate(comparison: .before, value: Date()))
        let evaluation = RuleEngine().evaluate(file: file(name: "x.txt"), rule: value)
        XCTAssertFalse(evaluation.matched)
        XCTAssertEqual(evaluation.reasons.first?.explanation, "Date metadata is unavailable.")
    }

    func testDisabledRuleIsIgnored() {
        var value = rule(name: "Disabled", priority: 0, predicate: .fileExtension(values: ["pdf"]))
        value.isEnabled = false
        XCTAssertNil(RuleEngine().firstMatch(file: file(name: "x.pdf"), sourceGrantID: source, rules: [value]))
    }

    private func rule(name: String, priority: Int, predicate: RulePredicate) -> OrganizationRule {
        OrganizationRule(
            name: name,
            isEnabled: true,
            priority: priority,
            sourceGrantIDs: [source],
            match: .init(operation: .all, predicates: [predicate]),
            action: .init(disposition: .move(.init(grantID: destination)))
        )
    }

    private func file(name: String) -> FileMetadata {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return .init(url: url, filename: name, fileExtension: url.pathExtension, size: 10)
    }
}
