import Foundation

public enum ClaudeUsageProviderError: Error, Equatable, Sendable {
    case authRequired
    case refreshFailed
    case unauthorized
    case rateLimited
    case interactionNotAllowed
    case networkError
    case limitsUnavailable
    case parseError
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
        case .interactionNotAllowed:
            "auth_required"
        case .networkError:
            "network_error"
        case .limitsUnavailable:
            "limits_unavailable"
        case .parseError:
            "parse_error"
        case .unknown:
            "unknown"
        }
    }

    var userMessage: String {
        switch self {
        case .authRequired:
            "Claude の認証が必要です。"
        case .refreshFailed:
            "Claude の認証更新に失敗しました。"
        case .unauthorized:
            "Claude の認証が無効です。"
        case .rateLimited:
            "Claude API がレート制限中です。"
        case .interactionNotAllowed:
            "Claude Code の Keychain 許可が必要です。"
        case .networkError:
            "Claude API への接続に失敗しました。"
        case .limitsUnavailable:
            "Claude の利用制限データが見つかりませんでした。"
        case .parseError:
            "Claude の利用量データを解析できませんでした。"
        case .unknown:
            "Claude の利用量取得に失敗しました。"
        }
    }
}

extension ClaudeUsageProviderError: ProviderUsageDisplayError {
    var requiresAuthentication: Bool {
        self == .authRequired || self == .unauthorized || self == .interactionNotAllowed
    }
}
