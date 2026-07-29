import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            save(settings)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: DefaultsKey.claudeKeychainPromptPolicy)
        settings = Self.load(from: defaults)
    }

    public func resetToDefaults() {
        settings = AppSettings()
    }

    private func save(_ settings: AppSettings) {
        defaults.set(settings.refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        AppSettings(
            refreshInterval: RefreshInterval(
                rawValue: defaults.integer(forKey: DefaultsKey.refreshInterval)) ?? .fiveMinutes)
    }
}

private enum DefaultsKey {
    static let refreshInterval = "settings.refreshInterval"
    static let claudeKeychainPromptPolicy = "settings.claudeKeychainPromptPolicy"
}
