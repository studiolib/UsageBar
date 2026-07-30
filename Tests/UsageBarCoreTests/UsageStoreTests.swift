import XCTest
@testable import UsageBarCore

final class UsageStoreTests: XCTestCase {
    @MainActor
    func testInitialStateContainsCodexAndClaudeSnapshots() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(now: now)

        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
        XCTAssertEqual(store.lastUpdated, now)
        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 98)
        XCTAssertEqual(store.weeklyRemainingPercent(for: .claude), 88)
        XCTAssertEqual(Provider.codex.usagePageURL.absoluteString, "https://chatgpt.com/#settings/Usage")
        XCTAssertEqual(Provider.claude.usagePageURL.absoluteString, "https://claude.ai/new#settings/usage")
        XCTAssertEqual(
            store.states.first { $0.provider == .claude }?.lastSuccessful?.shortWindow?.resetAt,
            now.addingTimeInterval(8_100))
        XCTAssertEqual(
            store.states.first { $0.provider == .codex }?.lastSuccessful?.weeklyWindow?.resetAt,
            now.addingTimeInterval(597_600))
        XCTAssertTrue(store.states.allSatisfy { $0.lastSuccessful != nil })
    }

    @MainActor
    func testRefreshUpdatesTimestampAndKeepsLastSuccessfulSnapshots() {
        let initial = Date(timeIntervalSince1970: 1_785_196_800)
        let refreshed = Date(timeIntervalSince1970: 1_785_197_100)
        let store = UsageStore(now: initial)

        store.refreshDummyData(now: refreshed)

        XCTAssertEqual(store.lastUpdated, refreshed)
        XCTAssertEqual(store.states.count, 2)
        XCTAssertTrue(store.states.allSatisfy { $0.lastSuccessful?.capturedAt == refreshed })
    }

    @MainActor
    func testClaudeReauthenticationClearsOnlyClaudeSnapshot() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(now: now)

        store.requestClaudeReauthentication(now: now)

        let codex = store.states.first { $0.provider == .codex }
        let claude = store.states.first { $0.provider == .claude }

        XCTAssertEqual(codex?.status, .fresh)
        XCTAssertNotNil(codex?.lastSuccessful)
        XCTAssertEqual(claude?.status, .authRequired)
        XCTAssertNil(claude?.lastSuccessful)
        XCTAssertEqual(claude?.lastFailure?.code, "auth_required")
    }

    @MainActor
    func testClearCachedSnapshotsClearsEveryProviderSnapshot() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(now: now)

        store.clearCachedSnapshots(now: now)

        XCTAssertNil(store.weeklyRemainingPercent(for: .codex))
        XCTAssertNil(store.weeklyRemainingPercent(for: .claude))
        XCTAssertTrue(store.states.allSatisfy { $0.status == .stale })
        XCTAssertTrue(store.states.allSatisfy { $0.current == nil })
        XCTAssertTrue(store.states.allSatisfy { $0.lastSuccessful == nil })
        XCTAssertTrue(store.states.allSatisfy { $0.lastFailure?.code == "cache_cleared" })
    }

    @MainActor
    func testClearCachedSnapshotsDoesNotDeleteCredentials() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let claudeProvider = StubCredentialCachingProvider(provider: .claude)
        let codexProvider = StubCredentialCachingProvider(provider: .codex)
        let store = UsageStore(
            now: now,
            usageProviders: [claudeProvider, codexProvider],
            nowProvider: { now })

        store.clearCachedSnapshots(now: now)

        XCTAssertEqual(claudeProvider.deleteCallCount, 0)
        XCTAssertEqual(codexProvider.deleteCallCount, 0)
        XCTAssertTrue(store.states.allSatisfy { $0.lastFailure?.code == "cache_cleared" })
    }

    @MainActor
    func testDeleteCachedCredentialsDeletesEveryProviderCredentialCache() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let claudeProvider = StubCredentialCachingProvider(provider: .claude)
        let codexProvider = StubCredentialCachingProvider(provider: .codex)
        let store = UsageStore(
            now: now,
            usageProviders: [claudeProvider, codexProvider],
            nowProvider: { now })

        let didDelete = store.deleteCachedCredentials(now: now)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(claudeProvider.deleteCallCount, 1)
        XCTAssertEqual(codexProvider.deleteCallCount, 1)
        XCTAssertTrue(store.states.allSatisfy { $0.status == .authRequired })
        XCTAssertTrue(store.states.allSatisfy { $0.lastFailure?.code == "credentials_deleted" })
    }

    @MainActor
    func testDeleteCachedCredentialsReportsProviderDeletionFailure() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let claudeProvider = StubCredentialCachingProvider(provider: .claude)
        let codexProvider = StubCredentialCachingProvider(provider: .codex, shouldThrowOnDelete: true)
        let store = UsageStore(
            now: now,
            usageProviders: [claudeProvider, codexProvider],
            nowProvider: { now })

        let didDelete = store.deleteCachedCredentials(now: now)
        let claude = store.states.first { $0.provider == .claude }
        let codex = store.states.first { $0.provider == .codex }

        XCTAssertFalse(didDelete)
        XCTAssertEqual(claudeProvider.deleteCallCount, 1)
        XCTAssertEqual(codexProvider.deleteCallCount, 1)
        XCTAssertEqual(claude?.lastFailure?.code, "credentials_deleted")
        XCTAssertEqual(codex?.lastFailure?.code, "credentials_delete_failed")
    }

    @MainActor
    func testDeleteCachedCredentialsLeavesNonCachingProvidersUnchanged() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let claudeProvider = StubCredentialCachingProvider(provider: .claude)
        let codexProvider = StubUsageProvider(
            provider: .codex,
            snapshot: snapshot(provider: .codex, remainingPercent: 70, capturedAt: now))
        let store = UsageStore(
            now: now,
            usageProviders: [claudeProvider, codexProvider],
            nowProvider: { now })

        let didDelete = store.deleteCachedCredentials(now: now)
        let claude = store.states.first { $0.provider == .claude }
        let codex = store.states.first { $0.provider == .codex }

        XCTAssertTrue(didDelete)
        XCTAssertEqual(claude?.status, .authRequired)
        XCTAssertEqual(claude?.lastFailure?.code, "credentials_deleted")
        XCTAssertEqual(codex?.status, .stale)
        XCTAssertNil(codex?.lastFailure)
    }

    @MainActor
    func testRefreshUsageMergesFetcherResultAndPreservesProviderOrder() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            accountLabel: "Codex",
            planLabel: "pro",
            capturedAt: now,
            shortWindow: UsageWindow(
                title: "5時間制限",
                usedPercent: 20,
                remainingPercent: 80,
                resetDescription: "1時間後",
                resetAt: now.addingTimeInterval(3_600)),
            weeklyWindow: UsageWindow(
                title: "週間制限",
                usedPercent: 30,
                remainingPercent: 70,
                resetDescription: "2日後",
                resetAt: now.addingTimeInterval(172_800)))
        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            accountLabel: "Claude",
            planLabel: "max",
            capturedAt: now,
            shortWindow: nil,
            weeklyWindow: UsageWindow(
                title: "週間制限",
                usedPercent: 40,
                remainingPercent: 60,
                resetDescription: "1日後",
                resetAt: now.addingTimeInterval(86_400)))
        let store = UsageStore(
            now: now,
            usageProviders: [
                StubUsageProvider(
                    provider: .codex,
                    snapshot: codexSnapshot),
                StubUsageProvider(
                    provider: .claude,
                    snapshot: claudeSnapshot),
            ],
            nowProvider: { now })

        await store.refreshUsage(now: now)

        XCTAssertEqual(store.states.map(\.provider), [.codex, .claude])
        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 70)
        XCTAssertEqual(store.weeklyRemainingPercent(for: .claude), 60)
        XCTAssertEqual(store.lastUpdated, now)
    }

    @MainActor
    func testRefreshUsagePreservesLastSuccessfulSnapshotWhenOneProviderFails() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let later = Date(timeIntervalSince1970: 1_785_197_100)
        let claudeProvider = MutableUsageProvider(
            provider: .claude,
            snapshot: snapshot(provider: .claude, remainingPercent: 80, capturedAt: now))
        let codexProvider = MutableUsageProvider(
            provider: .codex,
            snapshot: snapshot(provider: .codex, remainingPercent: 70, capturedAt: now))
        let store = UsageStore(
            now: now,
            usageProviders: [claudeProvider, codexProvider],
            nowProvider: { later })

        await store.refreshUsage(now: now)
        claudeProvider.setFailure(.claude(.networkError))
        codexProvider.setSnapshot(snapshot(provider: .codex, remainingPercent: 65, capturedAt: later))

        await store.refreshUsage(now: later)

        let claude = store.states.first { $0.provider == .claude }
        let codex = store.states.first { $0.provider == .codex }
        XCTAssertEqual(claude?.status, .stale)
        XCTAssertEqual(claude?.lastFailure?.code, "network_error")
        XCTAssertEqual(claude?.lastSuccessful?.weeklyWindow?.remainingPercent, 80)
        XCTAssertEqual(codex?.status, .fresh)
        XCTAssertEqual(codex?.lastSuccessful?.weeklyWindow?.remainingPercent, 65)
    }

    @MainActor
    func testRefreshUsageMapsAuthRequiredFailures() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(
            now: now,
            usageProviders: [
                FailingUsageProvider(provider: .claude, error: ClaudeUsageProviderError.authRequired),
            ],
            nowProvider: { now })

        await store.refreshUsage(now: now)

        let claude = store.states.first { $0.provider == .claude }
        XCTAssertEqual(claude?.status, .authRequired)
        XCTAssertEqual(claude?.lastFailure?.code, "auth_required")
    }

    @MainActor
    func testRefreshUsageIgnoresCancellationAndKeepsExistingState() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let provider = MutableUsageProvider(
            provider: .codex,
            snapshot: snapshot(provider: .codex, remainingPercent: 90, capturedAt: now))
        let store = UsageStore(
            now: now,
            usageProviders: [provider],
            nowProvider: { now })

        await store.refreshUsage(now: now)
        provider.setFailure(.cancellation)

        await store.refreshUsage(now: now.addingTimeInterval(60))

        let codex = store.states.first { $0.provider == .codex }
        XCTAssertEqual(codex?.status, .fresh)
        XCTAssertFalse(codex?.isRefreshing ?? true)
        XCTAssertNil(codex?.lastFailure)
        XCTAssertEqual(codex?.lastSuccessful?.weeklyWindow?.remainingPercent, 90)
    }

    @MainActor
    func testImportCredentialFailureShowsReimportGuidance() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let provider = ThrowingClaudeImportProvider()
        let store = UsageStore(
            now: now,
            usageProviders: [provider],
            nowProvider: { now })

        await store.importClaudeCredentials(now: now)

        let claude = store.states.first { $0.provider == .claude }
        XCTAssertEqual(claude?.status, .authRequired)
        XCTAssertEqual(claude?.lastFailure?.code, "auth_required")
        XCTAssertEqual(
            claude?.lastFailure?.message,
            "Claude Codeでログイン後、UsageBarへ認証情報を再取り込みしてください。")
    }

    @MainActor
    func testImportClaudeCredentialsMergesClaudeProviderResult() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let snapshot = UsageSnapshot(
            provider: .claude,
            accountLabel: "Claude",
            planLabel: "max",
            capturedAt: now,
            shortWindow: UsageWindow(
                title: "5時間制限",
                usedPercent: 20,
                remainingPercent: 80,
                resetDescription: "1時間後",
                resetAt: now.addingTimeInterval(3_600)),
            weeklyWindow: UsageWindow(
                title: "週間制限",
                usedPercent: 30,
                remainingPercent: 70,
                resetDescription: "2日後",
                resetAt: now.addingTimeInterval(172_800)))
        let store = UsageStore(
            now: now,
            usageProviders: [
                StubClaudeUsageProvider(
                    snapshot: snapshot),
            ],
            nowProvider: { now })

        await store.importClaudeCredentials(now: now)

        XCTAssertEqual(store.weeklyRemainingPercent(for: .claude), 70)
        XCTAssertEqual(store.states.map(\.provider), [.claude])
        XCTAssertEqual(store.lastUpdated, now)
    }

    @MainActor
    func testImportCodexCredentialsMergesCodexProviderResult() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let snapshot = UsageSnapshot(
            provider: .codex,
            accountLabel: "Codex",
            planLabel: "Plus",
            capturedAt: now,
            shortWindow: nil,
            weeklyWindow: UsageWindow(
                title: "週間制限",
                usedPercent: 30,
                remainingPercent: 70,
                resetDescription: "2日後",
                resetAt: now.addingTimeInterval(172_800)))
        let store = UsageStore(
            now: now,
            usageProviders: [
                StubCodexUsageProvider(
                    snapshot: snapshot),
            ],
            nowProvider: { now })

        await store.importCodexCredentials(now: now)

        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 70)
        XCTAssertEqual(store.states.map(\.provider), [.codex])
        XCTAssertEqual(store.lastUpdated, now)
    }

    @MainActor
    func testRefreshUsagePreventsConcurrentOperations() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let gate = AsyncOperationGate()
        let provider = BlockingUsageProvider(provider: .claude, gate: gate)
        let store = UsageStore(
            now: now,
            usageProviders: [provider],
            nowProvider: { now })

        let firstRefresh = Task { @MainActor in
            await store.refreshUsage(now: now)
        }
        await gate.waitForStart()

        XCTAssertTrue(store.isPerformingOperation)

        await store.refreshUsage(now: now)

        let fetchCallCount = await gate.fetchCallCount()
        XCTAssertEqual(fetchCallCount, 1)

        await gate.release()
        await firstRefresh.value

        XCTAssertFalse(store.isPerformingOperation)
    }

    @MainActor
    func testRefreshUsageFetchesProvidersInParallel() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let gate = AsyncOperationGate()
        let store = UsageStore(
            now: now,
            usageProviders: [
                BlockingUsageProvider(provider: .claude, gate: gate),
                BlockingUsageProvider(provider: .codex, gate: gate),
            ],
            nowProvider: { now })

        let refresh = Task { @MainActor in
            await store.refreshUsage(now: now)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        let fetchCallCount = await gate.fetchCallCount()
        XCTAssertEqual(fetchCallCount, 2)

        await gate.release()
        await refresh.value

        XCTAssertFalse(store.isPerformingOperation)
    }
}

