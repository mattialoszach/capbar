import SwiftUI

struct StatusBarRenderModel: Equatable {
    struct Limit: Equatable {
        let fractionRemaining: Double
        let remainingPercentText: String

        init(metric: LimitMetric?) {
            fractionRemaining = metric?.fractionRemaining ?? 0
            remainingPercentText = metric?.remainingPercentText ?? "--%"
        }
    }

    let provider: ProviderID
    let displayMode: MenuBarDisplayMode
    let usesExpandedLayout: Bool
    let currentLimit: Limit
    let weeklyLimit: Limit
    let apiTodayText: String
    let apiMonthText: String
    let apiLimit: Limit
    let apiLimitAmountText: String
    let apiLimitAccessibilityText: String

    init(
        subscriptionSnapshot: ProviderSnapshot,
        apiSnapshot: APIAccountSnapshot,
        apiMonthlyBudgetUSD: Double?,
        displayMode: MenuBarDisplayMode,
        usesExpandedLayout: Bool
    ) {
        let spendSummary: APISpendSummary?
        if case let .spend(summary) = apiSnapshot.status {
            spendSummary = summary
        } else {
            spendSummary = nil
        }

        provider = subscriptionSnapshot.provider
        self.displayMode = displayMode
        self.usesExpandedLayout = usesExpandedLayout
        currentLimit = Limit(metric: subscriptionSnapshot.current)
        weeklyLimit = Limit(metric: subscriptionSnapshot.weekly)
        apiTodayText = Self.spendText(spendSummary?.todayUSD, summary: spendSummary)
        apiMonthText = Self.spendText(spendSummary?.monthToDateUSD, summary: spendSummary)
        let apiLimitMetric = spendSummary?.manualAPILimitMetric(monthlyBudgetUSD: apiMonthlyBudgetUSD)
        apiLimit = Limit(metric: apiLimitMetric)
        apiLimitAccessibilityText = apiLimitMetric?.remainingText ?? "unavailable"

        if let spent = spendSummary?.monthToDateUSD,
           let limit = apiMonthlyBudgetUSD,
           limit > 0 {
            apiLimitAmountText = "\(Formatters.menuBarUSD(spent))/\(Formatters.menuBarUSD(limit))"
        } else {
            apiLimitAmountText = "--/--"
        }
    }

    private static func spendText(_ amount: Double?, summary: APISpendSummary?) -> String {
        guard let summary, summary.hasSpend else { return "--" }
        let text = Formatters.compactUSD(amount ?? 0)
        return summary.includesEstimatedCurrentDay ? "~\(text)" : text
    }

    var accessibilityText: String {
        switch displayMode {
        case .subscription:
            return "\(provider.displayName) usage limits"
        case .api:
            return "\(provider.displayName) API spend, today \(apiTodayText), month \(apiMonthText)"
        case .apiLimit:
            return "\(provider.displayName) API monthly limit, \(apiLimitAccessibilityText), \(apiLimitAmountText)"
        }
    }
}

struct StatusBarLabel: View {
    let model: StatusBarRenderModel

    var body: some View {
        HStack(spacing: 4) {
            ProviderLogoView(provider: model.provider, size: 16)

            VStack(spacing: 2) {
                switch model.displayMode {
                case .subscription:
                    StatusLimitStrip(symbol: "clock", limit: model.currentLimit)
                    StatusLimitStrip(symbol: "calendar", limit: model.weeklyLimit)
                case .api:
                    StatusAPISpendStack(todayText: model.apiTodayText, monthText: model.apiMonthText)
                case .apiLimit:
                    StatusAPILimitStrip(limit: model.apiLimit, amountText: model.apiLimitAmountText)
                }
            }
        }
        .frame(width: contentWidth, height: 22, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(model.accessibilityText)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var contentWidth: CGFloat {
        if model.usesExpandedLayout {
            return 95
        }

        switch model.displayMode {
        case .subscription, .apiLimit:
            return 95
        case .api:
            return 66
        }
    }
}

private struct StatusLimitStrip: View {
    let symbol: String
    let limit: StatusBarRenderModel.Limit

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 8)

            TinyProgressBar(fraction: limit.fractionRemaining)
                .frame(width: 34, height: 5)
                .padding(.leading, 3)

            Text(limit.remainingPercentText)
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
    let limit: StatusBarRenderModel.Limit
    let amountText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 8)

                TinyProgressBar(fraction: limit.fractionRemaining)
                    .frame(width: 34, height: 5)
                    .padding(.leading, 3)

                Text(limit.remainingPercentText)
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
