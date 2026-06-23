import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onQuit: () -> Void

    @State private var isShowingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isShowingSettings {
                settingsContent
            } else {
                usageContent
            }
        }
        .animation(.providerSelection, value: selectedSnapshot.provider)
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 360)
        .overlay(alignment: .topTrailing) {
            popoverControls
        }
        .environment(\.popoverPalette, palette)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            isShowingSettings = false
        }
    }

    private var palette: PopoverPalette {
        PopoverPalette(colorScheme: colorScheme)
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
                .overlay(palette.divider)
                .padding(.leading, 2)
            LimitRow(
                metric: selectedSnapshot.weekly,
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled
            )
        }
        .background(palette.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.panelStroke, lineWidth: 1)
        )

        Text(selectedSnapshot.sourceDescription)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.tertiaryText)
            .lineLimit(1)
    }

    @ViewBuilder
    private var settingsContent: some View {
        settingsHeader

        VStack(spacing: 0) {
            ProviderRotationPickerRow(selection: providerRotationIntervalBinding)

            Divider()
                .overlay(palette.divider)
                .padding(.leading, 40)

            RefreshIntervalPickerRow(selection: refreshIntervalBinding)

            Divider()
                .overlay(palette.divider)
                .padding(.leading, 40)

            SettingsToggleRow(
                title: "Low usage colors",
                systemName: "exclamationmark.triangle",
                isOn: lowUsageColorsBinding
            )

            Divider()
                .overlay(palette.divider)
                .padding(.leading, 40)

            SettingsRefreshRow(
                isRefreshing: store.isRefreshing,
                onRefresh: { store.refresh() }
            )
        }
        .background(palette.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.panelStroke, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            ProviderLogoView(provider: selectedSnapshot.provider, size: 22, foregroundColor: palette.primaryText)
                .padding(5)
                .background(palette.iconBackground, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedSnapshot.provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Text("Usage limits")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()
        }
        .padding(.trailing, 62)
    }

    private var settingsHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 22, height: 22)
                .padding(5)
                .background(palette.iconBackground, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Text("Preferences")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()
        }
        .padding(.trailing, 62)
    }

    private var popoverControls: some View {
        HStack(spacing: 8) {
            Button {
                toggleSettings()
            } label: {
                Image(systemName: isShowingSettings ? "arrow.left" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.controlIcon)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isShowingSettings ? "Back to usage" : "Settings")
            .accessibilityLabel(isShowingSettings ? "Back to usage" : "Settings")

            Button {
                onQuit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.controlIcon)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    private func toggleSettings() {
        isShowingSettings.toggle()
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

    private var providerRotationIntervalBinding: Binding<ProviderRotationInterval> {
        Binding(
            get: { store.settings.providerRotationInterval },
            set: { store.setProviderRotationInterval($0) }
        )
    }

    private var lowUsageColorsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.lowUsageColorsEnabled },
            set: { store.setLowUsageColorsEnabled($0) }
        )
    }
}

private struct PopoverPalette {
    private let isDark: Bool

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
    }

    var primaryText: Color {
        isDark ? .white : Color(red: 0.08, green: 0.09, blue: 0.11)
    }

    var secondaryText: Color {
        primaryText.opacity(isDark ? 0.58 : 0.68)
    }

    var tertiaryText: Color {
        primaryText.opacity(isDark ? 0.48 : 0.56)
    }

    var controlIcon: Color {
        primaryText.opacity(isDark ? 0.55 : 0.62)
    }

    var iconBackground: Color {
        primaryText.opacity(isDark ? 0.08 : 0.07)
    }

    var panelBackground: Color {
        primaryText.opacity(isDark ? 0.06 : 0.045)
    }

    var panelStroke: Color {
        primaryText.opacity(isDark ? 0.11 : 0.12)
    }

    var divider: Color {
        primaryText.opacity(isDark ? 0.08 : 0.12)
    }

    var selectedProviderText: Color {
        isDark ? .white : primaryText
    }

    var activeStatus: Color {
        isDark ? Color(red: 0.62, green: 0.80, blue: 1.0) : Color(red: 0.02, green: 0.38, blue: 0.70)
    }

    var activeStatusDetail: Color {
        activeStatus.opacity(isDark ? 0.68 : 0.76)
    }

    var inactiveStatus: Color {
        primaryText.opacity(isDark ? 0.36 : 0.48)
    }

    var inactiveStatusDetail: Color {
        primaryText.opacity(isDark ? 0.42 : 0.54)
    }

    var normalProgressText: Color {
        primaryText.opacity(isDark ? 0.70 : 0.72)
    }

    var unavailableProgressText: Color {
        primaryText.opacity(isDark ? 0.38 : 0.44)
    }

    var normalProgressFill: Color {
        primaryText.opacity(isDark ? 0.88 : 0.68)
    }

    var unavailableProgressFill: Color {
        primaryText.opacity(isDark ? 0.28 : 0.24)
    }

    var neutralProgressTrack: Color {
        primaryText.opacity(isDark ? 0.16 : 0.14)
    }

    var warningText: Color {
        isDark ? Color(red: 1.0, green: 0.68, blue: 0.30).opacity(0.92) : Color(red: 0.70, green: 0.37, blue: 0.00)
    }

    var warningProgressFill: Color {
        isDark ? Color(red: 1.0, green: 0.66, blue: 0.28).opacity(0.88) : Color(red: 0.80, green: 0.43, blue: 0.00)
    }

    var warningProgressTrack: Color {
        Color(red: 1.0, green: 0.66, blue: 0.28).opacity(isDark ? 0.18 : 0.20)
    }

    var dangerText: Color {
        isDark ? Color(red: 1.0, green: 0.36, blue: 0.32).opacity(0.94) : Color(red: 0.72, green: 0.08, blue: 0.05)
    }

    var dangerProgressFill: Color {
        isDark ? Color(red: 1.0, green: 0.32, blue: 0.30).opacity(0.90) : Color(red: 0.80, green: 0.10, blue: 0.07)
    }

    var dangerProgressTrack: Color {
        Color(red: 1.0, green: 0.32, blue: 0.30).opacity(isDark ? 0.20 : 0.18)
    }

    func selectedProviderBackground(for provider: ProviderID) -> Color {
        provider.selectionAccentColor.opacity(isDark ? 0.22 : 0.16)
    }

    func selectedProviderStroke(for provider: ProviderID) -> Color {
        provider.selectionAccentColor.opacity(isDark ? 0.34 : 0.28)
    }

    func selectedProviderShadow(for provider: ProviderID) -> Color {
        provider.selectionAccentColor.opacity(isDark ? 0.16 : 0.10)
    }
}

