import Foundation

public struct AppSettings: Equatable, Sendable {
    public var refreshInterval: RefreshInterval

    public init(refreshInterval: RefreshInterval = .fiveMinutes)
    {
        self.refreshInterval = refreshInterval
    }
}
