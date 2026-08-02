import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var states: [ProviderUsageState]
    @Published public private(set) var lastUpdated: Date
    @Published public private(set) var isPerformingOperation = false

    private let claudeProvider: (any ClaudeCredentialImportingProvider)?
    private let codexProvider: (any CodexCredentialImportingProvider)?
    private let credentialCommands: CredentialCommandService
    private let nowProvider: @MainActor () -> Date
    private let isDummyDataMode: Bool

    public convenience init(nowProvider: @escaping @MainActor () -> Date = Date.init) {
        self.init(
            now: nowProvider(),
            claudeProvider: ClaudeUsageProvider(),
            codexProvider: CodexUsageProvider(),
            nowProvider: nowProvider)
    }

    public init(dummyDataAt now: Date = Date(), nowProvider: @escaping @MainActor () -> Date = Date.init) {
        claudeProvider = nil
        codexProvider = nil
        credentialCommands = CredentialCommandService(
            claudeProvider: nil,
            codexProvider: nil)
        self.nowProvider = nowProvider
        isDummyDataMode = true
        lastUpdated = now
        states = Self.makeDummyStates(now: now)
    }

    init(
        now: Date = Date(),
        claudeProvider: (any ClaudeCredentialImportingProvider)?,
        codexProvider: (any CodexCredentialImportingProvider)?,
        nowProvider: @escaping @MainActor () -> Date = Date.init)
    {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
        credentialCommands = CredentialCommandService(
            claudeProvider: claudeProvider,
            codexProvider: codexProvider)
        self.nowProvider = nowProvider
        isDummyDataMode = false
        lastUpdated = now
        var providers: [Provider] = []
        if claudeProvider != nil {
            providers.append(.claude)
        }
        if codexProvider != nil {
            providers.append(.codex)
        }
        states = Self.makeInitialStates(providers: providers)
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

        guard let claudeProvider = credentialCommands.claudeImporter() else {
            requestClaudeReauthentication(now: now)
            return
        }

        lastUpdated = now
        markRefreshing(provider: .claude)
        let importedState = await stateFromCredentialImport(provider: .claude) {
            try await claudeProvider.importExistingCredentials()
        }
        if let importedState {
            merge(importedState)
        } else {
            markNotRefreshing(provider: .claude)
        }
        lastUpdated = nowProvider()
    }

    public func importCodexCredentials(now: Date = Date()) async {
        guard beginOperation() else { return }
        defer { isPerformingOperation = false }

        guard let codexProvider = credentialCommands.codexImporter() else {
            return
        }

        lastUpdated = now
        markRefreshing(provider: .codex)
        let importedState = await stateFromCredentialImport(provider: .codex) {
            try await codexProvider.importExistingCredentials()
        }
        if let importedState {
            merge(importedState)
        } else {
            markNotRefreshing(provider: .codex)
        }
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

        let result = credentialCommands.deleteCachedCredentials()

        states = states.map { state in
            if result.failedProviders.contains(state.provider) {
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
            guard result.deletedProviders.contains(state.provider) else {
                return state
            }
            return ProviderUsageState(
                provider: state.provider,
                status: .authRequired,
                current: nil,
                lastSuccessful: nil,
                lastFailure: UsageFailure(
                    occurredAt: now,
                    code: "credentials_deleted",
                    message: "UsageBar の資格情報を削除しました。Claude Code / Codex CLIでログイン後、認証情報を再取り込みしてください。",
                    retryAfter: nil),
                isRefreshing: false)
        }

        return result.didDeleteAll
    }

    public func refreshDummyData(now: Date = Date()) {
        lastUpdated = now
        states = Self.makeDummyStates(now: now)
    }

    public func refreshUsage(now: Date = Date()) async
    {
        guard beginOperation() else { return }
        defer { isPerformingOperation = false }

        guard !isDummyDataMode else {
            refreshDummyData(now: now)
            return
        }

        guard claudeProvider != nil || codexProvider != nil else {
            lastUpdated = nowProvider()
            return
        }

        lastUpdated = now
        if claudeProvider != nil {
            markRefreshing(provider: .claude)
        }
        if codexProvider != nil {
            markRefreshing(provider: .codex)
        }
        let fetchedStates = await statesFromFetches()
        mergeFetchedState(fetchedStates, for: .claude, isConfigured: claudeProvider != nil)
        mergeFetchedState(fetchedStates, for: .codex, isConfigured: codexProvider != nil)
        lastUpdated = nowProvider()
    }

    private func statesFromFetches() async -> [Provider: ProviderUsageState?] {
        await withTaskGroup(of: ProviderFetchResult.self, returning: [Provider: ProviderUsageState?].self) { group in
            if let claudeProvider {
                group.addTask {
                    do {
                        let snapshot = try await claudeProvider.fetchSnapshot()
                        try validateSnapshot(snapshot, expected: .claude)
                        return ProviderFetchResult(provider: .claude, snapshot: snapshot, error: nil)
                    } catch is CancellationError {
                        return ProviderFetchResult(provider: .claude, snapshot: nil, error: nil)
                    } catch {
                        return ProviderFetchResult(provider: .claude, snapshot: nil, error: error)
                    }
                }
            }
            if let codexProvider {
                group.addTask {
                    do {
                        let snapshot = try await codexProvider.fetchSnapshot()
                        try validateSnapshot(snapshot, expected: .codex)
                        return ProviderFetchResult(provider: .codex, snapshot: snapshot, error: nil)
                    } catch is CancellationError {
                        return ProviderFetchResult(provider: .codex, snapshot: nil, error: nil)
                    } catch {
                        return ProviderFetchResult(provider: .codex, snapshot: nil, error: error)
                    }
                }
            }

            var states: [Provider: ProviderUsageState?] = [:]
            for await result in group {
                states[result.provider] = state(from: result)
            }
            return states
        }
    }

    private func state(from result: ProviderFetchResult) -> ProviderUsageState? {
        if let snapshot = result.snapshot {
            return ProviderUsageStateFactory.fresh(provider: result.provider, snapshot: snapshot)
        }
        guard let error = result.error else { return nil }
        return failureState(provider: result.provider, error: error)
    }

    private func mergeFetchedState(
        _ fetchedStates: [Provider: ProviderUsageState?],
        for provider: Provider,
        isConfigured: Bool)
    {
        guard isConfigured else { return }
        if let fetchedState = fetchedStates[provider] ?? nil {
            merge(fetchedState)
        } else {
            markNotRefreshing(provider: provider)
        }
    }

    private func stateFromCredentialImport(
        provider: Provider,
        importSnapshot: () async throws -> UsageSnapshot)
        async -> ProviderUsageState?
    {
        do {
            let snapshot = try await importSnapshot()
            try validateSnapshot(snapshot, expected: provider)
            return ProviderUsageStateFactory.fresh(provider: provider, snapshot: snapshot)
        } catch is CancellationError {
            return nil
        } catch {
            return credentialImportFailureState(provider: provider, error: error)
        }
    }

    private func credentialImportFailureState(provider: Provider, error: Error) -> ProviderUsageState {
        if let displayError = error as? any ProviderUsageDisplayError {
            return ProviderUsageStateFactory.failure(
                provider: provider,
                now: nowProvider(),
                code: displayError.failureCode,
                message: displayError.userMessage,
                requiresAuthentication: displayError.requiresAuthentication)
        }

        let serviceName = provider == .claude ? "Claude Code" : "Codex CLI"
        return ProviderUsageStateFactory.failure(
            provider: provider,
            now: nowProvider(),
            code: "auth_required",
            message: "\(serviceName)でログイン後、UsageBarへ認証情報を再取り込みしてください。",
            requiresAuthentication: true)
    }

    private func failureState(provider: Provider, error: Error) -> ProviderUsageState {
        let displayError = usageDisplayError(provider: provider, error: error)
        return ProviderUsageStateFactory.failure(
            provider: provider,
            now: nowProvider(),
            code: displayError.failureCode,
            message: displayError.userMessage,
            requiresAuthentication: displayError.requiresAuthentication)
    }

    private func usageDisplayError(provider: Provider, error: Error) -> any ProviderUsageDisplayError {
        if let error = error as? any ProviderUsageDisplayError {
            return error
        }
        if let keychainError = error as? KeychainClientError {
            return keychainDisplayError(provider: provider, keychainError: keychainError)
        }

        switch provider {
        case .claude:
            return ClaudeUsageProviderError.unknown
        case .codex:
            return CodexUsageProviderError.unknown
        }
    }

    private func keychainDisplayError(provider: Provider, keychainError: KeychainClientError) -> any ProviderUsageDisplayError {
        switch provider {
        case .claude:
            return keychainError == .interactionNotAllowed ? ClaudeUsageProviderError.interactionNotAllowed : ClaudeUsageProviderError.authRequired
        case .codex:
            return CodexUsageProviderError.authRequired
        }
    }

    private func markRefreshing(provider: Provider) {
        states = states.map { state in
            guard state.provider == provider else { return state }
            var refreshingState = state
            refreshingState.isRefreshing = true
            return refreshingState
        }
    }

    private func markNotRefreshing(provider: Provider) {
        states = states.map { state in
            guard state.provider == provider else { return state }
            var currentState = state
            currentState.isRefreshing = false
            return currentState
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

    private static func makeInitialStates(providers: [Provider]) -> [ProviderUsageState] {
        providers.map { provider in
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

private struct ProviderFetchResult {
    let provider: Provider
    let snapshot: UsageSnapshot?
    let error: Error?
}

private func validateSnapshot(_ snapshot: UsageSnapshot, expected: Provider) throws {
    guard snapshot.provider == expected else {
        throw SnapshotProviderMismatchError(expected: expected, actual: snapshot.provider)
    }
}

private struct SnapshotProviderMismatchError: Error, ProviderUsageDisplayError {
    let expected: Provider
    let actual: Provider

    var failureCode: String { "provider_mismatch" }
    var userMessage: String {
        "\(expected.displayName) の使用量データを確認できませんでした。"
    }
    var requiresAuthentication: Bool { false }
}
