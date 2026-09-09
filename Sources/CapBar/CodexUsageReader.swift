import Foundation

struct CodexUsageReader {
    private static let scanCache = CodexSessionScanCache()
    private static let defaultScanByteLimit: UInt64 = 8 * 1024 * 1024
    private static let defaultScanFileLimit = 64

    private let sessionsURL: URL
    private let authURL: URL
    private let scanByteLimit: UInt64
    private let scanFileLimit: Int

    init(
        sessionsURL: URL = LocalPaths.codexSessions,
        authURL: URL = LocalPaths.codexAuthFile,
        scanByteLimit: UInt64 = CodexUsageReader.defaultScanByteLimit,
        scanFileLimit: Int = CodexUsageReader.defaultScanFileLimit
    ) {
        self.sessionsURL = sessionsURL
        self.authURL = authURL
        self.scanByteLimit = scanByteLimit
        self.scanFileLimit = scanFileLimit
    }

    func read() -> ProviderSnapshot {
        let account = ProviderAccount(
            isLoggedIn: authURL.fileExists,
            email: nil,
            detail: "CLI account"
        )

        guard sessionsURL.fileExists else {
            return ProviderSnapshot(
                provider: .codex,
                account: account,
                current: nil,
                weekly: nil,
                sourceDescription: "No Codex sessions found",
                refreshedAt: Date()
            )
        }

        guard let rateLimits = latestRateLimits() else {
            return ProviderSnapshot(
                provider: .codex,
                account: account,
                current: nil,
                weekly: nil,
                sourceDescription: "Run Codex once to refresh limits",
                refreshedAt: Date()
            )
        }

        return Self.snapshot(
            limits: rateLimits,
            account: account,
            sourceDescription: "Local Codex session limits",
            refreshedAt: Date()
        )
    }

    static func snapshot(
        limits: CodexRateLimits,
        account: ProviderAccount,
        sourceDescription: String,
        refreshedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex,
            account: account,
            current: metric(
                title: "Current session",
                fallbackDetail: "5 hour usage limit",
                limit: limits.primary,
                resetStyle: .relative
            ),
            weekly: metric(
                title: "Weekly limit",
                fallbackDetail: "All models",
                limit: limits.secondary,
                resetStyle: .calendar
            ),
            sourceDescription: limits.planType.map { "\($0.capitalized) plan · \(sourceDescription)" } ?? sourceDescription,
            refreshedAt: refreshedAt
        )
    }

    private static func metric(title: String, fallbackDetail: String, limit: CodexRateLimitWindow?, resetStyle: ResetStyle) -> LimitMetric? {
        guard let limit else { return nil }
        let resetDate = limit.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
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
            usedPercent: limit.usedPercent.map { min(100, max(0, $0)) },
            resetDate: resetDate
        )
    }

    private func latestRateLimits() -> CodexRateLimits? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        var latest: (date: Date, limits: CodexRateLimits)?
        var files: [CodexSessionFile] = []

        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true, let modifiedAt = values?.contentModificationDate else { continue }
            files.append(CodexSessionFile(url: file, modifiedAt: modifiedAt, size: UInt64(values?.fileSize ?? 0)))
        }

        files.sort { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.url.path > rhs.url.path
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        if let cached = Self.scanCache.value(
            for: sessionsURL.path,
            files: files,
            byteLimit: scanByteLimit,
            fileLimit: scanFileLimit
        ) {
            return cached.limits
        }

        var remainingScanBytes = scanByteLimit

        for file in files.prefix(max(0, scanFileLimit)) {
            guard remainingScanBytes > 0 else { break }

            // A file cannot contain an event written after its modification date.
            // Once older files predate the best event, they cannot improve it.
            if let latest, file.modifiedAt < latest.date {
                break
            }

            guard let candidate = latestRateLimits(
                in: file.url,
                decoder: decoder,
                remainingScanBytes: &remainingScanBytes
            ) else { continue }
            if latest == nil || candidate.date > latest!.date {
                latest = candidate
            }
        }

        let limits = latest?.limits
        Self.scanCache.store(
            limits,
            for: sessionsURL.path,
            files: files,
            byteLimit: scanByteLimit,
            fileLimit: scanFileLimit
        )
        return limits
    }

    private func latestRateLimits(
        in file: URL,
        decoder: JSONDecoder,
        remainingScanBytes: inout UInt64
    ) -> (date: Date, limits: CodexRateLimits)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let chunkSize: UInt64 = 64 * 1024
        var unreadBytes = fileSize
        var trailingPartialLine = Data()

        while unreadBytes > 0, remainingScanBytes > 0 {
            let bytesToRead = min(chunkSize, unreadBytes, remainingScanBytes)
            unreadBytes -= bytesToRead
            remainingScanBytes -= bytesToRead

            do {
                try handle.seek(toOffset: unreadBytes)
                guard var chunk = try handle.read(upToCount: Int(bytesToRead)) else { return nil }
                chunk.append(trailingPartialLine)

                let lines = chunk.split(separator: 0x0A, omittingEmptySubsequences: false)
                let firstCompleteLine = unreadBytes == 0 ? 0 : 1
                if firstCompleteLine < lines.count {
                    for line in lines[firstCompleteLine...].reversed() where line.isEmpty == false {
                        guard line.range(of: Data("\"rate_limits\"".utf8)) != nil,
                              let event = try? decoder.decode(CodexLimitEvent.self, from: line),
                              let limits = event.payload?.rateLimits,
                              limits.isCodexBucket,
                              limits.primary != nil || limits.secondary != nil,
                              let timestamp = DateParser.parse(event.timestamp) else {
                            continue
                        }
                        return (timestamp, limits)
                    }
                }

                trailingPartialLine = unreadBytes == 0 ? Data() : Data(lines.first ?? Data.SubSequence())
            } catch {
                return nil
            }
        }

        return nil
    }
}

