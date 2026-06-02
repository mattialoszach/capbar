import Darwin
import Foundation

struct ClaudeUsageReader {
    private let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let oauthBetaHeader = "oauth-2025-04-20"
    private let keychainServiceName = "Claude Code-credentials"

    func read() async -> ProviderSnapshot {
        let status = readAuthStatus()
        let credentials = readOAuthCredentials()
        let usage = await readOAuthUsage(credentials: credentials)
        let account = ProviderAccount(
            isLoggedIn: status?.loggedIn == true || usage != nil || credentials != nil,
            email: status?.email,
            detail: accountDetail(status: status, credentials: credentials)
        )

        if let usage {
            return ProviderSnapshot(
                provider: .claude,
                account: account,
                current: metric(
                    title: "Current session",
                    fallbackDetail: "5 hour usage limit",
                    window: usage.fiveHour,
                    resetStyle: .relative
                ),
                weekly: metric(
                    title: "Weekly limit",
                    fallbackDetail: "All models",
                    window: usage.sevenDay,
                    resetStyle: .calendar
                ),
                sourceDescription: "Claude OAuth usage",
                refreshedAt: Date()
            )
        }

        let unavailableDetail = account.isLoggedIn ? "OAuth usage unavailable" : "Login required"
        let current = LimitMetric(
            title: "Current session",
            detail: unavailableDetail,
            usedPercent: nil,
            resetDate: nil
        )
        let weekly = LimitMetric(
            title: "Weekly limit",
            detail: unavailableDetail,
            usedPercent: nil,
            resetDate: nil
        )

        return ProviderSnapshot(
            provider: .claude,
            account: account,
            current: current,
            weekly: weekly,
            sourceDescription: account.isLoggedIn ? "Claude Code account" : "Not logged in",
            refreshedAt: Date()
        )
    }

    private func metric(title: String, fallbackDetail: String, window: ClaudeOAuthUsageWindow?, resetStyle: ResetStyle) -> LimitMetric? {
        guard let window else { return nil }

        let resetDate = window.resetDate
        let detail = resetDate.map { Formatters.resetDetail(for: $0, style: resetStyle) } ?? fallbackDetail
        return LimitMetric(
            title: title,
            detail: detail,
            usedPercent: window.utilization.map { min(100, max(0, $0)) },
            resetDate: resetDate
        )
    }

    private func accountDetail(status: ClaudeAuthStatus?, credentials: ClaudeOAuthCredentials?) -> String? {
        if let subscriptionType = status?.subscriptionType ?? credentials?.subscriptionType {
            return "\(subscriptionType.capitalized) plan"
        }

        if let rateLimitTier = credentials?.rateLimitTier {
            return rateLimitTier.replacingOccurrences(of: "_", with: " ")
        }

        return status?.authMethod
    }

    private func readAuthStatus() -> ClaudeAuthStatus? {
        guard let data = processOutput(
            executablePath: "/usr/bin/env",
            arguments: ["claude", "auth", "status", "--json"],
            timeout: 5
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data)
    }

    private func readOAuthCredentials() -> ClaudeOAuthCredentials? {
        for candidate in credentialFileCandidates {
            if let credentials = readCredentialsFile(at: candidate) {
                return credentials
            }
        }

        return readKeychainCredentials()
    }

    private var credentialFileCandidates: [URL] {
        [
            LocalPaths.claudeCredentialsFile
        ]
    }

