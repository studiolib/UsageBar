import Foundation

enum UsagePercent {
    static func normalize(_ value: Double) -> Double {
        let percent = value < 1 ? value * 100 : value
        return min(max(percent, 0), 100)
    }
}
