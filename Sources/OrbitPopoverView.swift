import SwiftUI
import AppKit

// MARK: - Toolbar Tooltip Enum
public enum ToolbarTooltip: Equatable {
    case refresh
    case settings
    case style
    case quit
}

// MARK: - View Model
public class OrbitViewModel: ObservableObject {
    @Published public var accounts: [AccountStatus] = []
    @Published public var isRefreshing: Bool = false
    @Published public var autoRotateEnabled: Bool = ConfigManager.shared.config.autoRotateEnabled
    @Published public var thresholdPercentage: Int = ConfigManager.shared.config.thresholdPercentage
    @Published public var showAccountAlias: Bool = ConfigManager.shared.config.showAccountAlias
    @Published public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    @Published public var layoutStyle: PopoverLayoutStyle = ConfigManager.shared.config.popoverLayoutStyle
    @Published public var spinDegree: Double = 0
    @Published public var hoveredAccountId: String? = nil
    @Published public var isRotateHovered: Bool = false
    @Published public var activeToolbarTooltip: ToolbarTooltip? = nil

    // Action Closures
    public var onRefresh: (() -> Void)?
    public var onRotateNow: (() -> Void)?
    public var onSwitchAccount: ((String) -> Void)?
    public var onSelectModel: ((String, String) -> Void)?
    public var onToggleAutoRotate: (() -> Void)?
    public var onOpenSettings: ((Int?) -> Void)?
    public var onOpenAbout: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onSelectLanguage: ((AppLanguage) -> Void)?
    public var onLoginBrowserOAuth: (() -> Void)?
    public var onImportIde: (() -> Void)?
    public var onSelectLayoutStyle: ((PopoverLayoutStyle) -> Void)?

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .languageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAvatarChanged),
            name: .avatarDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLayoutChanged),
            name: .popoverLayoutDidChange,
            object: nil
        )
    }

    @objc private func handleLanguageChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.currentLanguage = LocalizationManager.shared.currentLanguage
            self?.objectWillChange.send()
        }
    }

    @objc private func handleAvatarChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    @objc private func handleLayoutChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.layoutStyle = ConfigManager.shared.config.popoverLayoutStyle
            self?.objectWillChange.send()
        }
    }

    public func update(
        accounts: [AccountStatus],
        isRefreshing: Bool,
        autoRotate: Bool,
        threshold: Int
    ) {
        self.accounts = accounts
        self.isRefreshing = isRefreshing
        self.autoRotateEnabled = autoRotate
        self.thresholdPercentage = threshold
        self.showAccountAlias = ConfigManager.shared.config.showAccountAlias
        self.currentLanguage = LocalizationManager.shared.currentLanguage
        self.layoutStyle = ConfigManager.shared.config.popoverLayoutStyle
    }

    public var activeAccount: AccountStatus? {
        return accounts.first(where: { $0.isCurrent })
    }

    public var standbyAccounts: [AccountStatus] {
        return accounts.filter { !$0.isCurrent }
    }

    public var nextRotationAccount: AccountStatus? {
        guard accounts.count > 1, let active = activeAccount else { return nil }
        guard let currentIndex = accounts.firstIndex(where: { $0.id == active.id }) else { return nil }

        let threshold = thresholdPercentage
        for offset in 1..<accounts.count {
            let nextIndex = (currentIndex + offset) % accounts.count
            let candidate = accounts[nextIndex]
            let pct = candidate.gemini5hPercentage ?? candidate.remainingPercentage
            if pct > threshold {
                return candidate
            }
        }

        let nonActive = accounts.filter { $0.id != active.id }
        return nonActive.max(by: {
            ($0.gemini5hPercentage ?? $0.remainingPercentage) < ($1.gemini5hPercentage ?? $1.remainingPercentage)
        })
    }
}

// MARK: - Main Popover View (Router)
public struct OrbitPopoverView: View {
    @ObservedObject public var viewModel: OrbitViewModel

