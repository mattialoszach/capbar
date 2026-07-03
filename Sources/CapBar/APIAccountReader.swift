import CryptoKit
import Foundation

struct APIAccountReader {
    let provider: ProviderID

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapBar/api-spend-\(provider.rawValue).json")
    }

    func read(force: Bool = false) async -> APIAccountSnapshot {
        let now = Date()
        if let summary = Self.mockSpendSummary(environment: ProcessInfo.processInfo.environment) {
            return APIAccountSnapshot(provider: provider, status: .spend(summary), fetchedAt: now)
        }

        guard let apiKey = APIKeyStore.key(for: provider) else {
            clearCache()
            return .noKey(provider: provider)
        }

        let keyFingerprint = fingerprint(for: apiKey)
        let keyChanged = readCacheState().map { $0.keyFingerprint != keyFingerprint } ?? false
        let cached = keyChanged ? nil : readCacheState()
        let retryUnavailableWithoutSummary = cached?.summary == nil && cached?.lastFailure == .unavailable
        let canFetch = force || keyChanged || retryUnavailableWithoutSummary || (cached?.nextFetchAt.map { $0 <= now } ?? true)

        if canFetch == false, let cached {
            return snapshot(from: cached, now: now)
        }

        switch await fetchSpend(apiKey: apiKey, now: now) {
        case let .success(summary):
            writeCacheState(
                APISpendCacheState(
                    summary: summary,
                    fetchedAt: now,
                    nextFetchAt: now.addingTimeInterval(APISpendRetryPolicy.minimumFetchInterval),
                    keyFingerprint: keyFingerprint,
                    lastFailure: nil,
                    lastFailureDetail: nil
                )
            )
            return APIAccountSnapshot(provider: provider, status: .spend(summary), fetchedAt: now)
        case let .unauthorized(message):
            writeCacheState(
                APISpendCacheState(
                    summary: nil,
                    fetchedAt: nil,
                    nextFetchAt: now.addingTimeInterval(APISpendRetryPolicy.unauthorizedRetryInterval),
                    keyFingerprint: keyFingerprint,
                    lastFailure: .unauthorized,
                    lastFailureDetail: message
                )
            )
            return APIAccountSnapshot(provider: provider, status: .invalidKey(detail: message), fetchedAt: nil)
        case .rateLimited:
            writeCacheState(
                APISpendCacheState(
                    summary: cached?.summary,
                    fetchedAt: cached?.fetchedAt,
                    nextFetchAt: now.addingTimeInterval(APISpendRetryPolicy.rateLimitRetryInterval),
                    keyFingerprint: keyFingerprint,
                    lastFailure: .rateLimited,
                    lastFailureDetail: nil
                )
            )
            return fallbackSnapshot(cached: cached, now: now, status: .rateLimited)
        case .unavailable:
            writeCacheState(
                APISpendCacheState(
                    summary: cached?.summary,
                    fetchedAt: cached?.fetchedAt,
                    nextFetchAt: now.addingTimeInterval(APISpendRetryPolicy.transientRetryInterval),
                    keyFingerprint: keyFingerprint,
                    lastFailure: .unavailable,
                    lastFailureDetail: nil
                )
            )
            return fallbackSnapshot(cached: cached, now: now, status: .unavailable)
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    static func startOfMonthUTC(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func startOfNextDayUTC(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
    }

    static func mockSpendSummary(environment: [String: String]) -> APISpendSummary? {
        guard let monthToDateUSD = mockUSDValue("CAPBAR_MOCK_API_MONTH_USD", in: environment) else {
            return nil
        }
        return APISpendSummary(
            monthToDateUSD: monthToDateUSD,
            todayUSD: mockUSDValue("CAPBAR_MOCK_API_TODAY_USD", in: environment) ?? monthToDateUSD
        )
    }

    private func snapshot(from state: APISpendCacheState, now: Date) -> APIAccountSnapshot {
        if let summary = state.summary,
           let fetchedAt = state.fetchedAt,
           APISpendRetryPolicy.canUseCache(fetchedAt: fetchedAt, now: now) {
            return APIAccountSnapshot(provider: provider, status: .spend(summary), fetchedAt: fetchedAt)
        }

        switch state.lastFailure {
        case .unauthorized:
            return APIAccountSnapshot(provider: provider, status: .invalidKey(detail: state.lastFailureDetail), fetchedAt: nil)
        case .rateLimited:
            return APIAccountSnapshot(provider: provider, status: .rateLimited, fetchedAt: nil)
        default:
            return APIAccountSnapshot(provider: provider, status: .unavailable, fetchedAt: nil)
        }
    }

    private func fallbackSnapshot(cached: APISpendCacheState?, now: Date, status: APIAccountStatus) -> APIAccountSnapshot {
        if let summary = cached?.summary,
           let fetchedAt = cached?.fetchedAt,
           APISpendRetryPolicy.canUseCache(fetchedAt: fetchedAt, now: now) {
            return APIAccountSnapshot(provider: provider, status: .spend(summary), fetchedAt: fetchedAt)
        }
        return APIAccountSnapshot(provider: provider, status: status, fetchedAt: nil)
    }

    private func fetchSpend(apiKey: String, now: Date) async -> APISpendFetchResult {
        switch provider {
        case .claude:
            switch await fetchCostTotals(apiKey: apiKey, now: now) {
            case let .success(month, today):
                return .success(APISpendSummary(monthToDateUSD: month, todayUSD: today))
            case let .unauthorized(message):
                return .unauthorized(message: message)
            case .rateLimited:
                return .rateLimited
            case .unavailable:
                return .unavailable
            }
        case .codex:
            // The org costs endpoint needs an admin key; the legacy credit_grants
            // and billing/subscription endpoints accept some regular user keys.
            // Try all, show what works.
            let costs = await fetchCostTotals(apiKey: apiKey, now: now)
            let credits = await fetchOpenAICredits(apiKey: apiKey)
            let monthlyLimit = await fetchOpenAIMonthlyLimit(apiKey: apiKey)

            if case let .success(month, today) = costs {
                return .success(
                    APISpendSummary(
                        monthToDateUSD: month,
                        todayUSD: today,
                        creditsRemainingUSD: credits?.remaining,
                        creditsGrantedUSD: credits?.granted,
                        monthlyLimitUSD: monthlyLimit
                    )
                )
            }
            if let credits {
                return .success(
                    APISpendSummary(
                        monthToDateUSD: nil,
                        todayUSD: nil,
                        creditsRemainingUSD: credits.remaining,
                        creditsGrantedUSD: credits.granted,
                        monthlyLimitUSD: monthlyLimit
                    )
                )
            }
            switch costs {
            case .success:
                return .unavailable
            case let .unauthorized(message):
                return .unauthorized(message: message)
            case .rateLimited:
                return .rateLimited
            case .unavailable:
                return .unavailable
            }
        }
    }

    private func fetchCostTotals(apiKey: String, now: Date) async -> CostFetchResult {
        let monthStart = Self.startOfMonthUTC(for: now)
        let end = Self.startOfNextDayUTC(for: now)
        var monthTotal = 0.0
        var today: Double?
        var page: String?

        for _ in 0..<8 {
            guard let request = makeRequest(apiKey: apiKey, start: monthStart, end: end, page: page) else {
                return .unavailable
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return .unavailable }
                switch httpResponse.statusCode {
                case 200:
                    break
                case 401, 403:
                    return .unauthorized(message: Self.errorMessage(from: data))
                case 429:
                    return .rateLimited
                default:
                    return .unavailable
                }

                guard let parsed = parsePage(data, now: now) else { return .unavailable }
                monthTotal += parsed.totalUSD
                if let bucketToday = parsed.todayUSD {
                    today = (today ?? 0) + bucketToday
                }

                guard let nextPage = parsed.nextPage else {
                    return .success(monthUSD: monthTotal, todayUSD: today)
                }
                page = nextPage
            } catch {
                return .unavailable
            }
        }

        return .unavailable
    }

    private func fetchOpenAICredits(apiKey: String) async -> APICreditGrants? {
        guard let url = URL(string: "https://api.openai.com/v1/dashboard/billing/credit_grants") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        return APISpendParser.openAICredits(from: data)
    }

    private func fetchOpenAIMonthlyLimit(apiKey: String) async -> Double? {
        guard let url = URL(string: "https://api.openai.com/v1/dashboard/billing/subscription") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        return APISpendParser.openAIMonthlyLimit(from: data)
    }

    private func makeRequest(apiKey: String, start: Date, end: Date, page: String?) -> URLRequest? {
        switch provider {
        case .claude:
            var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")
            var items = [
                URLQueryItem(name: "starting_at", value: ISO8601DateFormatter().string(from: start)),
                URLQueryItem(name: "ending_at", value: ISO8601DateFormatter().string(from: end)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31")
            ]
            if let page {
                items.append(URLQueryItem(name: "page", value: page))
            }
            components?.queryItems = items
            guard let url = components?.url else { return nil }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        case .codex:
            var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")
            var items = [
                URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970.rounded(.down)))),
                URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970.rounded(.up)))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
                URLQueryItem(name: "group_by", value: "line_item")
            ]
            if let page {
                items.append(URLQueryItem(name: "page", value: page))
            }
            components?.queryItems = items
            guard let url = components?.url else { return nil }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
    }

    private func parsePage(_ data: Data, now: Date) -> APISpendPage? {
        switch provider {
        case .claude:
            APISpendParser.anthropicPage(from: data, now: now)
        case .codex:
            APISpendParser.openAIPage(from: data, now: now)
        }
    }

    // Anthropic and OpenAI use the same {"error": {"message": ...}} envelope.
    static func errorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable {
                let message: String?
            }
            let error: Inner?
        }

        guard let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message,
              message.isEmpty == false else {
            return nil
        }
        return message
    }

    private func fingerprint(for apiKey: String) -> String {
        SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func mockUSDValue(_ key: String, in environment: [String: String]) -> Double? {
        guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }
        let normalized = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private func readCacheState() -> APISpendCacheState? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        guard let state = try? JSONDecoder().decode(APISpendCacheState.self, from: data),
              state.schemaVersion == APISpendCacheState.currentSchemaVersion else {
            return nil
        }
        return state
    }

    private func writeCacheState(_ state: APISpendCacheState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}

