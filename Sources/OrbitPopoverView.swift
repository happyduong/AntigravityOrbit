import SwiftUI
import AppKit

// MARK: - Toolbar Tooltip Enum
public enum ToolbarTooltip: Equatable {
    case refresh
    case settings
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
        StreamlinedPopoverView(viewModel: viewModel)
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
public struct AccountModelSelectorMenu: View {
    let account: AccountStatus
    let onSelectModel: ((String, String) -> Void)?

    public init(account: AccountStatus, onSelectModel: ((String, String) -> Void)?) {
        self.account = account
        self.onSelectModel = onSelectModel
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(L10n.tr("popover.model_label"))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            // Inline Model Menu
            Menu {
                Toggle(isOn: Binding(
                    get: { account.isModelSelected("") },
                    set: { _ in onSelectModel?(account.id, "") }
                )) {
                    if account.isCurrent, let active = account.activeModel, !active.isEmpty, account.isModelSelected("") {
                        Text("\(L10n.tr("model.auto")) (\(active))")
                            .font(.system(size: 10.5, weight: .medium))
                    } else {
                        Text(L10n.tr("model.auto"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }

                Section("Google Gemini") {
                    ForEach(AIModelCatalog.geminiModels, id: \.id) { opt in
                        Toggle(isOn: Binding(
                            get: { account.isModelSelected(opt.id) },
                            set: { _ in onSelectModel?(account.id, opt.id) }
                        )) {
                            Text(opt.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                }

                Section("Anthropic Claude") {
                    ForEach(AIModelCatalog.claudeModels, id: \.id) { opt in
                        Toggle(isOn: Binding(
                            get: { account.isModelSelected(opt.id) },
                            set: { _ in onSelectModel?(account.id, opt.id) }
                        )) {
                            Text(opt.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                }

                Section(L10n.tr("model.group_other")) {
                    ForEach(AIModelCatalog.otherModels, id: \.id) { opt in
                        Toggle(isOn: Binding(
                            get: { account.isModelSelected(opt.id) },
                            set: { _ in onSelectModel?(account.id, opt.id) }
                        )) {
                            Text(opt.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                }

                if !account.isModelSelected(""),
                   let customId = account.preferredModelId,
                   !AIModelCatalog.allModels.contains(where: { account.isModelSelected($0.id) }) {
                    Section(L10n.tr("model.group_other")) {
                        Toggle(isOn: Binding(
                            get: { true },
                            set: { _ in onSelectModel?(account.id, customId) }
                        )) {
                            Text(AIModelCatalog.displayName(forId: customId))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("🤖 \(account.displayModelName)")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7))
                        .opacity(0.6)
                }
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
        }
    }
}

private struct ReusableModelSelectorMenu: View {
    let account: AccountStatus
    @ObservedObject var viewModel: OrbitViewModel

    var body: some View {
        AccountModelSelectorMenu(account: account, onSelectModel: viewModel.onSelectModel)
    }
}

// MARK: - Tooltip Dynamic Arrow Components
public enum TooltipArrowDirection: Sendable {
    case up
    case down
}

public enum TooltipArrowPosition: Sendable {
    case center
    case leading
    case trailing
}

private struct TooltipArrowShape: Shape {
    let direction: TooltipArrowDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .up:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + 1))
            path.closeSubpath()
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY - 1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 1))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private struct TooltipArrowBorder: Shape {
    let direction: TooltipArrowDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .up:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

private struct TooltipArrowView: View {
    let direction: TooltipArrowDirection
    let position: TooltipArrowPosition

    private let arrowWidth: CGFloat = 8
    private let arrowHeight: CGFloat = 4
    private let sideInset: CGFloat = 7

    var body: some View {
        HStack(spacing: 0) {
            if position == .trailing || position == .center {
                Spacer(minLength: 0)
            }

            ZStack {
                TooltipArrowShape(direction: direction)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.96))

                TooltipArrowBorder(direction: direction)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: arrowWidth, height: arrowHeight)
            .padding(.leading, position == .leading ? sideInset : 0)
            .padding(.trailing, position == .trailing ? sideInset : 0)

            if position == .leading || position == .center {
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Dynamic Arrow Tooltip View
private struct DynamicArrowTooltipView: View {
    let text: String
    let arrowDirection: TooltipArrowDirection
    let arrowPosition: TooltipArrowPosition

    var body: some View {
        VStack(spacing: 0) {
            if arrowDirection == .up {
                TooltipArrowView(direction: .up, position: arrowPosition)
                    .zIndex(2)

                bubbleContent
                    .zIndex(1)
            } else {
                bubbleContent
                    .zIndex(1)

                TooltipArrowView(direction: .down, position: arrowPosition)
                    .zIndex(2)
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 7, x: 0, y: 1.5)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private var bubbleContent: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

// MARK: - Instant Tooltip ViewModifier
private struct InstantTooltipModifier: ViewModifier {
    let tooltip: ToolbarTooltip
    let text: String
    let alignment: Alignment
    let offsetY: CGFloat
    @ObservedObject var viewModel: OrbitViewModel

    private var arrowDirection: TooltipArrowDirection {
        return offsetY < 0 ? .down : .up
    }

    private var arrowPosition: TooltipArrowPosition {
        if alignment == .bottomTrailing || alignment == .topTrailing || alignment == .trailing {
            return .trailing
        } else if alignment == .bottomLeading || alignment == .topLeading || alignment == .leading {
            return .leading
        } else {
            return .center
        }
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    if hovering {
                        viewModel.activeToolbarTooltip = tooltip
                    } else if viewModel.activeToolbarTooltip == tooltip {
                        viewModel.activeToolbarTooltip = nil
                    }
                }
            }
            .overlay(
                Group {
                    if viewModel.activeToolbarTooltip == tooltip {
                        DynamicArrowTooltipView(
                            text: text,
                            arrowDirection: arrowDirection,
                            arrowPosition: arrowPosition
                        )
                        .offset(y: offsetY)
                        .transition(.opacity)
                        .zIndex(999)
                    }
                },
                alignment: alignment
            )
    }
}

private extension View {
    func instantTooltip(
        _ tooltip: ToolbarTooltip,
        text: String,
        viewModel: OrbitViewModel,
        alignment: Alignment = .bottom,
        offsetY: CGFloat = 22
    ) -> some View {
        self.modifier(
            InstantTooltipModifier(
                tooltip: tooltip,
                text: text,
                alignment: alignment,
                offsetY: offsetY,
                viewModel: viewModel
            )
        )
    }
}

// MARK: - Standby Account Instant Tooltip
private struct StandbyAccountTooltipView: View {
    var body: some View {
        DynamicArrowTooltipView(
            text: L10n.tr("menu.switch_to_account"),
            arrowDirection: .down,
            arrowPosition: .center
        )
    }
}

// MARK: - Quota Progress Bar
public struct QuotaProgressBar: View {
    public let percentage: Int
    public let height: CGFloat
    public let tintColor: Color

    public init(percentage: Int, height: CGFloat, tintColor: Color) {
        self.percentage = percentage
        self.height = height
        self.tintColor = tintColor
    }

    public var body: some View {
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
                .zIndex(100)

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
                    .zIndex(90)
            }

            // 4. Unified Control Bar (1 Row)
            if !viewModel.accounts.isEmpty {
                StreamlinedControlBar(viewModel: viewModel)
            }
        }
        .padding(12)
        .frame(width: 340)
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(active.displayName(showAlias: viewModel.showAccountAlias))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(active.displayTierName)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
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
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .instantTooltip(.refresh, text: L10n.tr("popover.tooltip_refresh"), viewModel: viewModel)

                // Settings Button
                Button(action: {
                    viewModel.onOpenSettings?(nil)
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .instantTooltip(.settings, text: L10n.tr("popover.tooltip_settings"), viewModel: viewModel)

                // Quit Button
                Button(action: {
                    viewModel.onQuit?()
                }) {
                    Image(systemName: "escape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .scaleEffect(x: -1)
                }
                .buttonStyle(PlainButtonStyle())
                .instantTooltip(.quit, text: L10n.tr("popover.tooltip_quit"), viewModel: viewModel, alignment: .bottomTrailing)
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
                ReusableModelSelectorMenu(account: account, viewModel: viewModel)
                Spacer()
            }
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
                        .foregroundColor(.secondary)
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color(NSColor.textBackgroundColor).opacity(0.18))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                if hovering {
                    viewModel.hoveredAccountId = account.id
                } else if viewModel.hoveredAccountId == account.id {
                    viewModel.hoveredAccountId = nil
                }
            }
        }
        .onTapGesture {
            viewModel.onSwitchAccount?(account.id)
        }
        .overlay(
            Group {
                if isHovered {
                    StandbyAccountTooltipView()
                        .offset(y: -20)
                        .transition(.opacity)
                        .zIndex(999)
                }
            },
            alignment: .top
        )
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

            Spacer()

            // Auto Rotate Toggle
            Toggle(isOn: Binding(
                get: { viewModel.autoRotateEnabled },
                set: { _ in viewModel.onToggleAutoRotate?() }
            )) {
                Text(String(format: L10n.tr("popover.auto_rotate_short"), viewModel.thresholdPercentage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(SwitchToggleStyle())
            .scaleEffect(0.72, anchor: .trailing)
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
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
