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

    static var claudeCredentialsFile: URL {
        homeDirectory.appendingPathComponent(".claude/.credentials.json")
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

    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func compactUSD(_ value: Double) -> String {
        let absolute = abs(value)
        guard absolute >= 1_000 else {
            return usd(value)
        }

        let sign = value < 0 ? "-" : ""
        let units: [(divisor: Double, suffix: String)] = [
            (1_000, "k"),
            (1_000_000, "M"),
            (1_000_000_000, "B"),
            (1_000_000_000_000, "T")
        ]
        var unitIndex = units.lastIndex { absolute >= $0.divisor } ?? 0
        var formatted = compactNumber(absolute / units[unitIndex].divisor)

        if formatted.rounded >= 1_000, unitIndex < units.count - 1 {
            unitIndex += 1
            formatted = compactNumber(absolute / units[unitIndex].divisor)
        }

        let number = String(
            format: "%.\(formatted.fractionDigits)f",
            locale: Locale(identifier: "en_US_POSIX"),
            formatted.rounded
        )
        return "\(sign)$\(number)\(units[unitIndex].suffix)"
    }

    static func plainNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted.hasSuffix(".00") ? String(formatted.dropLast(3)) : formatted
    }

    private static func compactNumber(_ value: Double) -> (rounded: Double, fractionDigits: Int) {
        let fractionDigits: Int
        switch value {
        case ..<10:
            fractionDigits = 3
        case ..<100:
            fractionDigits = 2
        default:
            fractionDigits = 1
        }

        let multiplier = pow(10, Double(fractionDigits))
        return ((value * multiplier).rounded() / multiplier, fractionDigits)
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
