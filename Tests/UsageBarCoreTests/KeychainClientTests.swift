import Security
import XCTest
@testable import UsageBarCore

final class KeychainClientTests: XCTestCase {
    func testUsageBarCredentialsStayOnThisDeviceAfterFirstUnlock() {
        XCTAssertEqual(
            SecurityKeychainClient.credentialAccessibility as String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
}
