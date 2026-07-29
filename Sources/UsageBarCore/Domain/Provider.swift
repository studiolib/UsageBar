import Foundation

public enum Provider: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case claude = "Claude"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var usagePageURL: URL {
        switch self {
        case .codex:
            URL(string: "https://chatgpt.com/#settings/Usage")!
        case .claude:
            URL(string: "https://claude.ai/new#settings/usage")!
        }
    }
}
