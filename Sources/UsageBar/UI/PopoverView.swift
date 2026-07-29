import AppKit
import SwiftUI
import UsageBarCore

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settingsStore: SettingsStore
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 14) {
                ForEach(store.states) { state in
                    ProviderUsageCard(state: state)
                }
            }
            .padding(16)

            Divider()

            footer
        }
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settingsStore: settingsStore, usageStore: store)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UsageBar")
                    .font(.headline)
                Text("最終更新: \(store.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await store.refreshUsage()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isPerformingOperation)
            .help("更新")
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("設定...") {
                isShowingSettings = true
            }

            Spacer()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.callout)
        .padding(16)
    }
}
