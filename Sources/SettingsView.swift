import SwiftUI
import AppKit

// MARK: - Settings Tab Enumeration
public enum SettingsTab: Int, CaseIterable {
    case accounts = 0
    case rotation = 1
    case system = 2
    case about = 3

    public var title: String {
        switch self {
        case .accounts: return L10n.tr("settings.tab_accounts").trimmingCharacters(in: .whitespaces)
        case .rotation: return L10n.tr("settings.tab_rotation").trimmingCharacters(in: .whitespaces)
        case .system: return L10n.tr("settings.tab_system").trimmingCharacters(in: .whitespaces)
        case .about: return L10n.tr("menu.about").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
        }
    }

    public var icon: String {
        switch self {
        case .accounts: return "person.2.fill"
        case .rotation: return "arrow.triangle.2.circlepath"
        case .system: return "gearshape.fill"
        case .about: return "info.circle.fill"
        }
    }

    public var iconColor: Color {
        switch self {
        case .accounts: return .blue
        case .rotation: return .orange
        case .system: return .gray
        case .about: return .purple
        }
    }
}

// MARK: - Settings View Model
public class SettingsViewModel: ObservableObject {
    @Published public var selectedTab: SettingsTab = .accounts
    @Published public var accounts: [AccountStatus] = []
    @Published public var autoRotateEnabled: Bool = ConfigManager.shared.config.autoRotateEnabled
    @Published public var thresholdPercentage: Int = ConfigManager.shared.config.thresholdPercentage
    @Published public var checkIntervalSeconds: Int = ConfigManager.shared.config.checkIntervalSeconds
    @Published public var showAccountAlias: Bool = ConfigManager.shared.config.showAccountAlias
    @Published public var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @Published public var notificationsEnabled: Bool = ConfigManager.shared.config.notificationsEnabled
    @Published public var soundEnabled: Bool = ConfigManager.shared.config.soundEnabled
    @Published public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    @Published public var hoveredAccountId: String? = nil

    // Action Closures
    public var onRefreshQuotas: (() -> Void)?
    public var onSetActiveAccount: ((String) -> Void)?
    public var onEditAlias: ((AccountStatus) -> Void)?
    public var onSelectModel: ((String, String) -> Void)?
    public var onDeleteAccount: ((AccountStatus) -> Void)?
    public var onAddBrowserOAuth: (() -> Void)?
    public var onAddFromIde: (() -> Void)?
    public var onAddFromJson: (() -> Void)?
    public var onToggleAutoRotate: (() -> Void)?
    public var onUpdateThreshold: ((Int) -> Void)?
    public var onUpdateInterval: ((Int) -> Void)?
    public var onToggleShowAlias: (() -> Void)?
    public var onToggleLaunchAtLogin: (() -> Void)?
    public var onToggleNotifications: (() -> Void)?
    public var onToggleSound: (() -> Void)?
    public var onSetLanguage: ((AppLanguage) -> Void)?
    public var onOpenDesktopApp: (() -> Void)?
    public var onOpenIde: (() -> Void)?

    public init() {
        syncFromConfig()
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
    }

    @objc private func handleLanguageChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentLanguage = LocalizationManager.shared.currentLanguage
            self.objectWillChange.send()
        }
    }

    @objc private func handleAvatarChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func syncFromConfig() {
        let cfg = ConfigManager.shared.config
        self.autoRotateEnabled = cfg.autoRotateEnabled
        self.thresholdPercentage = cfg.thresholdPercentage
        self.checkIntervalSeconds = cfg.checkIntervalSeconds
        self.showAccountAlias = cfg.showAccountAlias
        self.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        self.notificationsEnabled = cfg.notificationsEnabled
        self.soundEnabled = cfg.soundEnabled
        self.currentLanguage = LocalizationManager.shared.currentLanguage
    }

    public func updateAccounts(accounts: [AccountStatus]) {
        self.accounts = accounts
    }
}

// MARK: - Main Settings View (macOS Sidebar Split-View Layout)
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar (~210px)
            SettingsSidebarView(viewModel: viewModel)
                .frame(width: 215)
                .background(VisualEffectBackground())

            Divider()
                .opacity(0.4)

            // Right Content Area
            SettingsContentView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 740, minHeight: 540)
    }
}

// MARK: - Sidebar View
private struct SettingsSidebarView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Text(L10n.tr("settings.sidebar_config"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 2)

            // Navigation List Items
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SidebarTabButton(
                    tab: tab,
                    isSelected: viewModel.selectedTab == tab,
                    count: tab == .accounts ? viewModel.accounts.count : nil
                ) {
                    viewModel.selectedTab = tab
                }
            }

            Spacer()

            // Service Status Card at Bottom of Sidebar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)

                    Text("Local Proxy 8045")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(L10n.tr("settings.proxy_status_desc"))
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
            )
            .padding(10)
        }
    }
}

private struct SidebarTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // SF Symbol with Rounded Box
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(tab.iconColor.opacity(isSelected ? 0.9 : 0.8))
                        .frame(width: 22, height: 22)

                    Image(systemName: tab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
}

