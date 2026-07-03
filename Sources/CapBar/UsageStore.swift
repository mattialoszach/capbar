import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var settings: UsageSettings
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var apiSnapshots: [APIAccountSnapshot] = []
    @Published private(set) var checkingAPIKeyProviderIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var pendingForceRefresh = false
    private var pendingAPIKeyCheckProviderIDs: Set<String> = []
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

    func apiSnapshot(for provider: ProviderID) -> APIAccountSnapshot {
        apiSnapshots.first { $0.provider == provider } ?? .noKey(provider: provider)
    }

    func isCheckingAPIKey(for provider: ProviderID) -> Bool {
        checkingAPIKeyProviderIDs.contains(provider.rawValue)
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else {
            if force {
                pendingForceRefresh = true
            }
            return
        }

        isRefreshing = true
        lastError = nil
        let activeAPIKeyCheckProviderIDs = pendingAPIKeyCheckProviderIDs
        pendingAPIKeyCheckProviderIDs.removeAll()

        let task = Task.detached(priority: .utility) { () -> ([ProviderSnapshot], [APIAccountSnapshot]) in
            let codex = CodexUsageReader().read()
            let claude = await ClaudeUsageReader().read()
            let codexAPI = await APIAccountReader(provider: .codex).read(force: force)
            let claudeAPI = await APIAccountReader(provider: .claude).read(force: force)
            return ([codex, claude], [codexAPI, claudeAPI])
        }

        Task { @MainActor [weak self] in
            let (snapshots, apiSnapshots) = await task.value
            self?.snapshots = snapshots
            self?.apiSnapshots = apiSnapshots
            if let self {
                let stillPending = self.pendingAPIKeyCheckProviderIDs
                self.checkingAPIKeyProviderIDs.subtract(activeAPIKeyCheckProviderIDs.subtracting(stillPending))
            }
            self?.isRefreshing = false
            if self?.pendingForceRefresh == true {
                self?.pendingForceRefresh = false
                self?.refresh(force: true)
            }
        }
    }

    func setAPIKey(_ key: String, for provider: ProviderID) {
        checkingAPIKeyProviderIDs.insert(provider.rawValue)
        pendingAPIKeyCheckProviderIDs.insert(provider.rawValue)
        guard APIKeyStore.setKey(key, for: provider) else {
            checkingAPIKeyProviderIDs.remove(provider.rawValue)
            pendingAPIKeyCheckProviderIDs.remove(provider.rawValue)
            lastError = "Could not save the API key to the Keychain"
            return
        }
        refresh(force: true)
    }

    func clearAPIKey(for provider: ProviderID) {
        checkingAPIKeyProviderIDs.remove(provider.rawValue)
        pendingAPIKeyCheckProviderIDs.remove(provider.rawValue)
        APIKeyStore.deleteKey(for: provider)
        APIAccountReader(provider: provider).clearCache()
        refresh()
    }

    func setAPIMonthlyBudget(_ budgetUSD: Double?, for provider: ProviderID) {
        if let budgetUSD, budgetUSD > 0 {
            settings.apiMonthlyBudgetsUSD[provider.rawValue] = budgetUSD
        } else {
            settings.apiMonthlyBudgetsUSD.removeValue(forKey: provider.rawValue)
        }
        persistSettings()
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
