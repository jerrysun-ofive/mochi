import CryptoKit
import Foundation

public actor DecisionCache {
    private struct Entry: Codable { let decision: DestinationDecision; let createdAt: Date }
    private var entries: [String: Entry] = [:]
    private let maximumAge: TimeInterval

    public init(maximumAge: TimeInterval = 30 * 24 * 60 * 60) { self.maximumAge = maximumAge }

    public func value(for key: String, now: Date = Date()) -> DestinationDecision? {
        guard let entry = entries[key], now.timeIntervalSince(entry.createdAt) <= maximumAge else {
            entries[key] = nil
            return nil
        }
        return entry.decision
    }

    public func insert(_ decision: DestinationDecision, for key: String, now: Date = Date()) {
        entries[key] = Entry(decision: decision, createdAt: now)
    }

    public func invalidateAll() { entries.removeAll() }

    public static func key(
        request: DestinationDecisionRequest,
        provider: AIProviderDescriptor,
        authenticationKey: Data
    ) throws -> String {
        guard !authenticationKey.isEmpty else { throw DecisionCacheError.emptyAuthenticationKey }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(CacheMaterial(request: request, provider: provider))
        let code = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: authenticationKey))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private struct CacheMaterial: Codable {
        let request: DestinationDecisionRequest
        let provider: AIProviderDescriptor
    }
}

public enum DecisionCacheError: Error, Equatable {
    case emptyAuthenticationKey
}
