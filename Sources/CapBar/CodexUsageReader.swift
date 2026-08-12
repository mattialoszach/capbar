import Foundation

struct CodexUsageReader {
    private let sessionsURL: URL
    private let authURL: URL

    init(
        sessionsURL: URL = LocalPaths.codexSessions,
        authURL: URL = LocalPaths.codexAuthFile
    ) {
        self.sessionsURL = sessionsURL
        self.authURL = authURL
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

        return ProviderSnapshot(
            provider: .codex,
            account: account,
            current: metric(
                title: "Current session",
                fallbackDetail: "5 hour usage limit",
                limit: rateLimits.primary,
                resetStyle: .relative
            ),
            weekly: metric(
                title: "Weekly limit",
                fallbackDetail: "All models",
                limit: rateLimits.secondary,
                resetStyle: .calendar
            ),
            sourceDescription: rateLimits.planType.map { "\($0.capitalized) plan" } ?? "Codex limits",
            refreshedAt: Date()
        )
    }

    private func metric(title: String, fallbackDetail: String, limit: CodexRateLimitWindow?, resetStyle: ResetStyle) -> LimitMetric? {
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
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        var latest: (date: Date, limits: CodexRateLimits)?
        var files: [(url: URL, modifiedAt: Date)] = []

        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modifiedAt = values?.contentModificationDate else { continue }
            files.append((file, modifiedAt))
        }

        files.sort { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.url.path > rhs.url.path
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        for file in files {
            // A file cannot contain an event written after its modification date.
            // Once older files predate the best event, they cannot improve it.
            if let latest, file.modifiedAt < latest.date {
                break
            }

            guard let candidate = latestRateLimits(in: file.url, decoder: decoder) else { continue }
            if latest == nil || candidate.date > latest!.date {
                latest = candidate
            }
        }

        return latest?.limits
    }

    private func latestRateLimits(
        in file: URL,
        decoder: JSONDecoder
    ) -> (date: Date, limits: CodexRateLimits)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let chunkSize: UInt64 = 64 * 1024
        var unreadBytes = fileSize
        var trailingPartialLine = Data()

        while unreadBytes > 0 {
            let bytesToRead = min(chunkSize, unreadBytes)
            unreadBytes -= bytesToRead

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

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case (nil, nil): nil
    case let (date?, nil), let (nil, date?): date
    case let (left?, right?): max(left, right)
    }
}
