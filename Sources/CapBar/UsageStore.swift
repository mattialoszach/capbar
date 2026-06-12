import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var settings: UsageSettings
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private let userDefaultsKey = "CapBar.UsageSettings.v2"

    init() {
        settings = Self.loadSettings(key: userDefaultsKey)
        refresh()
        configureRefreshTimer()
    }

    var menuBarSnapshot: ProviderSnapshot {
        snapshots.first { $0.provider == settings.menuBarProvider } ?? .loading(provider: settings.menuBarProvider)
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        snapshots.first { $0.provider == provider } ?? .loading(provider: provider)
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        lastError = nil

        let task = Task.detached(priority: .utility) {
            let codex = CodexUsageReader().read()
            let claude = await ClaudeUsageReader().read()
            return [codex, claude]
        }

        Task { @MainActor [weak self] in
            self?.snapshots = await task.value
            self?.isRefreshing = false
        }
    }

    func setMenuBarProvider(_ provider: ProviderID) {
        settings.menuBarProvider = provider
        persistSettings()
    }

    func rotateMenuBarProvider() {
        setMenuBarProvider(settings.menuBarProvider.next)
    }

    func setProviderRotationInterval(_ interval: ProviderRotationInterval) {
        settings.providerRotationInterval = interval
        persistSettings()
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        settings.refreshInterval = interval
        persistSettings()
        configureRefreshTimer()
    }

    func setLowUsageColorsEnabled(_ isEnabled: Bool) {
        settings.lowUsageColorsEnabled = isEnabled
        persistSettings()
    }

    func runCLILogin(for provider: ProviderID) {
        ProviderLoginRunner.runCLILogin(for: provider)
    }

    private func configureRefreshTimer() {
        timer?.invalidate()

        guard let interval = settings.refreshInterval.timeInterval else {
            timer = nil
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func persistSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func loadSettings(key: String) -> UsageSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(UsageSettings.self, from: data) else {
            return .default
        }
        return decoded
    }
}
