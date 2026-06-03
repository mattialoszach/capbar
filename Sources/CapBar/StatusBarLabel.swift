import SwiftUI

struct StatusBarLabel: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack(spacing: 9) {
            ProviderLogoView(provider: snapshot.provider, size: 16)

            VStack(spacing: 2) {
                StatusLimitStrip(symbol: "clock", metric: snapshot.current)
                StatusLimitStrip(symbol: "calendar", metric: snapshot.weekly)
            }
        }
        .frame(width: 100, height: 22)
        .contentShape(Rectangle())
        .accessibilityLabel("\(snapshot.provider.displayName) usage limits")
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
                .padding(.leading, 5)
                .frame(width: 26, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(height: 9)
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
