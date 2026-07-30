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

            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack {
                    Text(resetAtText)
                    Spacer()
                    Text(resetDescriptionText(now: context.date))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetAtText: String {
        UsageWindowDisplayFormatter.resetAtText(window.resetAt)
    }

    private func resetDescriptionText(now: Date) -> String {
        UsageWindowDisplayFormatter.resetDescriptionText(resetAt: window.resetAt, now: now)
    }
}
