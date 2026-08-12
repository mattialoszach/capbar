import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var settings: UsageSettings
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var apiSnapshots: [APIAccountSnapshot] = []
    @Published private(set) var checkingAPIKeyProviderIDs: Set<String> = []
    @Published private(set) var removingAPIKeyProviderIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var pendingForceRefresh = false
    private var pendingAPIKeyCheckProviderIDs: Set<String> = []
    private var pendingAPIKeyRemovalProviderIDs: Set<String> = []
    private let userDefaultsKey = "CapBar.UsageSettings.v2"

    init() {
        settings = Self.loadSettings(key: userDefaultsKey)
        refresh()
        configureRefreshTimer()
    }

    var menuBarSnapshot: ProviderSnapshot {
        snapshots.first { $0.provider == settings.menuBarProvider } ?? .loading(provider: settings.menuBarProvider)
    }

    var menuBarAPISnapshot: APIAccountSnapshot {
        apiSnapshot(for: settings.menuBarProvider)
    }

    var menuBarAPIMonthlyBudgetUSD: Double? {
        settings.apiMonthlyBudgetUSD(for: settings.menuBarProvider)
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        effectiveMenuBarDisplayMode(for: settings.menuBarProvider)
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        snapshots.first { $0.provider == provider } ?? .loading(provider: provider)
    }

    func apiSnapshot(for provider: ProviderID) -> APIAccountSnapshot {
        apiSnapshots.first { $0.provider == provider } ?? .noKey(provider: provider)
    }

    func configuredMenuBarDisplayMode(for provider: ProviderID) -> MenuBarDisplayMode {
        settings.menuBarDisplayMode(for: provider)
    }

    func effectiveMenuBarDisplayMode(for provider: ProviderID) -> MenuBarDisplayMode {
        let displayMode = configuredMenuBarDisplayMode(for: provider)

        switch displayMode {
        case .subscription:
            return .subscription
        case .api:
            return hasAPISpend(for: provider) ? .api : .subscription
        case .apiLimit:
            return manualAPILimitMetric(for: provider) == nil ? .subscription : .apiLimit
        }
    }

    func canSelectMenuBarDisplayMode(_ mode: MenuBarDisplayMode, for provider: ProviderID) -> Bool {
        switch mode {
        case .subscription:
            return true
        case .api:
            return hasAPISpend(for: provider)
        case .apiLimit:
            return manualAPILimitMetric(for: provider) != nil
        }
    }

    func isCheckingAPIKey(for provider: ProviderID) -> Bool {
        checkingAPIKeyProviderIDs.contains(provider.rawValue)
    }

    func isRemovingAPIKey(for provider: ProviderID) -> Bool {
        removingAPIKeyProviderIDs.contains(provider.rawValue)
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
        let activeAPIKeyRemovalProviderIDs = pendingAPIKeyRemovalProviderIDs
        pendingAPIKeyCheckProviderIDs.removeAll()
        pendingAPIKeyRemovalProviderIDs.removeAll()

        let task = Task.detached(priority: .utility) { () -> ([ProviderSnapshot], [APIAccountSnapshot]) in
            let codex = CodexUsageReader().read()
            let claude = await ClaudeUsageReader().read(force: force)
            let codexAPI = await APIAccountReader(provider: .codex).read(force: force)
            let claudeAPI = await APIAccountReader(provider: .claude).read(force: force)
            return ([codex, claude], [codexAPI, claudeAPI])
        }

        Task { @MainActor [weak self] in
            let (snapshots, apiSnapshots) = await task.value
            self?.snapshots = snapshots
            self?.apiSnapshots = apiSnapshots
            if let self {
                let stillPendingChecks = self.pendingAPIKeyCheckProviderIDs
                let stillPendingRemovals = self.pendingAPIKeyRemovalProviderIDs
                self.checkingAPIKeyProviderIDs.subtract(activeAPIKeyCheckProviderIDs.subtracting(stillPendingChecks))
                self.removingAPIKeyProviderIDs.subtract(activeAPIKeyRemovalProviderIDs.subtracting(stillPendingRemovals))
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
        removingAPIKeyProviderIDs.remove(provider.rawValue)
        pendingAPIKeyRemovalProviderIDs.remove(provider.rawValue)
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
        removingAPIKeyProviderIDs.insert(provider.rawValue)
        pendingAPIKeyRemovalProviderIDs.insert(provider.rawValue)
        APIKeyStore.deleteKey(for: provider)
        APIAccountReader(provider: provider).clearCache()
        settings.setMenuBarDisplayMode(.subscription, for: provider)
        persistSettings()
        refresh(force: true)
    }

    func setAPIMonthlyBudget(_ budgetUSD: Double?, for provider: ProviderID) {
        if let budgetUSD, budgetUSD > 0 {
            settings.apiMonthlyBudgetsUSD[provider.rawValue] = budgetUSD
        } else {
            settings.apiMonthlyBudgetsUSD.removeValue(forKey: provider.rawValue)
            if configuredMenuBarDisplayMode(for: provider) == .apiLimit {
                settings.setMenuBarDisplayMode(.subscription, for: provider)
            }
        }
        persistSettings()
    }

    func setMenuBarProvider(_ provider: ProviderID) {
        settings.menuBarProvider = provider
        persistSettings()
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        setMenuBarDisplayMode(mode, for: settings.menuBarProvider)
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode, for provider: ProviderID) {
        guard canSelectMenuBarDisplayMode(mode, for: provider) else { return }
        settings.setMenuBarDisplayMode(mode, for: provider)
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

    func setAPISectionVisible(_ isVisible: Bool) {
        settings.apiSectionVisible = isVisible
        persistSettings()
    }

    func runCLILogin(for provider: ProviderID) {
        ProviderLoginRunner.runCLILogin(for: provider)
    }

    private func hasAPISpend(for provider: ProviderID) -> Bool {
        guard case let .spend(summary) = apiSnapshot(for: provider).status else { return false }
        return summary.hasSpend
    }

    private func manualAPILimitMetric(for provider: ProviderID) -> LimitMetric? {
        guard case let .spend(summary) = apiSnapshot(for: provider).status else { return nil }
        return summary.manualAPILimitMetric(monthlyBudgetUSD: settings.apiMonthlyBudgetUSD(for: provider))
    }

    private func configureRefreshTimer() {
        timer?.invalidate()

        guard let interval = settings.refreshInterval.timeInterval else {
            timer = nil
            return
        }

        let refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refreshTimer.tolerance = min(5, interval * 0.1)
        timer = refreshTimer
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
