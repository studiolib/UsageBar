import Foundation

struct CredentialDeleteResult {
    let deletedProviders: Set<Provider>
    let failedProviders: Set<Provider>

    var didDeleteAll: Bool {
        !deletedProviders.isEmpty && failedProviders.isEmpty
    }
}

struct CredentialCommandService {
    private let claudeImporterProvider: (any ClaudeCredentialImportingProvider)?
    private let codexImporterProvider: (any CodexCredentialImportingProvider)?

    init(
        claudeProvider: (any ClaudeCredentialImportingProvider)?,
        codexProvider: (any CodexCredentialImportingProvider)?)
    {
        claudeImporterProvider = claudeProvider
        codexImporterProvider = codexProvider
    }

    func claudeImporter() -> (any ClaudeCredentialImportingProvider)? {
        claudeImporterProvider
    }

    func codexImporter() -> (any CodexCredentialImportingProvider)? {
        codexImporterProvider
    }

    func deleteCachedCredentials() -> CredentialDeleteResult {
        var deletedProviders = Set<Provider>()
        var failedProviders = Set<Provider>()
        if let claudeImporterProvider {
            do {
                try claudeImporterProvider.deleteCachedCredentials()
                deletedProviders.insert(.claude)
            } catch {
                failedProviders.insert(.claude)
            }
        }
        if let codexImporterProvider {
            do {
                try codexImporterProvider.deleteCachedCredentials()
                deletedProviders.insert(.codex)
            } catch {
                failedProviders.insert(.codex)
            }
        }
        return CredentialDeleteResult(
            deletedProviders: deletedProviders,
            failedProviders: failedProviders)
    }
}
