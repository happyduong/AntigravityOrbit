import Foundation
import AppKit
import UniformTypeIdentifiers

public class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var timer: Timer?
    private var accountStatuses: [AccountStatus] = []
    private var isRefreshing = false

    public override init() {
        super.init()
        _ = AccountManager.shared
        setupStatusItem()
        setupMenu()
        startTimer()
        refreshQuotas()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func handleLanguageChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateStatusBarDisplay()
            self.rebuildMenu()
        }
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
        }
    }

    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

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

        QuotaService.shared.fetchAllQuotas { [weak self] statuses in
            guard let self = self else { return }
            self.isRefreshing = false
            self.accountStatuses = statuses

            print("[StatusBarController] Refreshed quotas for \(statuses.count) accounts:")
            for s in statuses {
                print("   • \(s.email): 5h=\(s.gemini5hPercentage?.description ?? "nil")%, weekly=\(s.geminiWeeklyPercentage?.description ?? "nil")%, remaining=\(s.remainingPercentage)%, current=\(s.isCurrent), tier=\(s.subscriptionTier ?? "nil"), model=\(s.activeModel ?? "nil")")
            }

            DispatchQueue.main.async {
                self.updateStatusBarDisplay()
                self.rebuildMenu()
                self.checkAutoRotationThreshold()
                SettingsWindowController.shared.updateAccounts(accounts: statuses)
            }
        }
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
            if pct < 0 {
                button.toolTip = L10n.tr("menu.tooltip_error", current.email)
            } else if let wk = current.geminiWeeklyPercentage {
                let weekStr = L10n.tr("menu.week_label", wk)
                button.toolTip = "Antigravity Orbit: \(current.email)\nModel: \(modelName)\n(5h: \(pct)% • \(weekStr))"
            } else {
                button.toolTip = "Antigravity Orbit: \(current.email)\nModel: \(modelName)\n(5h: \(pct)%)"
            }
        } else {
            // Option 1: No active account -> Display "--% ⚪"
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
        if let path = Bundle.main.path(forResource: "AppIcon1024", ofType: "png"),
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
                "/Applications/Antigravity Orbit.app/Contents/Resources/AppIcon1024.png",
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
            print("[StatusBarController] Current account \(current.email) has \(current.remainingPercentage)% 5h-limit (<= \(threshold)%). Triggering auto-rotation...")
            let reason = L10n.tr("notif.reason_low_token", current.remainingPercentage, threshold)
            AccountRotator.shared.rotateToNext(currentStatuses: accountStatuses, reason: reason) { [weak self] success, newAcc in
                if success {
                    self?.refreshQuotas()
                }
            }
        }
    }

    // MARK: - NSMenuDelegate
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.autoenablesItems = false
        menu.removeAllItems()

        // 1. Round-Robin Accounts List (Active / Inactive)
        if accountStatuses.isEmpty {
            let unkItem = NSMenuItem(title: L10n.tr("menu.unidentified_account"), action: nil, keyEquivalent: "")
            unkItem.isEnabled = false
            menu.addItem(unkItem)
        } else {
            for (index, acc) in accountStatuses.enumerated() {
                let pctVal = acc.gemini5hPercentage ?? acc.remainingPercentage
                let quotaStr: String
                if pctVal < 0 {
                    quotaStr = L10n.tr("menu.token_error")
                } else if let wk = acc.geminiWeeklyPercentage {
                    let weekStr = L10n.tr("menu.week_label", wk)
                    quotaStr = "5h: \(pctVal)% • \(weekStr)"
                } else {
                    quotaStr = "5h: \(pctVal)%"
                }

                let titleText = "\(index + 1). \(acc.email)"

                let item = NSMenuItem(title: titleText, action: #selector(manualSwitchAccount(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = acc.id

                if let model = acc.activeModel, !model.isEmpty {
                    item.toolTip = "\(acc.email)\nModel: \(model)\nQuota: \(quotaStr)"
                } else {
                    item.toolTip = "\(acc.email)\nQuota: \(quotaStr)"
                }

                if acc.isCurrent {
                    item.state = .on
                    item.attributedTitle = NSAttributedString(
                        string: titleText,
                        attributes: [
                            .foregroundColor: NSColor.systemGreen
                        ]
                    )
                }
                menu.addItem(item)

                // Sub-item: Quota
                let quotaLineTitle = "   📊 " + L10n.tr("menu.quota_label", quotaStr)
                let quotaItem = NSMenuItem(title: quotaLineTitle, action: nil, keyEquivalent: "")
                quotaItem.isEnabled = false
                quotaItem.indentationLevel = 1
                quotaItem.attributedTitle = NSAttributedString(
                    string: quotaLineTitle,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11.5),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                menu.addItem(quotaItem)

                // Sub-item: Plan / Gói
                let tierDisplayName = acc.subscriptionTier ?? L10n.tr("tier.free")
                let tierLineTitle = "   🏷️ " + L10n.tr("menu.tier_label", tierDisplayName)
                let tierItem = NSMenuItem(title: tierLineTitle, action: nil, keyEquivalent: "")
                tierItem.isEnabled = false
                tierItem.indentationLevel = 1
                tierItem.attributedTitle = NSAttributedString(
                    string: tierLineTitle,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11.5),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                menu.addItem(tierItem)

                // Sub-item: Model
                if acc.isCurrent {
                    let activeModelName = acc.activeModel ?? QuotaService.shared.getCurrentAntigravityModel()
                    let currentModelTitle = "   🤖 " + L10n.tr("menu.current_model", activeModelName)
                    let currentModelItem = NSMenuItem(title: currentModelTitle, action: nil, keyEquivalent: "")
                    currentModelItem.isEnabled = false
                    currentModelItem.indentationLevel = 1
                    currentModelItem.attributedTitle = NSAttributedString(
                        string: currentModelTitle,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11.5),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                    menu.addItem(currentModelItem)
                } else if let model = acc.activeModel, !model.isEmpty {
                    let modelTitle = "   🤖 " + L10n.tr("menu.current_model", model)
                    let modelItem = NSMenuItem(title: modelTitle, action: nil, keyEquivalent: "")
                    modelItem.isEnabled = false
                    modelItem.indentationLevel = 1
                    modelItem.attributedTitle = NSAttributedString(
                        string: modelTitle,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11.5),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                    menu.addItem(modelItem)
                }
            }
        }

        // Account Settings item right below the accounts list
        let accountSettingsItem = NSMenuItem(title: L10n.tr("menu.account_settings"), action: #selector(showAccountSettings), keyEquivalent: "")
        accountSettingsItem.target = self
        menu.addItem(accountSettingsItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Core Actions
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })

        let autoRotateItem = NSMenuItem(
            title: L10n.tr("settings.auto_rotate_title"),
            action: #selector(toggleAutoRotate),
            keyEquivalent: ""
        )
        autoRotateItem.target = self
        autoRotateItem.state = ConfigManager.shared.config.autoRotateEnabled ? .on : .off
        autoRotateItem.isEnabled = hasActiveAccount
        menu.addItem(autoRotateItem)

        let rotateNowItem = NSMenuItem(title: L10n.tr("menu.rotate_now"), action: #selector(manualRotateNext), keyEquivalent: "r")
        rotateNowItem.target = self
        rotateNowItem.isEnabled = hasActiveAccount && (accountStatuses.count > 1)
        menu.addItem(rotateNowItem)

        let refreshItem = NSMenuItem(title: L10n.tr("menu.refresh_quota"), action: #selector(refreshQuotas), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = hasActiveAccount
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Utilities & System
        // Language Submenu for 1-click quick language switching
        let langSubmenu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(
                title: "\(lang.flag)  \(lang.displayName)",
                action: #selector(selectLanguageFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang.rawValue
            if lang == LocalizationManager.shared.currentLanguage {
                item.state = .on
            }
            langSubmenu.addItem(item)
        }
        let langParentItem = NSMenuItem(title: L10n.tr("menu.language_switcher"), action: nil, keyEquivalent: "")
        langParentItem.submenu = langSubmenu
        menu.addItem(langParentItem)

        let settingsItem = NSMenuItem(title: L10n.tr("menu.settings"), action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: L10n.tr("menu.about"), action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quit
        let quitItem = NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func manualRotateNext() {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        guard hasActiveAccount && accountStatuses.count > 1 else { return }

        let reason = L10n.tr("notif.reason_manual")
        AccountRotator.shared.rotateToNext(currentStatuses: accountStatuses, reason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.updateStatusBarDisplay()
                    self.rebuildMenu()
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

    @objc private func manualSwitchAccount(_ sender: NSMenuItem) {
        guard let accountId = sender.representedObject as? String else { return }
        AccountRotator.shared.switchToAccount(id: accountId) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    if let acc = self.accountStatuses.first(where: { $0.id == accountId }) {
                        NotificationManager.shared.sendManualSwitchNotification(account: acc.email, quota: acc.remainingPercentage)
                    }
                    self.updateStatusBarDisplay()
                    self.rebuildMenu()
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

    @objc private func toggleAutoRotate() {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        guard hasActiveAccount else { return }

        ConfigManager.shared.toggleAutoRotate()
        rebuildMenu()
        SettingsWindowController.shared.syncRotationValues()
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        ConfigManager.shared.updateThreshold(sender.tag)
        rebuildMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        ConfigManager.shared.updateCheckInterval(sender.tag)
        startTimer()
        rebuildMenu()
    }

    @objc private func toggleNotification() {
        ConfigManager.shared.toggleNotifications()
        rebuildMenu()
    }

    @objc private func toggleSound() {
        ConfigManager.shared.toggleSound()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let newState = !LaunchAtLoginManager.shared.isEnabled
        LaunchAtLoginManager.shared.setEnabled(newState)
        rebuildMenu()
    }

    // MARK: - Account Management Actions

    @objc private func actionImportFromIde() {
        let result = AccountManager.shared.importFromCurrentIdeLogin()
        showAlert(title: result.success ? "Thành công" : "Thông báo", message: result.message, style: result.success ? .informational : .warning)
        if result.success {
            refreshQuotas()
        }
    }

    @objc private func actionImportFromJson() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.title = "Chọn tệp JSON tài khoản"
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true

            if panel.runModal() == .OK, let url = panel.url {
                let result = AccountManager.shared.importFromJsonFile(url: url)
                self.showAlert(title: result.success ? "Thành công" : "Lỗi", message: result.message, style: result.success ? .informational : .warning)
                if result.success {
                    self.refreshQuotas()
                }
            }
        }
    }

    @objc private func actionLoginBrowserOAuth() {
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

    @objc private func actionDeleteAccount(_ sender: NSMenuItem) {
        guard let accountId = sender.representedObject as? String,
              let acc = accountStatuses.first(where: { $0.id == accountId }) else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.tr("alert.delete_confirm_title")
            alert.informativeText = L10n.tr("alert.delete_confirm_msg", acc.email)
            alert.alertStyle = .critical

            let delBtn = alert.addButton(withTitle: L10n.tr("alert.btn_delete"))
            delBtn.hasDestructiveAction = true
            alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))

            if alert.runModal() == .alertFirstButtonReturn {
                let result = AccountManager.shared.deleteAccount(id: accountId)
                self.showAlert(title: result.success ? L10n.tr("alert.success") : L10n.tr("alert.error"), message: result.message, style: result.success ? .informational : .warning)
                if result.success {
                    self.refreshQuotas()
                }
            }
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

    @objc private func selectLanguageFromMenu(_ sender: NSMenuItem) {
        guard let rawVal = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: rawVal) else { return }
        LocalizationManager.shared.setLanguage(lang)
    }

    @objc private func showAccountSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            SettingsWindowController.shared.showWindow(accounts: self.accountStatuses, initialTab: 0, onUpdate: { [weak self] in
                self?.refreshQuotas()
            })
        }
    }

    @objc private func showSettingsWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            SettingsWindowController.shared.showWindow(accounts: self.accountStatuses, initialTab: nil, onUpdate: { [weak self] in
                self?.refreshQuotas()
            })
        }
    }

    @objc private func showAboutWindow() {
        AboutWindowController.shared.showWindow()
    }

    @objc private func openAntigravityApp() {
        let appPath = "/Applications/Antigravity.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
    }

    @objc private func openAntigravityIde() {
        let idePath = "/Applications/Antigravity IDE.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: idePath))
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuItemValidation

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        if menuItem.action == #selector(toggleAutoRotate) {
            return hasActiveAccount
        }
        if menuItem.action == #selector(manualRotateNext) {
            return hasActiveAccount && (accountStatuses.count > 1)
        }
        if menuItem.action == #selector(refreshQuotas) {
            return hasActiveAccount
        }
        return true
    }
}
