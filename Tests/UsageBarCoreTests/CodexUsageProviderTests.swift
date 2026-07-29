import Foundation
import XCTest
@testable import UsageBarCore

final class CodexUsageProviderTests: XCTestCase {
    func testFetchParsesCodexUsageResponse() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT([
                "email": "codex@example.com",
                "chatgpt_plan_type": "pro",
            ]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.provider, .codex)
        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.accountLabel, "Codex")
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Pro")
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 10)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 90)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetDescription, "5時間0分後")
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 12)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 88)
        XCTAssertEqual(httpClient.requests.map(\.url.absoluteString), [
            "https://chatgpt.com/backend-api/wham/usage",
        ])
        XCTAssertEqual(httpClient.requests.first?.headers["OpenAI-Beta"], "codex-1")
        XCTAssertEqual(httpClient.requests.first?.headers["originator"], "UsageBar")
        XCTAssertEqual(httpClient.requests.first?.headers["User-Agent"], "UsageBar/0.1.0")
        XCTAssertEqual(httpClient.requests.first?.headers["ChatGPT-Account-ID"], "account-id")
    }

    func testFetchRefreshesStaleCodexTokenAndUpdatesAppKeychainWithoutUpdatingAuthFile() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: "old-access-token",
            refreshToken: "old-refresh-token",
            idToken: makeJWT(["email": "old@example.com"]),
            lastRefresh: now.addingTimeInterval(-9 * 24 * 60 * 60))
        let originalAuthData = try Data(contentsOf: authFileURL)
        let newIDToken = makeJWT([
            "email": "new@example.com",
            "chatgpt_plan_type": "plus",
        ])
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(
                statusCode: 200,
                data: Data("""
                {
                  "access_token": "new-access-token",
                  "refresh_token": "new-refresh-token",
                  "id_token": "\(newIDToken)"
                }
                """.utf8)),
            HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
        ])
        let keychain = CodexMockKeychainClient(items: [:])
        let credentialStore = CodexCredentialStore(
            keychain: keychain,
            authStore: CodexAuthStore(authFileURL: authFileURL))
        _ = try credentialStore.importExistingCodexCredentials()
        let provider = CodexUsageProvider(
            credentialStore: credentialStore,
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()
        let authDataAfterRefresh = try Data(contentsOf: authFileURL)
        let savedCredentials = try CodexCredentialStore.decodeCredentials(
            from: keychain.items[key(CodexCredentialStore.appService, CodexCredentialStore.defaultAccount)]!)

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.accountLabel, "Codex")
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Plus")
        XCTAssertEqual(savedCredentials.accessToken, "new-access-token")
        XCTAssertEqual(savedCredentials.refreshToken, "new-refresh-token")
        XCTAssertEqual(savedCredentials.lastRefresh, now)
        XCTAssertEqual(authDataAfterRefresh, originalAuthData)
        XCTAssertEqual(httpClient.requests.map(\.method), ["POST", "GET"])
        XCTAssertEqual(httpClient.requests.first?.url.absoluteString, "https://auth.openai.com/oauth/token")
    }

    func testCredentialStoreDeletesAppCredentials() throws {
        let keychain = CodexMockKeychainClient(items: [:])
        let store = CodexCredentialStore(
            keychain: keychain,
            authStore: CodexAuthStore(authFileURL: URL(fileURLWithPath: "/tmp/UsageBarTests-unused-auth.json")))
        try store.saveAppCredentials(CodexAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: nil,
            accountID: "account-id",
            lastRefresh: nil))

        try store.deleteAppCredentials()

        XCTAssertNil(keychain.items[key(CodexCredentialStore.appService, CodexCredentialStore.defaultAccount)])
    }

    func testFetchReturnsAuthRequiredWhenAuthFileIsMissing() async {
        let provider = CodexUsageProvider(
            credentialStore: CodexCredentialStore(keychain: CodexMockKeychainClient(items: [:]), authStore: CodexAuthStore(authFileURL: URL(fileURLWithPath: "/tmp/UsageBarTests-missing-auth.json"))),
            httpClient: MockHTTPClient(responses: []),
            now: { Date(timeIntervalSince1970: 1_785_196_800) })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .authRequired)
        XCTAssertEqual(state.lastFailure?.code, "auth_required")
    }

    func testFetchDoesNotImportCodexCLICredentialsWithoutExplicitReauthentication() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["chatgpt_plan_type": "pro"]),
            lastRefresh: now)
        let keychain = CodexMockKeychainClient(items: [:])
        let httpClient = MockHTTPClient(responses: [])
        let provider = CodexUsageProvider(
            credentialStore: CodexCredentialStore(
                keychain: keychain,
                authStore: CodexAuthStore(authFileURL: authFileURL)),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .authRequired)
        XCTAssertEqual(state.lastFailure?.code, "auth_required")
        XCTAssertTrue(keychain.items.isEmpty)
        XCTAssertTrue(httpClient.requests.isEmpty)
    }

    func testExplicitReauthenticationImportsCodexCLICredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["chatgpt_plan_type": "pro"]),
            lastRefresh: now)
        let keychain = CodexMockKeychainClient(items: [:])
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: CodexCredentialStore(
                keychain: keychain,
                authStore: CodexAuthStore(authFileURL: authFileURL)),
            httpClient: httpClient,
            now: { now })

        let state = await provider.importExistingCredentials()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertNotNil(keychain.items[key(CodexCredentialStore.appService, CodexCredentialStore.defaultAccount)])
        XCTAssertEqual(httpClient.requests.count, 1)
    }

    func testFetchParsesAlternativeCodexUsageResponseShape() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "rateLimits": {
                "primary": {
                  "usedPercent": 30,
                  "reset_after_seconds": 3600
                },
                "secondary": {
                  "used_percent": 40,
                  "resetsAt": "2026-07-28T17:30:00Z"
                }
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 30)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 70)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 40)
    }

    func testFetchParsesCodexCLIStyleRateLimitShape() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary": {
                  "used_percent": "8",
                  "window_minutes": 300,
                  "resets_at": 1785218600
                },
                "secondary": {
                  "used_percent": 22.5,
                  "window_minutes": 10080,
                  "resets_at": "1785819800"
                }
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 8)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetAt, Date(timeIntervalSince1970: 1_785_218_600))
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 22.5)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.resetAt, Date(timeIntervalSince1970: 1_785_819_800))
    }

    func testFetchTreatsSingleCodexRateLimitWindowAsWeeklyLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "plan_type": "pro",
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 18,
                  "limit_window_seconds": 604800,
                  "reset_after_seconds": 360000,
                  "reset_at": 1785556800
                },
                "secondary_window": null
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertNil(state.lastSuccessful?.shortWindow)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.title, "週間制限")
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 18)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 82)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.resetAt, Date(timeIntervalSince1970: 1_785_556_800))
    }

    func testFetchTreatsWholeNumberCodexUtilizationAsPercent() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 1,
                  "reset_after_seconds": 604800
                },
                "secondary_window": null
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 1)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 99)
    }

    func testFetchShowsCodexResetAsUnknownWhenUnavailable() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 25
                },
                "secondary_window": null
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 75)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.resetDescription, "不明")
        XCTAssertNil(state.lastSuccessful?.weeklyWindow?.resetAt)
    }

    func testFetchReportsLimitsUnavailableWhenRateLimitWindowsAreMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let authFileURL = try writeAuthFile(
            accessToken: makeJWT(["exp": now.addingTimeInterval(3_600).timeIntervalSince1970]),
            idToken: makeJWT(["email": "codex@example.com"]),
            lastRefresh: now)
        let httpClient = MockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "plan_type": "pro",
              "rate_limit": {
                "allowed": true,
                "limit_reached": false
              }
            }
            """.utf8)),
        ])
        let provider = CodexUsageProvider(
            credentialStore: try makeCredentialStore(authFileURL: authFileURL),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .stale)
        XCTAssertEqual(state.lastFailure?.code, "limits_unavailable")
    }

    private func writeAuthFile(
        accessToken: String,
        refreshToken: String = "refresh-token",
        idToken: String,
        lastRefresh: Date) throws -> URL
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authFileURL = directory.appendingPathComponent("auth.json")
        let authData = Data("""
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(accessToken)",
            "refresh_token": "\(refreshToken)",
            "id_token": "\(idToken)",
            "account_id": "account-id"
          },
          "last_refresh": "\(UsageBarISO8601.string(from: lastRefresh, fractionalSeconds: true))"
        }
        """.utf8)
        try authData.write(to: authFileURL)
        return authFileURL
    }

    private func makeCredentialStore(authFileURL: URL) throws -> CodexCredentialStore {
        let keychain = CodexMockKeychainClient(items: [:])
        let store = CodexCredentialStore(
            keychain: keychain,
            authStore: CodexAuthStore(authFileURL: authFileURL))
        _ = try store.importExistingCodexCredentials()
        return store
    }

    private func usageResponseData(now: Date) -> Data {
        let secondaryReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(7 * 24 * 60 * 60),
            fractionalSeconds: true)
        return Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 10,
              "reset_at": \(Int(now.addingTimeInterval(5 * 60 * 60).timeIntervalSince1970)),
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 12,
              "reset_at": "\(secondaryReset)",
              "limit_window_seconds": 604800
            }
          }
        }
        """.utf8)
    }

    private func makeJWT(_ payload: [String: Any]) -> String {
        let header = base64URL(Data("{}".utf8))
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(header).\(base64URL(payloadData)).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func key(_ service: String, _ account: String?) -> String {
        "\(service)|\(account ?? "<nil>")"
    }
}

private final class CodexMockKeychainClient: KeychainClient, @unchecked Sendable {
    var items: [String: Data]

    init(items: [String: Data]) {
        self.items = items
    }

    func readGenericPassword(service: String, account: String?, allowInteraction: Bool) throws -> Data {
        _ = allowInteraction
        guard let data = items[key(service, account)] else {
            throw KeychainClientError.itemNotFound
        }
        return data
    }

    func writeGenericPassword(_ data: Data, service: String, account: String) throws {
        items[key(service, account)] = data
    }

    func deleteGenericPassword(service: String, account: String) throws {
        items.removeValue(forKey: key(service, account))
    }

    private func key(_ service: String, _ account: String?) -> String {
        "\(service)|\(account ?? "<nil>")"
    }
}

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    private var responses: [HTTPResponse]

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }
}