private struct CodexSessionFile: Equatable {
    let url: URL
    let modifiedAt: Date
    let size: UInt64
}

private final class CodexSessionScanCache: @unchecked Sendable {
    struct Value {
        let limits: CodexRateLimits?
    }

    private struct Entry {
        let files: [CodexSessionFile]
        let byteLimit: UInt64
        let fileLimit: Int
        let limits: CodexRateLimits?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(
        for sessionsPath: String,
        files: [CodexSessionFile],
        byteLimit: UInt64,
        fileLimit: Int
    ) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[sessionsPath],
              entry.files == files,
              entry.byteLimit == byteLimit,
              entry.fileLimit == fileLimit else {
            return nil
        }
        return Value(limits: entry.limits)
    }

    func store(
        _ limits: CodexRateLimits?,
        for sessionsPath: String,
        files: [CodexSessionFile],
        byteLimit: UInt64,
        fileLimit: Int
    ) {
        lock.lock()
        entries[sessionsPath] = Entry(
            files: files,
            byteLimit: byteLimit,
            fileLimit: fileLimit,
            limits: limits
        )
        lock.unlock()
    }
}

private struct CodexLimitEvent: Decodable {
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let rateLimits: CodexRateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
    let limitId: String?

    var isCodexBucket: Bool { limitId == nil || limitId == "codex" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondary)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
            ?? container.decodeIfPresent(String.self, forKey: .planTypeCamel)
        limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
            ?? container.decodeIfPresent(String.self, forKey: .limitIdCamel)
    }

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
        case planTypeCamel = "planType"
        case limitId = "limit_id"
        case limitIdCamel = "limitId"
    }
}

struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            ?? container.decodeIfPresent(Double.self, forKey: .usedPercentCamel)
        windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
        resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetsAtCamel)
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
        case usedPercentCamel = "usedPercent"
        case windowDurationMins
        case resetsAtCamel = "resetsAt"
    }
}

func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case (nil, nil): nil
    case let (date?, nil), let (nil, date?): date
    case let (left?, right?): max(left, right)
    }
}