    public init(viewModel: OrbitViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.layoutStyle {
            case .streamlined:
                StreamlinedPopoverView(viewModel: viewModel)
            case .raycast:
                RaycastPopoverView(viewModel: viewModel)
            case .radial:
                RadialPopoverView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Visual Effect View for Native macOS Vibrancy
public struct VisualEffectBackground: NSViewRepresentable {
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - UI Helpers
public struct PopoverUIHelper {
    public static func quotaColor(_ pct: Int, threshold: Int) -> Color {
        if pct < 0 { return .red }
        if pct <= threshold { return .red }
        if pct <= 30 { return .orange }
        return .green
    }

    public static func formatCountdown(_ isoString: String?) -> String? {
        guard let iso = isoString, !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let target = date else { return nil }
        let diff = target.timeIntervalSinceNow
        if diff <= 0 { return "0m" }
        let days = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public static func loadAppLogo() -> NSImage? {
        if let path = Bundle.main.path(forResource: "StatusBarLogo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon1024", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return nil
    }
}

// MARK: - Reusable Model Selector Menu
private struct ReusableModelSelectorMenu: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        Menu {
            Button(action: {
                viewModel.onSelectModel?(account.id, "")
            }) {
                HStack {
                    Text(L10n.tr("model.auto"))
                    if account.preferredModelId == nil || account.preferredModelId?.isEmpty == true {
                        Text("✓")
                    }
                }
            }

            Divider()

            Section("Google Gemini") {
                ForEach(AIModelCatalog.geminiModels, id: \.id) { opt in
                    Button(action: {
                        viewModel.onSelectModel?(account.id, opt.id)
                    }) {
                        HStack {
                            Text(opt.displayName)
                            if account.preferredModelId == opt.id {
                                Text("✓")
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Anthropic Claude") {
                ForEach(AIModelCatalog.claudeModels, id: \.id) { opt in
                    Button(action: {
                        viewModel.onSelectModel?(account.id, opt.id)
                    }) {
                        HStack {
                            Text(opt.displayName)
                            if account.preferredModelId == opt.id {
                                Text("✓")
                            }
                        }
                    }
                }
            }

            Divider()

            Section(L10n.tr("model.group_other")) {
                ForEach(AIModelCatalog.otherModels, id: \.id) { opt in
                    Button(action: {
                        viewModel.onSelectModel?(account.id, opt.id)
                    }) {
                        HStack {
                            Text(opt.displayName)
                            if account.preferredModelId == opt.id {
                                Text("✓")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("🤖 \(account.displayModelName)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .opacity(0.6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
    }
}

// MARK: - Reusable Style Quick Menu
private struct StyleQuickMenu: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        Menu {
            Section(L10n.tr("settings.popover_style_title")) {
                ForEach(PopoverLayoutStyle.allCases) { style in
                    Button(action: {
                        ConfigManager.shared.updatePopoverLayoutStyle(style)
                    }) {
                        HStack {
                            Text(style.displayName)
                            if viewModel.layoutStyle == style {
                                Text("✓")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
    }
}

// MARK: - Quota Progress Bar
private struct QuotaProgressBar: View {
    let percentage: Int
    let height: CGFloat
    let tintColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: height)

                Capsule()
                    .fill(tintColor)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(clamped) / 100.0)), height: height)
                    .animation(.easeInOut(duration: 0.3), value: clamped)
            }
        }
        .frame(height: height)
    }

    private var clamped: Int {
        return max(0, min(100, percentage))
    }
}

// ====================================================================
// MARK: - LAYOUT 1: STREAMLINED GLANCEABLE (macOS Native / Apple HIG)
// ====================================================================
public struct StreamlinedPopoverView: View {
    @ObservedObject public var viewModel: OrbitViewModel

    public var body: some View {
        VStack(spacing: 10) {
            // 1. Header (Compact)
            StreamlinedHeader(viewModel: viewModel)

            // 2. Active Card or Empty State
            if let active = viewModel.activeAccount {
                StreamlinedActiveCard(account: active, viewModel: viewModel)
            } else if viewModel.accounts.isEmpty {
                NoAccountsView(viewModel: viewModel)
            } else {
                NoActiveAccountBanner(viewModel: viewModel)
            }

            // 3. Standby List (Clickable row)
            if !viewModel.standbyAccounts.isEmpty {
                StreamlinedStandbySection(viewModel: viewModel)
            }

            // 4. Unified Control Bar (1 Row)
            if !viewModel.accounts.isEmpty {
                StreamlinedControlBar(viewModel: viewModel)
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(VisualEffectBackground())
    }
}

private struct StreamlinedHeader: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack(spacing: 8) {
            if let active = viewModel.activeAccount {
                AccountAvatarView(
                    accountId: active.id,
                    pictureUrl: active.picture,
                    displayName: active.displayName(showAlias: viewModel.showAccountAlias),
                    isCurrent: true,
                    size: 22
                )

                VStack(alignment: .leading, spacing: 0.5) {
                    HStack(spacing: 5) {
                        Text(active.displayName(showAlias: viewModel.showAccountAlias))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(active.displayTierName)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.18))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }

                    Text(active.email)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                if let logo = PopoverUIHelper.loadAppLogo() {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text("Antigravity Orbit")
                    .font(.system(size: 12, weight: .bold))
            }

            Spacer()

            // Header Toolbar Buttons
            HStack(spacing: 2) {
                // Style Switcher
                StyleQuickMenu(viewModel: viewModel)

                // Refresh Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        viewModel.spinDegree += 360
                    }
                    viewModel.onRefresh?()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(viewModel.spinDegree))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Settings Button
                Button(action: {
                    viewModel.onOpenSettings?(nil)
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

private struct StreamlinedActiveCard: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 5-Hour Progress
            VStack(spacing: 3) {
                HStack {
                    Text(L10n.tr("popover.5h_limit"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    if let countdown = PopoverUIHelper.formatCountdown(account.geminiResetTime) {
                        Text(String(format: L10n.tr("popover.reset_in"), countdown))
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    Text("\(pct5h)%")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(PopoverUIHelper.quotaColor(pct5h, threshold: viewModel.thresholdPercentage))
                }

                QuotaProgressBar(percentage: pct5h, height: 5, tintColor: PopoverUIHelper.quotaColor(pct5h, threshold: viewModel.thresholdPercentage))
            }

            // Weekly Limit (if available)
            if let weekly = account.geminiWeeklyPercentage {
                VStack(spacing: 3) {
                    HStack {
                        Text(L10n.tr("popover.weekly_limit"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        if let countdown = PopoverUIHelper.formatCountdown(account.geminiWeeklyResetTime) {
                            Text(String(format: L10n.tr("popover.reset_in"), countdown))
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }

                        Text("\(weekly)%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.blue)
                    }

                    QuotaProgressBar(percentage: weekly, height: 5, tintColor: Color.blue.opacity(0.85))
                }
            }

            // Model Selector Row
            HStack {
                Text(L10n.tr("popover.model_label"))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                Spacer()

                ReusableModelSelectorMenu(account: account, viewModel: viewModel)
            }
            .padding(.top, 1)
        }
        .padding(9)
        .background(Color(NSColor.textBackgroundColor).opacity(0.35))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 0.5)
        )
    }

    private var pct5h: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }
}

private struct StreamlinedStandbySection: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L10n.tr("popover.standby_accounts", viewModel.standbyAccounts.count))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                Spacer()

                Button(action: {
                    viewModel.onOpenSettings?(0)
                }) {
                    Text(L10n.tr("menu.account_settings"))
                        .font(.system(size: 9.5))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 2)

            if viewModel.standbyAccounts.count > 3 {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                            StreamlinedStandbyRow(account: acc, viewModel: viewModel)
                        }
                    }
                }
                .frame(maxHeight: 160)
            } else {
                VStack(spacing: 3) {
                    ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                        StreamlinedStandbyRow(account: acc, viewModel: viewModel)
                    }
                }
            }
        }
    }
}

private struct StreamlinedStandbyRow: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    private var isHovered: Bool {
        return viewModel.hoveredAccountId == account.id
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(statusDot)
                .font(.system(size: 7))

            AccountAvatarView(
                accountId: account.id,
                pictureUrl: account.picture,
                displayName: account.displayName(showAlias: viewModel.showAccountAlias),
                isCurrent: false,
                size: 16
            )

            VStack(alignment: .leading, spacing: 0.5) {
                Text(account.displayName(showAlias: viewModel.showAccountAlias))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(quotaSubtext)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(pct)%")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(PopoverUIHelper.quotaColor(pct, threshold: viewModel.thresholdPercentage))

            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .opacity(isHovered ? 1.0 : 0)
                .frame(width: 14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color(NSColor.textBackgroundColor).opacity(0.18))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                viewModel.hoveredAccountId = account.id
            } else if viewModel.hoveredAccountId == account.id {
                viewModel.hoveredAccountId = nil
            }
        }
        .onTapGesture {
            viewModel.onSwitchAccount?(account.id)
        }
    }

    private var pct: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }

    private var statusDot: String {
        if pct < 0 || pct <= viewModel.thresholdPercentage { return "🔴" }
        if pct <= 30 { return "🟡" }
        return "🟢"
    }

    private var quotaSubtext: String {
        if let wk = account.geminiWeeklyPercentage {
            return "5h: \(pct)% • \(L10n.tr("menu.week_label", wk))"
        }
        return "5h: \(pct)%"
    }
}

private struct StreamlinedControlBar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack {
            // Auto Rotate Toggle
            Toggle(isOn: Binding(
                get: { viewModel.autoRotateEnabled },
                set: { _ in viewModel.onToggleAutoRotate?() }
            )) {
                Text(String(format: L10n.tr("popover.auto_rotate_short"), viewModel.thresholdPercentage))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(SwitchToggleStyle())
            .scaleEffect(0.72)

            Spacer()

            // Quick Rotate Button
            Button(action: {
                viewModel.onRotateNow?()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.tr("popover.rotate_now_short"))
                        .font(.system(size: 10.5, weight: .medium))
                    Text("⌘R")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.secondary.opacity(viewModel.isRotateHovered ? 0.16 : 0.08))
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                viewModel.isRotateHovered = hovering
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
    }
}

// ====================================================================
// MARK: - LAYOUT 2: RAYCAST / COMMAND PALETTE (Developer Style)
// ====================================================================
public struct RaycastPopoverView: View {
    @ObservedObject public var viewModel: OrbitViewModel

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Raycast Top Header
            RaycastTopBar(viewModel: viewModel)

            // 2. Unified Account List
            if viewModel.accounts.isEmpty {
                NoAccountsView(viewModel: viewModel)
            } else {
                RaycastAccountList(viewModel: viewModel)
            }

            // 3. Command Bar Footer
            RaycastCommandFooter(viewModel: viewModel)
        }
        .padding(10)
        .frame(width: 340)
        .background(VisualEffectBackground())
    }
}

private struct RaycastTopBar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack {
            Text("ACCOUNTS (\(viewModel.accounts.count))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(0.6)

            Spacer()

            // Auto-rotate badge pill (clickable)
            Button(action: {
                viewModel.onToggleAutoRotate?()
            }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.autoRotateEnabled ? Color.green : Color.gray)
                        .frame(width: 5, height: 5)
                    Text(viewModel.autoRotateEnabled ? String(format: "Auto: ON (<%d%%)", viewModel.thresholdPercentage) : "Auto: OFF")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(viewModel.autoRotateEnabled ? .primary : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())

            StyleQuickMenu(viewModel: viewModel)

            Button(action: {
                viewModel.onOpenSettings?(nil)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}

private struct RaycastAccountList: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Active Account Row
            if let active = viewModel.activeAccount {
                RaycastActiveRow(account: active, viewModel: viewModel)
            }

            // Standby Accounts Rows
            if !viewModel.standbyAccounts.isEmpty {
                if viewModel.standbyAccounts.count > 4 {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                                RaycastStandbyRow(account: acc, viewModel: viewModel)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                } else {
                    VStack(spacing: 3) {
                        ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                            RaycastStandbyRow(account: acc, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
}

private struct RaycastActiveRow: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text(account.displayName(showAlias: viewModel.showAccountAlias))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(L10n.tr("popover.active_badge"))
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(3)

                Spacer()

                Text("\(pct5h)%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(PopoverUIHelper.quotaColor(pct5h, threshold: viewModel.thresholdPercentage))

                if let wk = account.geminiWeeklyPercentage {
                    Text("/ \(wk)%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.blue)
                }
            }

            // Mini progress bar
            QuotaProgressBar(percentage: pct5h, height: 3.5, tintColor: PopoverUIHelper.quotaColor(pct5h, threshold: viewModel.thresholdPercentage))

            HStack {
                Text("🤖 \(account.displayModelName)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if let cd = PopoverUIHelper.formatCountdown(account.geminiResetTime) {
                    Text(String(format: L10n.tr("popover.reset_in"), cd))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.10))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.8)
        )
    }

    private var pct5h: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }
}

private struct RaycastStandbyRow: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    private var isHovered: Bool {
        return viewModel.hoveredAccountId == account.id
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)

            AccountAvatarView(
                accountId: account.id,
                pictureUrl: account.picture,
                displayName: account.displayName(showAlias: viewModel.showAccountAlias),
                isCurrent: false,
                size: 15
            )

            Text(account.displayName(showAlias: viewModel.showAccountAlias))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(pct)%")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(PopoverUIHelper.quotaColor(pct, threshold: viewModel.thresholdPercentage))

            if let wk = account.geminiWeeklyPercentage {
                Text("/ \(wk)%")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text("↵")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1.0 : 0)
                .frame(width: 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                viewModel.hoveredAccountId = account.id
            } else if viewModel.hoveredAccountId == account.id {
                viewModel.hoveredAccountId = nil
            }
        }
        .onTapGesture {
            viewModel.onSwitchAccount?(account.id)
        }
    }

    private var pct: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }
}

private struct RaycastCommandFooter: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if let next = viewModel.nextRotationAccount {
                    viewModel.onSwitchAccount?(next.id)
                }
            }) {
                HStack(spacing: 3) {
                    Text("↵")
                        .font(.system(size: 9, weight: .bold))
                    Text(L10n.tr("popover.btn_switch"))
                        .font(.system(size: 9.5, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                viewModel.onRotateNow?()
            }) {
                HStack(spacing: 3) {
                    Text("⌘R")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    Text(L10n.tr("popover.rotate_now_short"))
                        .font(.system(size: 9.5, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.6)) {
                    viewModel.spinDegree += 360
                }
                viewModel.onRefresh?()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5))
                    .rotationEffect(.degrees(viewModel.spinDegree))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .border(width: 0.5, edges: [.top], color: Color.secondary.opacity(0.15))
    }
}

