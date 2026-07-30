import Foundation

struct CredentialDeleteResult {
    let deletedProviders: Set<Provider>
    let failedProviders: Set<Provider>

    var didDeleteAll: Bool {
        failedProviders.isEmpty
    }
}

struct CredentialCommandService {
    private let usageProviders: [any UsageProvider]

    init(usageProviders: [any UsageProvider]) {
        self.usageProviders = usageProviders
    }

    func claudeImporter() -> (any ClaudeCredentialImportingProvider)? {
        usageProviders.first { $0.provider == .claude } as? any ClaudeCredentialImportingProvider
    }

    func codexImporter() -> (any CodexCredentialImportingProvider)? {
        usageProviders.first { $0.provider == .codex } as? any CodexCredentialImportingProvider
    }

    func deleteCachedCredentials() -> CredentialDeleteResult {
        var deletedProviders = Set<Provider>()
        var failedProviders = Set<Provider>()
        for usageProvider in usageProviders {
            guard let credentialProvider = usageProvider as? any CredentialCachingProvider else {
                continue
            }
            do {
                try credentialProvider.deleteCachedCredentials()
                deletedProviders.insert(usageProvider.provider)
            } catch {
                failedProviders.insert(usageProvider.provider)
            }
        }
        return CredentialDeleteResult(
            deletedProviders: deletedProviders,
            failedProviders: failedProviders)
    }
}