private func snapshot(provider: Provider, remainingPercent: Double, capturedAt: Date) -> UsageSnapshot {
    UsageSnapshot(
        provider: provider,
        accountLabel: provider.displayName,
        planLabel: provider.displayName,
        capturedAt: capturedAt,
        shortWindow: nil,
        weeklyWindow: UsageWindow(
            title: "週間制限",
            usedPercent: 100 - remainingPercent,
            remainingPercent: remainingPercent,
            resetDescription: "1日後",
            resetAt: capturedAt.addingTimeInterval(86_400)))
}

private actor AsyncOperationGate {
    private var hasStarted = false
    private var isReleased = false
    private var fetchCalls = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var targetFetchCallCount = 0
    private var targetFetchCallContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        fetchCalls += 1
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        if fetchCalls >= targetFetchCallCount {
            releaseTargetFetchCallContinuation()
        }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func waitForFetchCalls(_ count: Int) async {
        guard fetchCalls < count else { return }
        await withCheckedContinuation { continuation in
            targetFetchCallCount = count
            targetFetchCallContinuation = continuation
        }
    }

    func waitForRelease() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }

    func fetchCallCount() -> Int {
        fetchCalls
    }

    private func releaseTargetFetchCallContinuation() {
        targetFetchCallContinuation?.resume()
        targetFetchCallContinuation = nil
    }
}

