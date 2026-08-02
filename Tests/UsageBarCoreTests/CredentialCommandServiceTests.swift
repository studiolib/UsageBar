import XCTest
@testable import UsageBarCore

final class CredentialCommandServiceTests: XCTestCase {
    func testFindsProviderSpecificImporters() {
        let claudeProvider = StubClaudeCredentialProvider()
        let codexProvider = StubCodexCredentialProvider()
        let service = CredentialCommandService(claudeProvider: claudeProvider, codexProvider: codexProvider)

        XCTAssertNotNil(service.claudeImporter())
        XCTAssertNotNil(service.codexImporter())
    }

    func testDeleteCachedCredentialsReportsOnlyFailedProviders() {
        let claudeProvider = StubClaudeCredentialProvider()
        let codexProvider = StubCodexCredentialProvider(shouldThrowOnDelete: true)
        let service = CredentialCommandService(claudeProvider: claudeProvider, codexProvider: codexProvider)

        let result = service.deleteCachedCredentials()

        XCTAssertFalse(result.didDeleteAll)
        XCTAssertEqual(result.deletedProviders, [.claude])
        XCTAssertEqual(result.failedProviders, [.codex])
        XCTAssertEqual(claudeProvider.deleteCallCount, 1)
        XCTAssertEqual(codexProvider.deleteCallCount, 1)
    }
}

private final class StubClaudeCredentialProvider: ClaudeCredentialImportingProvider {
    private let shouldThrowOnDelete: Bool
    private let deleteCallCountStore = Locked(0)

    var deleteCallCount: Int {
        deleteCallCountStore.withLock { $0 }
    }

    init(shouldThrowOnDelete: Bool = false) {
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot(provider: .claude)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        snapshot(provider: .claude)
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

private final class StubCodexCredentialProvider: CodexCredentialImportingProvider {
    private let shouldThrowOnDelete: Bool
    private let deleteCallCountStore = Locked(0)

    var deleteCallCount: Int {
        deleteCallCountStore.withLock { $0 }
    }

    init(shouldThrowOnDelete: Bool = false) {
        self.shouldThrowOnDelete = shouldThrowOnDelete
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot(provider: .codex)
    }

    func importExistingCredentials() async throws -> UsageSnapshot {
        snapshot(provider: .codex)
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

private func snapshot(provider: Provider) -> UsageSnapshot {
    UsageSnapshot(
        provider: provider,
        accountLabel: provider.displayName,
        planLabel: provider.displayName,
        capturedAt: Date(timeIntervalSince1970: 0),
        shortWindow: nil,
        weeklyWindow: nil)
}