struct APISpendPage: Equatable {
    let totalUSD: Double
    let todayUSD: Double?
    let nextPage: String?
}

struct APICreditGrants: Equatable {
    let remaining: Double
    let granted: Double?
}

private enum CostFetchResult {
    case success(monthUSD: Double, todayUSD: Double?)
    case unauthorized(message: String?)
    case rateLimited
    case unavailable
}

enum APISpendParser {
    static func anthropicPage(from data: Data, now: Date) -> APISpendPage? {
        guard let report = try? JSONDecoder().decode(AnthropicCostReport.self, from: data) else { return nil }

        var total = 0.0
        var today: Double?
        for bucket in report.data {
            // Anthropic reports amounts as decimal strings in cents.
            let bucketTotal = bucket.results.reduce(0.0) { $0 + ((Double($1.amount) ?? 0) / 100) }
            total += bucketTotal
            if let start = DateParser.parse(bucket.startingAt),
               let end = DateParser.parse(bucket.endingAt),
               start <= now, now < end {
                today = (today ?? 0) + bucketTotal
            }
        }

        return APISpendPage(
            totalUSD: total,
            todayUSD: today,
            nextPage: report.hasMore == true ? report.nextPage : nil
        )
    }

    static func openAICredits(from data: Data) -> APICreditGrants? {
        struct CreditGrants: Decodable {
            let totalGranted: Double?
            let totalAvailable: Double?

            enum CodingKeys: String, CodingKey {
                case totalGranted = "total_granted"
                case totalAvailable = "total_available"
            }
        }

        guard let grants = try? JSONDecoder().decode(CreditGrants.self, from: data),
              let remaining = grants.totalAvailable else {
            return nil
        }
        return APICreditGrants(remaining: remaining, granted: grants.totalGranted)
    }

