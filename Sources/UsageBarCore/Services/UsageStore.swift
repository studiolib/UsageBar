import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var states: [ProviderUsageState]
    @Published public private(set) var lastUpdated: Date
    @Published public private(set) var isPerformingOperation = false

    private let usageProviders: [any UsageProvider]
    private let nowProvider: @MainActor () -> Date

    public init(now: Date = Date(), nowProvider: @escaping @MainActor () -> Date = Date.init) {
        usageProviders = []
        self.nowProvider = nowProvider
        lastUpdated = now
        states = Self.makeDummyStates(now: now)
    }

    public init(
        now: Date = Date(),
        usageProviders: [any UsageProvider],
        nowProvider: @escaping @MainActor () -> Date = Date.init)
    {
        self.usageProviders = usageProviders
        self.nowProvider = nowProvider
        lastUpdated = now
        states = Self.makeInitialStates()
    }

    public func weeklyRemainingPercent(for provider: Provider) -> Double? {
        states.first { $0.provider == provider }?.lastSuccessful?.weeklyWindow?.remainingPercent
    }

    public func requestClaudeReauthentication(now: Date = Date()) {
        states = states.map { state in
            guard state.provider == .claude else { return state }
            return ProviderUsageState(
                provider: state.provider,
                status: .authRequired,
                current: nil,
                lastSuccessful: nil,
                lastFailure: UsageFailure(
                    occurredAt: now,
                    code: "auth_required",
                    message: "Claude の再認証が必要です。",
                    retryAfter: nil),
                isRefreshing: false)
        }
    }

    public func importClaudeCredentials(now: Date = Date()) async
    {
        guard beginOperation() else { return }
        defer { isPerformingOperation = false }

        guard let claudeProvider = usageProviders.first(where: { $0.provider == .claude }) as? any ClaudeCredentialImportingProvider else {
            requestClaudeReauthentication(now: now)
            return
        }

        lastUpdated = now
        markRefreshing(provider: .claude)
        let importedState = await claudeProvider.importExistingCredentials()
        merge(importedState)
        lastUpdated = nowProvider()
    }

    public func importCodexCredentials(now: Date = Date()) async {
        guard beginOperation() else { return }
        defer { isPerformingOperation = false }

        guard let codexProvider = usageProviders.first(where: { $0.provider == .codex }) as? any CodexCredentialImportingProvider else {
            return
        }

        lastUpdated = now
        markRefreshing(provider: .codex)
        let importedState = await codexProvider.importExistingCredentials()
        merge(importedState)
        lastUpdated = nowProvider()
    }

    public func clearCachedSnapshots(now: Date = Date()) {
        guard !isPerformingOperation else { return }

        states = states.map { state in
            ProviderUsageState(
                provider: state.provider,
                status: .stale,
                current: nil,
                lastSuccessful: nil,
                lastFailure: UsageFailure(
                    occurredAt: now,
                    code: "cache_cleared",
                    message: "キャッシュを削除しました。",
                    retryAfter: nil),
                isRefreshing: false)
        }
    }

    @discardableResult
    public func deleteCachedCredentials(now: Date = Date()) -> Bool {
        guard !isPerformingOperation else { return false }

        var failedProviders = Set<Provider>()
        for usageProvider in usageProviders {
            guard let credentialProvider = usageProvider as? any CredentialCachingProvider else {
                continue
            }
            do {
                try credentialProvider.deleteCachedCredentials()
            } catch {
                failedProviders.insert(usageProvider.provider)
            }
        }

        states = states.map { state in
            if failedProviders.contains(state.provider) {
                return ProviderUsageState(
                    provider: state.provider,
                    status: .stale,
                    current: state.current,
                    lastSuccessful: state.lastSuccessful,
                    lastFailure: UsageFailure(
                        occurredAt: now,
                        code: "credentials_delete_failed",
                        message: "\(state.provider.displayName) の資格情報を削除できませんでした。",
                        retryAfter: nil),
                    isRefreshing: false)
            }
            return ProviderUsageState(
                provider: state.provider,
                status: .authRequired,
                current: nil,
                lastSuccessful: nil,
                lastFailure: UsageFailure(
                    occurredAt: now,
                    code: "credentials_deleted",
                    message: "資格情報を削除しました。再認証してください。",
                    retryAfter: nil),
                isRefreshing: false)
        }

        return failedProviders.isEmpty
    }

    public func refreshDummyData(now: Date = Date()) {
        lastUpdated = now
        states = Self.makeDummyStates(now: now)
    }

    public func refreshUsage(now: Date = Date()) async
    {
        guard beginOperation() else { return }
        defer { isPerformingOperation = false }

        guard !usageProviders.isEmpty else {
            refreshDummyData(now: now)
            return
        }

        lastUpdated = now
        for usageProvider in usageProviders {
            markRefreshing(provider: usageProvider.provider)
            let fetchedState: ProviderUsageState
            fetchedState = await usageProvider.fetch()
            merge(fetchedState)
        }
        lastUpdated = nowProvider()
    }

    private func markRefreshing(provider: Provider) {
        states = states.map { state in
            guard state.provider == provider else { return state }
            var refreshingState = state
            refreshingState.isRefreshing = true
            return refreshingState
        }
    }

    private func beginOperation() -> Bool {
        guard !isPerformingOperation else { return false }
        isPerformingOperation = true
        return true
    }

    private func merge(_ fetchedState: ProviderUsageState) {
        states = states.map { existing in
            guard existing.provider == fetchedState.provider else { return existing }
            var merged = fetchedState
            if merged.lastSuccessful == nil {
                merged.lastSuccessful = existing.lastSuccessful
            }
            return merged
        }
    }

    private static func makeInitialStates() -> [ProviderUsageState] {
        [Provider.claude, .codex].map { provider in
            ProviderUsageState(
                provider: provider,
                status: .stale,
                current: nil,
                lastSuccessful: nil,
                lastFailure: nil,
                isRefreshing: false)
        }
    }

    static func makeDummyStates(now: Date) -> [ProviderUsageState] {
        [
            ProviderUsageState(
                provider: .claude,
                status: .fresh,
                current: Self.snapshot(
                    provider: .claude,
                    account: "Claude",
                    plan: "Max",
                    shortRemaining: 76,
                    weeklyRemaining: 88,
                    shortReset: "2時間15分後",
                    weeklyReset: "5日10時間後",
                    shortResetOffset: 8_100,
                    weeklyResetOffset: 468_000,
                    now: now),
                lastSuccessful: Self.snapshot(
                    provider: .claude,
                    account: "Claude",
                    plan: "Max",
                    shortRemaining: 76,
                    weeklyRemaining: 88,
                    shortReset: "2時間15分後",
                    weeklyReset: "5日10時間後",
                    shortResetOffset: 8_100,
                    weeklyResetOffset: 468_000,
                    now: now),
                lastFailure: nil,
                isRefreshing: false),
            ProviderUsageState(
                provider: .codex,
                status: .fresh,
                current: Self.snapshot(
                    provider: .codex,
                    account: "Codex",
                    plan: "Pro",
                    shortRemaining: 90,
                    weeklyRemaining: 98,
                    shortReset: "4時間48分後",
                    weeklyReset: "6日22時間後",
                    shortResetOffset: 17_280,
                    weeklyResetOffset: 597_600,
                    now: now),
                lastSuccessful: Self.snapshot(
                    provider: .codex,
                    account: "Codex",
                    plan: "Pro",
                    shortRemaining: 90,
                    weeklyRemaining: 98,
                    shortReset: "4時間48分後",
                    weeklyReset: "6日22時間後",
                    shortResetOffset: 17_280,
                    weeklyResetOffset: 597_600,
                    now: now),
                lastFailure: nil,
                isRefreshing: false),
        ]
    }

    private static func snapshot(
        provider: Provider,
        account: String,
        plan: String,
        shortRemaining: Double,
        weeklyRemaining: Double,
        shortReset: String,
        weeklyReset: String,
        shortResetOffset: TimeInterval,
        weeklyResetOffset: TimeInterval,
        now: Date) -> UsageSnapshot
    {
        UsageSnapshot(
            provider: provider,
            accountLabel: account,
            planLabel: plan,
            capturedAt: now,
            shortWindow: UsageWindow(
                title: "5時間制限",
                usedPercent: 100 - shortRemaining,
                remainingPercent: shortRemaining,
                resetDescription: shortReset,
                resetAt: now.addingTimeInterval(shortResetOffset)),
            weeklyWindow: UsageWindow(
                title: "週間制限",
                usedPercent: 100 - weeklyRemaining,
                remainingPercent: weeklyRemaining,
                resetDescription: weeklyReset,
                resetAt: now.addingTimeInterval(weeklyResetOffset)))
    }
}
