import SwiftUI
import AppKit

// MARK: - View Model
public class OrbitViewModel: ObservableObject {
    @Published public var accounts: [AccountStatus] = []
    @Published public var isRefreshing: Bool = false
    @Published public var autoRotateEnabled: Bool = ConfigManager.shared.config.autoRotateEnabled
    @Published public var thresholdPercentage: Int = ConfigManager.shared.config.thresholdPercentage
    @Published public var showAccountAlias: Bool = ConfigManager.shared.config.showAccountAlias
    @Published public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    @Published public var spinDegree: Double = 0
    @Published public var hoveredAccountId: String? = nil

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

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func handleLanguageChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.currentLanguage = LocalizationManager.shared.currentLanguage
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
    }

    public var activeAccount: AccountStatus? {
        return accounts.first(where: { $0.isCurrent })
    }

    public var standbyAccounts: [AccountStatus] {
        return accounts.filter { !$0.isCurrent }
    }
}

// MARK: - Main Popover View
public struct OrbitPopoverView: View {
    @ObservedObject public var viewModel: OrbitViewModel

    public init(viewModel: OrbitViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 1. Header Toolbar
            HeaderToolbar(viewModel: viewModel)

            Divider()
                .opacity(0.5)

            // 2. Active Account Hero Card or Empty State
            if let active = viewModel.activeAccount {
                ActiveAccountHeroCard(account: active, viewModel: viewModel)
            } else if viewModel.accounts.isEmpty {
                NoAccountsView(viewModel: viewModel)
            } else {
                NoActiveAccountBanner(viewModel: viewModel)
            }

            // 3. Standby Accounts List
            if !viewModel.standbyAccounts.isEmpty {
                StandbyAccountsSection(viewModel: viewModel)
            }

            // 4. Controls & Rotation
            if !viewModel.accounts.isEmpty {
                ControlsSection(viewModel: viewModel)
            }

            // 5. Footer Shortcuts & System
            FooterBar(viewModel: viewModel)
        }
        .padding(14)
        .frame(width: 340)
        .background(VisualEffectBackground().ignoresSafeArea())
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

// MARK: - Header Toolbar
private struct HeaderToolbar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack(spacing: 8) {
            // App Logo
            if let img = loadStatusBarLogo() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "bolt.circle.fill")
                    .resizable()
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Antigravity Orbit")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    Text("v1.0")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }

