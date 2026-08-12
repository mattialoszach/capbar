import Foundation

extension ProviderID {
    var platformName: String {
        switch self {
        case .codex: "OpenAI"
        case .claude: "Anthropic"
        }
    }

    var adminKeyHint: String {
        switch self {
        case .codex: "sk-admin-..."
        case .claude: "sk-ant-admin..."
        }
    }
}

struct APISpendSummary: Codable, Equatable {
    let monthToDateUSD: Double?
    let todayUSD: Double?
    let creditsRemainingUSD: Double?
    let creditsGrantedUSD: Double?
    let monthlyLimitUSD: Double?
    let includesEstimatedCurrentDay: Bool

    init(
        monthToDateUSD: Double?,
        todayUSD: Double?,
        creditsRemainingUSD: Double? = nil,
        creditsGrantedUSD: Double? = nil,
        monthlyLimitUSD: Double? = nil,
        includesEstimatedCurrentDay: Bool = false
    ) {
        self.monthToDateUSD = monthToDateUSD
        self.todayUSD = todayUSD
        self.creditsRemainingUSD = creditsRemainingUSD
        self.creditsGrantedUSD = creditsGrantedUSD
        self.monthlyLimitUSD = monthlyLimitUSD
        self.includesEstimatedCurrentDay = includesEstimatedCurrentDay
    }

    enum CodingKeys: String, CodingKey {
        case monthToDateUSD
        case todayUSD
        case creditsRemainingUSD
        case creditsGrantedUSD
        case monthlyLimitUSD
        case includesEstimatedCurrentDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthToDateUSD = try container.decodeIfPresent(Double.self, forKey: .monthToDateUSD)
        todayUSD = try container.decodeIfPresent(Double.self, forKey: .todayUSD)
        creditsRemainingUSD = try container.decodeIfPresent(Double.self, forKey: .creditsRemainingUSD)
        creditsGrantedUSD = try container.decodeIfPresent(Double.self, forKey: .creditsGrantedUSD)
        monthlyLimitUSD = try container.decodeIfPresent(Double.self, forKey: .monthlyLimitUSD)
        includesEstimatedCurrentDay = try container.decodeIfPresent(Bool.self, forKey: .includesEstimatedCurrentDay) ?? false
    }

    var hasSpend: Bool {
        monthToDateUSD != nil
    }

    var hasCredits: Bool {
        creditsRemainingUSD != nil
    }

    var monthToDateText: String {
        Formatters.usd(monthToDateUSD ?? 0)
    }

    var todayText: String {
        Formatters.usd(todayUSD ?? 0)
    }

    var creditsRemainingText: String {
        Formatters.usd(creditsRemainingUSD ?? 0)
    }

    var creditsGrantedText: String {
        Formatters.usd(creditsGrantedUSD ?? 0)
    }

    func apiLimitMetric(monthlyBudgetUSD: Double?) -> LimitMetric? {
        if let metric = manualAPILimitMetric(monthlyBudgetUSD: monthlyBudgetUSD) {
            return metric
        }

        if let spent = monthToDateUSD, let limit = monthlyLimitUSD, limit > 0 {
            return LimitMetric(
                title: "Monthly limit",
                detail: "\(Formatters.usd(spent)) of \(Formatters.usd(limit))",
                usedPercent: min(100, max(0, spent / limit * 100)),
                resetDate: nil
            )
        }

        if let remaining = creditsRemainingUSD,
           let granted = creditsGrantedUSD, granted > 0 {
            let used = max(0, granted - remaining)
            return LimitMetric(
                title: "API credits",
                detail: "\(Formatters.usd(used)) of \(Formatters.usd(granted))",
                usedPercent: min(100, max(0, used / granted * 100)),
                resetDate: nil
            )
        }

        return nil
    }

    func manualAPILimitMetric(monthlyBudgetUSD: Double?) -> LimitMetric? {
        guard let spent = monthToDateUSD,
              let limit = monthlyBudgetUSD,
              limit > 0 else {
            return nil
        }

        return LimitMetric(
            title: "Monthly limit",
            detail: "\(Formatters.usd(spent)) of \(Formatters.usd(limit))",
            usedPercent: min(100, max(0, spent / limit * 100)),
            resetDate: nil
        )
    }
}

enum APIAccountStatus: Equatable {
    case noKey
    case spend(APISpendSummary)
    case invalidKey(detail: String?)
    case rateLimited
    case unavailable
}

struct APIAccountSnapshot: Identifiable, Equatable {
    var id: ProviderID { provider }

    let provider: ProviderID
    let status: APIAccountStatus
    let fetchedAt: Date?

    static func noKey(provider: ProviderID) -> APIAccountSnapshot {
        APIAccountSnapshot(provider: provider, status: .noKey, fetchedAt: nil)
    }
}

enum APISpendRetryPolicy {
    static let minimumFetchInterval: TimeInterval = 5 * 60
    static let rateLimitRetryInterval: TimeInterval = 15 * 60
    static let transientRetryInterval: TimeInterval = 5 * 60
    static let unauthorizedRetryInterval: TimeInterval = 15 * 60
    static let maximumCachedSpendAge: TimeInterval = 24 * 60 * 60

    static func canUseCache(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) <= maximumCachedSpendAge
    }
}

enum OpenAILegacyRetryPolicy {
    static let maximumAutomaticFailures = 2

    static func isAdminKey(_ apiKey: String) -> Bool {
        apiKey.hasPrefix("sk-admin-")
    }

    static func shouldProbe(apiKey: String, failureCount: Int, force: Bool) -> Bool {
        guard isAdminKey(apiKey) == false else { return false }
        return force || failureCount < maximumAutomaticFailures
    }
}