    private func readCredentialsFile(at url: URL) -> ClaudeOAuthCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeCredentials(from: data)
    }

    private func readKeychainCredentials() -> ClaudeOAuthCredentials? {
        guard let data = processOutput(
            executablePath: "/usr/bin/security",
            arguments: ["find-generic-password", "-w", "-s", keychainServiceName],
            timeout: 5
        ) else {
            return nil
        }

        return decodeCredentials(from: data)
    }

    private func decodeCredentials(from data: Data) -> ClaudeOAuthCredentials? {
        guard let document = try? JSONDecoder().decode(ClaudeCredentialsDocument.self, from: data),
              let credentials = document.credentials,
              credentials.accessToken.isEmpty == false else {
            return nil
        }

        return credentials
    }

    private func readOAuthUsage(credentials: ClaudeOAuthCredentials?) async -> ClaudeOAuthUsage? {
        guard let accessToken = credentials?.accessToken else { return nil }

        for attempt in 0..<3 {
            var request = URLRequest(url: oauthUsageURL, timeoutInterval: 8)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return nil }
                guard httpResponse.statusCode == 200 else {
                    if isTransientOAuthStatus(httpResponse.statusCode), attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                        continue
                    }
                    return nil
                }

                return try JSONDecoder().decode(ClaudeOAuthUsage.self, from: data)
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                    continue
                }
                return nil
            }
        }

        return nil
    }

    private func isTransientOAuthStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504 || statusCode == 529
    }

    private func processOutput(executablePath: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 1)
            }
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let email: String?
    let subscriptionType: String?
}

private struct ClaudeOAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?
}

private struct ClaudeCredentialsDocument: Decodable {
    let credentials: ClaudeOAuthCredentials?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.decodeIfPresent(ClaudeOAuthBlock.self, forKey: .claudeAiOauth)
            ?? container.decodeIfPresent(ClaudeOAuthBlock.self, forKey: .claudeAiOauthSnake)
            ?? container.decodeIfPresent(ClaudeOAuthBlock.self, forKey: .oauth)
        let root = ClaudeOAuthBlock(
            accessToken: try container.decodeIfPresent(String.self, forKey: .accessToken)
                ?? container.decodeIfPresent(String.self, forKey: .accessTokenSnake),
            refreshToken: try container.decodeIfPresent(String.self, forKey: .refreshToken)
                ?? container.decodeIfPresent(String.self, forKey: .refreshTokenSnake),
            subscriptionType: try container.decodeIfPresent(String.self, forKey: .subscriptionType)
                ?? container.decodeIfPresent(String.self, forKey: .subscriptionTypeSnake),
            rateLimitTier: try container.decodeIfPresent(String.self, forKey: .rateLimitTier)
                ?? container.decodeIfPresent(String.self, forKey: .rateLimitTierSnake)
        )
        let block = nested ?? root

        if let accessToken = block.accessToken {
            credentials = ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: block.refreshToken,
                subscriptionType: block.subscriptionType,
                rateLimitTier: block.rateLimitTier
            )
        } else {
            credentials = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case claudeAiOauth
        case claudeAiOauthSnake = "claude_ai_oauth"
        case oauth
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case subscriptionType
        case subscriptionTypeSnake = "subscription_type"
        case rateLimitTier
        case rateLimitTierSnake = "rate_limit_tier"
    }
}

private struct ClaudeOAuthBlock: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?

    init(accessToken: String?, refreshToken: String?, subscriptionType: String?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decodeIfPresent(String.self, forKey: .accessTokenSnake)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        subscriptionType = try container.decodeIfPresent(String.self, forKey: .subscriptionType)
            ?? container.decodeIfPresent(String.self, forKey: .subscriptionTypeSnake)
        rateLimitTier = try container.decodeIfPresent(String.self, forKey: .rateLimitTier)
            ?? container.decodeIfPresent(String.self, forKey: .rateLimitTierSnake)
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case subscriptionType
        case subscriptionTypeSnake = "subscription_type"
        case rateLimitTier
        case rateLimitTierSnake = "rate_limit_tier"
    }
}

private struct ClaudeOAuthUsage: Decodable {
    let fiveHour: ClaudeOAuthUsageWindow?
    let sevenDay: ClaudeOAuthUsageWindow?
    let sevenDaySonnet: ClaudeOAuthUsageWindow?
    let sevenDayOpus: ClaudeOAuthUsageWindow?
    let extraUsage: ClaudeExtraUsage?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

private struct ClaudeOAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    var resetDate: Date? {
        DateParser.parse(resetsAt)
    }

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ClaudeExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}
