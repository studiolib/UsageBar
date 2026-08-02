import AppKit
import Combine
import SwiftUI
import UsageBarCore

@main
@MainActor
final class UsageBarApplication: NSObject, NSApplicationDelegate {
    private static let appDelegate = UsageBarApplication()

    private let store = UsageStore()
    private let settingsStore = SettingsStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        configureStatusItem()
        configurePopover()
        configureBindings()
        scheduleAutoRefresh(for: settingsStore.settings.refreshInterval)
        performRefresh()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 30)
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleNone
        item.button?.title = ""
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        updateStatusItemAppearance()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 390)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store, settingsStore: settingsStore))
    }

    private func configureBindings() {
        store.$states
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItemAppearance()
                }
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .dropFirst()
            .map(\.refreshInterval)
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.scheduleAutoRefresh(for: interval)
            }
            .store(in: &cancellables)
    }

    private func scheduleAutoRefresh(for interval: RefreshInterval) {
        refreshTimer?.invalidate()

        let timer = Timer(timeInterval: interval.timeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func performRefresh() {
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await store.refreshUsage()
            refreshTask = nil
        }
    }

    private func updateStatusItemAppearance() {
        let claudeRemaining = store.weeklyRemainingPercent(for: .claude)
        let codexRemaining = store.weeklyRemainingPercent(for: .codex)

        statusItem?.button?.image = MenuBarUsageIconRenderer.image(
            claudeRemainingPercent: claudeRemaining,
            codexRemainingPercent: codexRemaining)
        statusItem?.button?.toolTip = "Claude \(percentageLabel(claudeRemaining)) / Codex \(percentageLabel(codexRemaining))"
    }

    private func percentageLabel(_ value: Double?) -> String {
        guard let value else { return "未取得" }
        return "\(Int(value.rounded()))%"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
