import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI

public class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHostingController: NSHostingController<OrbitPopoverView>!
    private var viewModel: OrbitViewModel!
    private var timer: Timer?
    private var accountStatuses: [AccountStatus] = []
    private var isRefreshing = false
    private var lastPopoverCloseTime: Date = Date.distantPast

    public override init() {
        super.init()
        _ = AccountManager.shared

        setupViewModel()
        setupPopover()
        setupStatusItem()
        startTimer()
        refreshQuotas()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }

    // MARK: - Setup Components

    private func setupViewModel() {
        viewModel = OrbitViewModel()

        viewModel.onRefresh = { [weak self] in
            self?.refreshQuotas()
        }
        viewModel.onRotateNow = { [weak self] in
            self?.manualRotateNext()
        }
        viewModel.onSwitchAccount = { [weak self] accountId in
            self?.manualSwitchAccountById(accountId)
        }
        viewModel.onSelectModel = { [weak self] accountId, modelId in
            self?.updateModelForAccount(accountId: accountId, modelId: modelId)
        }
        viewModel.onToggleAutoRotate = { [weak self] in
            self?.toggleAutoRotate()
        }
        viewModel.onOpenSettings = { [weak self] tab in
            self?.showSettingsWindowWithTab(tab)
        }
        viewModel.onOpenAbout = { [weak self] in
            self?.showAboutWindow()
        }
        viewModel.onQuit = { [weak self] in
            self?.quitApp()
        }
        viewModel.onSelectLanguage = { [weak self] lang in
            LocalizationManager.shared.setLanguage(lang)
            self?.handleLanguageChange()
        }
        viewModel.onLoginBrowserOAuth = { [weak self] in
            self?.actionLoginBrowserOAuth()
        }
        viewModel.onImportIde = { [weak self] in
            self?.actionImportFromIde()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = OrbitPopoverView(viewModel: viewModel)
        popoverHostingController = NSHostingController(rootView: rootView)
        popover.contentViewController = popoverHostingController
        popover.contentSize = NSSize(width: 340, height: 460)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let logo = loadAppLogo() {
                button.image = logo
                button.imagePosition = .imageLeft
            }
            let font = NSFont.menuBarFont(ofSize: 0)
            let attrTitle = NSMutableAttributedString(string: "--% ", attributes: [.font: font])
            attrTitle.append(NSAttributedString(string: "⚪", attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .baselineOffset: 1.5
            ]))
            button.attributedTitle = attrTitle
            button.toolTip = "Antigravity Orbit"

            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Status Bar Button & Popover Interaction

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Prevent immediate reopen if user clicked status item to dismiss
            if Date().timeIntervalSince(lastPopoverCloseTime) < 0.25 {
                return
            }
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        updateViewModelState()
        popover.contentViewController = popoverHostingController
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTime = Date()
    }

    // MARK: - Quota & Timer

    private func startTimer() {
        timer?.invalidate()
        let interval = Double(ConfigManager.shared.config.checkIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshQuotas()
        }
    }

    @objc public func refreshQuotas() {
        guard !isRefreshing else { return }
        isRefreshing = true
        updateViewModelState()

        QuotaService.shared.fetchAllQuotas { [weak self] statuses in
            guard let self = self else { return }
            self.isRefreshing = false
            self.accountStatuses = statuses

            DispatchQueue.main.async {
                self.updateStatusBarDisplay()
                self.updateViewModelState()
                self.checkAutoRotationThreshold()
                SettingsWindowController.shared.updateAccounts(accounts: statuses)
            }
        }
    }

    private func updateViewModelState() {
        viewModel.update(
            accounts: accountStatuses,
            isRefreshing: isRefreshing,
            autoRotate: ConfigManager.shared.config.autoRotateEnabled,
            threshold: ConfigManager.shared.config.thresholdPercentage
        )
    }

    private func updateStatusBarDisplay() {
        guard let button = statusItem.button else { return }

        if button.image == nil {
            if let logo = loadAppLogo() {
                button.image = logo
                button.imagePosition = .imageLeft
            }
        }

        let current = accountStatuses.first(where: { $0.isCurrent })

        let levelIcon: String
        let titleText: String

        if let current = current {
            let pct = current.remainingPercentage
            if pct < 0 {
                levelIcon = "🔴"
                titleText = "ERR"
            } else {
                let threshold = ConfigManager.shared.config.thresholdPercentage
                if pct <= threshold {
                    levelIcon = "🔴"
                } else if pct <= 30 {
                    levelIcon = "🟡"
                } else {
                    levelIcon = "🟢"
                }
                titleText = "\(pct)%"
            }

            let modelName = current.activeModel ?? QuotaService.shared.getCurrentAntigravityModel()
            let accountDisplay = current.currentDisplayName
            if pct < 0 {
                button.toolTip = L10n.tr("menu.tooltip_error", accountDisplay)
            } else if let wk = current.geminiWeeklyPercentage {
                let weekStr = L10n.tr("menu.week_label", wk)
                button.toolTip = "Antigravity Orbit: \(accountDisplay)\nModel: \(modelName)\n(5h: \(pct)% • \(weekStr))"
            } else {
                button.toolTip = "Antigravity Orbit: \(accountDisplay)\nModel: \(modelName)\n(5h: \(pct)%)"
            }
        } else {
            levelIcon = "⚪"
            titleText = "--%"
            if accountStatuses.isEmpty {
                button.toolTip = L10n.tr("menu.tooltip_no_accounts")
            } else {
                button.toolTip = L10n.tr("menu.tooltip_no_active")
            }
        }

        let font = NSFont.menuBarFont(ofSize: 0)
        let attrTitle = NSMutableAttributedString(string: "\(titleText) ", attributes: [
            .font: font
        ])
        let iconAttr = NSAttributedString(string: levelIcon, attributes: [
            .font: NSFont.systemFont(ofSize: 7),
            .baselineOffset: 1.5
        ])
        attrTitle.append(iconAttr)
        button.attributedTitle = attrTitle
    }

    private func loadAppLogo() -> NSImage? {
        var image: NSImage?
        if let path = Bundle.main.path(forResource: "StatusBarLogo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            image = img
        } else if let path = Bundle.main.path(forResource: "AppIcon1024", ofType: "png"),
                  let img = NSImage(contentsOfFile: path) {
            image = img
        } else if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                  let img = NSImage(contentsOfFile: path) {
            image = img
        } else if let img = NSImage(named: "AppIcon") {
            image = img
        } else if let img = NSApp.applicationIconImage {
            image = img
        } else {
            let directCandidates = [
                "/Applications/Antigravity Orbit.app/Contents/Resources/StatusBarLogo.png",
                "/Applications/Antigravity Orbit.app/Contents/Resources/AppIcon1024.png",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AntigravityOrbit/Resources/StatusBarLogo.png").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AntigravityOrbit/Resources/AppIcon1024.png").path
            ]
            for path in directCandidates {
                if let img = NSImage(contentsOfFile: path) {
                    image = img
                    break
                }
            }
        }

        guard let original = image else { return nil }
        let resized = original.copy() as! NSImage
        resized.size = NSSize(width: 21, height: 21)
        resized.isTemplate = false
        return resized
    }

    private func checkAutoRotationThreshold() {
        guard ConfigManager.shared.config.autoRotateEnabled else { return }
        guard let current = accountStatuses.first(where: { $0.isCurrent }) else { return }

        let threshold = ConfigManager.shared.config.thresholdPercentage
        if current.remainingPercentage >= 0 && current.remainingPercentage <= threshold {
            print("[StatusBarController] Current account \(current.currentDisplayName) has \(current.remainingPercentage)% 5h-limit (<= \(threshold)%). Triggering auto-rotation...")
            let reason = L10n.tr("notif.reason_low_token", current.remainingPercentage, threshold)
            AccountRotator.shared.rotateToNext(currentStatuses: accountStatuses, reason: reason) { [weak self] success, newAcc in
                if success {
                    self?.refreshQuotas()
                }
            }
        }
    }

    @objc private func handleLanguageChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateStatusBarDisplay()
            self.updateViewModelState()
        }
    }

    // MARK: - Actions

    @objc public func manualRotateNext() {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        guard hasActiveAccount && accountStatuses.count > 1 else { return }

        let reason = L10n.tr("notif.reason_manual")
        AccountRotator.shared.rotateToNext(currentStatuses: accountStatuses, reason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.updateStatusBarDisplay()
                    self.refreshQuotas()
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("alert.switch_failed_title")
                    alert.informativeText = L10n.tr("alert.switch_failed_msg")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.tr("alert.btn_close"))
                    alert.runModal()
                }
            }
        }
    }

    public func manualSwitchAccountById(_ accountId: String) {
        AccountRotator.shared.switchToAccount(id: accountId) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    if let acc = self.accountStatuses.first(where: { $0.id == accountId }) {
                        NotificationManager.shared.sendManualSwitchNotification(account: acc.currentDisplayName, quota: acc.remainingPercentage)
                    }
                    self.updateStatusBarDisplay()
                    self.refreshQuotas()
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("alert.switch_failed_title")
                    alert.informativeText = L10n.tr("alert.switch_specific_failed")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.tr("alert.btn_close"))
                    alert.runModal()
                }
            }
        }
    }

    public func updateModelForAccount(accountId: String, modelId: String) {
        let res = AccountManager.shared.updateAccountModel(id: accountId, modelId: modelId)
        if res.success {
            refreshQuotas()
        }
    }

    @objc public func toggleAutoRotate() {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        guard hasActiveAccount else { return }

        ConfigManager.shared.toggleAutoRotate()
        updateViewModelState()
        SettingsWindowController.shared.syncRotationValues()
    }

    @objc public func showSettingsWindow() {
        showSettingsWindowWithTab(nil)
    }

    public func showSettingsWindowWithTab(_ tab: Int?) {
        if popover.isShown {
            popover.performClose(nil)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            SettingsWindowController.shared.showWindow(accounts: self.accountStatuses, initialTab: tab, onUpdate: { [weak self] in
                self?.refreshQuotas()
            })
        }
    }

    @objc public func showAboutWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        AboutWindowController.shared.showWindow()
    }

    @objc public func actionLoginBrowserOAuth() {
        OAuthServer.shared.startLoginFlow { [weak self] success, message in
            DispatchQueue.main.async {
                self?.showAlert(
                    title: success ? "Thành công" : "Thông báo",
                    message: message,
                    style: success ? .informational : .warning
                )
                if success {
                    self?.refreshQuotas()
                }
            }
        }
    }

    @objc public func actionImportFromIde() {
        let result = AccountManager.shared.importFromCurrentIdeLogin()
        showAlert(title: result.success ? "Thành công" : "Thông báo", message: result.message, style: result.success ? .informational : .warning)
        if result.success {
            refreshQuotas()
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: L10n.tr("alert.btn_close"))
            alert.runModal()
        }
    }

    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
