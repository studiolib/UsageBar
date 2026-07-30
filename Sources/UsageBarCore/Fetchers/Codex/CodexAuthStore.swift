import Foundation

public struct CodexAuthCredentials: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var accountID: String?
    public var lastRefresh: Date?
}

public final class CodexAuthStore: Sendable {
    public let authFileURL: URL

    public init(authFileURL: URL = CodexAuthStore.defaultAuthFileURL()) {
        self.authFileURL = authFileURL
    }

    public static func defaultAuthFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: expandTilde(codexHome)).appendingPathComponent("auth.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }

    public func read() throws -> CodexAuthCredentials {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw CodexUsageProviderError.authRequired
        }
        let data = try Data(contentsOf: authFileURL)
        let root = try Self.jsonObject(from: data)
        guard let tokens = root["tokens"] as? [String: Any] else {
            throw CodexUsageProviderError.authRequired
        }
        guard let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
            throw CodexUsageProviderError.authRequired
        }

        return CodexAuthCredentials(
            accessToken: accessToken,
            refreshToken: tokens["refresh_token"] as? String,
            idToken: tokens["id_token"] as? String,
            accountID: (tokens["account_id"] as? String) ?? (root["account_id"] as? String),
            lastRefresh: (root["last_refresh"] as? String).flatMap(Self.parseDate))
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageProviderError.parseError
        }
        return object
    }

    private static func parseDate(_ value: String) -> Date? {
        UsageBarISO8601.date(from: value)
    }

    private static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
