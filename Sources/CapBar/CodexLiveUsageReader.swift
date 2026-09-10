import Darwin
import Foundation

/// Uses the CLI's account API so file and Keychain logins follow Codex's own rules.
/// No threads or model turns are started by this client.
actor CodexLiveUsageReader {
    static let shared = CodexLiveUsageReader()

    private let usageLoader: @Sendable () throws -> CodexAccountUsage
    private let fallbackReader: CodexUsageReader

    init(
        usageLoader: @escaping @Sendable () throws -> CodexAccountUsage = { try CodexAppServerClient().read() },
        fallbackReader: CodexUsageReader = CodexUsageReader()
    ) {
        self.usageLoader = usageLoader
        self.fallbackReader = fallbackReader
    }

    func read() -> ProviderSnapshot {
        // UsageStore owns the refresh cadence. Query on every automatic or manual
        // refresh so a separate cache cannot override the selected interval.
        guard let usage = try? usageLoader() else { return fallbackReader.read() }
        return usage.snapshot(refreshedAt: Date())
    }
}

struct CodexAccountUsage: Sendable {
    let account: CodexAccountResponse.Account?
    let limits: CodexRateLimits?

    func snapshot(refreshedAt: Date) -> ProviderSnapshot {
        let providerAccount = ProviderAccount(
            isLoggedIn: account != nil,
            email: account?.email,
            detail: account?.planType.map { "\($0.capitalized) plan" } ?? account?.type
        )
        if let limits {
            return CodexUsageReader.snapshot(
                limits: limits,
                account: providerAccount,
                sourceDescription: "Codex live limits",
                refreshedAt: refreshedAt
            )
        }

        let detail: String
        switch account?.type {
        case nil: detail = "Login required"
        case "chatgpt": detail = "Codex usage unavailable"
        default: detail = "Subscription limits require a ChatGPT login"
        }
        return ProviderSnapshot(
            provider: .codex,
            account: providerAccount,
            current: nil,
            weekly: nil,
            sourceDescription: detail,
            refreshedAt: refreshedAt
        )
    }
}

struct CodexAccountResponse: Decodable, Sendable {
    let account: Account?

    struct Account: Decodable, Sendable {
        let type: String
        let email: String?
        let planType: String?
    }
}

struct CodexRateLimitsResponse: Decodable {
    let rateLimits: CodexRateLimits?
    let rateLimitsByLimitId: [String: CodexRateLimits]?

    var codexLimits: CodexRateLimits? {
        if let limits = rateLimitsByLimitId?["codex"] { return limits }
        // Other metered buckets must never replace the account-wide Codex bars.
        return rateLimits?.isCodexBucket == true ? rateLimits : nil
    }
}

struct CodexAppServerClient {
    var executableURL: URL? = Self.findExecutable()
    var arguments = ["app-server"]
    var timeout: TimeInterval = 10

    func read() throws -> CodexAccountUsage {
        guard let executableURL else { throw CodexRPCError.unavailable }
        let connection = try CodexRPCConnection(executableURL: executableURL, arguments: arguments)
        defer { connection.close() }
        let deadline = Date().addingTimeInterval(timeout)
        try connection.send([
            "id": 0, "method": "initialize",
            "params": ["clientInfo": ["name": "capbar", "title": "CapBar", "version": "0.3.1"]]
        ])
        _ = try connection.receive(id: 0, deadline: deadline)
        try connection.send(["method": "initialized"])
        try connection.send(["id": 1, "method": "account/read", "params": ["refreshToken": false]])
        let account = try JSONDecoder().decode(
            CodexAccountResponse.self,
            from: connection.receive(id: 1, deadline: deadline)
        ).account

        guard account?.type == "chatgpt" else {
            return CodexAccountUsage(account: account, limits: nil)
        }
        try connection.send(["id": 2, "method": "account/rateLimits/read"])
        // A confirmed account with unavailable limits must not inherit another
        // account's historical session usage.
        let response = try? JSONDecoder().decode(
            CodexRateLimitsResponse.self,
            from: connection.receive(id: 2, deadline: deadline)
        )
        return CodexAccountUsage(account: account, limits: response?.codexLimits)
    }

    private static func findExecutable() -> URL? {
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + [LocalPaths.homeDirectory.appendingPathComponent(".local/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin", "/Applications/Codex.app/Contents/Resources"]
        return searchPaths.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private enum CodexRPCError: Error {
    case unavailable
    case timedOut
    case invalidResponse
}

/// Bounded stdio exchange. Drains stdout while the process is alive and discards
/// stderr so a full pipe cannot deadlock a menu-bar refresh.
private final class CodexRPCConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let terminated = DispatchSemaphore(value: 0)
    private var buffer = Data()

    init(executableURL: URL, arguments: [String]) throws {
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = LocalPaths.homeDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [terminated] _ in terminated.signal() }
        try process.run()
        // A CLI that exits between the handshake and a write must not send
        // SIGPIPE to the app itself.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
    }

    func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func receive(id: Int, deadline: Date) throws -> Data {
        while Date() < deadline {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      message["id"] as? Int == id else { continue }
                guard message["error"] == nil, let result = message["result"] else {
                    throw CodexRPCError.invalidResponse
                }
                return try JSONSerialization.data(withJSONObject: result)
            }

            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(max(1, min(200, deadline.timeIntervalSinceNow * 1000)))
            let ready = poll(&descriptor, 1, milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw CodexRPCError.unavailable
            }
            guard ready > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw CodexRPCError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 2 * 1024 * 1024 else { throw CodexRPCError.invalidResponse }
        }
        throw CodexRPCError.timedOut
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            if terminated.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 0.5)
            }
        }
        try? output.fileHandleForReading.close()
    }
}
