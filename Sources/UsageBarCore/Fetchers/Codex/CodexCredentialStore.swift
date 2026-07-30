import Foundation

public final class CodexCredentialStore: Sendable {
    public static let appService = "UsageBar-CodexOAuth"
    public static let defaultAccount = "default"

    private let keychain: KeychainClient
    private let authStore: CodexAuthStore
    private let account: String

    public init(
        keychain: KeychainClient = SecurityKeychainClient(),
        authStore: CodexAuthStore = CodexAuthStore(),
        account: String = CodexCredentialStore.defaultAccount)
    {
        self.keychain = keychain
        self.authStore = authStore
        self.account = account
    }

    public func readAppCredentials() throws -> CodexAuthCredentials {
        let data = try keychain.readGenericPassword(
            service: Self.appService,
            account: account,
            allowInteraction: false)
        return try Self.decodeCredentials(from: data)
    }

    public func importExistingCodexCredentials() throws -> CodexAuthCredentials {
        let credentials = try authStore.read()
        try saveAppCredentials(credentials)
        return credentials
    }

    public func saveAppCredentials(_ credentials: CodexAuthCredentials) throws {
        let data = try Self.encodeCredentials(credentials)
        try keychain.writeGenericPassword(data, service: Self.appService, account: account)
    }

    public func deleteAppCredentials() throws {
        try keychain.deleteGenericPassword(service: Self.appService, account: account)
    }

    static func decodeCredentials(from data: Data) throws -> CodexAuthCredentials {
        let stored = try JSONDecoder().decode(StoredCodexCredentials.self, from: data)
        guard !stored.accessToken.isEmpty else {
            throw CodexUsageProviderError.authRequired
        }
        return CodexAuthCredentials(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            idToken: stored.idToken,
            accountID: stored.accountID,
            lastRefresh: stored.lastRefresh.flatMap(UsageBarISO8601.date(from:)))
    }

    static func encodeCredentials(_ credentials: CodexAuthCredentials) throws -> Data {
        let stored = StoredCodexCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            idToken: credentials.idToken,
            accountID: credentials.accountID,
            lastRefresh: credentials.lastRefresh.map {
                UsageBarISO8601.string(from: $0, fractionalSeconds: true)
            })
        return try JSONEncoder().encode(stored)
    }
}

private struct StoredCodexCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var accountID: String?
    var lastRefresh: String?
}
