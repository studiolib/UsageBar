import Foundation

public struct ClaudeOAuthCredentials: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scopes: [String]
    public var accountLabel: String?
    public var rateLimitTier: String?
    public var subscriptionType: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        scopes: [String],
        accountLabel: String?,
        rateLimitTier: String?,
        subscriptionType: String? = nil)
    {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.accountLabel = accountLabel
        self.rateLimitTier = rateLimitTier
        self.subscriptionType = subscriptionType
    }
}

public final class ClaudeOAuthCredentialStore: Sendable {
    public static let appService = "UsageBar-ClaudeOAuth"
    public static let claudeCodeService = "Claude Code-credentials"
    public static let defaultAccount = "default"

    private let keychain: KeychainClient
    private let account: String
    private let credentialsFileURL: URL

    public init(
        keychain: KeychainClient = SecurityKeychainClient(),
        account: String = ClaudeOAuthCredentialStore.defaultAccount,
        credentialsFileURL: URL = ClaudeOAuthCredentialStore.defaultCredentialsFileURL())
    {
        self.keychain = keychain
        self.account = account
        self.credentialsFileURL = credentialsFileURL
    }

    public static func defaultCredentialsFileURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    public func readAppCredentials() throws -> ClaudeOAuthCredentials {
        let data = try keychain.readGenericPassword(
            service: Self.appService,
            account: account,
            allowInteraction: false)
        return try Self.decodeCredentials(from: data)
    }

    public func saveAppCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        let data = try Self.encodeCredentials(credentials)
        try keychain.writeGenericPassword(data, service: Self.appService, account: account)
    }

    public func deleteAppCredentials() throws {
        try keychain.deleteGenericPassword(service: Self.appService, account: account)
    }

    public func importExistingClaudeCodeCredentials(allowInteraction: Bool) throws -> ClaudeOAuthCredentials {
        if let data = try? keychain.readGenericPassword(
            service: Self.claudeCodeService,
            account: nil,
            allowInteraction: allowInteraction)
        {
            let credentials = try Self.decodeCredentials(from: data)
            try saveAppCredentials(credentials)
            return credentials
        }

        guard FileManager.default.fileExists(atPath: credentialsFileURL.path) else {
            throw ClaudeUsageProviderError.authRequired
        }
        let data = try Data(contentsOf: credentialsFileURL)
        let credentials = try Self.decodeCredentials(from: data)
        try saveAppCredentials(credentials)
        return credentials
    }

    static func decodeCredentials(from data: Data) throws -> ClaudeOAuthCredentials {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let root = try decoder.decode(ClaudeCredentialRoot.self, from: data)
        guard let accessToken = root.oauth.accessToken, !accessToken.isEmpty else {
            throw ClaudeUsageProviderError.authRequired
        }

        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: root.oauth.refreshToken,
            expiresAt: root.oauth.expiresAtDate,
            scopes: root.oauth.scopes ?? [],
            accountLabel: root.oauth.account?.email ?? root.oauth.email,
            rateLimitTier: root.oauth.rateLimitTier,
            subscriptionType: root.oauth.subscriptionType)
    }

    static func encodeCredentials(_ credentials: ClaudeOAuthCredentials) throws -> Data {
        let root = ClaudeCredentialRoot(
            claudeAiOauth: ClaudeCredentialPayload(
                accessToken: credentials.accessToken,
                refreshToken: credentials.refreshToken,
                expiresAt: credentials.expiresAt.map { Int64($0.timeIntervalSince1970 * 1_000) },
                scopes: credentials.scopes,
                email: nil,
                rateLimitTier: credentials.rateLimitTier,
                subscriptionType: credentials.subscriptionType,
                account: nil))
        return try JSONEncoder().encode(root)
    }
}

private struct ClaudeCredentialRoot: Codable {
    var claudeAiOauth: ClaudeCredentialPayload?
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Int64?
    var scopes: [String]?
    var email: String?
    var rateLimitTier: String?
    var subscriptionType: String?
    var account: ClaudeCredentialAccount?

    var oauth: ClaudeCredentialPayload {
        claudeAiOauth ?? ClaudeCredentialPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes,
            email: email,
            rateLimitTier: rateLimitTier,
            subscriptionType: subscriptionType,
            account: account)
    }
}

private struct ClaudeCredentialPayload: Codable {
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Int64?
    var scopes: [String]?
    var email: String?
    var rateLimitTier: String?
    var subscriptionType: String?
    var account: ClaudeCredentialAccount?

    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        let seconds = expiresAt > 10_000_000_000 ? TimeInterval(expiresAt) / 1_000 : TimeInterval(expiresAt)
        return Date(timeIntervalSince1970: seconds)
    }
}

private struct ClaudeCredentialAccount: Codable {
    var email: String?
}
