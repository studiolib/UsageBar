protocol ProviderUsageDisplayError: Error {
    var failureCode: String { get }
    var userMessage: String { get }
    var requiresAuthentication: Bool { get }
}
