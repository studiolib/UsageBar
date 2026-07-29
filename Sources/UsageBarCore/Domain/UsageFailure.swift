import Foundation

public struct UsageFailure: Equatable, Sendable {
    public let occurredAt: Date
    public let code: String
    public let message: String
    public let retryAfter: Date?

    public init(
        occurredAt: Date,
        code: String,
        message: String,
        retryAfter: Date?)
    {
        self.occurredAt = occurredAt
        self.code = code
        self.message = message
        self.retryAfter = retryAfter
    }
}
