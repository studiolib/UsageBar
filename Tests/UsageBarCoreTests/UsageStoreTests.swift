import XCTest
@testable import UsageBarCore

final class UsageStoreTests: XCTestCase {
    @MainActor
    func testInitialStateContainsCodexAndClaudeSnapshots() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(dummyDataAt: now)

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
    func testProductionInitializerConfiguresClaudeAndCodexProviders() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(nowProvider: { now })

        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
        XCTAssertTrue(store.states.allSatisfy { $0.status == .stale })
        XCTAssertEqual(store.lastUpdated, now)
    }

    @MainActor
    func testEmptyProviderConfigurationDoesNotCreateDummyDataOrReportDeletionSuccess() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(
            now: now,
            claudeProvider: nil,
            codexProvider: nil,
            nowProvider: { now })

        await store.refreshUsage(now: now)

        XCTAssertTrue(store.states.isEmpty)
        XCTAssertFalse(store.deleteCachedCredentials(now: now))
    }

    @MainActor
    func testRefreshUpdatesTimestampAndKeepsLastSuccessfulSnapshots() {
        let initial = Date(timeIntervalSince1970: 1_785_196_800)
        let refreshed = Date(timeIntervalSince1970: 1_785_197_100)
        let store = UsageStore(dummyDataAt: initial)

        store.refreshDummyData(now: refreshed)

        XCTAssertEqual(store.lastUpdated, refreshed)
        XCTAssertEqual(store.states.count, 2)
        XCTAssertTrue(store.states.allSatisfy { $0.lastSuccessful?.capturedAt == refreshed })
    }

    @MainActor
    func testClaudeReauthenticationClearsOnlyClaudeSnapshot() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(dummyDataAt: now)

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
        let store = UsageStore(dummyDataAt: now)

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
        let claudeProvider = StubClaudeCredentialCachingProvider()
        let codexProvider = StubCodexCredentialCachingProvider()
        let store = UsageStore(
            now: now,
            claudeProvider: claudeProvider,
            codexProvider: codexProvider,
            nowProvider: { now })

        store.clearCachedSnapshots(now: now)

        XCTAssertEqual(claudeProvider.deleteCallCount, 0)
        XCTAssertEqual(codexProvider.deleteCallCount, 0)
        XCTAssertTrue(store.states.allSatisfy { $0.lastFailure?.code == "cache_cleared" })
    }

    @MainActor
    func testDeleteCachedCredentialsDeletesEveryProviderCredentialCache() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let claudeProvider = StubClaudeCredentialCachingProvider()
        let codexProvider = StubCodexCredentialCachingProvider()
        let store = UsageStore(
            now: now,
            claudeProvider: claudeProvider,
            codexProvider: codexProvider,
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
        let claudeProvider = StubClaudeCredentialCachingProvider()
        let codexProvider = StubCodexCredentialCachingProvider(shouldThrowOnDelete: true)
        let store = UsageStore(
            now: now,
            claudeProvider: claudeProvider,
            codexProvider: codexProvider,
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
            claudeProvider: StubClaudeUsageProvider(
                snapshot: claudeSnapshot),
            codexProvider: StubCodexUsageProvider(
                snapshot: codexSnapshot),
            nowProvider: { now })

        await store.refreshUsage(now: now)

        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 70)
        XCTAssertEqual(store.weeklyRemainingPercent(for: .claude), 60)
        XCTAssertEqual(store.lastUpdated, now)
    }

    @MainActor
    func testRefreshUsagePreservesLastSuccessfulSnapshotWhenOneProviderFails() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let later = Date(timeIntervalSince1970: 1_785_197_100)
        let claudeProvider = MutableClaudeUsageProvider(
            snapshot: snapshot(provider: .claude, remainingPercent: 80, capturedAt: now))
        let codexProvider = MutableCodexUsageProvider(
            snapshot: snapshot(provider: .codex, remainingPercent: 70, capturedAt: now))
        let store = UsageStore(
            now: now,
            claudeProvider: claudeProvider,
            codexProvider: codexProvider,
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
            claudeProvider: FailingClaudeUsageProvider(error: ClaudeUsageProviderError.authRequired),
            codexProvider: nil,
            nowProvider: { now })

        await store.refreshUsage(now: now)

        let claude = store.states.first { $0.provider == .claude }
        XCTAssertEqual(claude?.status, .authRequired)
        XCTAssertEqual(claude?.lastFailure?.code, "auth_required")
    }

    @MainActor
    func testRefreshUsageRejectsSnapshotFromAnotherProvider() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let store = UsageStore(
            now: now,
            claudeProvider: StubClaudeUsageProvider(
                snapshot: snapshot(provider: .codex, remainingPercent: 70, capturedAt: now)),
            codexProvider: nil,
            nowProvider: { now })

        await store.refreshUsage(now: now)

        let claude = store.states.first { $0.provider == .claude }
        XCTAssertEqual(claude?.status, .stale)
        XCTAssertEqual(claude?.lastFailure?.code, "provider_mismatch")
        XCTAssertNil(claude?.lastSuccessful)
    }

    @MainActor
    func testRefreshUsageIgnoresCancellationAndKeepsExistingState() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let provider = MutableCodexUsageProvider(
            snapshot: snapshot(provider: .codex, remainingPercent: 90, capturedAt: now))
        let store = UsageStore(
            now: now,
            claudeProvider: nil,
            codexProvider: provider,
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
            claudeProvider: provider,
            codexProvider: nil,
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
            claudeProvider: StubClaudeUsageProvider(snapshot: snapshot),
            codexProvider: nil,
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
            claudeProvider: nil,
            codexProvider: StubCodexUsageProvider(snapshot: snapshot),
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
        let provider = BlockingClaudeUsageProvider(gate: gate)
        let store = UsageStore(
            now: now,
            claudeProvider: provider,
            codexProvider: nil,
            nowProvider: { now })

        let firstRefresh = Task { @MainActor in
            await store.refreshUsage(now: now)
        }
        guard await gate.waitForStart() else {
            await gate.release()
            await firstRefresh.value
            XCTFail("最初のProvider取得が開始されませんでした")
            return
        }

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
            claudeProvider: BlockingClaudeUsageProvider(gate: gate),
            codexProvider: BlockingCodexUsageProvider(gate: gate),
            nowProvider: { now })

        let refresh = Task { @MainActor in
            await store.refreshUsage(now: now)
        }
        guard await gate.waitForFetchCalls(2) else {
            await gate.release()
            await refresh.value
            XCTFail("ClaudeとCodexの取得が並列に開始されませんでした")
            return
        }

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
    private var isReleased = false
    private var fetchCalls = 0
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        fetchCalls += 1
    }

    func waitForStart(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        await waitForFetchCalls(1, timeoutNanoseconds: timeoutNanoseconds)
    }

    func waitForFetchCalls(_ count: Int, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        while fetchCalls < count {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
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

}

private final class MutableClaudeUsageProvider: ClaudeCredentialImportingProvider {
    private let resultStore: Locked<Result<UsageSnapshot, MutableUsageProviderFailure>>

    init(snapshot: UsageSnapshot) {
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

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
    }

    func deleteCachedCredentials() throws {
    }
}

private final class MutableCodexUsageProvider: CodexCredentialImportingProvider {
    private let resultStore: Locked<Result<UsageSnapshot, MutableUsageProviderFailure>>

    init(snapshot: UsageSnapshot) {
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

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
    }

    func deleteCachedCredentials() throws {
    }
}

private enum MutableUsageProviderFailure: Error, Sendable {
    case cancellation
    case claude(ClaudeUsageProviderError)
}

private struct FailingClaudeUsageProvider: ClaudeCredentialImportingProvider {
    let error: ClaudeUsageProviderError

    func fetchSnapshot() async throws -> UsageSnapshot {
        throw error
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        throw error
    }

    func deleteCachedCredentials() throws {
    }
}

private struct BlockingClaudeUsageProvider: ClaudeCredentialImportingProvider {
    let gate: AsyncOperationGate

    func fetchSnapshot() async throws -> UsageSnapshot {
        await gate.markStarted()
        await gate.waitForRelease()
        return UsageSnapshot(
            provider: .claude,
            accountLabel: Provider.claude.displayName,
            planLabel: Provider.claude.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
    }

    func deleteCachedCredentials() throws {
    }
}

private struct StubClaudeUsageProvider: ClaudeCredentialImportingProvider {
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

private final class StubClaudeCredentialCachingProvider: ClaudeCredentialImportingProvider {
    private let shouldThrowOnDelete: Bool
    private let deleteCallCountStore = Locked(0)

    var deleteCallCount: Int {
        deleteCallCountStore.withLock { $0 }
    }

    init(shouldThrowOnDelete: Bool = false) {
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            accountLabel: Provider.claude.displayName,
            planLabel: Provider.claude.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
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

private struct BlockingCodexUsageProvider: CodexCredentialImportingProvider {
    let gate: AsyncOperationGate

    func fetchSnapshot() async throws -> UsageSnapshot {
        await gate.markStarted()
        await gate.waitForRelease()
        return UsageSnapshot(
            provider: .codex,
            accountLabel: Provider.codex.displayName,
            planLabel: Provider.codex.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
    }

    func deleteCachedCredentials() throws {
    }
}

private final class StubCodexCredentialCachingProvider: CodexCredentialImportingProvider {
    private let shouldThrowOnDelete: Bool
    private let deleteCallCountStore = Locked(0)

    var deleteCallCount: Int {
        deleteCallCountStore.withLock { $0 }
    }

    init(shouldThrowOnDelete: Bool = false) {
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            accountLabel: Provider.codex.displayName,
            planLabel: Provider.codex.displayName,
            capturedAt: Date(timeIntervalSince1970: 0),
            shortWindow: nil,
            weeklyWindow: nil)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        try await fetchSnapshot()
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
