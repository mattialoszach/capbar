import SwiftUI

struct StatusBarLabel: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack(spacing: 6) {
            ProviderLogoView(provider: snapshot.provider, size: 15)

            TinyProgressBar(fraction: snapshot.menuBarMetric?.fractionUsed ?? 0)
                .frame(width: 48, height: 6)

            Text(snapshot.menuBarMetric?.percentText ?? "--%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 30, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 105, height: 20)
        .contentShape(Rectangle())
        .accessibilityLabel("\(snapshot.provider.displayName) \(snapshot.menuBarMetric?.usedText ?? "limit unavailable")")
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
