import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var isShowingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isShowingSettings {
                settingsContent
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                usageContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.providerSelection, value: selectedSnapshot.provider)
        .animation(.providerSelection, value: isShowingSettings)
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .overlay(alignment: .topTrailing) {
            popoverControls
        }
        .environment(\.colorScheme, .dark)
    }

    private var selectedSnapshot: ProviderSnapshot {
        store.snapshot(for: store.settings.menuBarProvider)
    }

    @ViewBuilder
    private var usageContent: some View {
        header

        ProviderSelector(selection: menuBarProviderBinding)

        AccountLine(
            snapshot: selectedSnapshot,
            isRefreshing: store.isRefreshing,
            onLogin: { store.runCLILogin(for: selectedSnapshot.provider) },
            onRefresh: { store.refresh() }
        )

        VStack(spacing: 0) {
            LimitRow(
                metric: selectedSnapshot.current,
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled
            )
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.leading, 2)
            LimitRow(
                metric: selectedSnapshot.weekly,
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled
            )
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

    @ViewBuilder
    private var settingsContent: some View {
        settingsHeader

        VStack(spacing: 0) {
            SettingsPickerRow(selection: refreshIntervalBinding)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.leading, 40)

            SettingsToggleRow(
                title: "Low usage colors",
                systemName: "exclamationmark.triangle",
                isOn: lowUsageColorsBinding
            )

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.leading, 40)

            SettingsRefreshRow(
                isRefreshing: store.isRefreshing,
                onRefresh: { store.refresh() }
            )
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
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
        .padding(.trailing, 62)
    }

    private var settingsHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .padding(5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Preferences")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer()
        }
        .padding(.trailing, 62)
    }

    private var popoverControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.providerSelection) {
                    isShowingSettings.toggle()
                }
            } label: {
                Image(systemName: isShowingSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isShowingSettings ? Color.white.opacity(0.82) : Color.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isShowingSettings ? "Usage" : "Settings")

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
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    private var menuBarProviderBinding: Binding<ProviderID> {
        Binding(
            get: { store.settings.menuBarProvider },
            set: { provider in
                withAnimation(.providerSelection) {
                    store.setMenuBarProvider(provider)
                }
            }
        )
    }

    private var refreshIntervalBinding: Binding<RefreshInterval> {
        Binding(
            get: { store.settings.refreshInterval },
            set: { store.setRefreshInterval($0) }
        )
    }

    private var lowUsageColorsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.lowUsageColorsEnabled },
            set: { store.setLowUsageColorsEnabled($0) }
        )
    }
}

private struct ProviderSelector: View {
    @Binding var selection: ProviderID
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ProviderID.allCases) { provider in
                Button {
                    guard selection != provider else { return }
                    withAnimation(.providerSelection) {
                        selection = provider
                    }
                } label: {
                    ZStack {
                        if selection == provider {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(provider.selectionAccentColor.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(provider.selectionAccentColor.opacity(0.34), lineWidth: 1)
                                )
                                .shadow(color: provider.selectionAccentColor.opacity(0.16), radius: 5, y: 1)
                                .matchedGeometryEffect(id: "selectedProvider", in: selectionNamespace)
                        }

                        HStack(spacing: 7) {
                            ProviderLogoView(
                                provider: provider,
                                size: 14,
                                fallbackColor: selection == provider ? .white : Color.white.opacity(0.62)
                            )
                            Text(provider.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selection == provider ? Color.white : Color.white.opacity(0.58))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Show \(provider.displayName) in the menu bar")
                .accessibilityLabel(provider.displayName)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
    }
}

private extension ProviderID {
    var selectionAccentColor: Color {
        switch self {
        case .codex:
            Color(red: 0.32, green: 0.62, blue: 1.0)
        case .claude:
            Color(red: 0.86, green: 0.42, blue: 0.20)
        }
    }
}

private struct SettingsPickerRow: View {
    @Binding var selection: RefreshInterval

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: "arrow.clockwise")

            Text("Auto refresh")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 96)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemName: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: systemName)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct SettingsRefreshRow: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: "bolt")

            Text("Refresh now")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            RefreshButton(isRefreshing: isRefreshing, onRefresh: onRefresh)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct SettingsIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(width: 18, height: 18)
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
    let lowUsageColorsEnabled: Bool

    var body: some View {
        let tone = UsageTone(metric: metric, lowUsageColorsEnabled: lowUsageColorsEnabled)

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

            SimpleProgressBar(
                fraction: metric?.fractionRemaining ?? 0,
                fillColor: tone.progressFillColor,
                trackColor: tone.progressTrackColor
            )
                .frame(height: 6)

            Text(metric?.remainingText ?? "Unavailable")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.remainingTextColor)
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
    let fillColor: Color
    let trackColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth(total: geometry.size.width))
            }
        }
        .animation(.providerSelection, value: fraction)
    }

    private func fillWidth(total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(3, total * min(1, max(0, fraction)))
    }
}

private enum UsageTone {
    case unavailable
    case normal
    case warning
    case danger

    init(metric: LimitMetric?, lowUsageColorsEnabled: Bool) {
        guard let remainingPercent = metric?.remainingPercent else {
            self = .unavailable
            return
        }

        guard lowUsageColorsEnabled else {
            self = .normal
            return
        }

        if remainingPercent <= 15 {
            self = .danger
        } else if remainingPercent <= 30 {
            self = .warning
        } else {
            self = .normal
        }
    }

    var remainingTextColor: Color {
        switch self {
        case .unavailable:
            Color.white.opacity(0.38)
        case .normal:
            Color.white.opacity(0.70)
        case .warning:
            Color(red: 1.0, green: 0.68, blue: 0.30).opacity(0.92)
        case .danger:
            Color(red: 1.0, green: 0.36, blue: 0.32).opacity(0.94)
        }
    }

    var progressFillColor: Color {
        switch self {
        case .unavailable:
            Color.white.opacity(0.28)
        case .normal:
            Color.white.opacity(0.88)
        case .warning:
            Color(red: 1.0, green: 0.66, blue: 0.28).opacity(0.88)
        case .danger:
            Color(red: 1.0, green: 0.32, blue: 0.30).opacity(0.90)
        }
    }

    var progressTrackColor: Color {
        switch self {
        case .warning:
            Color(red: 1.0, green: 0.66, blue: 0.28).opacity(0.18)
        case .danger:
            Color(red: 1.0, green: 0.32, blue: 0.30).opacity(0.20)
        default:
            Color.white.opacity(0.16)
        }
    }
}

private extension Animation {
    static let providerSelection = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)
}
