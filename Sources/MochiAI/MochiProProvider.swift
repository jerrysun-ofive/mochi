import Foundation

/// Thin client for Mochi Pro's provider-neutral gateway. Filesystem paths and
/// executable actions are absent from every request and response type.
public struct MochiProProvider: DestinationDecisionProvider, GenerativeAIProvider {
    public let descriptor: AIProviderDescriptor
    public let capabilities: DecisionCapabilities
    public let generativeCapabilities: GenerativeCapabilities

    private let baseURL: URL
    private let accessToken: String
    private let apiKey: String?
    private let session: URLSession

    public init(
        baseURL: URL,
        accessToken: String,
        registryVersion: String,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.apiKey = apiKey
        self.session = session
        self.descriptor = .init(providerID: "mochi-pro", modelID: "automatic", modelVersion: registryVersion)
        self.capabilities = .init(supportsBatch: true, supportsModelPinning: false, reportsUsage: true)
        self.generativeCapabilities = .init(structuredOutputs: true, supportsBatch: true, supportsCachedInput: true)
    }

    public func chooseDestination(_ request: DestinationDecisionRequest) async throws -> DestinationDecision {
        try await send(request, path: "v1/ai/destination-decision", response: DestinationDecision.self)
    }

    public func resolveDestination(_ request: DestinationGenerationRequest) async throws -> GenerativeDestinationResult {
        try await send(request, path: "v1/ai/destination-generation", response: GenerativeDestinationResult.self)
    }

    public func compileRule(_ request: NaturalLanguageRuleRequest) async throws -> RuleCompilationResult {
        try await send(request, path: "v1/ai/rule-compilation", response: RuleCompilationResult.self)
    }

    private func send<Request: Encodable, Response: Decodable>(
        _ payload: Request,
        path: String,
        response: Response.Type
    ) async throws -> Response {
        guard !accessToken.isEmpty else { throw AIProviderError.missingCredential }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(descriptor.modelVersion, forHTTPHeaderField: "X-Mochi-Model-Registry")
        request.httpBody = try JSONEncoder.mochi.encode(payload)
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.unavailable(statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder.mochi.decode(Response.self, from: data)
        } catch {
            throw AIProviderError.invalidResponse
        }
    }
}
