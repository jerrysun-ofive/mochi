import Foundation
import XCTest
@testable import MochiAI
@testable import MochiCore

final class BenchmarkTests: XCTestCase {
    func testBenchmarkComputesAccuracyAndNoneMetrics() async {
        let destination = UUID()
        let metadata = FileMetadata(url: URL(fileURLWithPath: "/tmp/a.pdf"), filename: "a.pdf", fileExtension: "pdf", size: 1)
        let requestA = DestinationDecisionRequest(file: .init(metadata: metadata), candidates: [.init(id: destination, displayName: "Docs")], candidateSetHash: "a")
        let requestB = DestinationDecisionRequest(file: .init(metadata: metadata), candidates: [.init(id: destination, displayName: "Docs")], candidateSetHash: "b")
        let cases = [
            BenchmarkCase(id: "1", taxonomyID: "t1", request: requestA, expectedDestinationID: destination.uuidString, ambiguous: false),
            BenchmarkCase(id: "2", taxonomyID: "t2", request: requestB, expectedDestinationID: DestinationDecision.noneOfTheseID, ambiguous: false),
        ]
        let provider = StaticDecisionProvider(decisions: ["a": destination.uuidString, "b": DestinationDecision.noneOfTheseID])
        let report = await BenchmarkRunner().run(cases: cases, provider: provider)
        XCTAssertEqual(report.metrics.accuracy, 1)
        XCTAssertEqual(report.metrics.nonePrecision, 1)
        XCTAssertEqual(report.metrics.noneRecall, 1)
        XCTAssertEqual(report.metrics.noneF1, 1)
        XCTAssertEqual(report.metrics.errorRate, 0)
        XCTAssertGreaterThan(report.metrics.totalTransmittedBytes, 0)
        XCTAssertEqual(report.metrics.totalAttempts, 2)
        XCTAssertFalse(report.datasetFingerprint.isEmpty)
    }
}
