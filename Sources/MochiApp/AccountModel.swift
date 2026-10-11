import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import MochiAI
import Security

struct SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String
    let redirectURL: URL

    static let mochi = SupabaseConfiguration(
        url: URL(string: "https://qrsxwbkajfcplbtgiwpi.supabase.co")!,
        publishableKey: "sb_publishable_24kHcinVcx65peVbIfxCpg_GA6a3Vj2",
        redirectURL: URL(string: "mochi://auth-callback")!
    )

    var callbackScheme: String { redirectURL.scheme ?? "mochi" }
}

struct MochiProGatewayConfiguration: Sendable {
    let baseURL: URL

    static let production = MochiProGatewayConfiguration(
        baseURL: URL(string: "https://www.trymochi.dev/api")!
    )
}

struct AccountUser: Codable, Equatable, Sendable {
    var id: String
    var email: String?
    var fullName: String?
    var avatarURL: URL?
}

struct AccountSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: AccountUser
}

struct AccountProfile: Codable, Equatable, Sendable {
    var id: String
    var email: String?
    var fullName: String?
    var avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}

struct MochiProEntitlement: Codable, Equatable, Sendable {
    let plan: String
    let status: String
    let isActive: Bool
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool
    let requestsUsed: Int
    let requestLimit: Int

    static let free = MochiProEntitlement(
        plan: "free", status: "inactive", isActive: false, currentPeriodEnd: nil,
        cancelAtPeriodEnd: false, requestsUsed: 0, requestLimit: 0
    )
}

private struct BillingLink: Decodable { let url: URL }

enum AccountError: LocalizedError, Equatable {
    case cancelled
    case browserUnavailable
    case missingAuthorizationCode
    case provider(String)
    case server(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign in was cancelled."
        case .browserUnavailable: "Mochi could not open the sign-in window."
        case .missingAuthorizationCode: "Google did not return a sign-in code. Please try again."
        case .provider(let message): message
        case .server(_, let message): message
        case .invalidResponse: "The account service returned an unexpected response."
        }
    }
}

struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String = PKCE.randomVerifier()) {
        self.verifier = verifier
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct SupabaseAuthClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let configuration: SupabaseConfiguration
    let proConfiguration: MochiProGatewayConfiguration
    private let transport: Transport

    init(
        configuration: SupabaseConfiguration = .mochi,
        proConfiguration: MochiProGatewayConfiguration = .production,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.proConfiguration = proConfiguration
        self.transport = transport
    }

    func googleAuthorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(url: endpoint("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components.url!
    }

    func authorizationCode(from callbackURL: URL) throws -> String {
        var items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callbackURL.fragment {
            items += URLComponents(string: "?\(fragment)")?.queryItems ?? []
        }
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        if let code = value("code"), !code.isEmpty { return code }
        if let error = value("error_description") ?? value("error") { throw AccountError.provider(error) }
        throw AccountError.missingAuthorizationCode
    }

    func exchange(code: String, verifier: String) async throws -> AccountSession {
        let response: TokenResponse = try await send(
            path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "pkce")],
            method: "POST", body: ["auth_code": code, "code_verifier": verifier]
        )
        return response.session
    }

    func refresh(_ session: AccountSession) async throws -> AccountSession {
        let response: TokenResponse = try await send(
            path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST", body: ["refresh_token": session.refreshToken]
        )
        return response.session
    }

    func signOut(_ session: AccountSession) async throws {
        let _: EmptyResponse = try await send(path: "auth/v1/logout", method: "POST", accessToken: session.accessToken)
    }

    func profile(for session: AccountSession) async throws -> AccountProfile? {
        let rows: [AccountProfile] = try await send(
            path: "rest/v1/profiles",
            query: [URLQueryItem(name: "select", value: "id,email,full_name,avatar_url"), URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            accessToken: session.accessToken
        )
        return rows.first
    }

    func updateDisplayName(_ name: String, session: AccountSession) async throws -> AccountProfile {
        let rows: [AccountProfile] = try await send(
            path: "rest/v1/profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(session.user.id)"), URLQueryItem(name: "select", value: "id,email,full_name,avatar_url")],
            method: "PATCH", body: ["full_name": name], accessToken: session.accessToken,
            headers: ["Prefer": "return=representation"]
        )
        guard let profile = rows.first else { throw AccountError.invalidResponse }
        return profile
    }

    func recordFilesSorted(_ count: Int, session: AccountSession) async throws -> Int {
        try await send(path: "rest/v1/rpc/record_files_sorted", method: "POST", body: ["p_count": count], accessToken: session.accessToken)
    }

    func mochiProEntitlement(session: AccountSession) async throws -> MochiProEntitlement {
        try await sendPro(path: "v1/billing/status", accessToken: session.accessToken)
    }

    func createMochiProCheckout(session: AccountSession) async throws -> URL {
        let link: BillingLink = try await sendPro(
            path: "v1/billing/checkout", method: "POST", accessToken: session.accessToken
        )
        return link.url
    }

    func createMochiProPortal(session: AccountSession) async throws -> URL {
        let link: BillingLink = try await sendPro(
            path: "v1/billing/portal", method: "POST", accessToken: session.accessToken
        )
        return link.url
    }

    private func endpoint(_ path: String) -> URL { configuration.url.appendingPathComponent(path) }

    private func sendPro<Response: Decodable>(path: String, method: String = "GET", accessToken: String) async throws -> Response {
        var request = URLRequest(url: proConfiguration.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.message
            throw AccountError.server(status: http.statusCode, message: message ?? "The Mochi Pro service returned status \(http.statusCode).")
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountError.invalidResponse }
    }

    private func send<Response: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: (any Encodable)? = nil,
        accessToken: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var components = URLComponents(url: endpoint(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.message
            throw AccountError.server(status: http.statusCode, message: message ?? "The account service returned status \(http.statusCode).")
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw AccountError.invalidResponse }
    }
}

