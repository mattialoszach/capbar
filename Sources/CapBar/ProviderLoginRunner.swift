import AppKit
import Foundation

enum ProviderLoginRunner {
    @MainActor
    static func runCLILogin(for provider: ProviderID) {
        let command: String
        switch provider {
        case .codex:
            command = "codex login"
        case .claude:
            command = "claude auth login"
        }

        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    @MainActor
    static func openCredentialPage(for provider: ProviderID) {
        let urlString: String
        switch provider {
        case .codex:
            urlString = "https://platform.openai.com/settings/organization/admin-keys"
        case .claude:
            urlString = "https://console.anthropic.com/settings/organization"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
