import Foundation

public struct UsageSnapshot: Equatable, Identifiable, Sendable {
    public let provider: Provider
    public let accountLabel: String
    public let planLabel: String
    public let capturedAt: Date
    public let shortWindow: UsageWindow?
    public let weeklyWindow: UsageWindow?

    public var id: Provider { provider }

    public init(
        provider: Provider,
        accountLabel: String,
        planLabel: String,
        capturedAt: Date,
        shortWindow: UsageWindow?,
        weeklyWindow: UsageWindow?)
    {
        self.provider = provider
        self.accountLabel = accountLabel
        self.planLabel = planLabel
        self.capturedAt = capturedAt
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
    }
}