private struct StubUsageProvider: UsageProvider {
    let provider: Provider
    let snapshot: UsageSnapshot

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot
    }
}

private final class MutableUsageProvider: UsageProvider {
    let provider: Provider
    private let resultStore: Locked<Result<UsageSnapshot, MutableUsageProviderFailure>>

    init(provider: Provider, snapshot: UsageSnapshot) {
        self.provider = provider
        resultStore = Locked(.success(snapshot))
    }

    func setSnapshot(_ snapshot: UsageSnapshot) {
        resultStore.withLock {
            $0 = .success(snapshot)
        }
    }

    func setFailure(_ failure: MutableUsageProviderFailure) {
        resultStore.withLock {
            $0 = .failure(failure)
        }
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let result = resultStore.withLock { $0 }
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(failure):
            switch failure {
            case .cancellation:
                throw CancellationError()
            case let .claude(error):
                throw error
            }
        }
    }
}

private enum MutableUsageProviderFailure: Error, Sendable {
    case cancellation
    case claude(ClaudeUsageProviderError)
}

private struct FailingUsageProvider: UsageProvider {
    let provider: Provider
    let error: ClaudeUsageProviderError

    func fetchSnapshot() async throws -> UsageSnapshot {
        throw error
    }
}

private struct BlockingUsageProvider: UsageProvider {
    let provider: Provider
    let gate: AsyncOperationGate

