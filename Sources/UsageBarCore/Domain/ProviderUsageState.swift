import Foundation

public struct ProviderUsageState: Equatable, Identifiable, Sendable {
    public let provider: Provider
    public var status: FetchStatus
    public var current: UsageSnapshot?
    public var lastSuccessful: UsageSnapshot?
    public var lastFailure: UsageFailure?
    public var isRefreshing: Bool

    public var id: Provider { provider }

    public init(
        provider: Provider,
        status: FetchStatus,
        current: UsageSnapshot?,
        lastSuccessful: UsageSnapshot?,
        lastFailure: UsageFailure?,
        isRefreshing: Bool)
    {
        self.provider = provider
        self.status = status
        self.current = current
        self.lastSuccessful = lastSuccessful
        self.lastFailure = lastFailure
        self.isRefreshing = isRefreshing
    }
}
