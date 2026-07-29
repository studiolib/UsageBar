import AppKit
import SwiftUI
import UsageBarCore

struct ProviderUsageCard: View {
    let state: ProviderUsageState

    private var snapshot: UsageSnapshot? {
        state.current ?? state.lastSuccessful
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.provider.displayName)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 12)

                if let headerDetail = snapshot.map(headerDetailText(for:)) {
                    Text(headerDetail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let snapshot {
                if let cachedSnapshotNotice {
                    Label(cachedSnapshotNotice.title, systemImage: cachedSnapshotNotice.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cachedSnapshotNotice.color)

                    if let failureMessage = state.lastFailure?.message {
                        Text(failureMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let shortWindow = snapshot.shortWindow {
                    UsageWindowRow(window: shortWindow, accent: state.provider.accentColor)
                }
                if let weeklyWindow = snapshot.weeklyWindow {
                    UsageWindowRow(window: weeklyWindow, accent: state.provider.accentColor)
                }
                HStack(alignment: .center) {
                    Text("\(snapshotTimestampLabel): \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(state.provider.usagePageURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("\(state.provider.displayName) の使用量ページを開く")
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.lastFailure?.message ?? "利用制限データがありません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let failure = state.lastFailure {
                        Text("コード: \(failure.code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func headerDetailText(for snapshot: UsageSnapshot) -> String {
        snapshot.planLabel
    }

    private var isShowingCachedSnapshot: Bool {
        state.current == nil && state.lastSuccessful != nil
    }

    private var snapshotTimestampLabel: String {
        isShowingCachedSnapshot ? "前回取得" : "取得"
    }

    private var cachedSnapshotNotice: CachedSnapshotNotice? {
        guard isShowingCachedSnapshot else { return nil }

        switch state.status {
        case .authRequired:
            return CachedSnapshotNotice(
                title: "認証が必要です。前回の取得結果を表示しています。",
                systemImage: "key.fill",
                color: .red)
        case .stale:
            return CachedSnapshotNotice(
                title: "更新に失敗しました。前回の取得結果を表示しています。",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange)
        case .fresh:
            return nil
        }
    }
}

private struct CachedSnapshotNotice {
    let title: String
    let systemImage: String
    let color: Color
}

private extension Provider {
    var accentColor: Color {
        switch self {
        case .codex:
            .blue
        case .claude:
            .orange
        }
    }
}
