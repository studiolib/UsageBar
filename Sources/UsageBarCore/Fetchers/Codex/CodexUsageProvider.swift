import Foundation

public protocol CodexCredentialImportingProvider: Sendable {
    func fetchSnapshot() async throws -> UsageSnapshot
    func importExistingCredentials() async throws -> UsageSnapshot
    func deleteCachedCredentials() throws
}

public final class CodexUsageProvider: CodexCredentialImportingProvider {
    private let credentialStore: CodexCredentialStore
    private let httpClient: HTTPClient
    private let now: @Sendable () -> Date
    private let usageURL: URL
    private let tokenURL: URL
    private let clientID: String

    public init(
        credentialStore: CodexCredentialStore = CodexCredentialStore(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init,
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        tokenURL: URL = URL(string: "https://auth.openai.com/oauth/token")!,
        clientID: String = "app_EMoamEEZ73f0CkXaXp7hrann")
    {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        self.now = now
        self.usageURL = usageURL
        self.tokenURL = tokenURL
        self.clientID = clientID
    }

    public func deleteCachedCredentials() throws {
        try credentialStore.deleteAppCredentials()
    }

    public func importExistingCredentials() async throws -> UsageSnapshot {
        _ = try credentialStore.importExistingCodexCredentials()
        return try await fetchSnapshot()
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var credentials = try credentialStore.readAppCredentials()
        if shouldRefresh(credentials) {
            credentials = try await refresh(credentials)
        }

        var response = try await requestUsage(credentials: credentials)
        if response.statusCode == 401, credentials.refreshToken != nil {
            credentials = try await refresh(credentials)
            response = try await requestUsage(credentials: credentials)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw error(forStatusCode: response.statusCode)
        }

        do {
            return try parseSnapshot(data: response.data, credentials: credentials)
        } catch let error as CodexUsageProviderError {
            throw error
        } catch {
            throw CodexUsageProviderError.parseError
        }
    }

    private func shouldRefresh(_ credentials: CodexAuthCredentials) -> Bool {
        if let expiration = credentials.accessToken.jwtExpiration, expiration.timeIntervalSince(now()) <= 300 {
            return true
        }
        guard let lastRefresh = credentials.lastRefresh else { return false }
        return now().timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
    }

    private func refresh(_ credentials: CodexAuthCredentials) async throws -> CodexAuthCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw CodexUsageProviderError.authRequired
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
            throw CodexUsageProviderError.refreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(CodexTokenRefreshResponse.self, from: response.data)
        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            throw CodexUsageProviderError.refreshFailed
        }

        let refreshed = CodexAuthCredentials(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken ?? credentials.refreshToken,
            idToken: tokenResponse.idToken ?? credentials.idToken,
            accountID: credentials.accountID,
            lastRefresh: now())
        try credentialStore.saveAppCredentials(refreshed)
        return refreshed
    }

    private func requestUsage(credentials: CodexAuthCredentials) async throws -> HTTPResponse {
        try await send(
            HTTPRequest(
                url: usageURL,
                headers: usageHeaders(credentials: credentials)))
    }

    private func usageHeaders(credentials: CodexAuthCredentials) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "OpenAI-Beta": "codex-1",
            "originator": "UsageBar",
            "User-Agent": "UsageBar/0.1.0",
        ]
        if let accountID = credentials.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-ID"] = accountID
        }
        return headers
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CodexUsageProviderError.networkError
        }
    }

    private func parseSnapshot(data: Data, credentials: CodexAuthCredentials) throws -> UsageSnapshot {
        let response = try CodexUsageResponse.parse(data: data)
        let capturedAt = now()
        let claims = credentials.idToken.flatMap { JWTClaims(idToken: $0) }

        let primaryWindow = response.rateLimit.primaryWindow
        let secondaryWindow = response.rateLimit.secondaryWindow
        guard primaryWindow != nil || secondaryWindow != nil else {
            throw CodexUsageProviderError.limitsUnavailable
        }

        let singleWindowOnly = primaryWindow != nil
            && (secondaryWindow == nil || secondaryWindow == primaryWindow)
        let shortWindow = singleWindowOnly
            ? nil
            : primaryWindow.map { usageWindow(title: "5時間制限", $0, now: capturedAt) }
        let weeklyWindow = (singleWindowOnly ? primaryWindow : secondaryWindow ?? primaryWindow)
            .map { usageWindow(title: "週間制限", $0, now: capturedAt) }

        return UsageSnapshot(
            provider: .codex,
            accountLabel: "Codex",
            planLabel: planLabel(claims?.planLabel ?? response.planType),
            capturedAt: capturedAt,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow)
    }

    private func usageWindow(
        title: String,
        _ window: CodexRateLimitWindow,
        now: Date) -> UsageWindow
    {
        let usedPercent = normalizePercent(window.usedPercent)
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

    private func planLabel(_ rawPlan: String?) -> String {
        let plan = rawPlan?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch plan {
        case "plus", "chatgpt_plus":
            return "Plus"
        case "pro", "chatgpt_pro":
            return "Pro"
        case "team", "chatgpt_team":
            return "Team"
        case "enterprise", "chatgpt_enterprise":
            return "Enterprise"
        case "free", "chatgpt_free":
            return "Free"
        case "":
            return "ChatGPT"
        default:
            return rawPlan?
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ") ?? "ChatGPT"
        }
    }

    private func error(forStatusCode statusCode: Int) -> CodexUsageProviderError {
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

private struct CodexTokenRefreshResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

private struct JWTClaims {
    var planLabel: String?

    init?(idToken: String) {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = String(parts[1]).base64URLDecodedData,
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }

        planLabel = (object["chatgpt_plan_type"] as? String)
            ?? (object["plan_type"] as? String)
            ?? (object["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String
    }
}

private extension String {
    var jwtExpiration: Date? {
        let parts = split(separator: ".")
        guard parts.count >= 2,
              let payloadData = String(parts[1]).base64URLDecodedData,
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = object["exp"] as? TimeInterval
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    var base64URLDecodedData: Data? {
        var value = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = value.count % 4
        if padding > 0 {
            value += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: value)
    }
}

func formURLEncoded(_ values: [String: String]) -> String {
    values
        .map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .joined(separator: "&")
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }()
}
