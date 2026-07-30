import Foundation

public enum CodexUsageProviderError: Error, Equatable, Sendable {
    case authRequired
    case refreshFailed
    case unauthorized
    case rateLimited
    case networkError
    case parseError
    case limitsUnavailable
    case unknown

    var failureCode: String {
        switch self {
        case .authRequired:
            "auth_required"
        case .refreshFailed:
            "auth_expired"
        case .unauthorized:
            "auth_required"
        case .rateLimited:
            "rate_limited"
        case .networkError:
            "network_error"
        case .parseError:
            "parse_error"
        case .limitsUnavailable:
            "limits_unavailable"
        case .unknown:
            "unknown"
        }
    }

    var userMessage: String {
        switch self {
        case .authRequired:
            "Codex の認証が必要です。"
        case .refreshFailed:
            "Codex の認証更新に失敗しました。"
        case .unauthorized:
            "Codex の認証が無効です。"
        case .rateLimited:
            "Codex API がレート制限中です。"
        case .networkError:
            "Codex API への接続に失敗しました。"
        case .parseError:
            "Codex の利用量データを解析できませんでした。"
        case .limitsUnavailable:
            "Codex の利用量データがまだ提供されていません。"
        case .unknown:
            "Codex の利用量取得に失敗しました。"
        }
    }
}

extension CodexUsageProviderError: ProviderUsageDisplayError {
    var requiresAuthentication: Bool {
        self == .authRequired || self == .unauthorized
    }
}
