import Foundation
import XCTest
@testable import UsageBarCore

final class ClaudeUsageProviderTests: XCTestCase {
    func testEncodeCredentialsDoesNotPersistAccountEmail() throws {
        let data = try ClaudeOAuthCredentialStore.encodeCredentials(
            ClaudeOAuthCredentials(
                accessToken: "access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_785_196_800),
                scopes: ["usage"],
                accountLabel: "claude@example.com",
                rateLimitTier: "max"))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("claude@example.com"))
        XCTAssertFalse(json.contains("\"email\""))
        XCTAssertFalse(json.contains("\"account\""))
        XCTAssertTrue(json.contains("\"rateLimitTier\""))
    }

    func testFetchParsesClaudeUsageResponseFromAppKeychainCache() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.provider, .claude)
        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.accountLabel, "Claude")
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Max")
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 25)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 75)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 10)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 90)
        XCTAssertEqual(httpClient.requests.map(\.url.absoluteString), [
            "https://api.anthropic.com/api/oauth/usage",
        ])
        XCTAssertEqual(httpClient.requests.first?.headers["User-Agent"], "UsageBar/0.1.0")
    }

    func testFetchPrefersClaudeSubscriptionTypeForPlanLabel() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: nil,
                        rateLimitTier: "default_claude_ai",
                        subscriptionType: "pro")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Pro")
    }

    func testFetchMapsClaudeRateLimitTierFallbackForPlanLabel() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: nil,
                        rateLimitTier: "default_claude_ai")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Pro")
    }

    func testFetchMapsClaudeMaxMultiplierRateLimitTierForPlanLabel() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: nil,
                        rateLimitTier: "default_claude_max_5x")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.planLabel, "Max 5x")
    }

    func testFetchDoesNotImportClaudeCodeCredentialsByDefaultWhenAppCacheIsMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.claudeCodeService, nil):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "imported-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: [],
                        accountLabel: "imported@example.com",
                        rateLimitTier: "pro")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .authRequired)
        XCTAssertFalse(keychain.reads.contains { $0.service == ClaudeOAuthCredentialStore.claudeCodeService })
        XCTAssertNil(keychain.items[key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount)])
    }

    func testExplicitReauthenticationImportsClaudeCodeCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.claudeCodeService, nil):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "imported-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: [],
                        accountLabel: "imported@example.com",
                        rateLimitTier: "pro")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.importExistingCredentials()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.accountLabel, "Claude")
        XCTAssertTrue(keychain.reads.contains(KeychainRead(
            service: ClaudeOAuthCredentialStore.claudeCodeService,
            account: nil,
            allowInteraction: true)))
        XCTAssertNotNil(keychain.items[key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount)])
    }

    func testFetchRefreshesExpiredClaudeTokenAndUpdatesAppCache() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "old-token",
                        refreshToken: "old-refresh-token",
                        expiresAt: now.addingTimeInterval(-10),
                        scopes: ["old"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "team")),
        ])
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(
                statusCode: 200,
                data: Data("""
                {
                  "access_token": "new-token",
                  "refresh_token": "new-refresh-token",
                  "expires_in": 3600,
                  "scope": "usage profile"
                }
                """.utf8)),
            HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()
        let saved = try ClaudeOAuthCredentialStore.decodeCredentials(
            from: keychain.items[key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount)]!)

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(saved.accessToken, "new-token")
        XCTAssertEqual(saved.refreshToken, "new-refresh-token")
        XCTAssertEqual(saved.scopes, ["usage", "profile"])
        XCTAssertEqual(httpClient.requests.map(\.method), ["POST", "GET"])
    }

    func testFetchParsesClaudeUsageResponseWithoutFiveHourLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let weeklyReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(7 * 24 * 60 * 60),
            fractionalSeconds: false)
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "seven_day": {
                "utilization": 12,
                "resets_at": "\(weeklyReset)"
              }
            }
            """.utf8)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertNil(state.lastSuccessful?.shortWindow)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.title, "週間制限")
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 12)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 88)
    }

    func testFetchParsesFlexibleClaudeUsageResponseShape() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "rateLimits": {
                "session": {
                  "utilization": "0.18",
                  "resetAt": 1785218600,
                  "window_minutes": 300
                },
                "weekly": {
                  "usedPercent": "35",
                  "reset_at": "1785819800",
                  "limit_window_seconds": 604800
                }
              }
            }
            """.utf8)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 18)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetAt, Date(timeIntervalSince1970: 1_785_218_600))
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 35)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.resetAt, Date(timeIntervalSince1970: 1_785_819_800))
    }

    func testFetchParsesClaudeFiveHourLimitWithResetAfterSeconds() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let weeklyReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(7 * 24 * 60 * 60),
            fractionalSeconds: false)
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "five_hour": {
                "utilization": 0.22,
                "reset_after_seconds": 7200
              },
              "seven_day": {
                "utilization": 12,
                "resets_at": "\(weeklyReset)"
              }
            }
            """.utf8)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 22)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 78)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetAt, now.addingTimeInterval(7_200))
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 12)
    }

    func testFetchShowsClaudeFiveHourLimitWhenResetIsUnavailable() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let weeklyReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(7 * 24 * 60 * 60),
            fractionalSeconds: false)
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "five_hour": {
                "utilization": 0.18,
                "resets_at": null
              },
              "seven_day": {
                "utilization": 13,
                "resets_at": "\(weeklyReset)"
              }
            }
            """.utf8)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.title, "5時間制限")
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 18)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 82)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.resetDescription, "不明")
        XCTAssertNil(state.lastSuccessful?.shortWindow?.resetAt)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 13)
    }

    func testFetchTreatsWholeNumberClaudeUtilizationAsPercent() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "pro")),
        ])
        let reset = UsageBarISO8601.string(
            from: now.addingTimeInterval(5 * 60 * 60),
            fractionalSeconds: false)
        let httpClient = MockClaudeHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: Data("""
            {
              "five_hour": {
                "utilization": 1,
                "resets_at": "\(reset)"
              },
              "seven_day": {
                "utilization": 13,
                "resets_at": "\(reset)"
              }
            }
            """.utf8)),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: httpClient,
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.usedPercent, 1)
        XCTAssertEqual(state.lastSuccessful?.shortWindow?.remainingPercent, 99)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.usedPercent, 13)
        XCTAssertEqual(state.lastSuccessful?.weeklyWindow?.remainingPercent, 87)
    }

    func testFetchReportsLimitsUnavailableWhenClaudeLimitWindowsAreMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: ["usage"],
                        accountLabel: "claude@example.com",
                        rateLimitTier: "max")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: Data("{}".utf8)),
            ]),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .stale)
        XCTAssertEqual(state.lastFailure?.code, "limits_unavailable")
    }

    func testFetchReturnsAuthRequiredWhenCredentialsAreUnavailable() async {
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(
                keychain: MockKeychainClient(items: [:]),
                credentialsFileURL: URL(fileURLWithPath: "/tmp/UsageBarTests-missing-claude-credentials.json")),
            httpClient: MockClaudeHTTPClient(responses: []),
            now: { Date(timeIntervalSince1970: 1_785_196_800) })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .authRequired)
        XCTAssertEqual(state.lastFailure?.code, "auth_required")
    }

    func testFetchWithAppKeychainOnlyDoesNotReadClaudeCodeCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.claudeCodeService, nil):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "imported-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: [],
                        accountLabel: "imported@example.com",
                        rateLimitTier: "pro")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: []),
            now: { now })

        let state = await provider.fetch()

        XCTAssertEqual(state.status, .authRequired)
        XCTAssertFalse(keychain.reads.contains { $0.service == ClaudeOAuthCredentialStore.claudeCodeService })
    }

    func testExplicitReauthenticationAllowsInteractiveClaudeCodeImport() async throws {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let keychain = MockKeychainClient(items: [
            key(ClaudeOAuthCredentialStore.claudeCodeService, nil):
                try ClaudeOAuthCredentialStore.encodeCredentials(
                    ClaudeOAuthCredentials(
                        accessToken: "imported-token",
                        refreshToken: "refresh-token",
                        expiresAt: now.addingTimeInterval(3_600),
                        scopes: [],
                        accountLabel: "imported@example.com",
                        rateLimitTier: "pro")),
        ])
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(keychain: keychain),
            httpClient: MockClaudeHTTPClient(responses: [
                HTTPResponse(statusCode: 200, data: usageResponseData(now: now)),
            ]),
            now: { now })

        let state = await provider.importExistingCredentials()

        XCTAssertEqual(state.status, .fresh)
        XCTAssertTrue(keychain.reads.contains(KeychainRead(
            service: ClaudeOAuthCredentialStore.claudeCodeService,
            account: nil,
            allowInteraction: true)))
    }

    private func usageResponseData(now: Date) -> Data {
        let fiveHourReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(5 * 60 * 60),
            fractionalSeconds: true)
        let weeklyReset = UsageBarISO8601.string(
            from: now.addingTimeInterval(7 * 24 * 60 * 60),
            fractionalSeconds: false)
        return Data("""
        {
          "five_hour": {
            "utilization": 0.25,
            "resets_at": "\(fiveHourReset)"
          },
          "seven_day": {
            "utilization": 10,
            "resets_at": "\(weeklyReset)"
          },
          "seven_day_sonnet": {
            "utilization": 0.2
          },
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 60000,
            "used_credits": 1200
          }
        }
        """.utf8)
    }

    private func key(_ service: String, _ account: String?) -> String {
        "\(service)|\(account ?? "*")"
    }
}

private struct KeychainRead: Equatable {
    var service: String
    var account: String?
    var allowInteraction: Bool
}

private final class MockKeychainClient: KeychainClient, @unchecked Sendable {
    var items: [String: Data]
    private(set) var reads: [KeychainRead] = []

    init(items: [String: Data]) {
        self.items = items
    }

    func readGenericPassword(service: String, account: String?, allowInteraction: Bool) throws -> Data {
        reads.append(KeychainRead(service: service, account: account, allowInteraction: allowInteraction))
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
        "\(service)|\(account ?? "*")"
    }
}

private final class MockClaudeHTTPClient: HTTPClient, @unchecked Sendable {
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
