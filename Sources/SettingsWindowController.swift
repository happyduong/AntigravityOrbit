import Cocoa
import UniformTypeIdentifiers
import SwiftUI

public class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private var viewModel = SettingsViewModel()
    private var onUpdateCallback: (() -> Void)?

    private override init() {
        super.init()
        setupViewModelActions()

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
            self.window?.title = L10n.tr("settings.title")
            self.viewModel.syncFromConfig()
        }
    }

    private func setupViewModelActions() {
        viewModel.onRefreshQuotas = { [weak self] in
            self?.onUpdateCallback?()
        }

        viewModel.onSetActiveAccount = { [weak self] accountId in
            self?.setActiveAccount(id: accountId)
        }

        viewModel.onEditAlias = { [weak self] acc in
            self?.showEditAliasDialog(acc: acc)
        }

        viewModel.onSelectModel = { [weak self] accountId, modelId in
            let res = AccountManager.shared.updateAccountModel(id: accountId, modelId: modelId)
            if res.success {
                self?.onUpdateCallback?()
            }
        }

        viewModel.onDeleteAccount = { [weak self] acc in
            self?.showDeleteAccountDialog(acc: acc)
        }

        viewModel.onAddBrowserOAuth = { [weak self] in
            self?.addBrowserOAuth()
        }

        viewModel.onAddFromIde = { [weak self] in
            self?.addFromIde()
        }

        viewModel.onAddFromJson = { [weak self] in
            self?.addFromJson()
        }

        viewModel.onToggleAutoRotate = { [weak self] in
            ConfigManager.shared.toggleAutoRotate()
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onUpdateThreshold = { [weak self] val in
            ConfigManager.shared.updateThreshold(val)
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onUpdateInterval = { [weak self] val in
            ConfigManager.shared.updateCheckInterval(val)
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onToggleShowAlias = { [weak self] in
            ConfigManager.shared.toggleShowAccountAlias()
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onToggleLaunchAtLogin = { [weak self] in
            let newState = !LaunchAtLoginManager.shared.isEnabled
            LaunchAtLoginManager.shared.setEnabled(newState)
            self?.viewModel.syncFromConfig()
        }

        viewModel.onToggleNotifications = { [weak self] in
            ConfigManager.shared.toggleNotifications()
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onToggleSound = { [weak self] in
            ConfigManager.shared.toggleSound()
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onSetLanguage = { [weak self] lang in
            LocalizationManager.shared.setLanguage(lang)
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onSetPopoverLayoutStyle = { [weak self] style in
            ConfigManager.shared.updatePopoverLayoutStyle(style)
            self?.viewModel.syncFromConfig()
            self?.onUpdateCallback?()
        }

        viewModel.onOpenDesktopApp = {
            let appPath = "/Applications/Antigravity.app"
            NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
        }

        viewModel.onOpenIde = {
            let idePath = "/Applications/Antigravity IDE.app"
            NSWorkspace.shared.open(URL(fileURLWithPath: idePath))
        }
    }

    // MARK: - Public Window API

    public func showWindow(accounts: [AccountStatus] = [], initialTab: Int? = nil, onUpdate: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onUpdateCallback = onUpdate
            self.viewModel.updateAccounts(accounts: accounts)
            self.viewModel.syncFromConfig()

            if let tabIdx = initialTab, let tab = SettingsTab(rawValue: tabIdx) {
                self.viewModel.selectedTab = tab
            }

            if let win = self.window {
                NSApp.activate(ignoringOtherApps: true)
                win.center()
                win.makeKeyAndOrderFront(nil)
                return
            }

            self.buildWindow()
            NSApp.activate(ignoringOtherApps: true)
            self.window?.center()
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    public func switchToTab(_ index: Int) {
        guard let tab = SettingsTab(rawValue: index) else { return }
        viewModel.selectedTab = tab
    }

    public func updateAccounts(accounts: [AccountStatus]) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.updateAccounts(accounts: accounts)
        }
    }

    public func syncRotationValues() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.syncFromConfig()
        }
    }

    // MARK: - Window Construction

    private func buildWindow() {
        let winWidth: CGFloat = 760
        let winHeight: CGFloat = 560
        let contentRect = NSRect(x: 0, y: 0, width: winWidth, height: winHeight)

        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("settings.title")
        win.minSize = NSSize(width: 720, height: 500)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let rootView = SettingsView(viewModel: viewModel)
        let hc = NSHostingController(rootView: rootView)
        win.contentViewController = hc
        self.hostingController = hc
        self.window = win
    }

    // MARK: - Actions

    private func setActiveAccount(id: String) {
        AccountRotator.shared.switchToAccount(id: id) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    if let acc = self.viewModel.accounts.first(where: { $0.id == id }) {
                        NotificationManager.shared.sendManualSwitchNotification(account: acc.currentDisplayName, quota: acc.remainingPercentage)
                    }
                    self.onUpdateCallback?()
                } else {
                    self.showAlert(
                        title: L10n.tr("alert.switch_failed_title"),
                        message: L10n.tr("alert.switch_specific_failed"),
                        style: .warning
                    )
                }
            }
        }
    }

    private func showEditAliasDialog(acc: AccountStatus) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("settings.edit_alias_title")
        alert.informativeText = L10n.tr("settings.edit_alias_msg", acc.email)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.font = NSFont.systemFont(ofSize: 13)
        input.stringValue = acc.name
        alert.accessoryView = input

        alert.addButton(withTitle: L10n.tr("settings.btn_save"))
        alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let newAlias = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let res = AccountManager.shared.updateAccountAlias(id: acc.id, newName: newAlias)
            if res.success {
                self.onUpdateCallback?()
            } else {
                showAlert(title: L10n.tr("alert.error"), message: res.message, style: .warning)
            }
        }
    }

    private func showDeleteAccountDialog(acc: AccountStatus) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("alert.delete_confirm_title")
        alert.informativeText = L10n.tr("alert.delete_confirm_msg", acc.email)
        alert.alertStyle = .critical

        let delBtn = alert.addButton(withTitle: L10n.tr("alert.btn_delete"))
        delBtn.hasDestructiveAction = true
        alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let res = AccountManager.shared.deleteAccount(id: acc.id)
            if res.success {
                self.onUpdateCallback?()
            } else {
                showAlert(title: L10n.tr("alert.error"), message: res.message, style: .warning)
            }
        }
    }

    private func addBrowserOAuth() {
        OAuthServer.shared.startLoginFlow { [weak self] success, message in
            DispatchQueue.main.async {
                self?.showAlert(
                    title: success ? L10n.tr("alert.success") : L10n.tr("alert.notice"),
                    message: message,
                    style: success ? .informational : .warning
                )
                if success {
                    self?.onUpdateCallback?()
                }
            }
        }
    }

    private func addFromIde() {
        let result = AccountManager.shared.importFromCurrentIdeLogin()
        showAlert(
            title: result.success ? L10n.tr("alert.success") : L10n.tr("alert.notice"),
            message: result.message,
            style: result.success ? .informational : .warning
        )
        if result.success {
            onUpdateCallback?()
        }
    }

    private func addFromJson() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = L10n.tr("alert.json_panel_title")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            let res = AccountManager.shared.importFromJsonFile(url: url)
            showAlert(
                title: res.success ? L10n.tr("alert.success") : L10n.tr("alert.error"),
                message: res.message,
                style: res.success ? .informational : .warning
            )
            if res.success {
                onUpdateCallback?()
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
}
