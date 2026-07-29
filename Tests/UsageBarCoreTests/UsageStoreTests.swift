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
    func testRefreshUsageMergesFetcherResultAndPreservesProviderOrder() async {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let snapshot = UsageSnapshot(
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
        let store = UsageStore(
            now: now,
            usageProviders: [
                StubUsageProvider(
                    provider: .codex,
                    state: ProviderUsageState(
                        provider: .codex,
                        status: .fresh,
                        current: snapshot,
                        lastSuccessful: snapshot,
                        lastFailure: nil,
                        isRefreshing: false)),
            ],
            nowProvider: { now })

        await store.refreshUsage(now: now)

        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
        XCTAssertNil(store.states.first { $0.provider == .claude }?.lastSuccessful)
        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 70)
        XCTAssertEqual(store.lastUpdated, now)
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
                    state: ProviderUsageState(
                        provider: .claude,
                        status: .fresh,
                        current: snapshot,
                        lastSuccessful: snapshot,
                        lastFailure: nil,
                        isRefreshing: false)),
            ],
            nowProvider: { now })

        await store.importClaudeCredentials(now: now)

        XCTAssertEqual(store.weeklyRemainingPercent(for: .claude), 70)
        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
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
                    state: ProviderUsageState(
                        provider: .codex,
                        status: .fresh,
                        current: snapshot,
                        lastSuccessful: snapshot,
                        lastFailure: nil,
                        isRefreshing: false)),
            ],
            nowProvider: { now })

        await store.importCodexCredentials(now: now)

        XCTAssertEqual(store.weeklyRemainingPercent(for: .codex), 70)
        XCTAssertEqual(store.states.map(\.provider), [.claude, .codex])
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
}

private actor AsyncOperationGate {
    private var hasStarted = false
    private var isReleased = false
    private var fetchCalls = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        fetchCalls += 1
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func waitForRelease() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func fetchCallCount() -> Int {
        fetchCalls
    }
}

private struct StubUsageProvider: UsageProvider {
    let provider: Provider
    let state: ProviderUsageState

    func fetch() async -> ProviderUsageState {
        state
    }
}

private struct BlockingUsageProvider: UsageProvider {
    let provider: Provider
    let gate: AsyncOperationGate

    func fetch() async -> ProviderUsageState {
        await gate.markStarted()
        await gate.waitForRelease()
        return ProviderUsageState(
            provider: provider,
            status: .stale,
            current: nil,
            lastSuccessful: nil,
            lastFailure: nil,
            isRefreshing: false)
    }
}

private struct StubClaudeUsageProvider: ClaudeCredentialImportingProvider {
    let provider: Provider = .claude
    let state: ProviderUsageState

    func fetch() async -> ProviderUsageState {
        state
    }

    func importExistingCredentials() async -> ProviderUsageState {
        state
    }

    func deleteCachedCredentials() throws {
    }
}

private struct StubCodexUsageProvider: CodexCredentialImportingProvider {
    let provider: Provider = .codex
    let state: ProviderUsageState

    func fetch() async -> ProviderUsageState {
        state
    }

    func importExistingCredentials() async -> ProviderUsageState {
        state
    }

    func deleteCachedCredentials() throws {
    }
}

private final class StubCredentialCachingProvider: CredentialCachingProvider, @unchecked Sendable {
    let provider: Provider
    private let shouldThrowOnDelete: Bool
    private(set) var deleteCallCount = 0

    init(provider: Provider, shouldThrowOnDelete: Bool = false) {
        self.provider = provider
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetch() async -> ProviderUsageState {
        ProviderUsageState(
            provider: provider,
            status: .stale,
            current: nil,
            lastSuccessful: nil,
            lastFailure: nil,
            isRefreshing: false)
    }

    func deleteCachedCredentials() throws {
        deleteCallCount += 1
        if shouldThrowOnDelete {
            throw KeychainClientError.accessDenied
        }
    }
}
