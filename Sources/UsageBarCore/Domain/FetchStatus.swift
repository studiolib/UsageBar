import Foundation

public enum FetchStatus: Equatable, Sendable {
    case fresh
    case stale
    case authRequired

    public var label: String {
        switch self {
        case .fresh:
            "最新"
        case .stale:
            "取得失敗"
        case .authRequired:
            "認証が必要"
        }
    }
}
