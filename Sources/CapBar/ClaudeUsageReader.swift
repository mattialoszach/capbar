import Foundation

struct ClaudeUsageReader {
    func read() -> ProviderSnapshot {
        let status = readAuthStatus()
        let account = ProviderAccount(
            isLoggedIn: status?.loggedIn == true,
            email: status?.email,
            detail: status?.subscriptionType.map { "\($0.capitalized) plan" } ?? status?.authMethod
        )

        let current = LimitMetric(
            title: "5 hour usage limit",
            detail: account.isLoggedIn ? "Limit data not exposed by CLI" : "Login required",
            usedPercent: nil,
            resetDate: nil
        )

        let weekly = LimitMetric(
            title: "Weekly usage limit",
            detail: account.isLoggedIn ? "Limit data not exposed by CLI" : "Login required",
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

    private func readAuthStatus() -> ClaudeAuthStatus? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "auth", "status", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data)
    }
}

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
    let authMethod: String?
    let email: String?
    let subscriptionType: String?
}
