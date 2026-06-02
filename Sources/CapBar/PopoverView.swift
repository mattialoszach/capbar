import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("", selection: menuBarProviderBinding) {
                ForEach(ProviderID.allCases) { provider in
                    Text(provider.shortName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            AccountLine(
                snapshot: selectedSnapshot,
                isRefreshing: store.isRefreshing,
                onLogin: { store.runCLILogin(for: selectedSnapshot.provider) },
                onRefresh: { store.refresh() }
            )

            VStack(spacing: 0) {
                LimitRow(metric: selectedSnapshot.current)
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.leading, 2)
                LimitRow(metric: selectedSnapshot.weekly)
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )

            Text(selectedSnapshot.sourceDescription)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .overlay(alignment: .topTrailing) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit")
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .environment(\.colorScheme, .dark)
    }

    private var selectedSnapshot: ProviderSnapshot {
        store.snapshot(for: store.settings.menuBarProvider)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ProviderLogoView(provider: selectedSnapshot.provider, size: 22, fallbackColor: .white.opacity(0.88))
                .padding(5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedSnapshot.provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Usage limits")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer()
        }
        .padding(.trailing, 34)
    }

    private var menuBarProviderBinding: Binding<ProviderID> {
        Binding(
            get: { store.settings.menuBarProvider },
            set: { store.setMenuBarProvider($0) }
        )
    }
}

private struct AccountLine: View {
    let snapshot: ProviderSnapshot
    let isRefreshing: Bool
    let onLogin: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.account.isLoggedIn ? "Logged in" : "Not logged in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                if let detail = accountDetail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            RefreshButton(
                isRefreshing: isRefreshing,
                onRefresh: onRefresh
            )

            Button(action: onLogin) {
                Text(snapshot.account.isLoggedIn ? "Login" : "Login")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var accountDetail: String? {
        snapshot.account.email ?? snapshot.account.detail
    }

    private var statusColor: Color {
        snapshot.account.isLoggedIn ? Color(red: 0.62, green: 0.80, blue: 1.0) : Color.white.opacity(0.36)
    }

    private var detailColor: Color {
        snapshot.account.isLoggedIn ? Color(red: 0.62, green: 0.80, blue: 1.0).opacity(0.68) : Color.white.opacity(0.42)
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @State private var rotationDegrees = 0.0

    var body: some View {
        Button(action: onRefresh) {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isRefreshing ? Color(red: 0.62, green: 0.80, blue: 1.0) : Color.white.opacity(0.62))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isRefreshing ? "Refreshing" : "Refresh")
        .onAppear {
            updateAnimation(isRefreshing)
        }
        .onChange(of: isRefreshing) { refreshing in
            updateAnimation(refreshing)
        }
    }

    private func updateAnimation(_ refreshing: Bool) {
        if refreshing {
            rotationDegrees = 0
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                rotationDegrees = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                rotationDegrees = 0
            }
        }
    }
}

private struct LimitRow: View {
    let metric: LimitMetric?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric?.title ?? "Usage limit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metric?.detail ?? "Unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(width: 154, alignment: .leading)

            SimpleProgressBar(fraction: metric?.fractionRemaining ?? 0)
                .frame(height: 6)

            Text(metric?.remainingText ?? "Unavailable")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(metric?.usedPercent == nil ? 0.38 : 0.70))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
    }
}

private struct SimpleProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: fillWidth(total: geometry.size.width))
            }
        }
    }

    private func fillWidth(total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(3, total * min(1, max(0, fraction)))
    }
}
