import Darwin
import CryptoKit
import Foundation

struct ClaudeUsageReader {
    private static let authStatusCache = ClaudeAuthStatusCache()
    private static let credentialsCache = ClaudeCredentialsCache()
    private let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let oauthBetaHeader = "oauth-2025-04-20"
    static func keychainServiceName(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = "Claude Code-credentials"
        // Claude Code namespaces secure storage when a configuration directory
        // is set. The explicit secure-storage override can opt back into the
        // default Keychain by being present but empty.
        let path = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"] ?? environment["CLAUDE_CONFIG_DIR"]
        guard let path, !path.isEmpty else { return base }
        let digest = SHA256.hash(data: Data(path.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(digest.prefix(8))"
    }
    private let cacheURL: URL
    private let credentialsLoader: (@Sendable () -> ClaudeOAuthCredentials?)?
    private let usageLoader: (@Sendable (ClaudeOAuthCredentials) async -> ClaudeUsageFetchResult)?

    init(
        cacheURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapBar/claude-usage.json"),
        credentialsLoader: (@Sendable () -> ClaudeOAuthCredentials?)? = nil,
        usageLoader: (@Sendable (ClaudeOAuthCredentials) async -> ClaudeUsageFetchResult)? = nil
    ) {
        self.cacheURL = cacheURL
        self.credentialsLoader = credentialsLoader
        self.usageLoader = usageLoader
    }

    func read(force: Bool = false) async -> ProviderSnapshot {
        let now = Date()
        let credentials: ClaudeOAuthCredentials?
        if let credentialsLoader {
            credentials = credentialsLoader()
        } else {
            credentials = Self.credentialsCache.value(now: now, force: force, loader: readOAuthCredentials)
        }
        // Reading auth status starts the full Claude CLI. OAuth credentials already
        // contain everything needed for normal usage refreshes, so only pay that
        // startup cost when credentials are unavailable.
        let status = credentials == nil && credentialsLoader == nil
            ? Self.authStatusCache.value(now: now, force: force, loader: readAuthStatus)
            : nil
        let storedState = readCacheState()
        let tokenFingerprint = credentials.map { fingerprint(for: $0.accessToken) }
        // Never reuse usage or retry deadlines from a different login, including
        // legacy caches without an identity and logout (no current token).
        let cachedState = tokenFingerprint != nil && storedState?.tokenFingerprint == tokenFingerprint
            ? storedState : nil
        if storedState != nil, cachedState == nil {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        let credentialsExpired = credentials?.expiresAt.map { $0 <= now } ?? false
        // Manual refresh may bypass a successful-response cooldown, but never
        // an active rate-limit backoff. Automatic refresh follows the app timer
        // down to its shortest supported interval (30 seconds).
        let mayBypassCooldown = force && (cachedState?.rateLimitFailureCount ?? 0) == 0
        let canFetch = credentials != nil
            && (mayBypassCooldown || cachedState?.nextFetchAt.map { $0 <= now } ?? true)
        let fetchResult: ClaudeUsageFetchResult
        if credentialsExpired {
            fetchResult = .unauthorized
        } else if canFetch, let credentials {
            if let usageLoader {
                fetchResult = await usageLoader(credentials)
            } else {
                fetchResult = await readOAuthUsage(credentials: credentials)
            }
        } else {
            fetchResult = .deferred
        }
        let account = ProviderAccount(
            isLoggedIn: status?.loggedIn == true || credentials != nil,
            email: status?.email,
            detail: accountDetail(status: status, credentials: credentials)
        )

        switch fetchResult {
        case let .success(usage):
            writeCacheState(
                ClaudeUsageCacheState(
                    usage: usage,
                    fetchedAt: now,
                    nextFetchAt: now.addingTimeInterval(ClaudeUsageRetryPolicy.minimumFetchInterval),
                    rateLimitFailureCount: 0,
                    tokenFingerprint: tokenFingerprint
                )
            )
            return snapshot(usage: usage, account: account, sourceDescription: "Claude OAuth usage", refreshedAt: now)
        case let .rateLimited(retryAfter):
            let failureCount = (cachedState?.rateLimitFailureCount ?? 0) + 1
            let delay = ClaudeUsageRetryPolicy.rateLimitDelay(
                failureCount: failureCount,
                retryAfter: retryAfter
            )
            writeCacheState(
                ClaudeUsageCacheState(
                    usage: cachedState?.usage,
                    fetchedAt: cachedState?.fetchedAt,
                    nextFetchAt: now.addingTimeInterval(delay),
                    rateLimitFailureCount: failureCount,
                    tokenFingerprint: tokenFingerprint
                )
            )
        case .unauthorized:
            writeCacheState(
                ClaudeUsageCacheState(
                    usage: cachedState?.usage,
                    fetchedAt: cachedState?.fetchedAt,
                    nextFetchAt: now.addingTimeInterval(ClaudeUsageRetryPolicy.authenticationRetryInterval),
                    rateLimitFailureCount: 0,
                    tokenFingerprint: tokenFingerprint
                )
            )
        case .unavailable:
            writeCacheState(
                ClaudeUsageCacheState(
                    usage: cachedState?.usage,
                    fetchedAt: cachedState?.fetchedAt,
                    nextFetchAt: now.addingTimeInterval(ClaudeUsageRetryPolicy.transientRetryInterval),
                    rateLimitFailureCount: 0,
                    tokenFingerprint: tokenFingerprint
                )
            )
        case .deferred:
            break
        }

        if let usage = cachedState?.usage,
           let fetchedAt = cachedState?.fetchedAt,
           ClaudeUsageRetryPolicy.canUseCache(fetchedAt: fetchedAt, now: now) {
            let age = Formatters.relativeString(for: fetchedAt, relativeTo: now)
            return snapshot(
                usage: usage,
                account: account,
                sourceDescription: "Cached Claude usage - updated \(age)",
                refreshedAt: fetchedAt
            )
        }

        let unavailableDetail: String
        switch fetchResult {
        case .rateLimited:
            unavailableDetail = "Usage temporarily rate limited"
        case .unauthorized:
            unavailableDetail = "Open Claude to refresh login"
        case .deferred where account.isLoggedIn:
            unavailableDetail = "Usage refresh pending"
        default:
            unavailableDetail = account.isLoggedIn ? "OAuth usage unavailable" : "Login required"
        }
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

    private func snapshot(
        usage: ClaudeOAuthUsage,
        account: ProviderAccount,
        sourceDescription: String,
        refreshedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
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
            sourceDescription: sourceDescription,
            refreshedAt: refreshedAt
        )
    }

    private func metric(title: String, fallbackDetail: String, window: ClaudeOAuthUsageWindow?, resetStyle: ResetStyle) -> LimitMetric? {
        guard let window else { return nil }

        let resetDate = window.resetDate
        if let resetDate, resetDate <= Date() {
            return LimitMetric(
                title: title,
                detail: "Reset elapsed",
                usedPercent: 0,
                resetDate: nil
            )
        }

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
        for executablePath in claudeExecutableCandidates {
            let arguments = executablePath == "/usr/bin/env"
                ? ["claude", "auth", "status", "--json"]
                : ["auth", "status", "--json"]
            guard let data = processOutput(
                executablePath: executablePath,
                arguments: arguments,
                timeout: 5,
                acceptedExitCodes: [0, 1]
            ) else {
                continue
            }

            if let status = try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data) {
                return status
            }
        }

        return nil
    }

    private var claudeExecutableCandidates: [String] {
        [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/local/claude").path,
            "/usr/bin/env"
        ]
    }

    private func readOAuthCredentials() -> ClaudeOAuthCredentials? {
        var expiredCredentials: ClaudeOAuthCredentials?
        for candidate in credentialFileCandidates {
            if let credentials = readCredentialsFile(at: candidate) {
                if credentials.expiresAt.map({ $0 <= Date() }) != true { return credentials }
                expiredCredentials = credentials
            }
        }

        return readKeychainCredentials() ?? expiredCredentials
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
            arguments: ["find-generic-password", "-w", "-s", Self.keychainServiceName()],
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

    private func readOAuthUsage(credentials: ClaudeOAuthCredentials?) async -> ClaudeUsageFetchResult {
        guard let credentials else { return .unavailable }
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
            return .unauthorized
        }

        for attempt in 0..<3 {
            var request = URLRequest(url: oauthUsageURL, timeoutInterval: 8)
            request.httpMethod = "GET"
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return .unavailable }
                if httpResponse.statusCode == 429 {
                    return .rateLimited(retryAfter: retryAfter(from: httpResponse))
                }
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    return .unauthorized
                }
                guard httpResponse.statusCode == 200 else {
                    if isTransientOAuthStatus(httpResponse.statusCode), attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                        continue
                    }
                    return .unavailable
                }

                guard let usage = try? JSONDecoder().decode(ClaudeOAuthUsage.self, from: data) else {
                    return .unavailable
                }
                return .success(usage)
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                    continue
                }
                return .unavailable
            }
        }

        return .unavailable
    }

    private func isTransientOAuthStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504 || statusCode == 529
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        ClaudeUsageRetryPolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: Date())
    }

    private func fingerprint(for accessToken: String) -> String {
        SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func readCacheState() -> ClaudeUsageCacheState? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(ClaudeUsageCacheState.self, from: data)
    }

    private func writeCacheState(_ state: ClaudeUsageCacheState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func processOutput(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        acceptedExitCodes: Set<Int32> = [0]
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

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

        guard acceptedExitCodes.contains(process.terminationStatus) else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

struct ClaudeUsageRetryPolicy {
    static let authStatusRefreshInterval: TimeInterval = 5 * 60
    static let minimumFetchInterval: TimeInterval = 30
    static let transientRetryInterval: TimeInterval = 5 * 60
    static let authenticationRetryInterval: TimeInterval = 60
    static let maximumCachedUsageAge: TimeInterval = 24 * 60 * 60

    static func rateLimitDelay(failureCount: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let exponent = min(3, max(0, failureCount - 1))
        let backoff = 15 * 60 * pow(2, Double(exponent))
        return max(backoff, retryAfter ?? 0)
    }

    static func canUseCache(fetchedAt: Date, now: Date) -> Bool {
        (0...maximumCachedUsageAge).contains(now.timeIntervalSince(fetchedAt))
    }

    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds > 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value), date > now else { return nil }
        return date.timeIntervalSince(now)
    }
}