private struct PopoverPaletteKey: EnvironmentKey {
    static let defaultValue = PopoverPalette(colorScheme: .dark)
}

private extension EnvironmentValues {
    var popoverPalette: PopoverPalette {
        get { self[PopoverPaletteKey.self] }
        set { self[PopoverPaletteKey.self] = newValue }
    }
}

private struct ProviderSelector: View {
    @Binding var selection: ProviderID
    @Environment(\.popoverPalette) private var palette
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
                                .fill(palette.selectedProviderBackground(for: provider))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(palette.selectedProviderStroke(for: provider), lineWidth: 1)
                                )
                                .shadow(color: palette.selectedProviderShadow(for: provider), radius: 5, y: 1)
                                .matchedGeometryEffect(id: "selectedProvider", in: selectionNamespace)
                        }

                        HStack(spacing: 7) {
                            ProviderLogoView(
                                provider: provider,
                                size: 14,
                                foregroundColor: selection == provider ? palette.selectedProviderText : palette.secondaryText
                            )
                            Text(provider.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selection == provider ? palette.selectedProviderText : palette.secondaryText)
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
        .background(palette.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.panelStroke, lineWidth: 1)
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

private struct ProviderRotationPickerRow: View {
    @Binding var selection: ProviderRotationInterval
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: "arrow.triangle.2.circlepath")

            Text("Rotate provider")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(ProviderRotationInterval.allCases) { interval in
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

private struct RefreshIntervalPickerRow: View {
    @Binding var selection: RefreshInterval
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: "arrow.clockwise")

            Text("Auto refresh")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)

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
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: systemName)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)

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
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemName: "bolt")

            Text("Refresh now")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)

            Spacer()

            RefreshButton(isRefreshing: isRefreshing, onRefresh: onRefresh)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct SettingsIcon: View {
    let systemName: String
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.controlIcon)
            .frame(width: 18, height: 18)
    }
}

private struct AccountLine: View {
    let snapshot: ProviderSnapshot
    let isRefreshing: Bool
    let onLogin: () -> Void
    let onRefresh: () -> Void
    @Environment(\.popoverPalette) private var palette

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
        snapshot.account.isLoggedIn ? palette.activeStatus : palette.inactiveStatus
    }

    private var detailColor: Color {
        snapshot.account.isLoggedIn ? palette.activeStatusDetail : palette.inactiveStatusDetail
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @State private var rotationDegrees = 0.0
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        Button(action: onRefresh) {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isRefreshing ? palette.activeStatus : palette.controlIcon)
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
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        let tone = UsageTone(metric: metric, lowUsageColorsEnabled: lowUsageColorsEnabled)

        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric?.title ?? "Usage limit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(metric?.detail ?? "Unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(width: 154, alignment: .leading)

            SimpleProgressBar(
                fraction: metric?.fractionRemaining ?? 0,
                fillColor: tone.progressFillColor(in: palette),
                trackColor: tone.progressTrackColor(in: palette)
            )
                .frame(height: 6)

            Text(metric?.remainingText ?? "Unavailable")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.remainingTextColor(in: palette))
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

    func remainingTextColor(in palette: PopoverPalette) -> Color {
        switch self {
        case .unavailable:
            palette.unavailableProgressText
        case .normal:
            palette.normalProgressText
        case .warning:
            palette.warningText
        case .danger:
            palette.dangerText
        }
    }

    func progressFillColor(in palette: PopoverPalette) -> Color {
        switch self {
        case .unavailable:
            palette.unavailableProgressFill
        case .normal:
            palette.normalProgressFill
        case .warning:
            palette.warningProgressFill
        case .danger:
            palette.dangerProgressFill
        }
    }

    func progressTrackColor(in palette: PopoverPalette) -> Color {
        switch self {
        case .warning:
            palette.warningProgressTrack
        case .danger:
            palette.dangerProgressTrack
        default:
            palette.neutralProgressTrack
        }
    }
}

private extension Animation {
    static let providerSelection = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)
}
