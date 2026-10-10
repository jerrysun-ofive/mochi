import Foundation

public struct TypeSafeJevDecisionProvider: DestinationDecisionProvider {
    public let descriptor: AIProviderDescriptor
    public let capabilities: DecisionCapabilities
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "jev-latest",
        endpoint: URL = URL(string: "https://api.typesafe.ai/v1/systemone")!,
        maximumCandidates: Int? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
        self.descriptor = .init(providerID: "typesafe", modelID: model)
        self.capabilities = .init(maximumCandidates: maximumCandidates, supportsBatch: false, supportsModelPinning: true, reportsUsage: true)
    }

    public func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision {
        guard !apiKey.isEmpty else { throw AIProviderError.missingCredential }
        if let maximum = capabilities.maximumCandidates, request.candidates.count > maximum {
            throw AIProviderError.unsupportedCandidateCount(maximum: maximum)
        }
        var criteria = Dictionary(uniqueKeysWithValues: request.candidates.map {
            ($0.id.uuidString, [$0.displayName, $0.userDescription, $0.examples.joined(separator: ", ")].compactMap { $0 }.joined(separator: " — "))
        })
        criteria[DestinationDecision.noneOfTheseID] = "No listed destination is appropriate for this file."
        let stateData = try JSONEncoder.mochi.encode(request.file)
        guard let state = String(data: stateData, encoding: .utf8) else { throw AIProviderError.invalidResponse }
        let body = JevRequest(
            state: state,
            model: descriptor.modelID,
            questions: ["destination": .init(
                type: "choice",
                instructions: "Choose the single most appropriate destination for this file. Choose none_of_these if no destination is suitable or the evidence is insufficient.",
                criteria: criteria
            )]
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder.mochi.encode(body)
        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: urlRequest)
        let elapsed = start.duration(to: clock.now)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIProviderError.unavailable(statusCode: http.statusCode) }
        guard let decoded = try? JSONDecoder.mochi.decode(JevResponse.self, from: data),
              let answer = decoded.answers["destination"] else { throw AIProviderError.invalidResponse }
        return DestinationDecision(
            selectedID: answer.choice,
            probabilities: answer.probabilities,
            confidence: answer.confidence,
            provider: .init(providerID: "typesafe", modelID: decoded.model, modelVersion: decoded.modelVersion),
            latencyMilliseconds: Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000),
            usage: .init(inputTokens: decoded.usage?.inputTokens ?? 0, outputTokens: decoded.usage?.outputTokens ?? 0)
        )
    }
}

private struct JevRequest: Encodable {
    let state: String
    let model: String
    let questions: [String: JevQuestion]
}

private struct JevQuestion: Encodable {
    let type: String
    let instructions: String
    let criteria: [String: String]
}

private struct JevResponse: Decodable {
    let model: String
    let modelVersion: String?
    let answers: [String: JevChoiceAnswer]
    let usage: JevUsage?

    enum CodingKeys: String, CodingKey {
        case model, answers, usage
        case modelVersion = "model_version"
    }
}

private struct JevChoiceAnswer: Decodable {
    let choice: String
    let probabilities: [String: Double]
    let confidence: Double
}

private struct JevUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

public extension JSONEncoder {
    static var mochi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var mochi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
