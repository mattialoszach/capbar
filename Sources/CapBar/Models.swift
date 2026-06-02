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
}

struct UsageSettings: Codable, Equatable {
    var menuBarProvider: ProviderID

    static let `default` = UsageSettings(menuBarProvider: .codex)
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
}
