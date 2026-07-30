import Foundation

enum RelativeResetDescriptionFormatter {
    static func text(until resetAt: Date, now: Date) -> String {
        let seconds = max(0, Int(resetAt.timeIntervalSince(now).rounded()))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60

        if days > 0 {
            return "\(days)日\(hours)時間後"
        }
        if hours > 0 {
            return "\(hours)時間\(minutes)分後"
        }
        if minutes > 0 {
            return "\(minutes)分後"
        }
        return "\(seconds)秒後"
    }
}
