import SwiftUI
import UsageBarCore

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var usageStore: UsageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("設定")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Picker("更新間隔", selection: refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

            }
            .pickerStyle(.menu)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Claude を再認証") {
                    Task {
                        await usageStore.importClaudeCredentials()
                    }
                }
                .disabled(usageStore.isPerformingOperation)

                Button("Codex を再認証") {
                    Task {
                        await usageStore.importCodexCredentials()
                    }
                }
                .disabled(usageStore.isPerformingOperation)

                Button("表示キャッシュ削除") {
                    usageStore.clearCachedSnapshots()
                }
                .disabled(usageStore.isPerformingOperation)

                Button("資格情報削除") {
                    usageStore.deleteCachedCredentials()
                }
                .disabled(usageStore.isPerformingOperation)
            }

            HStack {
                Spacer()

                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var refreshInterval: Binding<RefreshInterval> {
        Binding {
            settingsStore.settings.refreshInterval
        } set: { value in
            settingsStore.settings.refreshInterval = value
        }
    }
}
