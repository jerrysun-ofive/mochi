import Foundation
import XCTest
@testable import MochiApp
@testable import MochiCore

@MainActor
final class UserWorkflowTests: XCTestCase {
    func testAuthorizeRulePreviewApproveHistoryAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = root.appendingPathComponent("state")
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = source.appendingPathComponent("invoice.pdf")
        try Data("fixture".utf8).write(to: original)

        let model = AppModel(supportRoot: state, securityScopedBookmarks: false)
        await model.authorizeFolder(url: source, role: .source)
        await model.authorizeFolder(url: destination, role: .destination)
        XCTAssertEqual(model.sourceGrants.count, 1)
        XCTAssertEqual(model.destinationGrants.count, 1)

        let rule = OrganizationRule(
            name: "PDF invoices",
            isEnabled: true,
            priority: 0,
            sourceGrantIDs: [model.sourceGrants[0].id],
            match: .init(operation: .all, predicates: [.fileExtension(values: ["pdf"])]),
            action: .init(disposition: .move(.init(grantID: model.destinationGrants[0].id)))
        )
        model.addRule(rule)
        XCTAssertEqual(model.rules.count, 1)

        await model.runNow()
        XCTAssertEqual(model.selectedSection, .review)
        XCTAssertEqual(model.proposals.count, 1)
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(proposal.source.filename, "invoice.pdf")

        await model.approve(proposal)
        let moved = destination.appendingPathComponent("invoice.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(model.history.first?.state, .committed)

        let record = try XCTUnwrap(model.history.first)
        await model.undo(record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(model.history.first?.state, .undone)
    }

    func testRuleEditingTogglingAndDeletionPersist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(supportRoot: root, securityScopedBookmarks: false)
        var rule = OrganizationRule(
            name: "Images",
            isEnabled: true,
            priority: 0,
            match: .init(operation: .all, predicates: [.fileExtension(values: ["png"])]),
            action: .init(disposition: .leave)
        )
        model.addRule(rule)
        model.setRuleEnabled(false, id: rule.id)
        XCTAssertFalse(model.rules[0].isEnabled)
        rule.name = "Screenshots"
        rule.isEnabled = true
        model.updateRule(rule)
        XCTAssertEqual(model.rules[0].name, "Screenshots")

        let reloaded = AppModel(supportRoot: root, securityScopedBookmarks: false)
        XCTAssertEqual(reloaded.rules.first?.name, "Screenshots")
        model.deleteRule(id: rule.id)
        XCTAssertTrue(model.rules.isEmpty)
    }

    func testMissingSetupRoutesUserToTheRequiredScreen() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(supportRoot: root, securityScopedBookmarks: false)
        await model.runNow()
        XCTAssertEqual(model.selectedSection, .folders)
        XCTAssertEqual(model.notice, "Add a watched folder before running Mochi.")
    }

    func testMonitoredChangeCreatesReviewWithoutTakingOverNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(supportRoot: root.appendingPathComponent("state"), securityScopedBookmarks: false)
        await model.authorizeFolder(url: source, role: .source)
        await model.authorizeFolder(url: destination, role: .destination)
        model.addRule(.init(
            name: "Text files",
            isEnabled: true,
            priority: 0,
            match: .init(operation: .all, predicates: [.fileExtension(values: ["txt"])]),
            action: .init(disposition: .move(.init(grantID: model.destinationGrants[0].id)))
        ))
        model.selectedSection = .overview
        try Data("new".utf8).write(to: source.appendingPathComponent("notes.txt"))
        await model.processMonitoredChangesNow()
        XCTAssertEqual(model.proposals.count, 1)
        XCTAssertEqual(model.selectedSection, .overview)
        XCTAssertTrue(model.notice?.contains("ready for review") == true)
    }

    func testQuickPDFRuleCreatesSubfolderAndRunsThroughReview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pdf = source.appendingPathComponent("guide.pdf")
        try Data("fixture".utf8).write(to: pdf)
        let model = AppModel(supportRoot: root.appendingPathComponent("state"), securityScopedBookmarks: false)
        await model.authorizeFolder(url: source, role: .source)
        await model.authorizeFolder(url: destination, role: .destination)

        let template = try XCTUnwrap(QuickRuleTemplate.builtIns.first(where: { $0.id == "pdfs" }))
        let added = await model.addQuickRule(template, sourceGrantID: model.sourceGrants[0].id, destinationGrantID: model.destinationGrants[0].id)
        XCTAssertTrue(added)
        XCTAssertEqual(model.rules.first?.name, "Sort PDFs")
        XCTAssertTrue(model.rules.first?.isEnabled == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("PDFs").path))
        let addedWithoutSource = await model.addQuickRule(template, sourceGrantID: nil, destinationGrantID: model.destinationGrants[0].id)
        XCTAssertFalse(addedWithoutSource)

        await model.runNow()
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(proposal.destinationURL?.path, destination.appendingPathComponent("PDFs/guide.pdf").path)
        await model.approve(proposal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("PDFs/guide.pdf").path))
    }

    func testQuickRuleInsideWatchedFolderIgnoresOtherDestinations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = root.appendingPathComponent("Downloads")
        let pdfFolder = downloads.appendingPathComponent("pdf")
        try FileManager.default.createDirectory(at: pdfFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fixture".utf8).write(to: downloads.appendingPathComponent("photo.png"))

        let model = AppModel(supportRoot: root.appendingPathComponent("state"), securityScopedBookmarks: false)
        await model.authorizeFolder(url: downloads, role: .source)
        await model.authorizeFolder(url: pdfFolder, role: .destination)

        let template = try XCTUnwrap(QuickRuleTemplate.builtIns.first(where: { $0.id == "images" }))
        let added = await model.addQuickRuleInsideWatchedFolder(template, sourceGrantID: model.sourceGrants[0].id)
        XCTAssertTrue(added)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("Images").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfFolder.appendingPathComponent("Images").path))

        await model.runNow()
        let proposal = try XCTUnwrap(model.proposals.first)
        XCTAssertEqual(proposal.destinationURL?.path, downloads.appendingPathComponent("Images/photo.png").path)
    }
}
