import Foundation

struct CodexUsageReader {
    func read() -> ProviderSnapshot {
        let account = ProviderAccount(
            isLoggedIn: LocalPaths.codexAuthFile.fileExists,
            email: nil,
            detail: "CLI account"
        )

        guard LocalPaths.codexSessions.fileExists else {
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
            at: LocalPaths.codexSessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        var latest: (date: Date, limits: CodexRateLimits)?

        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }

            let data = handle.readDataToEndOfFile()
            guard let contents = String(data: data, encoding: .utf8) else { continue }

            for line in contents.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let event = try? decoder.decode(CodexLimitEvent.self, from: lineData),
                      let limits = event.payload?.rateLimits,
                      let timestamp = DateParser.parse(event.timestamp) else {
                    continue
                }

                if latest == nil || timestamp > latest!.date {
                    latest = (timestamp, limits)
                }
            }
        }

        return latest?.limits
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
