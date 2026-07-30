import Foundation

enum ProviderUsageStateFactory {
    static func fresh(provider: Provider, snapshot: UsageSnapshot) -> ProviderUsageState {
        ProviderUsageState(
            provider: provider,
            status: .fresh,
            current: snapshot,
            lastSuccessful: snapshot,
            lastFailure: nil,
            isRefreshing: false)
    }

    static func failure(
        provider: Provider,
        now: Date,
        code: String,
        message: String,
        requiresAuthentication: Bool)
        -> ProviderUsageState
    {
        ProviderUsageState(
            provider: provider,
            status: requiresAuthentication ? .authRequired : .stale,
            current: nil,
            lastSuccessful: nil,
            lastFailure: UsageFailure(
                occurredAt: now,
                code: code,
                message: message,
                retryAfter: nil),
            isRefreshing: false)
    }
}