private struct EmptyResponse: Decodable {}

private struct ServerError: Decodable {
    let message: String?
    enum CodingKeys: String, CodingKey { case errorDescription = "error_description", error, msg, message }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .errorDescription)
            ?? container.decodeIfPresent(String.self, forKey: .error)
            ?? container.decodeIfPresent(String.self, forKey: .msg)
            ?? container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct TokenResponse: Decodable {
    struct User: Decodable {
        struct Metadata: Decodable {
            let fullName: String?
            let name: String?
            let avatarURL: String?
            let picture: String?
            enum CodingKeys: String, CodingKey { case fullName = "full_name", name, avatarURL = "avatar_url", picture }
        }
        let id: String
        let email: String?
        let userMetadata: Metadata?
        enum CodingKeys: String, CodingKey { case id, email, userMetadata = "user_metadata" }
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double?
    let expiresAt: Double?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token"
        case expiresIn = "expires_in", expiresAt = "expires_at", user
    }

    var session: AccountSession {
        let expiry = expiresAt.map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(expiresIn ?? 3600)
        let metadata = user.userMetadata
        return AccountSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            user: AccountUser(
                id: user.id,
                email: user.email,
                fullName: metadata?.fullName ?? metadata?.name,
                avatarURL: (metadata?.avatarURL ?? metadata?.picture).flatMap(URL.init(string:))
            )
        )
    }
}

typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

@MainActor
final class WebAuthenticationSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    static func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await WebAuthenticationSessionRunner().start(url: url, callbackScheme: callbackScheme)
    }

    private func start(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { @Sendable callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AccountError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AccountError.browserUnavailable)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: AccountError.browserUnavailable)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: \.isVisible) ?? ASPresentationAnchor()
        }
    }
}

@MainActor
final class AccountModel: ObservableObject {
    @Published private(set) var session: AccountSession?
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var syncedFilesSorted: Int?
    @Published private(set) var proEntitlement: MochiProEntitlement = .free
    @Published private(set) var pendingFilesSorted: Int {
        didSet { defaults.set(pendingFilesSorted, forKey: Self.pendingFilesSortedKey) }
    }
    @Published var displayNameEntry = ""

    private let client: SupabaseAuthClient
    private let credentials: any AICredentialStoring
    private let defaults: UserDefaults
    private let authenticate: WebAuthenticator
    private var isSyncingUsage = false
    private static let sessionAccount = "supabase-session"
    private static let pendingFilesSortedKey = "account.pendingFilesSorted"

    init(
        client: SupabaseAuthClient = SupabaseAuthClient(),
        credentials: any AICredentialStoring = KeychainCredentialStore(service: "app.mochi.account"),
        defaults: UserDefaults = .standard,
        authenticate: @escaping WebAuthenticator = { try await WebAuthenticationSessionRunner.authenticate(url: $0, callbackScheme: $1) }
    ) {
        self.client = client
        self.credentials = credentials
        self.defaults = defaults
        self.authenticate = authenticate
        pendingFilesSorted = max(0, defaults.integer(forKey: Self.pendingFilesSortedKey))
        if let stored = try? credentials.load(account: Self.sessionAccount),
           let session = try? JSONDecoder().decode(AccountSession.self, from: Data(stored.utf8)) {
            self.session = session
            displayNameEntry = session.user.fullName ?? ""
            Task { await reload() }
        }
    }

    var isSignedIn: Bool { session != nil }
    var isPro: Bool { proEntitlement.isActive }
    var totalFilesSorted: Int { (syncedFilesSorted ?? 0) + pendingFilesSorted }
    var email: String? { profile?.email ?? session?.user.email }
    var avatarURL: URL? { profile?.avatarURL ?? session?.user.avatarURL }