// MARK: - Content View Router
private struct SettingsContentView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.selectedTab {
            case .accounts:
                AccountsTabPane(viewModel: viewModel)
            case .rotation:
                RotationTabPane(viewModel: viewModel)
            case .system:
                SystemTabPane(viewModel: viewModel)
            case .about:
                AboutTabPane(viewModel: viewModel)
            }
        }
        .padding(20)
    }
}

// MARK: - Tab 1: Accounts Management Pane
private struct AccountsTabPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("settings.tab_accounts"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    Text(L10n.tr("settings.accounts_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Add Account Menu Button
                Menu {
                    Button(action: {
                        viewModel.onAddBrowserOAuth?()
                    }) {
                        HStack {
                            Text("🌐 \(L10n.tr("settings.btn_login_browser"))")
                        }
                    }

                    Button(action: {
                        viewModel.onAddFromIde?()
                    }) {
                        HStack {
                            Text("⚡ \(L10n.tr("settings.btn_import_ide"))")
                        }
                    }

                    Button(action: {
                        viewModel.onAddFromJson?()
                    }) {
                        HStack {
                            Text("📄 \(L10n.tr("settings.btn_import_json"))")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(L10n.tr("settings.btn_add_account"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden)
            }

            // Options Bar (Alias Toggle & Refresh)
            HStack {
                Toggle(isOn: Binding(
                    get: { viewModel.showAccountAlias },
                    set: { _ in viewModel.onToggleShowAlias?() }
                )) {
                    Text(L10n.tr("settings.show_alias_checkbox"))
                        .font(.system(size: 11.5))
                        .foregroundColor(.primary)
                }
                .toggleStyle(CheckboxToggleStyle())

                Spacer()

                Button(action: {
                    viewModel.onRefreshQuotas?()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text(L10n.tr("menu.refresh_quota"))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 2)

            // Accounts List or Empty State
            if viewModel.accounts.isEmpty {
                SettingsEmptyAccountsView(viewModel: viewModel)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.accounts, id: \.id) { acc in
                            SettingsAccountCard(account: acc, viewModel: viewModel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Settings Account Card
private struct SettingsAccountCard: View {
    let account: AccountStatus
    @ObservedObject var viewModel: SettingsViewModel

    private var isHovered: Bool {
        return viewModel.hoveredAccountId == account.id
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top Row: Avatar, Name, Email, Status Pill & Tier
            HStack(spacing: 9) {
                AccountAvatarView(
                    accountId: account.id,
                    pictureUrl: account.picture,
                    displayName: account.displayName(showAlias: viewModel.showAccountAlias),
                    isCurrent: account.isCurrent,
                    size: 26
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(account.displayName(showAlias: viewModel.showAccountAlias))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(account.displayTierName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                    }

                    if viewModel.showAccountAlias || account.name != account.email {
                        Text(account.email)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if account.isCurrent {
                    Text(L10n.tr("settings.sub_active").uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                } else {
                    Text(L10n.tr("settings.sub_standby"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                }
            }

            // Middle Row: Dual Quota Progress Bars
            HStack(spacing: 12) {
                // 5h Quota
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(L10n.tr("popover.5h_limit"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(pct5h)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(quotaColor(pct5h))
                    }
                    CapsuleProgressBar(percentage: pct5h, height: 6, tintColor: quotaColor(pct5h))
                }
                .padding(7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(6)

                // Weekly Quota
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(L10n.tr("popover.weekly_limit"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(account.geminiWeeklyPercentage ?? 100)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.blue)
                    }
                    CapsuleProgressBar(percentage: account.geminiWeeklyPercentage ?? 100, height: 6, tintColor: Color.blue.opacity(0.8))
                }
                .padding(7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(6)
            }

            // Bottom Row: Model Info & Actions
            HStack {
                AccountModelSelectorMenu(account: account, onSelectModel: viewModel.onSelectModel)

                Spacer()

                // Action Buttons
                HStack(spacing: 6) {
                    Button(action: {
                        viewModel.onEditAlias?(account)
                    }) {
                        Text(L10n.tr("settings.btn_edit_alias").replacingOccurrences(of: "...", with: ""))
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if !account.isCurrent {
                        Button(action: {
                            viewModel.onSetActiveAccount?(account.id)
                        }) {
                            Text(L10n.tr("settings.btn_activate"))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            viewModel.onDeleteAccount?(account)
                        }) {
                            Text(L10n.tr("settings.btn_delete_account"))
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .background(account.isCurrent ? Color.green.opacity(0.04) : Color(NSColor.controlBackgroundColor).opacity(0.25))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(account.isCurrent ? Color.green.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
        )
        .onHover { hovering in
            if hovering {
                viewModel.hoveredAccountId = account.id
            } else if viewModel.hoveredAccountId == account.id {
                viewModel.hoveredAccountId = nil
            }
        }
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
}

private struct CapsuleProgressBar: View {
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
            }
        }
        .frame(height: height)
    }

    private var clamped: Int {
        return max(0, min(100, percentage))
    }
}

private struct SettingsEmptyAccountsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 38))
                .foregroundColor(.secondary)

            Text(L10n.tr("settings.no_accounts_linked"))
                .font(.system(size: 14, weight: .bold))

            Text(L10n.tr("settings.no_accounts_desc"))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 10) {
                Button(action: {
                    viewModel.onAddBrowserOAuth?()
                }) {
                    Text(L10n.tr("settings.btn_login_browser"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    viewModel.onAddFromIde?()
                }) {
                    Text(L10n.tr("settings.btn_import_ide"))
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
        .cornerRadius(10)
    }
}

// MARK: - Tab 2: Rotation Settings Pane
private struct RotationTabPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("settings.rotation_strategy"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text(L10n.tr("settings.rotation_subtitle"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Grouped Settings Card
            VStack(spacing: 12) {
                // Auto Rotate Switch
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.auto_rotate_title"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(L10n.tr("settings.auto_rotate_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.autoRotateEnabled },
                        set: { _ in viewModel.onToggleAutoRotate?() }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }

                Divider()
                    .opacity(0.5)

                // Threshold Selector
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.tr("settings.threshold_label"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(viewModel.thresholdPercentage)%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack(spacing: 6) {
                        ForEach([5, 10, 15, 20, 25], id: \.self) { val in
                            Button(action: {
                                viewModel.onUpdateThreshold?(val)
                            }) {
                                Text("\(val)%")
                                    .font(.system(size: 11, weight: viewModel.thresholdPercentage == val ? .bold : .regular, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(viewModel.thresholdPercentage == val ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(viewModel.thresholdPercentage == val ? .white : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    Text(L10n.tr("settings.threshold_desc"))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .opacity(0.5)

                // Interval Picker
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.interval_label"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Text(L10n.tr("settings.interval_desc"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("", selection: Binding(
                        get: { viewModel.checkIntervalSeconds },
                        set: { val in viewModel.onUpdateInterval?(val) }
                    )) {
                        Text(String(format: L10n.tr("settings.interval_seconds"), 30)).tag(30)
                        Text(String(format: L10n.tr("settings.interval_seconds"), 60)).tag(60)
                        Text(String(format: L10n.tr("settings.interval_minutes"), 2)).tag(120)
                        Text(String(format: L10n.tr("settings.interval_minutes"), 5)).tag(300)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 160)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
            )

            // Rotation Note Card
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .padding(.top, 1)

                Text(L10n.tr("settings.rotation_note"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)

            Spacer()
        }
    }
}

// MARK: - Tab 3: System Settings Pane
private struct SystemTabPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("settings.tab_system"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text(L10n.tr("settings.system_subtitle"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Grouped Settings Card
            VStack(spacing: 12) {
                // Language Selection
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.language_section"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(L10n.tr("settings.language_instant_note"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("", selection: Binding(
                        get: { viewModel.currentLanguage },
                        set: { lang in viewModel.onSetLanguage?(lang) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 170)
                }

                Divider()
                    .opacity(0.5)

                // Launch at Login Switch
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.launch_at_login"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Text(L10n.tr("settings.launch_at_login_desc"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { _ in viewModel.onToggleLaunchAtLogin?() }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }

                Divider()
                    .opacity(0.5)

                // Notifications Switch
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.notifications_section"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Text(L10n.tr("settings.enable_notifications"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.notificationsEnabled },
                        set: { _ in viewModel.onToggleNotifications?() }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }

                Divider()
                    .opacity(0.5)

                // Sound Switch
                HStack {
                    Text(L10n.tr("settings.enable_sound"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.soundEnabled },
                        set: { _ in viewModel.onToggleSound?() }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
            )

            // Quick App Launchers Card
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("settings.quick_links"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.onOpenDesktopApp?()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                            Text(L10n.tr("settings.open_app"))
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        viewModel.onOpenIde?()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text(L10n.tr("settings.open_ide"))
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Spacer()
        }
    }
}

// MARK: - Tab 4: About & Credits Pane
private struct AboutTabPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // App Icon
            if let icon = loadSettingsAppIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
                    .shadow(radius: 6)
            } else {
                Image(systemName: "bolt.circle.fill")
                    .resizable()
                    .foregroundColor(.accentColor)
                    .frame(width: 64, height: 64)
            }

            Text("Antigravity Orbit for macOS")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            Text(L10n.tr("about.app_version"))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)

            Text(L10n.tr("about.app_desc"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Info Card
            VStack(spacing: 6) {
                HStack {
                    Text(L10n.tr("about.author_label"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Happy Duong (phucduongqb@gmail.com)")
                        .fontWeight(.medium)
                }
                Divider().opacity(0.4)
                HStack {
                    Text(L10n.tr("about.license_label"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("MIT Open Source License")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .font(.system(size: 11))
            .padding(12)
            .frame(maxWidth: 420)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadSettingsAppIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon1024", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSApp.applicationIconImage
    }
}

