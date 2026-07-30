import SwiftUI
import UsageBarCore

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var usageStore: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingCredentialDeleteConfirmation = false

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
                Button("Claude 認証情報を再取り込み") {
                    Task {
                        await usageStore.importClaudeCredentials()
                    }
                }
                .disabled(usageStore.isPerformingOperation)

                Button("Codex 認証情報を再取り込み") {
                    Task {
                        await usageStore.importCodexCredentials()
                    }
                }
                .disabled(usageStore.isPerformingOperation)

                Button("表示中の利用量を消去") {
                    usageStore.clearCachedSnapshots()
                }
                .disabled(usageStore.isPerformingOperation)

                Button("UsageBar資格情報を削除") {
                    isShowingCredentialDeleteConfirmation = true
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
        .alert("UsageBar資格情報を削除しますか？", isPresented: $isShowingCredentialDeleteConfirmation) {
            Button("削除", role: .destructive) {
                usageStore.deleteCachedCredentials()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Claude Code / Codex CLI 本体の資格情報は削除されません。UsageBar専用のKeychain情報だけを削除します。復旧するには、必要に応じてClaude Code / Codex CLIでログイン後、認証情報を再取り込みしてください。")
        }
    }

    private var refreshInterval: Binding<RefreshInterval> {
        Binding {
            settingsStore.settings.refreshInterval
        } set: { value in
            settingsStore.settings.refreshInterval = value
        }
    }
}