                Text(accountCountText)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Refresh Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.6)) {
                    viewModel.spinDegree += 360
                }
                viewModel.onRefresh?()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(viewModel.spinDegree))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(L10n.tr("menu.refresh_quota"))

            // Settings Button
            Button(action: {
                viewModel.onOpenSettings?(nil)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(L10n.tr("menu.settings"))

            // Quit Button
            Button(action: {
                viewModel.onQuit?()
            }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(L10n.tr("menu.quit"))
        }
    }

    private var accountCountText: String {
        let count = viewModel.accounts.count
        if count == 0 {
            return L10n.tr("menu.tooltip_no_accounts")
        } else if count == 1 {
            return "1 \(L10n.tr("settings.tab_accounts").lowercased())"
        } else {
            return "\(count) \(L10n.tr("settings.tab_accounts").lowercased())"
        }
    }

    private func loadStatusBarLogo() -> NSImage? {
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

// MARK: - Active Account Hero Card
private struct ActiveAccountHeroCard: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 9) {
            // Row 1: Active Pulse Indicator & Tier Badge
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)

                    Text(L10n.tr("menu.active_account").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }

                Spacer()

                Text(account.displayTierName)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.18))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                    )
            }

            // Row 2: Avatar & Account Names
            HStack(spacing: 8) {
                // Avatar with initial letter
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Text(avatarLetter)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayName(showAlias: viewModel.showAccountAlias))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if viewModel.showAccountAlias || account.name != account.email {
                        Text(account.email)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            // Row 3: Quota Gauges Box
            VStack(spacing: 7) {
                // 5-Hour Limit
                VStack(spacing: 3) {
                    HStack {
                        Text(L10n.tr("popover.5h_limit"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        if let countdown = formatCountdown(account.geminiResetTime) {
                            Text("(Reset: \(countdown))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Text("\(pct5h)%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(quotaColor(pct5h))
                    }

                    // Progress Bar 5h
                    QuotaProgressBar(percentage: pct5h, height: 7, tintColor: quotaColor(pct5h))
                }

                // Weekly Limit (if available)
                if let weekly = account.geminiWeeklyPercentage {
                    VStack(spacing: 3) {
                        HStack {
                            Text(L10n.tr("popover.weekly_limit"))
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(weekly)%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        QuotaProgressBar(percentage: weekly, height: 5, tintColor: Color.blue.opacity(0.8))
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // Row 4: Inline Model Selector Menu
            HStack {
                Text(L10n.tr("popover.model_label"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden)
            }
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor).opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var avatarLetter: String {
        let name = account.displayName(showAlias: viewModel.showAccountAlias)
        if let first = name.first {
            return String(first).uppercased()
        }
        return "A"
    }

    private var pct5h: Int {
        return account.gemini5hPercentage ?? account.remainingPercentage
    }

    private func quotaColor(_ pct: Int) -> Color {
        if pct < 0 { return .red }
        if pct <= viewModel.thresholdPercentage { return .red }
        if pct <= 30 { return .orange }
        return .green
    }

    private func formatCountdown(_ isoString: String?) -> String? {
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
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
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

// MARK: - Standby Accounts Section
private struct StandbyAccountsSection: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 6) {
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
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 2)

            VStack(spacing: 4) {
                ForEach(viewModel.standbyAccounts, id: \.id) { acc in
                    StandbyAccountRow(account: acc, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Standby Account Row
private struct StandbyAccountRow: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    private var isHovered: Bool {
        return viewModel.hoveredAccountId == account.id
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status Dot
            Text(statusDot)
                .font(.system(size: 8))

            // Info
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName(showAlias: viewModel.showAccountAlias))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(quotaSubtext)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Quota %
            Text("\(pct)%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(pctColor)

            // Switch Button (Visible on hover or compact)
            Button(action: {
                viewModel.onSwitchAccount?(account.id)
            }) {
                Text(L10n.tr("popover.btn_switch"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(isHovered ? 0.9 : 0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered ? 1.0 : 0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color(NSColor.textBackgroundColor).opacity(0.2))
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
        if pct < 0 { return "🔴" }
        if pct <= viewModel.thresholdPercentage { return "🔴" }
        if pct <= 30 { return "🟡" }
        return "🟢"
    }

    private var pctColor: Color {
        if pct < 0 || pct <= viewModel.thresholdPercentage { return .red }
        if pct <= 30 { return .orange }
        return .green
    }

    private var quotaSubtext: String {
        if let wk = account.geminiWeeklyPercentage {
            return "5h: \(pct)% • \(L10n.tr("menu.week_label", wk))"
        }
        return "5h: \(pct)%"
    }
}

// MARK: - Controls Section
private struct ControlsSection: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Auto Rotate Toggle
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(L10n.tr("settings.auto_rotate_title"))
                    .font(.system(size: 11))
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.autoRotateEnabled },
                    set: { _ in viewModel.onToggleAutoRotate?() }
                ))
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.75)
                .labelsHidden()
            }
            .padding(.horizontal, 2)

            // Primary Action Button: Rotate Now (⌘R)
            Button(action: {
                viewModel.onRotateNow?()
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))

                    Text(L10n.tr("menu.rotate_now"))
                        .font(.system(size: 11.5, weight: .semibold))

                    Spacer()

                    Text("⌘R")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(3)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(7)
                .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.top, 2)
    }
}

// MARK: - Empty States
private struct NoAccountsView: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 26))
                .foregroundColor(.secondary)

            Text(L10n.tr("settings.no_accounts_linked"))
                .font(.system(size: 12, weight: .semibold))

            Text(L10n.tr("settings.no_accounts_desc"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.onLoginBrowserOAuth?()
                }) {
                    Text(L10n.tr("settings.btn_login_browser"))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    viewModel.onOpenSettings?(0)
                }) {
                    Text(L10n.tr("menu.account_settings"))
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        .cornerRadius(10)
    }
}

private struct NoActiveAccountBanner: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("⚠️")
                Text(L10n.tr("menu.unidentified_account"))
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
            }

            if let first = viewModel.accounts.first {
                Button(action: {
                    viewModel.onSwitchAccount?(first.id)
                }) {
                    Text(L10n.tr("popover.activate_account", first.displayName(showAlias: viewModel.showAccountAlias)))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .cornerRadius(8)
    }
}

// MARK: - Footer Bar
private struct FooterBar: View {
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        HStack {
            // Quick Language Menu
            Picker("", selection: Binding(
                get: { viewModel.currentLanguage },
                set: { lang in viewModel.onSelectLanguage?(lang) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .controlSize(.small)

            Spacer()

            // Subtle Shortcuts
            HStack(spacing: 6) {
                Text(L10n.tr("popover.shortcut_rotate"))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.system(size: 8))

                Text(L10n.tr("popover.shortcut_settings"))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .onTapGesture {
                        viewModel.onOpenSettings?(nil)
                    }
            }
        }
        .padding(.top, 2)
    }
}
