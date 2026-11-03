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
            for acc in accountStatuses {
                let pctVal = acc.gemini5hPercentage ?? acc.remainingPercentage
                let quotaStr: String
                let quotaBadge: String

                if pctVal < 0 {
                    quotaStr = L10n.tr("menu.token_error")
                    quotaBadge = "⚠️"
                } else if let wk = acc.geminiWeeklyPercentage {
                    let weekStr = L10n.tr("menu.week_label", wk)
                    quotaStr = "5h: \(pctVal)% • \(weekStr)"
                    quotaBadge = pctVal > 50 ? "\(pctVal)% 🟢" : (pctVal > 20 ? "\(pctVal)% 🟡" : "\(pctVal)% 🔴")
                } else {
                    quotaStr = "5h: \(pctVal)%"
                    quotaBadge = pctVal > 50 ? "\(pctVal)% 🟢" : (pctVal > 20 ? "\(pctVal)% 🟡" : "\(pctVal)% 🔴")
                }

                // Main Menu Account Row (Clean, single-line with quota badge, no tooltip popup)
                let accountDisplay = acc.currentDisplayName
                let mainTitle = "\(accountDisplay)   (\(quotaBadge))"
                let accountItem = NSMenuItem(title: mainTitle, action: nil, keyEquivalent: "")

                if acc.isCurrent {
                    accountItem.state = .on
                    accountItem.attributedTitle = NSAttributedString(
                        string: mainTitle,
                        attributes: [
                            .foregroundColor: NSColor.systemGreen
                        ]
                    )
                }

                // Native Hierarchical Submenu (Flyout)
                let subMenu = NSMenu()
                subMenu.autoenablesItems = false

                // Action: Active status or switch to this account
                if acc.isCurrent {
                    let activeItem = createStaticStatusMenuItem(text: "✓  \(L10n.tr("menu.active_account"))")
                    subMenu.addItem(activeItem)
                } else {
                    let switchItem = NSMenuItem(
                        title: "🔄  \(L10n.tr("menu.switch_to_account"))",
                        action: #selector(manualSwitchAccount(_:)),
                        keyEquivalent: ""
                    )
                    switchItem.target = self
                    switchItem.representedObject = acc.id
                    subMenu.addItem(switchItem)
                }

                subMenu.addItem(NSMenuItem.separator())

                let showAlias = ConfigManager.shared.config.showAccountAlias
                if showAlias {
                    let emailLineTitle = L10n.tr("menu.email_label", acc.email)
                    subMenu.addItem(createStaticInfoMenuItem(icon: "📧", text: emailLineTitle))
                } else {
                    let trimmedName = acc.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty && trimmedName.lowercased() != acc.email.lowercased() {
                        let aliasLineTitle = L10n.tr("menu.alias_label", trimmedName)
                        subMenu.addItem(createStaticInfoMenuItem(icon: "🏷️", text: aliasLineTitle))
                    }
                }

                // 1. Quota details (Static view: bright, crisp, hover-blocked, click-blocked)
                let quotaLineTitle = L10n.tr("menu.quota_label", quotaStr)
                subMenu.addItem(createStaticInfoMenuItem(icon: "📊", text: quotaLineTitle))

                // 2. Plan / Tier
                let tierDisplayName = acc.subscriptionTier ?? L10n.tr("tier.free")
                let tierLineTitle = L10n.tr("menu.tier_label", tierDisplayName)
                subMenu.addItem(createStaticInfoMenuItem(icon: "🏷️", text: tierLineTitle))

                // 3. Preferred Model selector flyout menu: "🤖 Model ưu tiên: [Model Name] ▶"
                let currentModelDesc = acc.displayModelName
                let modelMenuTitle = "\(L10n.tr("menu.preferred_model")): \(currentModelDesc)"
                let modelParentItem = NSMenuItem(title: "🤖  \(modelMenuTitle)", action: nil, keyEquivalent: "")

                let modelMenu = NSMenu()

                // Option Auto
                let autoItem = NSMenuItem(title: L10n.tr("model.auto"), action: #selector(accountModelSelected(_:)), keyEquivalent: "")
                autoItem.target = self
                autoItem.representedObject = ["accountId": acc.id, "modelId": ""]
                let isAuto = (acc.preferredModelId == nil || acc.preferredModelId?.isEmpty == true)
                if isAuto {
                    autoItem.state = .on
                }
                modelMenu.addItem(autoItem)

                // Group: Google Gemini
                modelMenu.addItem(NSMenuItem.separator())
                let geminiHeader = NSMenuItem(title: "── Google Gemini ──", action: nil, keyEquivalent: "")
                geminiHeader.isEnabled = false
                modelMenu.addItem(geminiHeader)

                for opt in AIModelCatalog.geminiModels {
                    let mItem = NSMenuItem(title: opt.displayName, action: #selector(accountModelSelected(_:)), keyEquivalent: "")
                    mItem.target = self
                    mItem.representedObject = ["accountId": acc.id, "modelId": opt.id]
                    if acc.preferredModelId == opt.id {
                        mItem.state = .on
                    }
                    modelMenu.addItem(mItem)
                }

                // Group: Anthropic Claude
                modelMenu.addItem(NSMenuItem.separator())
                let claudeHeader = NSMenuItem(title: "── Anthropic Claude ──", action: nil, keyEquivalent: "")
                claudeHeader.isEnabled = false
                modelMenu.addItem(claudeHeader)

                for opt in AIModelCatalog.claudeModels {
                    let mItem = NSMenuItem(title: opt.displayName, action: #selector(accountModelSelected(_:)), keyEquivalent: "")
                    mItem.target = self
                    mItem.representedObject = ["accountId": acc.id, "modelId": opt.id]
                    if acc.preferredModelId == opt.id {
                        mItem.state = .on
                    }
                    modelMenu.addItem(mItem)
                }

                // Group: Other
                modelMenu.addItem(NSMenuItem.separator())
                let otherHeader = NSMenuItem(title: "── \(L10n.tr("model.group_other")) ──", action: nil, keyEquivalent: "")
                otherHeader.isEnabled = false
                modelMenu.addItem(otherHeader)

                for opt in AIModelCatalog.otherModels {
                    let mItem = NSMenuItem(title: opt.displayName, action: #selector(accountModelSelected(_:)), keyEquivalent: "")
                    mItem.target = self
                    mItem.representedObject = ["accountId": acc.id, "modelId": opt.id]
                    if acc.preferredModelId == opt.id {
                        mItem.state = .on
                    }
                    modelMenu.addItem(mItem)
                }

                modelParentItem.submenu = modelMenu
                subMenu.addItem(modelParentItem)

                accountItem.submenu = subMenu
                menu.addItem(accountItem)
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

        let showAliasItem = NSMenuItem(
            title: L10n.tr("menu.show_alias_title"),
            action: #selector(toggleShowAccountAlias),
            keyEquivalent: ""
        )
        showAliasItem.target = self
        showAliasItem.state = ConfigManager.shared.config.showAccountAlias ? .on : .off
        menu.addItem(showAliasItem)

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
                        NotificationManager.shared.sendManualSwitchNotification(account: acc.currentDisplayName, quota: acc.remainingPercentage)
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

    @objc private func accountModelSelected(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let accountId = info["accountId"],
              let modelId = info["modelId"] else { return }
        let res = AccountManager.shared.updateAccountModel(id: accountId, modelId: modelId)
        if res.success {
            refreshQuotas()
        }
    }

    @objc private func toggleAutoRotate() {
        let hasActiveAccount = accountStatuses.contains(where: { $0.isCurrent })
        guard hasActiveAccount else { return }

        ConfigManager.shared.toggleAutoRotate()
        rebuildMenu()
        SettingsWindowController.shared.syncRotationValues()
    }

    @objc private func toggleShowAccountAlias() {
        ConfigManager.shared.toggleShowAccountAlias()
        updateStatusBarDisplay()
        rebuildMenu()
        SettingsWindowController.shared.updateAccounts(accounts: self.accountStatuses)
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

    // MARK: - Static (Non-Clickable, Non-Hoverable) Submenu Items

    private func createStaticStatusMenuItem(text: String) -> NSMenuItem {
        let item = NSMenuItem()
        let font = NSFont.boldSystemFont(ofSize: 12.5)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let width = max(270.0, ceil(textSize.width) + 36.0)
        let height: CGFloat = 24.0

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.width]

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = NSColor.systemGreen
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.frame = NSRect(x: 14, y: 4, width: width - 20, height: 18)
        label.autoresizingMask = [.width]

        container.addSubview(label)
        item.view = container
        return item
    }

    private func createStaticInfoMenuItem(icon: String, text: String) -> NSMenuItem {
        let item = NSMenuItem()
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let fullText = "\(icon)  \(text)"
        let textSize = (fullText as NSString).size(withAttributes: [.font: font])
        let width = max(270.0, ceil(textSize.width) + 36.0)
        let height: CGFloat = 22.0

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.width]

        let attr = NSMutableAttributedString()
        if let colonIndex = text.firstIndex(of: ":") {
            let labelPart = String(text[..<colonIndex]) + ":"
            let valuePart = String(text[text.index(after: colonIndex)...])
            attr.append(NSAttributedString(
                string: "\(icon)  \(labelPart)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
            attr.append(NSAttributedString(
                string: valuePart,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            ))
        } else {
            attr.append(NSAttributedString(
                string: fullText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            ))
        }

        let label = NSTextField(labelWithAttributedString: attr)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.frame = NSRect(x: 14, y: 3, width: width - 20, height: 18)
        label.autoresizingMask = [.width]

        container.addSubview(label)
        item.view = container
        return item
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
