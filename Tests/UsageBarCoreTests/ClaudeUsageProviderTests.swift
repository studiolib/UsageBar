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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.accountLabel, "Claude")
        XCTAssertEqual(snapshot.planLabel, "Max")
        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 25)
        XCTAssertEqual(snapshot.shortWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 10)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 90)
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.planLabel, "Pro")
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.planLabel, "Pro")
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.planLabel, "Max 5x")
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

        await assertThrowsKeychainError(.itemNotFound) {
            try await provider.fetchSnapshot()
        }

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

        let snapshot = try await provider.importExistingCredentials()

        XCTAssertEqual(snapshot.accountLabel, "Claude")
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

        _ = try await provider.fetchSnapshot()
        let saved = try ClaudeOAuthCredentialStore.decodeCredentials(
            from: keychain.items[key(ClaudeOAuthCredentialStore.appService, ClaudeOAuthCredentialStore.defaultAccount)]!)

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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.shortWindow)
        XCTAssertEqual(snapshot.weeklyWindow?.title, "週間制限")
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 12)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 88)
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.shortWindow?.resetAt, Date(timeIntervalSince1970: 1_785_218_600))
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 35)
        XCTAssertEqual(snapshot.weeklyWindow?.resetAt, Date(timeIntervalSince1970: 1_785_819_800))
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 22)
        XCTAssertEqual(snapshot.shortWindow?.remainingPercent, 78)
        XCTAssertEqual(snapshot.shortWindow?.resetAt, now.addingTimeInterval(7_200))
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 12)
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.shortWindow?.title, "5時間制限")
        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.shortWindow?.remainingPercent, 82)
        XCTAssertEqual(snapshot.shortWindow?.resetDescription, "不明")
        XCTAssertNil(snapshot.shortWindow?.resetAt)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 13)
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

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.shortWindow?.usedPercent, 1)
        XCTAssertEqual(snapshot.shortWindow?.remainingPercent, 99)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 13)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 87)
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

        await assertThrowsClaudeError(.limitsUnavailable) {
            try await provider.fetchSnapshot()
        }

    }

    func testFetchReturnsAuthRequiredWhenCredentialsAreUnavailable() async {
        let provider = ClaudeUsageProvider(
            credentialStore: ClaudeOAuthCredentialStore(
                keychain: MockKeychainClient(items: [:]),
                credentialsFileURL: URL(fileURLWithPath: "/tmp/UsageBarTests-missing-claude-credentials.json")),
            httpClient: MockClaudeHTTPClient(responses: []),
            now: { Date(timeIntervalSince1970: 1_785_196_800) })

        await assertThrowsKeychainError(.itemNotFound) {
            try await provider.fetchSnapshot()
        }

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

        await assertThrowsKeychainError(.itemNotFound) {
            try await provider.fetchSnapshot()
        }

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

        _ = try await provider.importExistingCredentials()

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

    private func assertThrowsClaudeError(
        _ expectedError: ClaudeUsageProviderError,
        operation: () async throws -> UsageSnapshot)
        async
    {
        do {
            _ = try await operation()
            XCTFail("Expected ClaudeUsageProviderError.\(expectedError)")
        } catch let error as ClaudeUsageProviderError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Expected ClaudeUsageProviderError.\(expectedError), got \(error)")
        }
    }

    private func assertThrowsKeychainError(
        _ expectedError: KeychainClientError,
        operation: () async throws -> UsageSnapshot)
        async
    {
        do {
            _ = try await operation()
            XCTFail("Expected KeychainClientError.\(expectedError)")
        } catch let error as KeychainClientError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Expected KeychainClientError.\(expectedError), got \(error)")
        }
    }
}

private struct KeychainRead: Equatable, Sendable {
    var service: String
    var account: String?
    var allowInteraction: Bool
}

private final class MockKeychainClient: KeychainClient {
    private let itemsStore: Locked<[String: Data]>
    private let readsStore = Locked<[KeychainRead]>([])

    var items: [String: Data] {
        itemsStore.withLock { $0 }
    }

    var reads: [KeychainRead] {
        readsStore.withLock { $0 }
    }

    init(items: [String: Data]) {
        itemsStore = Locked(items)
    }

    func readGenericPassword(service: String, account: String?, allowInteraction: Bool) throws -> Data {
        readsStore.withLock {
            $0.append(KeychainRead(service: service, account: account, allowInteraction: allowInteraction))
        }
        guard let data = itemsStore.withLock({ $0[key(service, account)] }) else {
            throw KeychainClientError.itemNotFound
        }
        return data
    }

    func writeGenericPassword(_ data: Data, service: String, account: String) throws {
        itemsStore.withLock {
            $0[key(service, account)] = data
        }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        _ = itemsStore.withLock {
            $0.removeValue(forKey: key(service, account))
        }
    }

    private func key(_ service: String, _ account: String?) -> String {
        "\(service)|\(account ?? "*")"
    }
}

private final class MockClaudeHTTPClient: HTTPClient {
    private let requestsStore = Locked<[HTTPRequest]>([])
    private let responsesStore: Locked<[HTTPResponse]>

    var requests: [HTTPRequest] {
        requestsStore.withLock { $0 }
    }

    init(responses: [HTTPResponse]) {
        responsesStore = Locked(responses)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestsStore.withLock {
            $0.append(request)
        }
        guard let response = responsesStore.withLock({ responses -> HTTPResponse? in
            guard !responses.isEmpty else { return nil }
            return responses.removeFirst()
        }) else {
            throw URLError(.badServerResponse)
        }
        return response
    }
}
