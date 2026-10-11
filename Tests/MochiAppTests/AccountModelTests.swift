import CryptoKit
import Foundation
import XCTest
@testable import MochiApp

@MainActor
final class AccountModelTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertGreaterThanOrEqual(PKCE().verifier.count, 43)
    }

    func testGoogleAuthorizationURLUsesPKCEAndAppCallback() throws {
        let client = SupabaseAuthClient(configuration: .mochi)
        let url = client.googleAuthorizationURL(codeChallenge: "challenge")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.path, "/auth/v1/authorize")
        XCTAssertEqual(items.first(where: { $0.name == "provider" })?.value, "google")
        XCTAssertEqual(items.first(where: { $0.name == "redirect_to" })?.value, "mochi://auth-callback")
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge" })?.value, "challenge")
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "s256")
    }

    func testCallbackParsingReturnsCodeOrProviderError() throws {
        let client = SupabaseAuthClient(configuration: .mochi)
        XCTAssertEqual(try client.authorizationCode(from: URL(string: "mochi://auth-callback?code=abc")!), "abc")
        XCTAssertThrowsError(try client.authorizationCode(from: URL(string: "mochi://auth-callback#error=access_denied&error_description=Denied")!)) {
            XCTAssertEqual($0 as? AccountError, .provider("Denied"))
        }
        XCTAssertThrowsError(try client.authorizationCode(from: URL(string: "mochi://auth-callback")!)) {
            XCTAssertEqual($0 as? AccountError, .missingAuthorizationCode)
        }
    }

    func testGoogleSignInStoresSessionInCredentialStoreAndSignOutClearsIt() async throws {
        let server = FakeSupabase()
        let credentials = MemoryAccountCredentialStore()
        let client = SupabaseAuthClient(configuration: .mochi, transport: server.handle)
        let defaults = Self.isolatedDefaults()
        let model = AccountModel(client: client, credentials: credentials, defaults: defaults) { url, scheme in
            XCTAssertEqual(scheme, "mochi")
            server.challenge = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code_challenge" })?.value
            return URL(string: "mochi://auth-callback?code=auth-code")!
        }
        XCTAssertFalse(model.isSignedIn)

        await model.signInWithGoogle()

        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(model.displayName, "Mochi Fan")
        XCTAssertEqual(model.email, "fan@example.com")
        XCTAssertEqual(model.initials, "MF")
        XCTAssertTrue(server.verifierMatchedChallenge)
        let stored = try XCTUnwrap(credentials.values["supabase-session"])
        XCTAssertTrue(stored.contains("refresh-token"))

        model.displayNameEntry = "Renamed Fan"
        await model.saveDisplayName()
        XCTAssertEqual(model.displayName, "Renamed Fan")

        let restored = AccountModel(client: client, credentials: credentials, defaults: defaults) { _, _ in XCTFail("Should not reauthenticate"); throw AccountError.cancelled }
        XCTAssertTrue(restored.isSignedIn)

        await model.signOut()
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(credentials.values["supabase-session"])
        XCTAssertTrue(server.loggedOut)
    }

    func testSortedFilesAreKeptWhileSignedOutAndSyncedAfterSignIn() async throws {
        let server = FakeSupabase()
        let defaults = Self.isolatedDefaults()
        let model = AccountModel(client: SupabaseAuthClient(configuration: .mochi, transport: server.handle),
                                 credentials: MemoryAccountCredentialStore(), defaults: defaults) { url, _ in
            server.challenge = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code_challenge" })?.value
            return URL(string: "mochi://auth-callback?code=auth-code")!
        }

        model.recordSortedFiles(3)
        await model.syncUsage()
        XCTAssertEqual(model.pendingFilesSorted, 3)
        XCTAssertNil(model.syncedFilesSorted)
        XCTAssertEqual(defaults.integer(forKey: "account.pendingFilesSorted"), 3)

        await model.signInWithGoogle()
        XCTAssertEqual(model.syncedFilesSorted, 13)
        XCTAssertEqual(model.pendingFilesSorted, 0)
        XCTAssertEqual(model.totalFilesSorted, 13)

        model.recordSortedFiles(2)
        XCTAssertEqual(model.totalFilesSorted, 15)
        await model.syncUsage()
        XCTAssertEqual(model.syncedFilesSorted, 15)
        XCTAssertEqual(model.pendingFilesSorted, 0)
    }

    func testCancelledSignInLeavesAccountSignedOutWithoutError() async {
        let model = AccountModel(client: SupabaseAuthClient(configuration: .mochi, transport: { _ in throw URLError(.badURL) }),
                                 credentials: MemoryAccountCredentialStore(), defaults: Self.isolatedDefaults()) { _, _ in throw AccountError.cancelled }
        await model.signInWithGoogle()
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.statusMessage)
    }

    func testMochiProEntitlementUsesAuthenticatedEdgeFunction() async throws {
        let server = FakeSupabase()
        let client = SupabaseAuthClient(configuration: .mochi, transport: server.handle)
        let session = AccountSession(
            accessToken: "access-token", refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600),
            user: .init(id: "user-1", email: "fan@example.com", fullName: "Mochi Fan", avatarURL: nil)
        )
        let entitlement = try await client.mochiProEntitlement(session: session)
        XCTAssertTrue(entitlement.isActive)
        XCTAssertEqual(entitlement.plan, "pro")
        XCTAssertEqual(entitlement.requestsUsed, 12)
        XCTAssertEqual(entitlement.requestLimit, 1_000)
    }

    private static func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MochiAccountTests.\(UUID().uuidString)")!
    }
}