    func fetchSnapshot() async throws -> UsageSnapshot {
        await gate.markStarted()
        await gate.waitForRelease()
        return UsageSnapshot(
            provider: provider,
            accountLabel: provider.displayName,
            planLabel: provider.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }
}

private struct StubClaudeUsageProvider: ClaudeCredentialImportingProvider {
    let provider: Provider = .claude
    let snapshot: UsageSnapshot

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        snapshot
    }

    func deleteCachedCredentials() throws {
    }
}

private struct ThrowingClaudeImportProvider: ClaudeCredentialImportingProvider {
    let provider: Provider = .claude

    func fetchSnapshot() async throws -> UsageSnapshot {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "broken"))
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "broken"))
    }

    func deleteCachedCredentials() throws {
    }
}

private struct StubCodexUsageProvider: CodexCredentialImportingProvider {
    let provider: Provider = .codex
    let snapshot: UsageSnapshot

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        snapshot
    }

    func deleteCachedCredentials() throws {
    }
}

private final class StubCredentialCachingProvider: CredentialCachingProvider {
    let provider: Provider
    private let shouldThrowOnDelete: Bool
    private let deleteCallCountStore = Locked(0)

    var deleteCallCount: Int {
        deleteCallCountStore.withLock { $0 }
    }

    init(provider: Provider, shouldThrowOnDelete: Bool = false) {
        self.provider = provider
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            accountLabel: provider.displayName,
            planLabel: provider.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }

    func deleteCachedCredentials() throws {
        deleteCallCountStore.withLock {
            $0 += 1
        }
        if shouldThrowOnDelete {
            throw KeychainClientError.accessDenied
        }
    }
}
