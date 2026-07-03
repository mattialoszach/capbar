import Foundation
import SwiftUI

enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    var shortName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "terminal.fill"
        case .claude: "sparkles"
        }
    }

    var logoResourceName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        }
    }

    var next: ProviderID {
        let providers = Self.allCases
        guard let currentIndex = providers.firstIndex(of: self) else { return self }
        return providers[(currentIndex + 1) % providers.count]
    }
}

struct UsageSettings: Codable, Equatable {
    var menuBarProvider: ProviderID
    var menuBarDisplayMode: MenuBarDisplayMode
    var providerRotationInterval: ProviderRotationInterval
    var refreshInterval: RefreshInterval
    var lowUsageColorsEnabled: Bool
    var apiSectionVisible: Bool
    var apiMonthlyBudgetsUSD: [String: Double]

    static let `default` = UsageSettings(menuBarProvider: .codex)

    init(
        menuBarProvider: ProviderID,
        menuBarDisplayMode: MenuBarDisplayMode = .subscription,
        providerRotationInterval: ProviderRotationInterval = .off,
        refreshInterval: RefreshInterval = .oneMinute,
        lowUsageColorsEnabled: Bool = true,
        apiSectionVisible: Bool = true,
        apiMonthlyBudgetsUSD: [String: Double] = [:]
    ) {
        self.menuBarProvider = menuBarProvider
        self.menuBarDisplayMode = menuBarDisplayMode
        self.providerRotationInterval = providerRotationInterval
        self.refreshInterval = refreshInterval
        self.lowUsageColorsEnabled = lowUsageColorsEnabled
        self.apiSectionVisible = apiSectionVisible
        self.apiMonthlyBudgetsUSD = apiMonthlyBudgetsUSD
    }

    func apiMonthlyBudgetUSD(for provider: ProviderID) -> Double? {
        apiMonthlyBudgetsUSD[provider.rawValue]
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarProvider
        case menuBarDisplayMode
        case providerRotationInterval
        case refreshInterval
        case lowUsageColorsEnabled
        case apiSectionVisible
        case apiMonthlyBudgetsUSD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarProvider = try container.decodeIfPresent(ProviderID.self, forKey: .menuBarProvider) ?? .codex
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .subscription
        providerRotationInterval = try container.decodeIfPresent(ProviderRotationInterval.self, forKey: .providerRotationInterval) ?? .off
        refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? .oneMinute
        lowUsageColorsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowUsageColorsEnabled) ?? true
        apiSectionVisible = try container.decodeIfPresent(Bool.self, forKey: .apiSectionVisible) ?? true
        apiMonthlyBudgetsUSD = try container.decodeIfPresent([String: Double].self, forKey: .apiMonthlyBudgetsUSD) ?? [:]
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case subscription
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscription: "Subscription"
        case .api: "API Data"
        }
    }
}

enum ProviderRotationInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    case off = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case twentySeconds = 20
    case thirtySeconds = 30

    var id: Int { rawValue }

    var timeInterval: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .fiveSeconds: "5 sec"
        case .tenSeconds: "10 sec"
        case .twentySeconds: "20 sec"
        case .thirtySeconds: "30 sec"
        }
    }
}

enum RefreshInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    case manual = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var timeInterval: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .manual: "Manual"
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        }
    }
}

struct ProviderAccount: Equatable {
    var isLoggedIn: Bool
    var email: String?
    var detail: String?

    static let loggedOut = ProviderAccount(isLoggedIn: false, email: nil, detail: nil)
}

struct ProviderSnapshot: Identifiable, Equatable {
    var id: ProviderID { provider }

    let provider: ProviderID
    let account: ProviderAccount
    let current: LimitMetric?
    let weekly: LimitMetric?
    let sourceDescription: String
    let refreshedAt: Date

    var menuBarMetric: LimitMetric? {
        current ?? weekly
    }

    var menuBarPercent: Double? {
        menuBarMetric?.usedPercent
    }

    var isAvailable: Bool {
        current != nil || weekly != nil
    }

    static func loading(provider: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            account: .loggedOut,
            current: nil,
            weekly: nil,
            sourceDescription: "Loading",
            refreshedAt: Date()
        )
    }
}

struct LimitMetric: Equatable {
    let title: String
    let detail: String
    let usedPercent: Double?
    let resetDate: Date?

    var fractionUsed: Double {
        guard let usedPercent else { return 0 }
        return min(1, max(0, usedPercent / 100))
    }

    var percentText: String {
        guard let usedPercent else { return "--%" }
        return "\(Int(usedPercent.rounded()))%"
    }

    var usedText: String {
        guard let usedPercent else { return "Unavailable" }
        return "\(Int(usedPercent.rounded()))% used"
    }

    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }

    var fractionRemaining: Double {
        guard let remainingPercent else { return 0 }
        return min(1, max(0, remainingPercent / 100))
    }

    var remainingPercentText: String {
        guard let remainingPercent else { return "--%" }
        return "\(Int(remainingPercent.rounded()))%"
    }

    var remainingText: String {
        guard let remainingPercent else { return "Unavailable" }
        return "\(Int(remainingPercent.rounded()))% left"
    }
}
