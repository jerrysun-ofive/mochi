import Foundation
import XCTest
@testable import MochiAI
@testable import MochiCore

final class DecisionCacheTests: XCTestCase {
    func testCacheKeyIsAuthenticatedAndModelSpecific() throws {
        let metadata = FileMetadata(
            url: URL(fileURLWithPath: "/tmp/report.pdf"),
            filename: "report.pdf",
            fileExtension: "pdf",
            size: 10
        )
        let request = DestinationDecisionRequest(
            file: .init(metadata: metadata),
            candidates: [.init(id: UUID(), displayName: "Reports")],
            candidateSetHash: "candidate-hash"
        )
        let key = Data("local-secret".utf8)
        let first = try DecisionCache.key(
            request: request,
            provider: .init(providerID: "provider", modelID: "model-a", modelVersion: "1"),
            authenticationKey: key
        )
        let second = try DecisionCache.key(
            request: request,
            provider: .init(providerID: "provider", modelID: "model-b", modelVersion: "1"),
            authenticationKey: key
        )
        XCTAssertNotEqual(first, second)
        XCTAssertThrowsError(try DecisionCache.key(
            request: request,
            provider: .init(providerID: "provider", modelID: "model-a"),
            authenticationKey: Data()
        ))
    }
}
