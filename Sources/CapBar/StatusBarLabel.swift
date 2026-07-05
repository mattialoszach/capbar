import SwiftUI

struct StatusBarLabel: View {
    let subscriptionSnapshot: ProviderSnapshot
    let apiSnapshot: APIAccountSnapshot
    let apiMonthlyBudgetUSD: Double?
    let displayMode: MenuBarDisplayMode
    let usesExpandedLayout: Bool

    var body: some View {
        HStack(spacing: 4) {
            ProviderLogoView(provider: subscriptionSnapshot.provider, size: 16)

            VStack(spacing: 2) {
                switch displayMode {
                case .subscription:
                    StatusLimitStrip(symbol: "clock", metric: subscriptionSnapshot.current)
                    StatusLimitStrip(symbol: "calendar", metric: subscriptionSnapshot.weekly)
                case .api:
                    StatusAPISpendStack(todayText: apiTodayText, monthText: apiMonthText)
                case .apiLimit:
                    StatusAPILimitStrip(metric: apiLimitMetric, amountText: apiLimitAmountText)
                }
            }
        }
        .frame(width: contentWidth, height: 22, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityText)
    }

    private var contentWidth: CGFloat {
        if usesExpandedLayout {
            return 95
        }

        switch displayMode {
        case .subscription, .apiLimit:
            return 95
        case .api:
            return 66
        }
    }

    private var apiSpendSummary: APISpendSummary? {
        guard case let .spend(summary) = apiSnapshot.status else { return nil }
        return summary
    }

    private var apiTodayText: String {
        guard let summary = apiSpendSummary, summary.hasSpend else { return "--" }
        return Formatters.compactUSD(summary.todayUSD ?? 0)
    }

    private var apiMonthText: String {
        guard let summary = apiSpendSummary, summary.hasSpend else { return "--" }
        return Formatters.compactUSD(summary.monthToDateUSD ?? 0)
    }

    private var apiLimitMetric: LimitMetric? {
        apiSpendSummary?.manualAPILimitMetric(monthlyBudgetUSD: apiMonthlyBudgetUSD)
    }

    private var apiLimitAmountText: String {
        guard let summary = apiSpendSummary,
              let spent = summary.monthToDateUSD,
              let limit = apiMonthlyBudgetUSD,
              limit > 0 else {
            return "--/--"
        }

        return "\(Formatters.menuBarUSD(spent))/\(Formatters.menuBarUSD(limit))"
    }

    private var accessibilityText: String {
        switch displayMode {
        case .subscription:
            return "\(subscriptionSnapshot.provider.displayName) usage limits"
        case .api:
            return "\(subscriptionSnapshot.provider.displayName) API spend, today \(apiTodayText), month \(apiMonthText)"
        case .apiLimit:
            return "\(subscriptionSnapshot.provider.displayName) API monthly limit, \(apiLimitMetric?.remainingText ?? "unavailable"), \(apiLimitAmountText)"
        }
    }
}

private struct StatusLimitStrip: View {
    let symbol: String
    let metric: LimitMetric?

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 8)

            TinyProgressBar(fraction: metric?.fractionRemaining ?? 0)
                .frame(width: 34, height: 5)
                .padding(.leading, 3)

            Text(metric?.remainingPercentText ?? "--%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.84))
                .padding(.leading, 4)
                .frame(width: 26, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 75, height: 9, alignment: .leading)
    }
}

private struct StatusAPISpendStack: View {
    let todayText: String
    let monthText: String

    var body: some View {
        VStack(spacing: 2) {
            StatusAPISpendStrip(symbol: "clock", text: todayText)
            StatusAPISpendStrip(symbol: "calendar", text: monthText)
        }
        .frame(width: 46, height: 20, alignment: .leading)
    }
}

private struct StatusAPISpendStrip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 8)

            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.84))
                .padding(.leading, 3)
                .frame(width: 35, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 46, height: 9, alignment: .leading)
    }
}

private struct StatusAPILimitStrip: View {
    let metric: LimitMetric?
    let amountText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 8)

                TinyProgressBar(fraction: metric?.fractionRemaining ?? 0)
                    .frame(width: 34, height: 5)
                    .padding(.leading, 3)

                Text(metric?.remainingPercentText ?? "--%")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.leading, 4)
                    .frame(width: 26, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 75, height: 9, alignment: .leading)

            HStack(spacing: 0) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .frame(width: 8)

                Text(amountText)
                    .font(.system(size: 8.4, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.leading, 3)
                    .frame(width: 64, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .offset(y: 0.7)
            }
            .frame(width: 75, height: 9, alignment: .leading)
        }
        .frame(width: 75, height: 20, alignment: .leading)
    }
}

struct TinyProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))

                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: fillWidth(total: geometry.size.width))
            }
        }
    }

    private func fillWidth(total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(3, total * min(1, max(0, fraction)))
    }
}
