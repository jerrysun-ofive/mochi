import Foundation

public struct BenchmarkCase: Codable, Identifiable, Sendable {
    public let id: String
    public let taxonomyID: String
    public let request: DestinationDecisionRequest
    public let expectedDestinationID: String
    public let ambiguous: Bool
}

public struct BenchmarkObservation: Codable, Sendable {
    public let caseID: String
    public let provider: AIProviderDescriptor
    public let expected: String
    public let predicted: String?
    public let confidence: Double?
    public let latencyMilliseconds: Int
    public let transmittedBytes: Int
    public let attempts: Int
    public let usage: AIUsage
    public let error: String?

    public var correct: Bool { expected == predicted }
}

public struct BenchmarkReport: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let datasetFingerprint: String
    public let observations: [BenchmarkObservation]
    public let metrics: BenchmarkMetrics
}

public struct BenchmarkMetrics: Codable, Sendable {
    public let total: Int
    public let accuracy: Double
    public let nonePrecision: Double
    public let noneRecall: Double
    public let noneF1: Double
    public let abstentionRate: Double
    public let errorRate: Double
    public let brierScore: Double
    public let expectedCalibrationError: Double
    public let medianLatencyMilliseconds: Double
    public let p95LatencyMilliseconds: Double
    public let p99LatencyMilliseconds: Double
    public let totalTransmittedBytes: Int
    public let totalAttempts: Int
    public let totalInputTokens: Int
    public let totalCachedInputTokens: Int
    public let totalOutputTokens: Int
    public let totalBilledCostUSD: Decimal
    public let projectedCostPerThousandUSD: Decimal
}

public struct BenchmarkRunner: Sendable {
    public init() {}

    public func run(cases: [BenchmarkCase], provider: any DestinationDecisionProvider) async -> BenchmarkReport {
        var observations: [BenchmarkObservation] = []
        for item in cases {
            let transmittedBytes = (try? JSONEncoder.mochi.encode(item.request).count) ?? 0
            do {
                let result = try await provider.chooseDestination(item.request)
                observations.append(.init(
                    caseID: item.id,
                    provider: result.provider,
                    expected: item.expectedDestinationID,
                    predicted: result.selectedID,
                    confidence: result.confidence,
                    latencyMilliseconds: result.latencyMilliseconds,
                    transmittedBytes: transmittedBytes,
                    attempts: 1,
                    usage: result.usage,
                    error: nil
                ))
            } catch {
                observations.append(.init(
                    caseID: item.id,
                    provider: provider.descriptor,
                    expected: item.expectedDestinationID,
                    predicted: nil,
                    confidence: nil,
                    latencyMilliseconds: 0,
                    transmittedBytes: transmittedBytes,
                    attempts: 1,
                    usage: .init(),
                    error: String(describing: error)
                ))
            }
        }
        return BenchmarkReport(
            schemaVersion: 1,
            generatedAt: Date(),
            datasetFingerprint: datasetFingerprint(cases),
            observations: observations,
            metrics: metrics(observations)
        )
    }

