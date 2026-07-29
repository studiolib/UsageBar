import Foundation

public protocol UsageProvider: Sendable {
    var provider: Provider { get }

    func fetch() async -> ProviderUsageState
}

public protocol CredentialCachingProvider: UsageProvider {
    func deleteCachedCredentials() throws
}
