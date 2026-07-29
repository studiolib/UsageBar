import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let title: String
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetDescription: String
    public let resetAt: Date?

    public init(
        title: String,
        usedPercent: Double,
        remainingPercent: Double,
        resetDescription: String,
        resetAt: Date?)
    {
        self.title = title
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetDescription = resetDescription
        self.resetAt = resetAt
    }
}