    static func openAIMonthlyLimit(from data: Data) -> Double? {
        struct Subscription: Decodable {
            let hardLimitUSD: Double?
            let systemHardLimitUSD: Double?

            enum CodingKeys: String, CodingKey {
                case hardLimitUSD = "hard_limit_usd"
                case systemHardLimitUSD = "system_hard_limit_usd"
            }
        }

        guard let subscription = try? JSONDecoder().decode(Subscription.self, from: data) else {
            return nil
        }
        let limit = subscription.hardLimitUSD ?? subscription.systemHardLimitUSD
        guard let limit, limit > 0 else { return nil }
        return limit
    }

    static func openAIPage(from data: Data, now: Date) -> APISpendPage? {
        guard let report = try? JSONDecoder().decode(OpenAICostReport.self, from: data) else { return nil }

        var total = 0.0
        var today: Double?
        for bucket in report.data {
            let bucketTotal = bucket.results.reduce(0.0) { $0 + ($1.amount?.value ?? 0) }
            total += bucketTotal
            if let start = bucket.startTime,
               let end = bucket.endTime {
                let startDate = Date(timeIntervalSince1970: TimeInterval(start))
                let endDate = Date(timeIntervalSince1970: TimeInterval(end))
                if startDate <= now, now < endDate {
                    today = (today ?? 0) + bucketTotal
                }
            }
        }

        return APISpendPage(
            totalUSD: total,
            todayUSD: today,
            nextPage: report.hasMore == true ? report.nextPage : nil
        )
    }
}