    private func metrics(_ values: [BenchmarkObservation]) -> BenchmarkMetrics {
        let successful = values.filter { $0.predicted != nil }
        let correct = successful.filter(\.correct).count
        let predictedNone = successful.filter { $0.predicted == DestinationDecision.noneOfTheseID }
        let expectedNone = successful.filter { $0.expected == DestinationDecision.noneOfTheseID }
        let trueNone = predictedNone.filter { $0.expected == DestinationDecision.noneOfTheseID }.count
        let nonePrecision = predictedNone.isEmpty ? 0 : Double(trueNone) / Double(predictedNone.count)
        let noneRecall = expectedNone.isEmpty ? 0 : Double(trueNone) / Double(expectedNone.count)
        let latencies = successful.map(\.latencyMilliseconds).sorted()
        let median = percentile(latencies, 0.5)
        let p95 = percentile(latencies, 0.95)
        let p99 = percentile(latencies, 0.99)
        let cost = successful.compactMap(\.usage.billedCostUSD).reduce(Decimal.zero, +)
        let projectedCost = successful.isEmpty ? Decimal.zero : cost * 1_000 / Decimal(successful.count)
        let brier = successful.isEmpty ? 0 : successful.reduce(0.0) { sum, observation in
            let predictedProbability = observation.confidence ?? 0
            let outcome = observation.correct ? 1.0 : 0.0
            return sum + pow(predictedProbability - outcome, 2)
        } / Double(successful.count)
        return BenchmarkMetrics(
            total: values.count,
            accuracy: successful.isEmpty ? 0 : Double(correct) / Double(successful.count),
            nonePrecision: nonePrecision,
            noneRecall: noneRecall,
            noneF1: nonePrecision + noneRecall == 0 ? 0 : 2 * nonePrecision * noneRecall / (nonePrecision + noneRecall),
            abstentionRate: values.isEmpty ? 0 : Double(predictedNone.count) / Double(values.count),
            errorRate: values.isEmpty ? 0 : Double(values.filter { $0.error != nil }.count) / Double(values.count),
            brierScore: brier,
            expectedCalibrationError: expectedCalibrationError(successful),
            medianLatencyMilliseconds: median,
            p95LatencyMilliseconds: p95,
            p99LatencyMilliseconds: p99,
            totalTransmittedBytes: values.map(\.transmittedBytes).reduce(0, +),
            totalAttempts: values.map(\.attempts).reduce(0, +),
            totalInputTokens: successful.map(\.usage.inputTokens).reduce(0, +),
            totalCachedInputTokens: successful.map(\.usage.cachedInputTokens).reduce(0, +),
            totalOutputTokens: successful.map(\.usage.outputTokens).reduce(0, +),
            totalBilledCostUSD: cost,
            projectedCostPerThousandUSD: projectedCost
        )
    }

    private func expectedCalibrationError(_ values: [BenchmarkObservation], buckets: Int = 10) -> Double {
        guard !values.isEmpty else { return 0 }
        var weightedError = 0.0
        for bucket in 0..<buckets {
            let lower = Double(bucket) / Double(buckets)
            let upper = Double(bucket + 1) / Double(buckets)
            let members = values.filter {
                let confidence = $0.confidence ?? 0
                return confidence >= lower && (bucket == buckets - 1 ? confidence <= upper : confidence < upper)
            }
            guard !members.isEmpty else { continue }
            let averageConfidence = members.compactMap(\.confidence).reduce(0, +) / Double(members.count)
            let accuracy = Double(members.filter(\.correct).count) / Double(members.count)
            weightedError += abs(accuracy - averageConfidence) * Double(members.count) / Double(values.count)
        }
        return weightedError
    }

    private func datasetFingerprint(_ cases: [BenchmarkCase]) -> String {
        guard let data = try? JSONEncoder.mochi.encode(cases) else { return "unavailable" }
        return StableDigest.hex(data)
    }

    private func percentile(_ sorted: [Int], _ percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
        return Double(sorted[index])
    }
}

private enum StableDigest {
    static func hex(_ data: Data) -> String {
        // FNV-1a is used only as a reproducibility fingerprint, not as a security primitive.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

public struct StaticDecisionProvider: DestinationDecisionProvider {
    public let descriptor: AIProviderDescriptor
    public let capabilities = DecisionCapabilities()
    private let decisions: [String: String]

    public init(providerID: String = "fixture", modelID: String = "static-v1", decisions: [String: String]) {
        self.descriptor = .init(providerID: providerID, modelID: modelID, modelVersion: "1")
        self.decisions = decisions
    }

    public func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision {
        let selected = decisions[request.candidateSetHash] ?? DestinationDecision.noneOfTheseID
        return .init(selectedID: selected, probabilities: [selected: 1], confidence: 1, provider: descriptor, latencyMilliseconds: 1, usage: .init())
    }
}
