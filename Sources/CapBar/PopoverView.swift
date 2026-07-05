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

    private var selectedProviderDisplayMode: MenuBarDisplayMode {
        store.effectiveMenuBarDisplayMode(for: selectedSnapshot.provider)
    }

    @ViewBuilder
    private var usageContent: some View {
        header

        ProviderSelector(selection: menuBarProviderBinding)

        AccountLine(
            snapshot: selectedSnapshot,
            isRefreshing: store.isRefreshing,
            onLogin: { store.runCLILogin(for: selectedSnapshot.provider) },
            onRefresh: { store.refresh(force: true) }
        )

        VStack(spacing: 0) {
            LimitRow(
                metric: selectedSnapshot.current,
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled
            )
            StableDivider(color: palette.fieldDivider)
                .padding(.leading, 2)
            LimitRow(
                metric: selectedSnapshot.weekly,
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled
            )
        }
        .menuBarSelectionStyle(
            provider: selectedSnapshot.provider,
            isSelected: selectedProviderDisplayMode == .subscription
        )
        .doubleClickSelection {
            store.setMenuBarDisplayMode(.subscription, for: selectedSnapshot.provider)
        }

        if store.settings.apiSectionVisible {
            APIAccountSection(
                snapshot: store.apiSnapshot(for: selectedSnapshot.provider),
                provider: selectedSnapshot.provider,
                isCheckingKey: store.isCheckingAPIKey(for: selectedSnapshot.provider),
                isRemovingKey: store.isRemovingAPIKey(for: selectedSnapshot.provider),
                lowUsageColorsEnabled: store.settings.lowUsageColorsEnabled,
                monthlyBudgetUSD: store.settings.apiMonthlyBudgetUSD(for: selectedSnapshot.provider),
                selectedDisplayMode: selectedProviderDisplayMode,
                onSaveKey: { store.setAPIKey($0, for: selectedSnapshot.provider) },
                onRemoveKey: { store.clearAPIKey(for: selectedSnapshot.provider) },
                onSaveBudget: { store.setAPIMonthlyBudget($0, for: selectedSnapshot.provider) },
                onSelectMenuBarDisplayMode: {
                    store.setMenuBarDisplayMode($0, for: selectedSnapshot.provider)
                }
            )
        }

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

            SettingsToggleRow(
                title: "Show API usage",
                systemName: "key",
                isOn: apiSectionVisibleBinding
            )

            Divider()
                .overlay(palette.divider)
                .padding(.leading, 40)

            SettingsRefreshRow(
                isRefreshing: store.isRefreshing,
                onRefresh: { store.refresh(force: true) }
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

    private var apiSectionVisibleBinding: Binding<Bool> {
        Binding(
            get: { store.settings.apiSectionVisible },
            set: { store.setAPISectionVisible($0) }
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

    var pressedControlIcon: Color {
        primaryText.opacity(isDark ? 0.42 : 0.78)
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

    var fieldDivider: Color {
        isDark ? .white.opacity(0.16) : .white.opacity(0.52)
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

    private let cellHeight: CGFloat = 28
    private let controlPadding: CGFloat = 3
    private let selectedCornerRadius: CGFloat = 6

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
                            RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous)
                                .fill(palette.selectedProviderBackground(for: provider))
                                .overlay(
                                    RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous)
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
                        .frame(maxWidth: .infinity)
                        .frame(height: cellHeight)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .contentShape(RoundedRectangle(cornerRadius: selectedCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .help("Show \(provider.displayName) in the menu bar")
                .accessibilityLabel(provider.displayName)
            }
        }
        .frame(height: cellHeight)
        .padding(controlPadding)
        .frame(height: cellHeight + controlPadding * 2)
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
            Color(red: 0.24, green: 0.48, blue: 0.76)
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

private struct StableDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .allowsHitTesting(false)
    }
}

private extension View {
    func menuBarSelectionStyle(
        provider: ProviderID,
        isSelected: Bool,
        drawsUnselectedFrame: Bool = true
    ) -> some View {
        modifier(
            MenuBarSelectionStyle(
                provider: provider,
                isSelected: isSelected,
                drawsUnselectedFrame: drawsUnselectedFrame
            )
        )
    }

    func doubleClickSelection(action: @escaping () -> Void) -> some View {
        doubleClickSelection(isEnabled: true, action: action)
    }

    @ViewBuilder
    func doubleClickSelection(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        if isEnabled {
            onTapGesture(count: 2, perform: action)
        } else {
            self
        }
    }
}

private struct MenuBarSelectionStyle: ViewModifier {
    let provider: ProviderID
    let isSelected: Bool
    let drawsUnselectedFrame: Bool
    @Environment(\.popoverPalette) private var palette

    func body(content: Content) -> some View {
        content
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: isSelected ? 1.4 : 1)
            )
            .shadow(
                color: isSelected ? palette.selectedProviderShadow(for: provider) : .clear,
                radius: isSelected ? 5 : 0,
                y: isSelected ? 1 : 0
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var drawsFrame: Bool {
        isSelected || drawsUnselectedFrame
    }

    private var backgroundColor: Color {
        guard drawsFrame else { return .clear }
        return isSelected ? palette.selectedProviderBackground(for: provider) : palette.panelBackground
    }

    private var strokeColor: Color {
        guard drawsFrame else { return .clear }
        return isSelected ? palette.selectedProviderStroke(for: provider) : palette.panelStroke
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
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tone.remainingTextColor(in: palette))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
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
        .transaction { transaction in
            transaction.animation = nil
        }
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

private struct APIAccountSection: View {
    let snapshot: APIAccountSnapshot
    let provider: ProviderID
    let isCheckingKey: Bool
    let isRemovingKey: Bool
    let lowUsageColorsEnabled: Bool
    let monthlyBudgetUSD: Double?
    let selectedDisplayMode: MenuBarDisplayMode
    let onSaveKey: (String) -> Void
    let onRemoveKey: () -> Void
    let onSaveBudget: (Double?) -> Void
    let onSelectMenuBarDisplayMode: (MenuBarDisplayMode) -> Void

    private enum EditingMode {
        case none
        case key
        case budget
    }

    @State private var editingMode: EditingMode = .none
    @State private var draftKey = ""
    @State private var draftBudget = ""
    @Environment(\.popoverPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch editingMode {
            case .none:
                statusRow
                if let metric = limitMetric {
                    Divider()
                        .overlay(palette.divider)
                        .padding(.leading, 2)
                    LimitRow(metric: metric, lowUsageColorsEnabled: lowUsageColorsEnabled)
                        .menuBarSelectionStyle(
                            provider: provider,
                            isSelected: selectedDisplayMode == .apiLimit,
                            drawsUnselectedFrame: false
                        )
                        .doubleClickSelection(isEnabled: canSelectAPILimit) {
                            onSelectMenuBarDisplayMode(.apiLimit)
                        }
                }
            case .key:
                keyEditor
            case .budget:
                budgetEditor
            }
        }
        .background(palette.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.panelStroke, lineWidth: 1)
        )
        .onChange(of: provider) { _ in
            cancelEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            cancelEditing()
        }
    }

    private var limitMetric: LimitMetric? {
        guard case let .spend(summary) = snapshot.status else { return nil }
        return summary.apiLimitMetric(monthlyBudgetUSD: monthlyBudgetUSD)
    }

    private var canSelectAPISpend: Bool {
        guard case let .spend(summary) = snapshot.status else { return false }
        return summary.hasSpend
    }

    private var canSelectAPILimit: Bool {
        guard case let .spend(summary) = snapshot.status else { return false }
        return summary.manualAPILimitMetric(monthlyBudgetUSD: monthlyBudgetUSD) != nil
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.controlIcon)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(provider.platformName) API")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(subtitleHelpText ?? subtitleText)
            }

            Spacer()

            trailingContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .menuBarSelectionStyle(
            provider: provider,
            isSelected: selectedDisplayMode == .api,
            drawsUnselectedFrame: false
        )
        .doubleClickSelection(isEnabled: canSelectAPISpend) {
            onSelectMenuBarDisplayMode(.api)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let keyOperationText {
            keyOperationIndicator(text: keyOperationText)
        } else {
            switch snapshot.status {
            case .noKey:
                Button {
                    startEditingKey()
                } label: {
                    Text("Add Key")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add a \(provider.platformName) admin API key")
            case let .spend(summary):
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(summary.hasSpend ? summary.monthToDateText : summary.creditsRemainingText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .monospacedDigit()
                        if let detail = trailingDetailText(for: summary) {
                            Text(detail)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    keyMenu
                }
            case .invalidKey, .rateLimited, .unavailable:
                keyMenu
            }
        }
    }

    private var keyOperationText: String? {
        if isRemovingKey {
            return "Removing"
        }
        if isCheckingKey {
            return "Checking"
        }
        return nil
    }

    private var isKeyOperationInProgress: Bool {
        keyOperationText != nil
    }

    private func keyOperationIndicator(text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.58)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.activeStatus)
                .lineLimit(1)
        }
        .fixedSize()
        .help("\(text) \(provider.platformName) API key")
    }

    private var keyMenu: some View {
        APIKeyOptionsButton(
            monthlyBudgetUSD: monthlyBudgetUSD,
            isDisabled: isKeyOperationInProgress,
            onUpdateKey: startEditingKey,
            onEditBudget: startEditingBudget,
            onRemoveKey: onRemoveKey
        )
        .frame(width: 22, height: 22)
    }

    private var keyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.controlIcon)
                    .frame(width: 18, height: 18)
                Text("\(provider.platformName) admin API key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
            }

            SecureField(provider.adminKeyHint, text: $draftKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(saveDraftKey)
                .disabled(isKeyOperationInProgress)

            HStack {
                Text("Stored locally for CapBar, only sent to \(provider.platformName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(2)

                Spacer()

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isKeyOperationInProgress)

                Button("Save") {
                    saveDraftKey()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isKeyOperationInProgress || draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var subtitleText: String {
        if let keyOperationText {
            return "\(keyOperationText) API key"
        }

        switch snapshot.status {
        case .noKey:
            return "Track API spend"
        case let .spend(summary):
            if summary.hasSpend, summary.hasCredits {
                return "Spend this month"
            } else if summary.hasSpend {
                return "Spend this month"
            }
            return "API credits remaining"
        case let .invalidKey(detail):
            return detail ?? "API key rejected"
        case .rateLimited:
            return "Rate limited, retrying later"
        case .unavailable:
            return "Spend unavailable"
        }
    }

    private var subtitleHelpText: String? {
        if case .spend = snapshot.status, let fetchedAt = snapshot.fetchedAt {
            return "Updated \(Formatters.relativeString(for: fetchedAt))"
        }

        guard case let .invalidKey(detail) = snapshot.status else { return nil }
        let reason = detail.map { "\($0)\n\n" } ?? ""
        let hint: String
        switch provider {
        case .claude:
            hint = "Anthropic only exposes billing data to organization admin keys (\(provider.adminKeyHint)). Regular API keys cannot read it."
        case .codex:
            hint = "Use an organization admin key (\(provider.adminKeyHint)) for spend, or a legacy user API key for the credit balance. Project keys (sk-proj-...) cannot read billing data."
        }
        return reason + hint
    }

    private func trailingDetailText(for summary: APISpendSummary) -> String? {
        if summary.hasSpend {
            if let today = summary.todayUSD {
                return "Today \(Formatters.usd(today))"
            }
            return nil
        }
        if summary.creditsGrantedUSD != nil {
            return "of \(summary.creditsGrantedText)"
        }
        return "credits left"
    }

    private var subtitleColor: Color {
        if isKeyOperationInProgress {
            return palette.activeStatus
        }

        switch snapshot.status {
        case .invalidKey:
            return palette.dangerText
        case .rateLimited, .unavailable:
            return palette.warningText
        default:
            return palette.secondaryText
        }
    }

    private var budgetEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.controlIcon)
                    .frame(width: 18, height: 18)
                Text("\(provider.platformName) monthly budget")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
            }

            TextField("e.g. 100", text: $draftBudget)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(saveDraftBudget)

            HStack {
                Text("USD per calendar month, drawn as a limit bar")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(2)

                Spacer()

                if monthlyBudgetUSD != nil {
                    Button("Clear") {
                        onSaveBudget(nil)
                        cancelEditing()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveDraftBudget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(parsedDraftBudget == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var parsedDraftBudget: Double? {
        let normalized = draftBudget
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private func startEditingKey() {
        draftKey = ""
        editingMode = .key
    }

    private func startEditingBudget() {
        draftBudget = monthlyBudgetUSD.map { Formatters.plainNumber($0) } ?? ""
        editingMode = .budget
    }

    private func cancelEditing() {
        editingMode = .none
        draftKey = ""
        draftBudget = ""
    }

    private func saveDraftKey() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isKeyOperationInProgress == false else { return }
        onSaveKey(trimmed)
        cancelEditing()
    }

    private func saveDraftBudget() {
        guard let value = parsedDraftBudget else { return }
        onSaveBudget(value)
        cancelEditing()
    }
}

private struct APIKeyOptionsButton: NSViewRepresentable {
    let monthlyBudgetUSD: Double?
    let isDisabled: Bool
    let onUpdateKey: () -> Void
    let onEditBudget: () -> Void
    let onRemoveKey: () -> Void

    @Environment(\.popoverPalette) private var palette

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.ignoresMultiClick = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        button.sendAction(on: [.leftMouseDown])
        button.toolTip = "API key options"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.monthlyBudgetUSD = monthlyBudgetUSD
        context.coordinator.onUpdateKey = onUpdateKey
        context.coordinator.onEditBudget = onEditBudget
        context.coordinator.onRemoveKey = onRemoveKey
        context.coordinator.normalTint = NSColor(palette.controlIcon)
        context.coordinator.pressedTint = NSColor(palette.pressedControlIcon)
        context.coordinator.button = button

        let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "API key options")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = context.coordinator.currentTint
        button.isEnabled = isDisabled == false
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var monthlyBudgetUSD: Double?
        var onUpdateKey: () -> Void = {}
        var onEditBudget: () -> Void = {}
        var onRemoveKey: () -> Void = {}
        var normalTint = NSColor.labelColor
        var pressedTint = NSColor.secondaryLabelColor
        weak var button: NSButton?
        private var isMenuOpen = false

        var currentTint: NSColor {
            isMenuOpen ? pressedTint : normalTint
        }

        @objc func openMenu(_ sender: NSButton) {
            guard sender.isEnabled, sender.window != nil else { return }

            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            menu.addItem(menuItem("Update Key…", action: #selector(updateKey(_:))))
            menu.addItem(menuItem(monthlyBudgetUSD == nil ? "Set Monthly Budget…" : "Edit Monthly Budget…", action: #selector(editBudget(_:))))
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove Key", action: #selector(removeKey(_:))))

            isMenuOpen = true
            sender.contentTintColor = currentTint

            guard let window = sender.window else {
                closeMenu()
                return
            }

            let frameInWindow = sender.convert(sender.bounds, to: nil)
            let frameOnScreen = window.convertToScreen(frameInWindow)
            let location = NSPoint(x: frameOnScreen.maxX + 6, y: frameOnScreen.maxY)
            if menu.popUp(positioning: nil, at: location, in: nil) == false {
                closeMenu()
            }
        }

        private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            return item
        }

        @objc private func updateKey(_ sender: NSMenuItem) {
            onUpdateKey()
        }

        @objc private func editBudget(_ sender: NSMenuItem) {
            onEditBudget()
        }

        @objc private func removeKey(_ sender: NSMenuItem) {
            onRemoveKey()
        }

        func menuDidClose(_ menu: NSMenu) {
            closeMenu()
        }

        private func closeMenu() {
            isMenuOpen = false
            button?.contentTintColor = currentTint
        }
    }
}

private extension Animation {
    static let providerSelection = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)
}
