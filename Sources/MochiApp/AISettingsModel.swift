import Foundation
import MochiAI

enum GenerativeProviderChoice: String, CaseIterable, Identifiable {
    case openAI
    case gemini
    case deepSeek
    case ollama

    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .ollama: "Ollama (local)"
        }
    }
    var requiresAPIKey: Bool { self != .ollama }
    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash-lite"
        case .deepSeek: "deepseek-flash"
        case .ollama: "qwen3:4b"
        }
    }
}

protocol AICredentialStoring {
    func save(_ secret: String, account: String) throws
    func load(account: String) throws -> String?
    func remove(account: String) throws
}

extension KeychainCredentialStore: AICredentialStoring {}

enum BYOKConfiguration {
    static let jevAccount = "typesafe-jev-api-key"

    static func providerAccount(for provider: GenerativeProviderChoice) -> String { "\(provider.rawValue)-api-key" }

    /// Returns nil unless a Jev key and a usable generative provider are both saved.
    static func makeOrchestrator(
        defaults: UserDefaults = .standard,
        credentials: any AICredentialStoring = KeychainCredentialStore()
    ) -> HybridDecisionOrchestrator? {
        guard let jevKey = try? credentials.load(account: jevAccount), !jevKey.isEmpty else { return nil }
        let provider = defaults.string(forKey: "ai.generativeProvider").flatMap(GenerativeProviderChoice.init(rawValue:)) ?? .openAI
        let savedModel = defaults.string(forKey: "ai.generativeModel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = savedModel.isEmpty ? provider.defaultModel : savedModel
        let generative: any GenerativeAIProvider
        if provider == .ollama {
            let endpoint = defaults.string(forKey: "ai.ollamaEndpoint").flatMap(URL.init(string:))
                ?? URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
            generative = OpenAICompatibleGenerativeProvider.ollama(endpoint: endpoint, model: model)
        } else {
            guard let key = try? credentials.load(account: providerAccount(for: provider)), !key.isEmpty else { return nil }
            switch provider {
            case .openAI: generative = OpenAICompatibleGenerativeProvider.openAI(apiKey: key, model: model)
            case .gemini: generative = GeminiGenerativeProvider(apiKey: key, model: model)
            case .deepSeek: generative = OpenAICompatibleGenerativeProvider.deepSeek(apiKey: key, model: model)
            case .ollama: return nil
            }
        }
        return HybridDecisionOrchestrator(decisionProvider: TypeSafeJevDecisionProvider(apiKey: jevKey), generativeProvider: generative)
    }
}

@MainActor
final class AISettingsModel: ObservableObject {
    @Published var provider: GenerativeProviderChoice
    @Published var model: String
    @Published var ollamaEndpoint: String
    @Published var jevKeyEntry = ""
    @Published var providerKeyEntry = ""
    @Published private(set) var hasJevKey = false
    @Published private(set) var hasProviderKey = false
    @Published private(set) var statusMessage: String?

    private let defaults: UserDefaults
    private let credentials: any AICredentialStoring
    private static let jevAccount = BYOKConfiguration.jevAccount

    init(defaults: UserDefaults = .standard, credentials: any AICredentialStoring = KeychainCredentialStore()) {
        self.defaults = defaults
        self.credentials = credentials
        let savedProvider = defaults.string(forKey: "ai.generativeProvider").flatMap(GenerativeProviderChoice.init(rawValue:)) ?? .openAI
        provider = savedProvider
        model = defaults.string(forKey: "ai.generativeModel") ?? savedProvider.defaultModel
        ollamaEndpoint = defaults.string(forKey: "ai.ollamaEndpoint") ?? "http://127.0.0.1:11434/v1/chat/completions"
        refreshCredentialStatus()
    }

    var configurationIsComplete: Bool {
        let jevReady = hasJevKey || !jevKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let providerReady = !provider.requiresAPIKey || hasProviderKey || !providerKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let modelReady = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let endpointReady = provider != .ollama || URL(string: ollamaEndpoint)?.scheme != nil
        return jevReady && providerReady && modelReady && endpointReady
    }

    func providerChanged() {
        providerKeyEntry = ""
        model = defaults.string(forKey: "ai.generativeModel.\(provider.rawValue)") ?? provider.defaultModel
        refreshCredentialStatus()
    }

    func save() {
        do {
            let jev = jevKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerKey = providerKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !jev.isEmpty { try credentials.save(jev, account: Self.jevAccount) }
            if provider.requiresAPIKey, !providerKey.isEmpty { try credentials.save(providerKey, account: providerAccount) }
            defaults.set(provider.rawValue, forKey: "ai.generativeProvider")
            defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.generativeModel")
            defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.generativeModel.\(provider.rawValue)")
            defaults.set(ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.ollamaEndpoint")
            jevKeyEntry = ""
            providerKeyEntry = ""
            refreshCredentialStatus()
            statusMessage = "BYOK configuration saved securely in Keychain."
        } catch {
            statusMessage = "Could not save the AI configuration: \(error.localizedDescription)"
        }
    }

    func removeJevKey() {
        do {
            try credentials.remove(account: Self.jevAccount)
            jevKeyEntry = ""
            refreshCredentialStatus()
            statusMessage = "Removed the TypeSafe Jev key."
        } catch { statusMessage = "Could not remove the key: \(error.localizedDescription)" }
    }

    func removeProviderKey() {
        do {
            try credentials.remove(account: providerAccount)
            providerKeyEntry = ""
            refreshCredentialStatus()
            statusMessage = "Removed the \(provider.title) key."
        } catch { statusMessage = "Could not remove the key: \(error.localizedDescription)" }
    }

    private var providerAccount: String { BYOKConfiguration.providerAccount(for: provider) }

    private func refreshCredentialStatus() {
        do {
            hasJevKey = try credentials.load(account: Self.jevAccount) != nil
            if provider.requiresAPIKey {
                hasProviderKey = try credentials.load(account: providerAccount) != nil
            } else {
                hasProviderKey = false
            }
        } catch {
            hasJevKey = false
            hasProviderKey = false
            statusMessage = "Could not read AI credentials from Keychain: \(error.localizedDescription)"
        }
    }
}
