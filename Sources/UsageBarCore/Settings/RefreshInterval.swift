import Foundation

public enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .oneMinute:
            "1分"
        case .fiveMinutes:
            "5分"
        case .tenMinutes:
            "10分"
        case .fifteenMinutes:
            "15分"
        case .thirtyMinutes:
            "30分"
        }
    }

    public var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }
}
