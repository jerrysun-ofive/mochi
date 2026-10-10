import Foundation
import XCTest
@testable import MochiCore

final class SafetyTests: XCTestCase {
    func testPathContainmentRejectsTraversal() {
        let root = URL(fileURLWithPath: "/tmp/mochi-root", isDirectory: true)
        XCTAssertNil(PathSafety.containedURL(root: root, relativePath: "../escape"))
        XCTAssertEqual(PathSafety.containedURL(root: root, relativePath: "Invoices")?.path, "/tmp/mochi-root/Invoices")
    }

    func testPathContainmentRejectsSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertNil(PathSafety.containedURL(root: root, relativePath: "escape/subfolder"))
    }

    func testValidatorRejectsUnknownRenameToken() {
        let rule = OrganizationRule(
            name: "Bad token",
            priority: 0,
            match: .init(operation: .all, predicates: [.fileExtension(values: ["pdf"])]),
            action: .init(disposition: .leave, renameTemplate: "{shell}")
        )
        XCTAssertEqual(RuleValidator().validate(rule), [.unsupportedRenameToken("{shell}")])
    }

    func testJournalRejectsInvalidTransition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = try OperationJournal(fileURL: directory.appendingPathComponent("journal.json"))
        let record = OperationRecord(ruleID: nil, sourceURL: directory.appendingPathComponent("a"), destinationURL: nil, sourceFingerprint: .init(size: 0, modificationDate: nil))
        try await journal.append(record)
        do {
            try await journal.transition(id: record.id, to: .committed)
            XCTFail("Expected invalid transition")
        } catch let error as JournalError {
            XCTAssertEqual(error, .invalidTransition(from: .planned, to: .committed))
        }
    }

    func testMoveCollisionAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceFolder = root.appendingPathComponent("source")
        let destinationFolder = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let conflict = destinationFolder.appendingPathComponent("report.txt")
        try Data("new".utf8).write(to: source)
        try Data("existing".utf8).write(to: conflict)
        let metadata = try MetadataExtractor().metadata(for: source)
        let journal = try OperationJournal(fileURL: root.appendingPathComponent("journal.json"))
        let executor = FileOperationExecutor(journal: journal)
        let proposal = ProposedOperation(source: metadata, ruleID: nil, destinationURL: conflict, reasons: [])
        let completed = try await executor.execute(proposal)
        XCTAssertEqual(completed.destinationURL?.lastPathComponent, "report (2).txt")
        XCTAssertEqual(completed.state, .committed)
        let undone = try await executor.undo(id: completed.id)
        XCTAssertEqual(undone.state, .undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: conflict, encoding: .utf8), "existing")
    }
}
