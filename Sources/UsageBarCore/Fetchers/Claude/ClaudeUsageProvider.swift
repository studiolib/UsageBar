import Foundation

public protocol ClaudeCredentialImportingProvider: CredentialCachingProvider {
    func importExistingCredentials() async throws -> UsageSnapshot
}

public final class ClaudeUsageProvider: ClaudeCredentialImportingProvider {
    public let provider: Provider = .claude

    private let credentialStore: ClaudeOAuthCredentialStore
    private let httpClient: HTTPClient
    private let now: @Sendable () -> Date
    private let usageURL: URL
    private let tokenURL: URL
    private let clientID: String
    private let userAgent: String

    public init(
        credentialStore: ClaudeOAuthCredentialStore = ClaudeOAuthCredentialStore(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init,
        usageURL: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        tokenURL: URL = URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientID: String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        userAgent: String = "UsageBar/0.1.0")
    {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        self.now = now
        self.usageURL = usageURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.userAgent = userAgent
    }

    public func importExistingCredentials() async throws -> UsageSnapshot {
        _ = try credentialStore.importExistingClaudeCodeCredentials(allowInteraction: true)
        return try await fetchSnapshot()
    }

    public func deleteCachedCredentials() throws {
        try credentialStore.deleteAppCredentials()
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var credentials = try credentialStore.readAppCredentials()
        if shouldRefresh(credentials) {
            credentials = try await refresh(credentials)
        }

        var response = try await requestUsage(accessToken: credentials.accessToken)
        if response.statusCode == 401 || response.statusCode == 403 {
            credentials = try await refresh(credentials)
            response = try await requestUsage(accessToken: credentials.accessToken)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw error(forStatusCode: response.statusCode)
        }

        do {
            return try parseSnapshot(data: response.data, credentials: credentials)
        } catch let error as ClaudeUsageProviderError {
            throw error
        } catch {
            throw ClaudeUsageProviderError.parseError
        }
    }

    private func shouldRefresh(_ credentials: ClaudeOAuthCredentials) -> Bool {
        guard let expiresAt = credentials.expiresAt else { return false }
        return expiresAt.timeIntervalSince(now()) <= 300
    }

    private func refresh(_ credentials: ClaudeOAuthCredentials) async throws -> ClaudeOAuthCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ClaudeUsageProviderError.authRequired
        }

        let body = formURLEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        let response = try await send(
            HTTPRequest(
                url: tokenURL,
                method: "POST",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: Data(body.utf8)))
        guard (200..<300).contains(response.statusCode) else {
            throw ClaudeUsageProviderError.refreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(ClaudeTokenRefreshResponse.self, from: response.data)
        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            throw ClaudeUsageProviderError.refreshFailed
        }

        let refreshed = ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken ?? credentials.refreshToken,
            expiresAt: tokenResponse.expiresAt(now: now()) ?? credentials.expiresAt,
            scopes: tokenResponse.scopes ?? credentials.scopes,
            accountLabel: nil,
            rateLimitTier: credentials.rateLimitTier,
            subscriptionType: credentials.subscriptionType)
        try credentialStore.saveAppCredentials(refreshed)
        return refreshed
    }

    private func requestUsage(accessToken: String) async throws -> HTTPResponse {
        try await send(
            HTTPRequest(
                url: usageURL,
                headers: [
                    "Authorization": "Bearer \(accessToken)",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "anthropic-beta": "oauth-2025-04-20",
                    "User-Agent": userAgent,
                ]))
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClaudeUsageProviderError.networkError
        }
    }

    private func parseSnapshot(data: Data, credentials: ClaudeOAuthCredentials) throws -> UsageSnapshot {
        let response = try ClaudeUsageResponse.parse(data: data)
        let capturedAt = now()
        guard response.fiveHour != nil || response.sevenDay != nil else {
            throw ClaudeUsageProviderError.limitsUnavailable
        }

        return UsageSnapshot(
            provider: .claude,
            accountLabel: "Claude",
            planLabel: planLabel(subscriptionType: credentials.subscriptionType, rateLimitTier: credentials.rateLimitTier),
            capturedAt: capturedAt,
            shortWindow: response.fiveHour.map {
                usageWindow(title: "5時間制限", $0, now: capturedAt)
            },
            weeklyWindow: response.sevenDay.map {
                usageWindow(title: "週間制限", $0, now: capturedAt)
            })
    }

    private func usageWindow(
        title: String,
        _ window: ClaudeUsageWindowResponse,
        now: Date) -> UsageWindow
    {
        let usedPercent = normalizePercent(window.utilization)
        let resetAt = window.resetsAt
            ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
        return UsageWindow(
            title: title,
            usedPercent: usedPercent,
            remainingPercent: 100 - usedPercent,
            resetDescription: resetAt.map { RelativeResetDescriptionFormatter.text(until: $0, now: now) } ?? "不明",
            resetAt: resetAt)
    }

    private func normalizePercent(_ value: Double) -> Double {
        UsagePercent.normalize(value)
    }

    private func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String {
        if let label = planLabelFromSubscriptionType(subscriptionType) {
            return label
        }
        if let label = planLabelFromRateLimitTier(rateLimitTier) {
            return label
        }
        return "Claude"
    }

    private func planLabelFromSubscriptionType(_ subscriptionType: String?) -> String? {
        switch normalizePlanToken(subscriptionType) {
        case "pro":
            return "Pro"
        case "max":
            return "Max"
        case "team":
            return "Team"
        case "enterprise":
            return "Enterprise"
        case "free":
            return "Free"
        default:
            return nil
        }
    }

    private func planLabelFromRateLimitTier(_ rateLimitTier: String?) -> String? {
        let tier = normalizePlanToken(rateLimitTier)
        guard !tier.isEmpty else { return nil }

        if tier.contains("max_20x") {
            return "Max 20x"
        }
        if tier.contains("max_5x") {
            return "Max 5x"
        }
        if tier.contains("max") {
            return "Max"
        }
        if tier.contains("pro") || tier == "default_claude_ai" {
            return "Pro"
        }
        if tier.contains("team") {
            return "Team"
        }
        if tier.contains("enterprise") {
            return "Enterprise"
        }
        return rateLimitTier?
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func normalizePlanToken(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func error(forStatusCode statusCode: Int) -> ClaudeUsageProviderError {
        switch statusCode {
        case 401, 403:
            .unauthorized
        case 429:
            .rateLimited
        default:
            .unknown
        }
    }

}

private struct ClaudeTokenRefreshResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: TimeInterval?
    var expiresAtMilliseconds: Int64?
    var scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAtMilliseconds = "expires_at"
        case scopes
        case scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresIn)
        expiresAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .expiresAtMilliseconds)
        if let decodedScopes = try container.decodeIfPresent([String].self, forKey: .scopes) {
            scopes = decodedScopes
        } else if let scope = try container.decodeIfPresent(String.self, forKey: .scope) {
            scopes = scope.split(separator: " ").map(String.init)
        } else {
            scopes = nil
        }
    }

    func expiresAt(now: Date) -> Date? {
        if let expiresAtMilliseconds {
            let seconds = expiresAtMilliseconds > 10_000_000_000
                ? TimeInterval(expiresAtMilliseconds) / 1_000
                : TimeInterval(expiresAtMilliseconds)
            return Date(timeIntervalSince1970: seconds)
        }
        return expiresIn.map { now.addingTimeInterval($0) }
    }
}