private final class MemoryAccountCredentialStore: AICredentialStoring {
    var values: [String: String] = [:]
    func save(_ secret: String, account: String) throws { values[account] = secret }
    func load(account: String) throws -> String? { values[account] }
    func remove(account: String) throws { values.removeValue(forKey: account) }
}

private final class FakeSupabase: @unchecked Sendable {
    private let lock = NSLock()
    private var state = (challenge: String?.none, verifierMatched: false, loggedOut: false, fullName: "Mochi Fan", filesSorted: 10)

    var challenge: String? {
        get { lock.withLock { state.challenge } }
        set { lock.withLock { state.challenge = newValue } }
    }
    var verifierMatchedChallenge: Bool { lock.withLock { state.verifierMatched } }
    var loggedOut: Bool { lock.withLock { state.loggedOut } }

    @Sendable func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        if url.host == SupabaseConfiguration.mochi.url.host {
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), SupabaseConfiguration.mochi.publishableKey)
        }
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let json: Any
        switch (request.httpMethod, url.path) {
        case ("POST", "/auth/v1/token"):
            XCTAssertEqual(body["auth_code"] as? String, "auth-code")
            let verifier = try XCTUnwrap(body["code_verifier"] as? String)
            let computed = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
            lock.withLock { state.verifierMatched = computed == state.challenge }
            json = [
                "access_token": "access-token", "refresh_token": "refresh-token", "expires_in": 3600,
                "user": ["id": "user-1", "email": "fan@example.com", "user_metadata": ["full_name": "Mochi Fan"]],
            ]
        case ("GET", "/rest/v1/profiles"):
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            json = [profileRow()]
        case ("PATCH", "/rest/v1/profiles"):
            lock.withLock { state.fullName = body["full_name"] as? String ?? state.fullName }
            json = [profileRow()]
        case ("POST", "/rest/v1/rpc/record_files_sorted"):
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let count = try XCTUnwrap(body["p_count"] as? Int)
            json = lock.withLock { state.filesSorted += count; return state.filesSorted }
        case ("POST", "/auth/v1/logout"):
            lock.withLock { state.loggedOut = true }
            return (Data(), HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        case ("GET", "/api/v1/billing/status"):
            XCTAssertEqual(url.host, "www.trymochi.dev")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            json = [
                "plan": "pro", "status": "active", "isActive": true,
                "currentPeriodEnd": NSNull(), "cancelAtPeriodEnd": false,
                "requestsUsed": 12, "requestLimit": 1_000,
            ]
        default:
            XCTFail("Unexpected request \(request.httpMethod ?? "") \(url)")
            json = [:]
        }
        return (try JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func profileRow() -> [String: Any] {
        ["id": "user-1", "email": "fan@example.com", "full_name": lock.withLock { state.fullName }, "avatar_url": NSNull()]
    }
}