enum ClaudeUsageFetchResult: Sendable {
    case success(ClaudeOAuthUsage)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case unavailable
    case deferred
}

private struct ClaudeUsageCacheState: Codable {
    let usage: ClaudeOAuthUsage?
    let fetchedAt: Date?
    let nextFetchAt: Date?
    let rateLimitFailureCount: Int
    let tokenFingerprint: String?
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let email: String?
    let subscriptionType: String?
}

private final class ClaudeAuthStatusCache: @unchecked Sendable {
    private let lock = NSLock()
    private var status: ClaudeAuthStatus?
    private var checkedAt: Date?

    func value(
        now: Date,
        force: Bool,
        loader: () -> ClaudeAuthStatus?
    ) -> ClaudeAuthStatus? {
        lock.lock()
        defer { lock.unlock() }

        if force == false,
           let checkedAt,
           now.timeIntervalSince(checkedAt) < ClaudeUsageRetryPolicy.authStatusRefreshInterval {
            return status
        }

        let loadedStatus = loader()
        status = loadedStatus
        checkedAt = now
        return loadedStatus
    }
}

private final class ClaudeCredentialsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: ClaudeOAuthCredentials?
    private var checkedAt: Date?
    private var fileSignature: String?

    func value(
        now: Date,
        force: Bool,
        loader: () -> ClaudeOAuthCredentials?
    ) -> ClaudeOAuthCredentials? {
        lock.lock()
        defer { lock.unlock() }

        let file = LocalPaths.claudeCredentialsFile
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let signature = "\(file.path):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0):\(ClaudeUsageReader.keychainServiceName())"
        let interval = credentials?.expiresAt.map { $0 <= now } == true
            ? ClaudeUsageRetryPolicy.authenticationRetryInterval
            : ClaudeUsageRetryPolicy.authStatusRefreshInterval
        if force == false, fileSignature == signature,
           let checkedAt,
           now.timeIntervalSince(checkedAt) < interval {
            return credentials
        }

        let loadedCredentials = loader()
        credentials = loadedCredentials
        checkedAt = now
        fileSignature = signature
        return loadedCredentials
    }
}