// ====================================================================
// MARK: - LAYOUT 3: RADIAL MINI-WIDGET (Apple Watch Style)
// ====================================================================
public struct RadialPopoverView: View {
    @ObservedObject public var viewModel: OrbitViewModel

    public var body: some View {
        VStack(spacing: 9) {
            // 1. Top Bar
            RadialTopBar(viewModel: viewModel)

            // 2. Circular Gauge
            if let active = viewModel.activeAccount {
                RadialHeroGauge(account: active, viewModel: viewModel)
            } else if viewModel.accounts.isEmpty {
                NoAccountsView(viewModel: viewModel)
            } else {
                NoActiveAccountBanner(viewModel: viewModel)
            }

            // 3. Standby Quick Switch Chips
            if !viewModel.standbyAccounts.isEmpty {
                RadialQuickSwitchSection(viewModel: viewModel)
            }

            // 4. Bottom Actions
            if !viewModel.accounts.isEmpty {
                RadialBottomBar(viewModel: viewModel)
            }
        }
        .padding(12)
        .frame(width: 310)
        .background(VisualEffectBackground())
    }
}

private struct RadialTopBar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack {
            if let logo = PopoverUIHelper.loadAppLogo() {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text("Orbit")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            Spacer()

            StyleQuickMenu(viewModel: viewModel)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.6)) {
                    viewModel.spinDegree += 360
                }
                viewModel.onRefresh?()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(viewModel.spinDegree))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                viewModel.onOpenSettings?(nil)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 2)
    }
}

