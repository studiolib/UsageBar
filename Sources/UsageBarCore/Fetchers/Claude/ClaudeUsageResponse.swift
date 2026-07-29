import Foundation

struct ClaudeUsageResponse: Equatable {
    var fiveHour: ClaudeUsageWindowResponse?
    var sevenDay: ClaudeUsageWindowResponse?

    static func parse(data: Data) throws -> ClaudeUsageResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageProviderError.parseError
        }

        var fiveHour = ClaudeUsageWindowResponse.parse(
            from: dictionary(in: root, keys: ["five_hour", "fiveHour", "fiveHourLimit"]))
        var sevenDay = ClaudeUsageWindowResponse.parse(
            from: dictionary(in: root, keys: ["seven_day", "sevenDay", "weekly", "weekly_limit", "weeklyLimit"]))

        for window in collectCandidateWindows(from: root) {
            if fiveHour == nil, window.isFiveHourWindow {
                fiveHour = window
            }
            if sevenDay == nil, window.isWeeklyWindow {
                sevenDay = window
            }
        }

        return ClaudeUsageResponse(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func collectCandidateWindows(from object: [String: Any]) -> [ClaudeUsageWindowResponse] {
        var windows: [ClaudeUsageWindowResponse] = []
        for key in [
            "five_hour",
            "fiveHour",
            "fiveHourLimit",
            "seven_day",
            "sevenDay",
            "weekly",
            "weekly_limit",
            "weeklyLimit",
        ] {
            windows.append(contentsOf: ClaudeUsageWindowResponse.parseMany(from: object[key]))
        }
        for key in ["limits", "usage", "rate_limits", "rateLimits", "windows"] {
            windows.append(contentsOf: ClaudeUsageWindowResponse.parseMany(from: object[key]))
        }
        return windows
    }
}

struct ClaudeUsageWindowResponse: Equatable {
    var utilization: Double
    var resetsAt: Date?
    var resetAfterSeconds: Double?
    var windowSeconds: Double?

    var isFiveHourWindow: Bool {
        windowSeconds.map { abs($0 - 18_000) < 1 } ?? false
    }

    var isWeeklyWindow: Bool {
        windowSeconds.map { abs($0 - 604_800) < 1 } ?? false
    }

    static func parse(from value: Any?) -> ClaudeUsageWindowResponse? {
        guard let object = value as? [String: Any],
              let utilization = ClaudeUsageResponse.double(
                in: object,
                keys: ["utilization", "used_percent", "usedPercent"])
        else {
            return nil
        }

        let resetsAt = parseResetDate(from: object)
        let resetAfterSeconds = ClaudeUsageResponse.double(
            in: object,
            keys: ["reset_after_seconds", "resetAfterSeconds"])

        return ClaudeUsageWindowResponse(
            utilization: utilization,
            resetsAt: resetsAt,
            resetAfterSeconds: resetAfterSeconds,
            windowSeconds: parseWindowSeconds(from: object))
    }

    static func parseMany(from value: Any?) -> [ClaudeUsageWindowResponse] {
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
        if let seconds = ClaudeUsageResponse.double(
            in: object,
            keys: ["limit_window_seconds", "window_seconds", "windowDurationSeconds"])
        {
            return seconds
        }
        return ClaudeUsageResponse.double(
            in: object,
            keys: ["window_minutes", "windowMinutes", "windowDurationMins"])
            .map { $0 * 60 }
    }

    private static func parseResetDate(from object: [String: Any]) -> Date? {
        if let timestamp = ClaudeUsageResponse.double(
            in: object,
            keys: ["reset_at", "resets_at", "resetsAt", "resetAt"])
        {
            return Date(timeIntervalSince1970: timestamp)
        }
        guard let value = ClaudeUsageResponse.string(
            in: object,
            keys: ["reset_at", "resets_at", "resetsAt", "resetAt"])
        else {
            return nil
        }
        return UsageBarISO8601.date(from: value)
            ?? Double(value).map { Date(timeIntervalSince1970: $0) }
    }
}

extension ClaudeUsageResponse {
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
