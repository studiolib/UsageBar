import Foundation
import LocalAuthentication
import Security

public enum KeychainClientError: Error, Equatable, Sendable {
    case itemNotFound
    case interactionNotAllowed
    case accessDenied
    case unexpectedStatus(OSStatus)
    case invalidData
}

public protocol KeychainClient: Sendable {
    func readGenericPassword(service: String, account: String?, allowInteraction: Bool) throws -> Data
    func writeGenericPassword(_ data: Data, service: String, account: String) throws
    func deleteGenericPassword(service: String, account: String) throws
}

public final class SecurityKeychainClient: KeychainClient, @unchecked Sendable {
    public static var credentialAccessibility: CFString {
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }

    public init() {}

    public func readGenericPassword(service: String, account: String?, allowInteraction: Bool) throws -> Data {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
        ]
        if let account {
            query[kSecAttrAccount] = account
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw mapStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainClientError.invalidData
        }
        return data
    }

    public func writeGenericPassword(_ data: Data, service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: Self.credentialAccessibility,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw mapStatus(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw mapStatus(addStatus)
        }
    }

    public func deleteGenericPassword(service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mapStatus(status)
        }
    }

    private func mapStatus(_ status: OSStatus) -> KeychainClientError {
        switch status {
        case errSecItemNotFound:
            .itemNotFound
        case errSecInteractionNotAllowed:
            .interactionNotAllowed
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem:
            .accessDenied
        default:
            .unexpectedStatus(status)
        }
    }
}