private struct RadialHeroGauge: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Circular Progress Ring
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 7)
                    .frame(width: 86, height: 86)

                // 5-Hour Progress Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(pct5h, 0), 100)) / 100.0)
                    .stroke(
                        PopoverUIHelper.quotaColor(pct5h, threshold: viewModel.thresholdPercentage),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 86, height: 86)
                    .animation(.easeInOut(duration: 0.4), value: pct5h)

                // Center Label
                VStack(spacing: 0) {
                    Text("\(pct5h)%")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if let countdown = PopoverUIHelper.formatCountdown(account.geminiResetTime) {
                        Text(countdown)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 2)

            // Account Name & Model
            VStack(spacing: 2) {
                Text(account.displayName(showAlias: viewModel.showAccountAlias))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(account.displayTierName)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(Color.purple.opacity(0.18))
                        .foregroundColor(.purple)
                        .cornerRadius(3)

                    if let wk = account.geminiWeeklyPercentage {
                        Text("• Week: \(wk)%")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Model Chip
            ReusableModelSelectorMenu(account: account, viewModel: viewModel)
        }
    }

    private var pct5h: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }
}

private struct RadialQuickSwitchSection: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("popover.quick_switch"))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                        let pct = acc.gemini5hPercentage ?? acc.remainingPercentage
                        Button(action: {
                            viewModel.onSwitchAccount?(acc.id)
                        }) {
                            HStack(spacing: 4) {
                                AccountAvatarView(
                                    accountId: acc.id,
                                    pictureUrl: acc.picture,
                                    displayName: acc.displayName(showAlias: viewModel.showAccountAlias),
                                    isCurrent: false,
                                    size: 13
                                )

                                Text(acc.displayName(showAlias: viewModel.showAccountAlias))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)

                                Text("\(pct)%")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(PopoverUIHelper.quotaColor(pct, threshold: viewModel.thresholdPercentage))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct RadialBottomBar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { viewModel.autoRotateEnabled },
                set: { _ in viewModel.onToggleAutoRotate?() }
            )) {
                Text(viewModel.autoRotateEnabled ? "Auto" : "Manual")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(SwitchToggleStyle())
            .scaleEffect(0.68)

            Spacer()

            Button(action: {
                viewModel.onRotateNow?()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9.5))
                    Text(L10n.tr("popover.rotate_now_short"))
                        .font(.system(size: 10, weight: .medium))
                    Text("⌘R")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 2)
    }
}

// ====================================================================
// MARK: - Empty States
// ====================================================================
private struct NoAccountsView: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text(L10n.tr("settings.no_accounts_linked"))
                .font(.system(size: 11.5, weight: .semibold))

            Text(L10n.tr("settings.no_accounts_desc"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.onLoginBrowserOAuth?()
                }) {
                    Text(L10n.tr("settings.btn_login_browser"))
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    viewModel.onOpenSettings?(0)
                }) {
                    Text(L10n.tr("menu.account_settings"))
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.25))
        .cornerRadius(9)
    }
}

private struct NoActiveAccountBanner: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("⚠️")
                Text(L10n.tr("menu.unidentified_account"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }

            if let first = viewModel.accounts.first {
                Button(action: {
                    viewModel.onSwitchAccount?(first.id)
                }) {
                    Text(L10n.tr("popover.activate_account", first.displayName(showAlias: viewModel.showAccountAlias)))
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3.5)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.12))
        .cornerRadius(7)
    }
}

// MARK: - View Extension for selective border
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
