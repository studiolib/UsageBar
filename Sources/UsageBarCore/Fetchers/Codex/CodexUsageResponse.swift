import Foundation

struct CodexUsageResponse: Equatable {
    var planType: String?
    var rateLimit: CodexRateLimit

    static func parse(data: Data) throws -> CodexUsageResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageProviderError.parseError
        }

        let rateLimitObject = dictionary(
            in: root,
            keys: ["rate_limit", "rateLimits", "rate_limits"])
            ?? root

        return CodexUsageResponse(
            planType: string(in: root, keys: ["plan_type", "planType"]),
            rateLimit: CodexRateLimit.parse(from: rateLimitObject))
    }
}

struct CodexRateLimit: Equatable {
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?

    static func parse(from object: [String: Any]) -> CodexRateLimit {
        var primary = CodexRateLimitWindow.parse(
            from: CodexUsageResponse.dictionary(
                in: object,
                keys: ["primary_window", "primaryWindow", "primary"]))
        var secondary = CodexRateLimitWindow.parse(
            from: CodexUsageResponse.dictionary(
                in: object,
                keys: ["secondary_window", "secondaryWindow", "secondary"]))

        for window in collectCandidateWindows(from: object) {
            if primary == nil, window.isFiveHourWindow {
                primary = window
            }
            if secondary == nil, window.isWeeklyWindow {
                secondary = window
            }
        }

        return CodexRateLimit(primaryWindow: primary, secondaryWindow: secondary)
    }

    private static func collectCandidateWindows(from object: [String: Any]) -> [CodexRateLimitWindow] {
        var windows: [CodexRateLimitWindow] = []
        let directKeys = [
            "primary_window",
            "primaryWindow",
            "primary",
            "secondary_window",
            "secondaryWindow",
            "secondary",
        ]
        for key in directKeys {
            windows.append(contentsOf: CodexRateLimitWindow.parseMany(from: object[key]))
        }
        for key in ["windows", "rate_limits", "rateLimits", "additional_rate_limits", "additionalRateLimits"] {
            windows.append(contentsOf: CodexRateLimitWindow.parseMany(from: object[key]))
        }
        return windows
    }
}

struct CodexRateLimitWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?
    var resetAfterSeconds: Double?
    var windowSeconds: Double?

    var isFiveHourWindow: Bool {
        windowSeconds.map { abs($0 - 18_000) < 1 } ?? false
    }

    var isWeeklyWindow: Bool {
        windowSeconds.map { abs($0 - 604_800) < 1 } ?? false
    }

    static func parse(from value: Any?) -> CodexRateLimitWindow? {
        guard let object = value as? [String: Any] else { return nil }
        guard let usedPercent = CodexUsageResponse.double(
            in: object,
            keys: ["used_percent", "usedPercent", "utilization"])
        else {
            return nil
        }

        let resetAfterSeconds = CodexUsageResponse.double(
            in: object,
            keys: ["reset_after_seconds", "resetAfterSeconds"])
        let windowSeconds = parseWindowSeconds(from: object)

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetsAt: parseResetDate(from: object),
            resetAfterSeconds: resetAfterSeconds,
            windowSeconds: windowSeconds)
    }

    static func parseMany(from value: Any?) -> [CodexRateLimitWindow] {
        if let window = parse(from: value) {
            return [window]
        }
        if let array = value as? [Any] {
            return array.compactMap(parse(from:))
        }
        if let object = value as? [String: Any] {
            return object.values.flatMap(parseMany(from:))
        }
        return []
    }

    private static func parseWindowSeconds(from object: [String: Any]) -> Double? {
        if let seconds = CodexUsageResponse.double(
            in: object,
            keys: ["limit_window_seconds", "window_seconds", "windowDurationSeconds"])
        {
            return seconds
        }
        return CodexUsageResponse.double(
            in: object,
            keys: ["window_minutes", "windowMinutes", "windowDurationMins"])
            .map { $0 * 60 }
    }

    private static func parseResetDate(from object: [String: Any]) -> Date? {
        if let timestamp = CodexUsageResponse.double(
            in: object,
            keys: ["reset_at", "resets_at", "resetsAt", "resetAt"])
        {
            return Date(timeIntervalSince1970: timestamp)
        }
        guard let value = CodexUsageResponse.string(
            in: object,
            keys: ["reset_at", "resets_at", "resetsAt", "resetAt"])
        else {
            return nil
        }
        return UsageBarISO8601.date(from: value)
            ?? Double(value).map { Date(timeIntervalSince1970: $0) }
    }
}

extension CodexUsageResponse {
    static func dictionary(in object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    static func double(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = object[key] as? String,
               let number = Double(value)
            {
                return number
            }
        }
        return nil
    }
}

enum UsageBarISO8601 {
    static func date(from value: String) -> Date? {
        formatter(fractionalSeconds: true).date(from: value)
            ?? formatter(fractionalSeconds: false).date(from: value)
    }

    static func string(from date: Date, fractionalSeconds: Bool) -> String {
        formatter(fractionalSeconds: fractionalSeconds).string(from: date)
    }

    private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
