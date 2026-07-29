import SwiftUI
import UsageBarCore

struct UsageWindowRow: View {
    let window: UsageWindow
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text("残り \(Int(window.remainingPercent.rounded()))%")
                    .font(.callout.weight(.semibold))
            }

            ProgressView(value: window.remainingPercent, total: 100)
                .tint(accent)

            HStack {
                Text(resetAtText)
                Spacer()
                Text(resetDescriptionText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetAtText: String {
        guard let resetAt = window.resetAt else { return "リセット: 不明" }
        return "リセット: \(resetAt.formatted(date: .numeric, time: .shortened))"
    }

    private var resetDescriptionText: String {
        guard window.resetDescription != "不明" else { return "リセット時刻不明" }
        return "\(window.resetDescription)にリセット"
    }
}