private enum APISpendFetchResult {
    case success(APISpendSummary)
    case unauthorized(message: String?)
    case rateLimited
    case unavailable
}

private struct APISpendCacheState: Codable {
    static let currentSchemaVersion = 2

    enum Failure: String, Codable {
        case unauthorized
        case rateLimited
        case unavailable
    }

    let schemaVersion: Int
    let summary: APISpendSummary?
    let fetchedAt: Date?
    let nextFetchAt: Date?
    let keyFingerprint: String?
    let lastFailure: Failure?
    let lastFailureDetail: String?

    init(
        summary: APISpendSummary?,
        fetchedAt: Date?,
        nextFetchAt: Date?,
        keyFingerprint: String?,
        lastFailure: Failure?,
        lastFailureDetail: String?,
        schemaVersion: Int = APISpendCacheState.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.fetchedAt = fetchedAt
        self.nextFetchAt = nextFetchAt
        self.keyFingerprint = keyFingerprint
        self.lastFailure = lastFailure
        self.lastFailureDetail = lastFailureDetail
    }
}

private struct AnthropicCostReport: Decodable {
    let data: [Bucket]
    let hasMore: Bool?
    let nextPage: String?

    struct Bucket: Decodable {
        let startingAt: String?
        let endingAt: String?
        let results: [Result]

        enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct Result: Decodable {
        let amount: String
        let currency: String?
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private struct OpenAICostReport: Decodable {
    let data: [Bucket]
    let hasMore: Bool?
    let nextPage: String?

    struct Bucket: Decodable {
        let startTime: Int?
        let endTime: Int?
        let results: [Result]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    struct Result: Decodable {
        let amount: Amount?
    }

    struct Amount: Decodable {
        let value: Double?
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case value
            case currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decodeIfPresent(Double.self, forKey: .value) {
                value = number
            } else if let raw = try? container.decodeIfPresent(String.self, forKey: .value),
                      let number = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                value = number
            } else {
                value = nil
            }
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
        }
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}
