import Foundation

enum LocalPaths {
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexSessions: URL {
        homeDirectory.appendingPathComponent(".codex/sessions")
    }

    static var codexStateDatabase: URL {
        homeDirectory.appendingPathComponent(".codex/state_5.sqlite")
    }

    static var claudeProjects: URL {
        homeDirectory.appendingPathComponent(".claude/projects")
    }

    static var codexAuthFile: URL {
        homeDirectory.appendingPathComponent(".codex/auth.json")
    }
}

enum DateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

enum Formatters {
    static func resetDetail(for date: Date?, style: ResetStyle = .relative) -> String {
        guard let date else { return "Reset unavailable" }

        switch style {
        case .relative:
            let seconds = max(0, Int(date.timeIntervalSinceNow))
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if hours > 0 {
                return "Resets in \(hours) hr \(minutes) min"
            }
            return "Resets in \(minutes) min"
        case .calendar:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return "Resets \(formatter.string(from: date))"
        }
    }

    static func relativeString(for date: Date, relativeTo referenceDate: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func tokenCount(_ value: Int64) -> String {
        let absolute = Double(abs(value))
        let sign = value < 0 ? "-" : ""

        switch absolute {
        case 1_000_000_000...:
            return "\(sign)\(trimmed(absolute / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(trimmed(absolute / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(trimmed(absolute / 1_000))K"
        default:
            return "\(value)"
        }
    }

    static func percentage(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func trimmed(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}

enum ResetStyle {
    case relative
    case calendar
}

extension URL {
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