struct ClaudeOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?
    let expiresAt: Date?
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
                ?? container.decodeIfPresent(String.self, forKey: .rateLimitTierSnake),
            expiresAt: Self.decodeExpiration(from: container)
        )
        let block = nested ?? root

        if let accessToken = block.accessToken {
            credentials = ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: block.refreshToken,
                subscriptionType: block.subscriptionType,
                rateLimitTier: block.rateLimitTier,
                expiresAt: block.expiresAt
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
        case expiresAt
        case expiresAtSnake = "expires_at"
    }

    private static func decodeExpiration(from container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        let timestamp = (try? container.decodeIfPresent(Double.self, forKey: .expiresAt))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .expiresAtSnake))
        guard let timestamp else { return nil }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }
}

private struct ClaudeOAuthBlock: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?
    let expiresAt: Date?

    init(accessToken: String?, refreshToken: String?, subscriptionType: String?, rateLimitTier: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.expiresAt = expiresAt
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
        let timestamp = try container.decodeIfPresent(Double.self, forKey: .expiresAt)
            ?? container.decodeIfPresent(Double.self, forKey: .expiresAtSnake)
        if let timestamp {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else {
            expiresAt = nil
        }
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
        case expiresAt
        case expiresAtSnake = "expires_at"
    }
}

struct ClaudeOAuthUsage: Codable, Sendable {
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

struct ClaudeOAuthUsageWindow: Codable, Sendable {
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

struct ClaudeExtraUsage: Codable, Sendable {
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
