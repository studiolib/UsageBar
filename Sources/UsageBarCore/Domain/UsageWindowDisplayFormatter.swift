import Foundation

public enum UsageWindowDisplayFormatter {
    public static func resetAtText(
        _ resetAt: Date?,
        locale: Locale = Locale(identifier: "ja_JP"),
        timeZone: TimeZone = .current)
        -> String
    {
        guard let resetAt else { return "リセット: 不明" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日(E) H:mm"
        return "リセット: \(formatter.string(from: resetAt))"
    }

    public static func resetDescriptionText(_ resetDescription: String) -> String {
        guard resetDescription != "不明" else { return "リセット時刻不明" }
        return "\(resetDescription)にリセット"
    }

    public static func resetDescriptionText(resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt else { return "リセット時刻不明" }
        return "\(RelativeResetDescriptionFormatter.text(until: resetAt, now: now))にリセット"
    }
}