    var displayName: String {
        let name = (profile?.fullName ?? session?.user.fullName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return email ?? "Mochi user"
    }

    var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var displayNameChanged: Bool {
        let entry = displayNameEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        return !entry.isEmpty && entry.count <= 120 && entry != (profile?.fullName ?? session?.user.fullName ?? "")
    }

    func signInWithGoogle() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        do {
            let pkce = PKCE()
            let callback = try await authenticate(client.googleAuthorizationURL(codeChallenge: pkce.challenge), client.configuration.callbackScheme)
            let code = try client.authorizationCode(from: callback)
            try store(try await client.exchange(code: code, verifier: pkce.verifier))
            profile = try? await client.profile(for: session!)
            displayNameEntry = profile?.fullName ?? session?.user.fullName ?? ""
            statusMessage = "Signed in as \(email ?? displayName)."
            await refreshProEntitlement(silently: true)
            await syncUsage()
        } catch AccountError.cancelled {
            statusMessage = nil
        } catch {
            statusMessage = "Could not sign in: \(error.localizedDescription)"
        }
    }

    func reload() async {
        do {
            let current = try await validSession()
            profile = try await client.profile(for: current)
            if let name = profile?.fullName { displayNameEntry = name }
            await refreshProEntitlement(silently: true)
            await syncUsage()
        } catch AccountError.server(let status, _) where status == 400 || status == 401 {
            clearSession()
            statusMessage = "Your session expired. Please sign in again."
        } catch {
            statusMessage = "Could not load your profile: \(error.localizedDescription)"
        }
    }

    func saveDisplayName() async {
        guard displayNameChanged, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let name = displayNameEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            profile = try await client.updateDisplayName(name, session: try await validSession())
            displayNameEntry = profile?.fullName ?? name
            statusMessage = "Profile saved."
        } catch {
            statusMessage = "Could not save your profile: \(error.localizedDescription)"
        }
    }

    func recordSortedFiles(_ count: Int) {
        guard count > 0 else { return }
        pendingFilesSorted += count
        Task { await syncUsage() }
    }

    func syncUsage() async {
        guard session != nil, !isSyncingUsage else { return }
        isSyncingUsage = true
        defer { isSyncingUsage = false }
        repeat {
            let batch = min(pendingFilesSorted, 10_000)
            do {
                syncedFilesSorted = try await client.recordFilesSorted(batch, session: try await validSession())
                pendingFilesSorted -= batch
            } catch {
                return
            }
        } while pendingFilesSorted > 0
    }

    func signOut() async {
        guard let session else { return }
        try? await client.signOut(session)
        clearSession()
        statusMessage = "Signed out."
    }

    func upgradeToPro() async {
        await openBillingPage(kind: .checkout)
    }

    func manageSubscription() async {
        await openBillingPage(kind: .portal)
    }

    func refreshPlan() async {
        await refreshProEntitlement(silently: false)
    }

    func mochiProProvider() async throws -> MochiProProvider {
        guard isPro else { throw AccountError.server(status: 402, message: "An active Mochi Pro subscription is required.") }
        let current = try await validSession()
        return MochiProProvider(
            baseURL: client.proConfiguration.baseURL,
            accessToken: current.accessToken,
            registryVersion: "2026-10-11"
        )
    }

    private enum BillingPage { case checkout, portal }

    private func openBillingPage(kind: BillingPage) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let current = try await validSession()
            let url = switch kind {
            case .checkout: try await client.createMochiProCheckout(session: current)
            case .portal: try await client.createMochiProPortal(session: current)
            }
            guard NSWorkspace.shared.open(url) else { throw AccountError.browserUnavailable }
            switch kind {
            case .checkout: statusMessage = "Finish checkout in your browser, then refresh your plan."
            case .portal: statusMessage = "Mochi Pro billing opened in your browser."
            }
        } catch {
            statusMessage = "Could not open Mochi Pro billing: \(error.localizedDescription)"
        }
    }

    private func refreshProEntitlement(silently: Bool) async {
        guard session != nil else { proEntitlement = .free; return }
        do {
            proEntitlement = try await client.mochiProEntitlement(session: try await validSession())
            if !silently { statusMessage = isPro ? "Mochi Pro is active." : "No active Mochi Pro subscription was found." }
        } catch {
            if !silently { statusMessage = "Could not refresh Mochi Pro: \(error.localizedDescription)" }
        }
    }

    private func validSession() async throws -> AccountSession {
        guard let session else { throw AccountError.server(status: 401, message: "Not signed in.") }
        guard session.expiresAt.timeIntervalSinceNow < 60 else { return session }
        let refreshed = try await client.refresh(session)
        try store(refreshed)
        return refreshed
    }

    private func store(_ session: AccountSession) throws {
        let data = try JSONEncoder().encode(session)
        try credentials.save(String(decoding: data, as: UTF8.self), account: Self.sessionAccount)
        self.session = session
    }

    private func clearSession() {
        try? credentials.remove(account: Self.sessionAccount)
        session = nil
        profile = nil
        proEntitlement = .free
        syncedFilesSorted = nil
        displayNameEntry = ""
    }
}
