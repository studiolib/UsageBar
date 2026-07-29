import XCTest
@testable import UsageBarCore

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testLoadsDefaultsWhenNoSettingsAreSaved() {
        let defaults = makeDefaults()

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, AppSettings())
    }

    @MainActor
    func testPersistsAndReloadsSettings() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.settings.refreshInterval = .fifteenMinutes

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings.refreshInterval, .fifteenMinutes)
    }

    @MainActor
    func testResetToDefaultsPersistsDefaultSettings() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.settings.refreshInterval = .thirtyMinutes

        store.resetToDefaults()
        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings, AppSettings())
    }

    @MainActor
    func testRemovesLegacyClaudeKeychainPromptPolicy() {
        let defaults = makeDefaults()
        defaults.set("alwaysAsk", forKey: "settings.claudeKeychainPromptPolicy")

        _ = SettingsStore(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "settings.claudeKeychainPromptPolicy"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UsageBarCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
