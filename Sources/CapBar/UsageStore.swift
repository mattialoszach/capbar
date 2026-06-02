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
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var menuBarSnapshot: ProviderSnapshot {
        snapshots.first { $0.provider == settings.menuBarProvider } ?? .loading(provider: settings.menuBarProvider)
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        snapshots.first { $0.provider == provider } ?? .loading(provider: provider)
    }

    func refresh() {
        isRefreshing = true
        lastError = nil

        let task = Task.detached(priority: .utility) {
            [
                CodexUsageReader().read(),
                ClaudeUsageReader().read()
            ]
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

    func runCLILogin(for provider: ProviderID) {
        ProviderLoginRunner.runCLILogin(for: provider)
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
