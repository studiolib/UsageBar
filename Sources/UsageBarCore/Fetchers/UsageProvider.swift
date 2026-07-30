import Foundation

public protocol UsageProvider: Sendable {
    var provider: Provider { get }

    func fetchSnapshot() async throws -> UsageSnapshot
}

public protocol CredentialCachingProvider: UsageProvider {
    func deleteCachedCredentials() throws
}

protocol ProviderUsageDisplayError: Error {
    var failureCode: String { get }
    var userMessage: String { get }
    var requiresAuthentication: Bool { get }
}
