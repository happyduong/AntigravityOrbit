import Cocoa
import UniformTypeIdentifiers

public class SettingsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var segmentedControl: NSSegmentedControl?
    private var containerView: NSView?

    private var currentTabIndex: Int = 0

    // Views for Tab 0: Accounts
    private var accountsView: NSView?
    private var tableView: NSTableView?
    private var deleteAccountButton: NSButton?
    private var switchAccountButton: NSButton?
    private var editAliasButton: NSButton?
    private var selectModelButton: NSButton?
    private var accountsShowAliasCheckbox: NSButton?
    private var accountsListHeaderLabel: NSTextField?
    private var accountsRefreshButton: NSButton?
    private var accountsScrollView: NSScrollView?
    private var accountsActionSeparator: NSBox?
    private var emptyStateContainer: NSView?
    private var accountsData: [AccountStatus] = []

    // Views for Tab 1: Rotation
    private var rotationView: NSView?
    private var autoRotateCheckbox: NSButton?
    private var thresholdPopUp: NSPopUpButton?
    private var intervalPopUp: NSPopUpButton?

    // Views for Tab 2: General & System
    private var generalView: NSView?
    private var languagePopUp: NSPopUpButton?
    private var generalShowAliasCheckbox: NSButton?
    private var launchAtLoginCheckbox: NSButton?
    private var notificationsCheckbox: NSButton?
    private var soundCheckbox: NSButton?

    private var onUpdateCallback: (() -> Void)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func handleLanguageChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let win = self.window else { return }
            win.title = L10n.tr("settings.title")
            self.updateSegmentedControlTitles()
            self.rebuildTabs()
        }
    }

    public func showWindow(accounts: [AccountStatus] = [], initialTab: Int? = nil, onUpdate: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.accountsData = accounts
            self.onUpdateCallback = onUpdate

            let targetTab = initialTab ?? self.currentTabIndex

            if let win = self.window {
                NSApp.activate(ignoringOtherApps: true)
                self.refreshAccountsList(accounts: accounts)
                self.switchToTab(targetTab)
                win.center()
                win.makeKeyAndOrderFront(nil)
                return
            }

            self.currentTabIndex = targetTab
            self.buildWindow()
            self.refreshAccountsList(accounts: accounts)
            NSApp.activate(ignoringOtherApps: true)
            self.window?.center()
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    public func switchToTab(_ index: Int) {
        guard index >= 0 && index < 3 else { return }
        currentTabIndex = index
        segmentedControl?.selectedSegment = index
        showTab(index: index)
    }

    public func updateAccounts(accounts: [AccountStatus]) {
        self.accountsData = accounts
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateAccountsVisibility()
            self.tableView?.reloadData()
            self.updateAccountButtonStates()
        }
    }

    // MARK: - Window Construction

    private func buildWindow() {
        let winWidth: CGFloat = 660
        let winHeight: CGFloat = 610
        let contentRect = NSRect(x: 0, y: 0, width: winWidth, height: winHeight)

        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("settings.title")
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let root = NSView(frame: contentRect)
        root.wantsLayer = true
        win.contentView = root

        // Header Tab Segmented Control
        let seg = NSSegmentedControl(
            labels: [
                L10n.tr("settings.tab_accounts"),
                L10n.tr("settings.tab_rotation"),
                L10n.tr("settings.tab_system")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(tabChanged(_:))
        )
        seg.selectedSegment = currentTabIndex
        seg.segmentStyle = .texturedRounded
        seg.frame = NSRect(x: (winWidth - 380) / 2, y: winHeight - 48, width: 380, height: 28)
        root.addSubview(seg)
        self.segmentedControl = seg

        // Separator below tabs
        let sep = NSBox(frame: NSRect(x: 0, y: winHeight - 60, width: winWidth, height: 1))
        sep.boxType = .separator
        root.addSubview(sep)

        // Content Container View
        let containerFrame = NSRect(x: 0, y: 0, width: winWidth, height: winHeight - 60)
        let cont = NSView(frame: containerFrame)
        root.addSubview(cont)
        self.containerView = cont

        // Setup Tab Views
        setupAccountsTab(frame: containerFrame)
        setupRotationTab(frame: containerFrame)
        setupGeneralTab(frame: containerFrame)

        // Show selected tab
        showTab(index: currentTabIndex)

        self.window = win
    }

    private func updateSegmentedControlTitles() {
        guard let seg = segmentedControl else { return }
        seg.setLabel(L10n.tr("settings.tab_accounts"), forSegment: 0)
        seg.setLabel(L10n.tr("settings.tab_rotation"), forSegment: 1)
        seg.setLabel(L10n.tr("settings.tab_system"), forSegment: 2)
    }

    private func rebuildTabs() {
        guard let containerView = containerView else { return }
        let frame = containerView.bounds
        setupAccountsTab(frame: frame)
        setupRotationTab(frame: frame)
        setupGeneralTab(frame: frame)
        showTab(index: currentTabIndex)
    }

    // MARK: - Tab Switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        currentTabIndex = sender.selectedSegment
        showTab(index: currentTabIndex)
    }

    private func showTab(index: Int) {
        guard let containerView = containerView else { return }
        containerView.subviews.forEach { $0.removeFromSuperview() }
        currentTabIndex = index
        switch index {
        case 0:
            if let accView = accountsView {
                updateAccountsVisibility()
                tableView?.reloadData()
                updateAccountButtonStates()
                containerView.addSubview(accView)
            }
        case 1:
            if let rot = rotationView {
                syncRotationValues()
                containerView.addSubview(rot)
            }
        case 2:
            if let gen = generalView {
                syncGeneralValues()
                containerView.addSubview(gen)
            }
        default:
            break
        }
    }

    // MARK: - Tab 1: Rotation Setup

    private func setupRotationTab(frame: NSRect) {
        let rotView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))

        let padX: CGFloat = 28
        var currentY: CGFloat = frame.height - 36

        // Section Title: Auto-rotation
        let sec1Title = NSTextField(labelWithString: L10n.tr("settings.rotation_strategy"))
        sec1Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec1Title.textColor = .labelColor
        sec1Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        rotView.addSubview(sec1Title)
        currentY -= 32

        // Card 1 Box
        let card1 = createCardBox(frame: NSRect(x: padX, y: currentY - 74, width: frame.width - padX * 2, height: 98))
        rotView.addSubview(card1)

        let chkAuto = NSButton(
            checkboxWithTitle: L10n.tr("settings.auto_rotate_title"),
            target: self,
            action: #selector(autoRotateToggled(_:))
        )
        chkAuto.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        chkAuto.frame = NSRect(x: 16, y: 58, width: card1.frame.width - 32, height: 24)
        card1.addSubview(chkAuto)
        self.autoRotateCheckbox = chkAuto

        let autoRotateDesc = NSTextField(labelWithString: L10n.tr("settings.auto_rotate_desc"))
        autoRotateDesc.font = NSFont.systemFont(ofSize: 11.5)
        autoRotateDesc.textColor = .secondaryLabelColor
        autoRotateDesc.frame = NSRect(x: 36, y: 12, width: card1.frame.width - 52, height: 42)
        if let cell = autoRotateDesc.cell as? NSTextFieldCell {
            cell.wraps = true
        }
        card1.addSubview(autoRotateDesc)

        currentY -= 125

        // Section Title: Rotation Conditions
        let sec2Title = NSTextField(labelWithString: L10n.tr("settings.rotation_conditions"))
        sec2Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec2Title.textColor = .labelColor
        sec2Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        rotView.addSubview(sec2Title)
        currentY -= 32

        // Card 2 Box
        let card2 = createCardBox(frame: NSRect(x: padX, y: currentY - 170, width: frame.width - padX * 2, height: 195))
        rotView.addSubview(card2)

        // Row 1: Threshold
        let thLabel = NSTextField(labelWithString: L10n.tr("settings.threshold_label"))
        thLabel.font = NSFont.systemFont(ofSize: 12.5)
        thLabel.frame = NSRect(x: 16, y: 152, width: 220, height: 20)
        card2.addSubview(thLabel)

        let popTh = NSPopUpButton(frame: NSRect(x: 240, y: 149, width: 250, height: 26), pullsDown: false)
        popTh.target = self
        popTh.action = #selector(thresholdChanged(_:))
        for val in [5, 10, 15, 20, 25] {
            let title = String(format: L10n.tr("settings.threshold_suffix"), val)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = val
            popTh.menu?.addItem(item)
        }
        card2.addSubview(popTh)
        self.thresholdPopUp = popTh

        let thDesc = NSTextField(labelWithString: L10n.tr("settings.threshold_desc"))
        thDesc.font = NSFont.systemFont(ofSize: 11)
        thDesc.textColor = .secondaryLabelColor
        thDesc.frame = NSRect(x: 242, y: 126, width: 280, height: 18)
        card2.addSubview(thDesc)

        // Row 2: Check Interval
        let intLabel = NSTextField(labelWithString: L10n.tr("settings.interval_label"))
        intLabel.font = NSFont.systemFont(ofSize: 12.5)
        intLabel.frame = NSRect(x: 16, y: 92, width: 220, height: 20)
        card2.addSubview(intLabel)

        let popInt = NSPopUpButton(frame: NSRect(x: 240, y: 89, width: 250, height: 26), pullsDown: false)
        popInt.target = self
        popInt.action = #selector(intervalChanged(_:))
        let intervals = [
            (30, String(format: L10n.tr("settings.interval_seconds"), 30)),
            (60, String(format: L10n.tr("settings.interval_seconds"), 60)),
            (120, String(format: L10n.tr("settings.interval_minutes"), 2)),
            (300, String(format: L10n.tr("settings.interval_minutes"), 5))
        ]
        for (sec, title) in intervals {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = sec
            popInt.menu?.addItem(item)
        }
        card2.addSubview(popInt)
        self.intervalPopUp = popInt

        let intDesc = NSTextField(labelWithString: L10n.tr("settings.interval_desc"))
        intDesc.font = NSFont.systemFont(ofSize: 11)
        intDesc.textColor = .secondaryLabelColor
        intDesc.frame = NSRect(x: 242, y: 66, width: 280, height: 18)
        card2.addSubview(intDesc)

        // Row 3: Rotation Note
        let noteLabel = NSTextField(labelWithString: L10n.tr("settings.rotation_note"))
        noteLabel.font = NSFont.systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: 16, y: 14, width: card2.frame.width - 32, height: 42)
        if let cell = noteLabel.cell as? NSTextFieldCell {
            cell.wraps = true
        }
        card2.addSubview(noteLabel)

        self.rotationView = rotView
    }

    public func syncRotationValues() {
        guard let autoRotateCheckbox = autoRotateCheckbox,
              let thresholdPopUp = thresholdPopUp,
              let intervalPopUp = intervalPopUp else { return }
        let cfg = ConfigManager.shared.config
        autoRotateCheckbox.state = cfg.autoRotateEnabled ? .on : .off
        thresholdPopUp.selectItem(withTag: cfg.thresholdPercentage)
        intervalPopUp.selectItem(withTag: cfg.checkIntervalSeconds)
    }

    @objc private func autoRotateToggled(_ sender: NSButton) {
        ConfigManager.shared.toggleAutoRotate()
        onUpdateCallback?()
    }

    @objc private func thresholdChanged(_ sender: NSPopUpButton) {
        if let sel = sender.selectedItem {
            ConfigManager.shared.updateThreshold(sel.tag)
            onUpdateCallback?()
        }
    }

    @objc private func intervalChanged(_ sender: NSPopUpButton) {
        if let sel = sender.selectedItem {
            ConfigManager.shared.updateCheckInterval(sel.tag)
            onUpdateCallback?()
        }
    }

    // MARK: - Tab 2: General & System Setup

    private func setupGeneralTab(frame: NSRect) {
        let genView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))

        let padX: CGFloat = 28
        var currentY: CGFloat = frame.height - 34

        // SECTION 0: Language & Display
        let sec0Title = NSTextField(labelWithString: L10n.tr("settings.language_section"))
        sec0Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec0Title.textColor = .labelColor
        sec0Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        genView.addSubview(sec0Title)
        currentY -= 26

        let card0 = createCardBox(frame: NSRect(x: padX, y: currentY - 122, width: frame.width - padX * 2, height: 122))
        genView.addSubview(card0)

        let langLabel = NSTextField(labelWithString: L10n.tr("settings.language_label"))
        langLabel.font = NSFont.systemFont(ofSize: 12.5)
        langLabel.frame = NSRect(x: 16, y: 86, width: 220, height: 20)
        card0.addSubview(langLabel)

        let popLang = NSPopUpButton(frame: NSRect(x: 240, y: 83, width: 260, height: 26), pullsDown: false)
        popLang.target = self
        popLang.action = #selector(languageSelected(_:))
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: "\(lang.flag)  \(lang.displayName)", action: nil, keyEquivalent: "")
            item.representedObject = lang.rawValue
            popLang.menu?.addItem(item)
        }
        card0.addSubview(popLang)
        self.languagePopUp = popLang

        // Separator between language and alias display
        let cardSep = NSBox(frame: NSRect(x: 16, y: 72, width: card0.frame.width - 32, height: 1))
        cardSep.boxType = .separator
        card0.addSubview(cardSep)

        let chkAliasGen = NSButton(
            checkboxWithTitle: L10n.tr("settings.show_alias_title"),
            target: self,
            action: #selector(showAliasToggled(_:))
        )
        chkAliasGen.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        chkAliasGen.frame = NSRect(x: 16, y: 40, width: card0.frame.width - 32, height: 24)
        card0.addSubview(chkAliasGen)
        self.generalShowAliasCheckbox = chkAliasGen

        let aliasDesc = NSTextField(labelWithString: L10n.tr("settings.show_alias_desc"))
        aliasDesc.font = NSFont.systemFont(ofSize: 11)
        aliasDesc.textColor = .secondaryLabelColor
        aliasDesc.frame = NSRect(x: 36, y: 12, width: card0.frame.width - 52, height: 26)
        if let cell = aliasDesc.cell as? NSTextFieldCell {
            cell.wraps = true
        }
        card0.addSubview(aliasDesc)

        currentY -= 138

        // SECTION 1: Startup & Background
        let sec1Title = NSTextField(labelWithString: L10n.tr("settings.startup_section"))
        sec1Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec1Title.textColor = .labelColor
        sec1Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        genView.addSubview(sec1Title)
        currentY -= 28

        let card1 = createCardBox(frame: NSRect(x: padX, y: currentY - 64, width: frame.width - padX * 2, height: 86))
        genView.addSubview(card1)

        let chkLogin = NSButton(
            checkboxWithTitle: L10n.tr("settings.launch_at_login"),
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        chkLogin.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        chkLogin.frame = NSRect(x: 16, y: 50, width: card1.frame.width - 32, height: 24)
        card1.addSubview(chkLogin)
        self.launchAtLoginCheckbox = chkLogin

        let loginDesc = NSTextField(labelWithString: L10n.tr("settings.launch_at_login_desc"))
        loginDesc.font = NSFont.systemFont(ofSize: 11)
        loginDesc.textColor = .secondaryLabelColor
        loginDesc.frame = NSRect(x: 36, y: 12, width: card1.frame.width - 52, height: 34)
        if let cell = loginDesc.cell as? NSTextFieldCell {
            cell.wraps = true
        }
        card1.addSubview(loginDesc)

        currentY -= 105

        // SECTION 2: Notifications & Sounds
        let sec2Title = NSTextField(labelWithString: L10n.tr("settings.notifications_section"))
        sec2Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec2Title.textColor = .labelColor
        sec2Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        genView.addSubview(sec2Title)
        currentY -= 28

        let card2 = createCardBox(frame: NSRect(x: padX, y: currentY - 110, width: frame.width - padX * 2, height: 132))
        genView.addSubview(card2)

        let chkNotif = NSButton(
            checkboxWithTitle: L10n.tr("settings.enable_notifications"),
            target: self,
            action: #selector(notificationsToggled(_:))
        )
        chkNotif.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        chkNotif.frame = NSRect(x: 16, y: 92, width: card2.frame.width - 32, height: 24)
        card2.addSubview(chkNotif)
        self.notificationsCheckbox = chkNotif

        let notifDesc = NSTextField(labelWithString: L10n.tr("settings.notifications_desc"))
        notifDesc.font = NSFont.systemFont(ofSize: 11)
        notifDesc.textColor = .secondaryLabelColor
        notifDesc.frame = NSRect(x: 36, y: 66, width: card2.frame.width - 52, height: 24)
        card2.addSubview(notifDesc)

        let chkSound = NSButton(
            checkboxWithTitle: L10n.tr("settings.enable_sound"),
            target: self,
            action: #selector(soundToggled(_:))
        )
        chkSound.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        chkSound.frame = NSRect(x: 16, y: 34, width: card2.frame.width - 32, height: 24)
        card2.addSubview(chkSound)
        self.soundCheckbox = chkSound

        let soundDesc = NSTextField(labelWithString: L10n.tr("settings.sound_desc"))
        soundDesc.font = NSFont.systemFont(ofSize: 11)
        soundDesc.textColor = .secondaryLabelColor
        soundDesc.frame = NSRect(x: 36, y: 10, width: card2.frame.width - 52, height: 20)
        card2.addSubview(soundDesc)

        currentY -= 150

        // SECTION 3: Shortcuts
        let sec3Title = NSTextField(labelWithString: L10n.tr("settings.shortcuts_section"))
        sec3Title.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sec3Title.textColor = .labelColor
        sec3Title.frame = NSRect(x: padX, y: currentY, width: frame.width - padX * 2, height: 20)
        genView.addSubview(sec3Title)
        currentY -= 32

        let openAppBtn = NSButton(
            title: L10n.tr("settings.open_app_btn"),
            target: self,
            action: #selector(openAntigravityApp)
        )
        openAppBtn.bezelStyle = .rounded
        openAppBtn.frame = NSRect(x: padX, y: currentY, width: 195, height: 28)
        genView.addSubview(openAppBtn)

        let openIdeBtn = NSButton(
            title: L10n.tr("settings.open_ide_btn"),
            target: self,
            action: #selector(openAntigravityIde)
        )
        openIdeBtn.bezelStyle = .rounded
        openIdeBtn.frame = NSRect(x: padX + 210, y: currentY, width: 195, height: 28)
        genView.addSubview(openIdeBtn)

        self.generalView = genView
    }

    private func syncGeneralValues() {
        guard let launchAtLoginCheckbox = launchAtLoginCheckbox,
              let notificationsCheckbox = notificationsCheckbox,
              let soundCheckbox = soundCheckbox else { return }
        let cfg = ConfigManager.shared.config
        launchAtLoginCheckbox.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        notificationsCheckbox.state = cfg.notificationsEnabled ? .on : .off
        soundCheckbox.state = cfg.soundEnabled ? .on : .off
        generalShowAliasCheckbox?.state = cfg.showAccountAlias ? .on : .off
        accountsShowAliasCheckbox?.state = cfg.showAccountAlias ? .on : .off

        if let languagePopUp = languagePopUp {
            let curLang = LocalizationManager.shared.currentLanguage.rawValue
            for item in languagePopUp.itemArray {
                if (item.representedObject as? String) == curLang {
                    languagePopUp.select(item)
                    break
                }
            }
        }
    }

    @objc private func showAliasToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        ConfigManager.shared.setShowAccountAlias(enabled)
        accountsShowAliasCheckbox?.state = enabled ? .on : .off
        generalShowAliasCheckbox?.state = enabled ? .on : .off
        tableView?.reloadData()
        onUpdateCallback?()
    }

    @objc private func languageSelected(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let rawVal = selectedItem.representedObject as? String,
              let lang = AppLanguage(rawValue: rawVal) else { return }
        LocalizationManager.shared.setLanguage(lang)
        onUpdateCallback?()
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enable = (sender.state == .on)
        LaunchAtLoginManager.shared.setEnabled(enable)
        onUpdateCallback?()
    }

    @objc private func notificationsToggled(_ sender: NSButton) {
        ConfigManager.shared.toggleNotifications()
        onUpdateCallback?()
    }

    @objc private func soundToggled(_ sender: NSButton) {
        ConfigManager.shared.toggleSound()
        onUpdateCallback?()
    }

    @objc private func openAntigravityApp() {
        let appPath = "/Applications/Antigravity.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
    }

    @objc private func openAntigravityIde() {
        let idePath = "/Applications/Antigravity IDE.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: idePath))
    }

    // MARK: - Tab 0: Accounts Management Setup

    private func setupAccountsTab(frame: NSRect) {
        let accView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))

        let padX: CGFloat = 20
        var currentY: CGFloat = frame.height - 34

        // Header Title, Alias Checkbox & Refresh Button
        let titleLabel = NSTextField(labelWithString: L10n.tr("settings.accounts_list_title"))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: padX, y: currentY, width: 230, height: 20)
        accView.addSubview(titleLabel)
        self.accountsListHeaderLabel = titleLabel

        let chkAlias = NSButton(
            checkboxWithTitle: L10n.tr("settings.show_alias_checkbox"),
            target: self,
            action: #selector(showAliasToggled(_:))
        )
        chkAlias.font = NSFont.systemFont(ofSize: 12)
        chkAlias.frame = NSRect(x: padX + 235, y: currentY - 2, width: 210, height: 24)
        chkAlias.state = ConfigManager.shared.config.showAccountAlias ? .on : .off
        accView.addSubview(chkAlias)
        self.accountsShowAliasCheckbox = chkAlias

        let refreshBtn = NSButton(title: "🔄 \(L10n.tr("menu.refresh_quota"))", target: self, action: #selector(refreshQuotasClicked))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = NSFont.systemFont(ofSize: 11.5)
        refreshBtn.frame = NSRect(x: frame.width - padX - 160, y: currentY - 2, width: 160, height: 26)
        accView.addSubview(refreshBtn)
        self.accountsRefreshButton = refreshBtn

        currentY -= 32

        // Table View inside ScrollView
        let tableHeight: CGFloat = 280
        let scrollFrame = NSRect(x: padX, y: currentY - tableHeight, width: frame.width - padX * 2, height: tableHeight)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let tv = NSTableView(frame: NSRect(x: 0, y: 0, width: scrollFrame.width - 20, height: tableHeight))
        tv.usesAlternatingRowBackgroundColors = true
        tv.rowHeight = 46
        tv.allowsEmptySelection = true
        tv.allowsMultipleSelection = false
        tv.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tv.target = self
        tv.doubleAction = #selector(tableDoubleClicked(_:))

        // Column 1: Account & Plan (Email + Tier)
        let colAccount = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AccountCol"))
        colAccount.title = L10n.tr("settings.col_account_plan")
        colAccount.width = 240
        colAccount.minWidth = 180
        colAccount.resizingMask = [.userResizingMask, .autoresizingMask]
        tv.addTableColumn(colAccount)

        // Column 2: Active Model & Operational Status
        let colModel = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ModelCol"))
        colModel.title = L10n.tr("settings.col_model_status")
        colModel.width = 170
        colModel.minWidth = 140
        colModel.resizingMask = [.userResizingMask, .autoresizingMask]
        tv.addTableColumn(colModel)

        // Column 3: Gemini 5h Quota
        let col5h = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Quota5hCol"))
        col5h.title = L10n.tr("settings.col_quota_5h")
        col5h.width = 100
        col5h.minWidth = 80
        col5h.resizingMask = [.userResizingMask, .autoresizingMask]
        tv.addTableColumn(col5h)

        // Column 4: Gemini Weekly Quota
        let colWk = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("QuotaWkCol"))
        colWk.title = L10n.tr("settings.col_quota_week")
        colWk.width = 100
        colWk.minWidth = 80
        colWk.resizingMask = [.userResizingMask, .autoresizingMask]
        tv.addTableColumn(colWk)

        scrollView.documentView = tv
        accView.addSubview(scrollView)
        self.accountsScrollView = scrollView

        // Action Buttons Row 1: Set Active, Edit Alias, Select Model & Delete (placed clearly BELOW scrollView)
        let scrollBottom = scrollFrame.origin.y
        let btnHeight: CGFloat = 28
        let btnRow1Y = scrollBottom - 14 - btnHeight

        let btnSwitch = NSButton(
            title: L10n.tr("settings.btn_switch_account"),
            target: self,
            action: #selector(setActiveAccountClicked)
        )
        btnSwitch.bezelStyle = .rounded
        btnSwitch.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        btnSwitch.frame = NSRect(x: padX, y: btnRow1Y, width: 150, height: btnHeight)
        btnSwitch.isEnabled = false
        accView.addSubview(btnSwitch)
        self.switchAccountButton = btnSwitch

        let btnEdit = NSButton(
            title: L10n.tr("settings.btn_edit_alias"),
            target: self,
            action: #selector(editAliasClicked)
        )
        btnEdit.bezelStyle = .rounded
        btnEdit.font = NSFont.systemFont(ofSize: 11.5)
        btnEdit.frame = NSRect(x: padX + 160, y: btnRow1Y, width: 145, height: btnHeight)
        btnEdit.isEnabled = false
        accView.addSubview(btnEdit)
        self.editAliasButton = btnEdit

        let btnModel = NSButton(
            title: L10n.tr("settings.btn_select_model"),
            target: self,
            action: #selector(selectModelClicked)
        )
        btnModel.bezelStyle = .rounded
        btnModel.font = NSFont.systemFont(ofSize: 11.5)
        btnModel.frame = NSRect(x: padX + 315, y: btnRow1Y, width: 155, height: btnHeight)
        btnModel.isEnabled = false
        accView.addSubview(btnModel)
        self.selectModelButton = btnModel

        let btnDel = NSButton(
            title: L10n.tr("settings.btn_delete_account"),
            target: self,
            action: #selector(deleteAccountClicked)
        )
        btnDel.bezelStyle = .rounded
        btnDel.font = NSFont.systemFont(ofSize: 11.5)
        btnDel.frame = NSRect(x: padX + 480, y: btnRow1Y, width: 140, height: btnHeight)
        btnDel.isEnabled = false
        accView.addSubview(btnDel)
        self.deleteAccountButton = btnDel

        // Separator between Row 1 and Row 2
        let sepY = btnRow1Y - 14
        let actionSep = NSBox(frame: NSRect(x: padX, y: sepY, width: frame.width - padX * 2, height: 1))
        actionSep.boxType = .separator
        accView.addSubview(actionSep)
        self.accountsActionSeparator = actionSep

        // Empty State View (in place of Header + Table + Row 1 Buttons)
        let emptyFrame = NSRect(x: padX, y: sepY + 14, width: frame.width - padX * 2, height: (frame.height - 34) - (sepY + 14))
        let emptyCard = createCardBox(frame: emptyFrame)

        let iconLabel = NSTextField(labelWithString: "🪐")
        iconLabel.font = NSFont.systemFont(ofSize: 48)
        iconLabel.alignment = .center
        iconLabel.frame = NSRect(x: 20, y: emptyFrame.height - 96, width: emptyFrame.width - 40, height: 56)
        emptyCard.addSubview(iconLabel)

        let emptyTitle = NSTextField(labelWithString: L10n.tr("settings.no_accounts_linked"))
        emptyTitle.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        emptyTitle.textColor = .labelColor
        emptyTitle.alignment = .center
        emptyTitle.frame = NSRect(x: 20, y: emptyFrame.height - 138, width: emptyFrame.width - 40, height: 24)
        emptyCard.addSubview(emptyTitle)

        let emptyDesc = NSTextField(labelWithString: L10n.tr("settings.no_accounts_desc"))
        emptyDesc.font = NSFont.systemFont(ofSize: 12.5)
        emptyDesc.textColor = .secondaryLabelColor
        emptyDesc.alignment = .center
        emptyDesc.frame = NSRect(x: 40, y: emptyFrame.height - 200, width: emptyFrame.width - 80, height: 48)
        if let cell = emptyDesc.cell as? NSTextFieldCell {
            cell.wraps = true
        }
        emptyCard.addSubview(emptyDesc)

        let tipLabel = NSTextField(labelWithString: L10n.tr("settings.no_accounts_action_tip"))
        tipLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        tipLabel.textColor = .systemBlue
        tipLabel.alignment = .center
        tipLabel.frame = NSRect(x: 20, y: 24, width: emptyFrame.width - 40, height: 20)
        emptyCard.addSubview(tipLabel)

        accView.addSubview(emptyCard)
        self.emptyStateContainer = emptyCard

        // Action Buttons Row 2: Add Accounts (OAuth, IDE, JSON)
        let btnRow2Y = sepY - 14 - btnHeight

        let addOAuthBtn = NSButton(
            title: L10n.tr("settings.btn_login_browser"),
            target: self,
            action: #selector(addBrowserOAuthClicked)
        )
        addOAuthBtn.bezelStyle = .rounded
        addOAuthBtn.font = NSFont.systemFont(ofSize: 11.5)
        addOAuthBtn.frame = NSRect(x: padX, y: btnRow2Y, width: 220, height: btnHeight)
        accView.addSubview(addOAuthBtn)

        let addIdeBtn = NSButton(
            title: L10n.tr("settings.btn_import_ide"),
            target: self,
            action: #selector(addFromIdeClicked)
        )
        addIdeBtn.bezelStyle = .rounded
        addIdeBtn.font = NSFont.systemFont(ofSize: 11.5)
        addIdeBtn.frame = NSRect(x: padX + 226, y: btnRow2Y, width: 190, height: btnHeight)
        accView.addSubview(addIdeBtn)

        let addJsonBtn = NSButton(
            title: L10n.tr("settings.btn_import_json"),
            target: self,
            action: #selector(addFromJsonClicked)
        )
        addJsonBtn.bezelStyle = .rounded
        addJsonBtn.font = NSFont.systemFont(ofSize: 11.5)
        addJsonBtn.frame = NSRect(x: padX + 422, y: btnRow2Y, width: 155, height: btnHeight)
        accView.addSubview(addJsonBtn)

        self.accountsView = accView
        self.tableView = tv

        tv.delegate = self
        tv.dataSource = self

        updateAccountsVisibility()
    }

    public func refreshAccountsList(accounts: [AccountStatus]) {
        self.accountsData = accounts
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateAccountsVisibility()
            self.tableView?.reloadData()
            self.updateAccountButtonStates()
        }
    }

    private func updateAccountsVisibility() {
        let hasAccounts = !accountsData.isEmpty

        accountsListHeaderLabel?.isHidden = !hasAccounts
        accountsShowAliasCheckbox?.isHidden = !hasAccounts
        accountsRefreshButton?.isHidden = !hasAccounts
        accountsScrollView?.isHidden = !hasAccounts
        switchAccountButton?.isHidden = !hasAccounts
        editAliasButton?.isHidden = !hasAccounts
        selectModelButton?.isHidden = !hasAccounts
        deleteAccountButton?.isHidden = !hasAccounts
        accountsActionSeparator?.isHidden = !hasAccounts

        emptyStateContainer?.isHidden = hasAccounts
    }

    private func updateAccountButtonStates() {
        guard let btnSwitch = switchAccountButton,
              let btnDel = deleteAccountButton else { return }
        guard let tv = tableView else {
            btnSwitch.isEnabled = false
            editAliasButton?.isEnabled = false
            selectModelButton?.isEnabled = false
            btnDel.isEnabled = false
            return
        }
        let selectedRow = tv.selectedRow
        if selectedRow >= 0 && selectedRow < accountsData.count {
            let acc = accountsData[selectedRow]
            btnSwitch.isEnabled = !acc.isCurrent
            editAliasButton?.isEnabled = true
            selectModelButton?.isEnabled = true
            btnDel.isEnabled = !acc.isCurrent
        } else {
            btnSwitch.isEnabled = false
            editAliasButton?.isEnabled = false
            selectModelButton?.isEnabled = false
            btnDel.isEnabled = false
        }
    }

    // MARK: - NSTableView DataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return accountsData.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < accountsData.count else { return nil }
        let acc = accountsData[row]
        let colId = tableColumn?.identifier.rawValue ?? ""

        let cellId = NSUserInterfaceItemIdentifier("TwoLineCell_\(colId)")
        let cellView: TwoLineTableCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? TwoLineTableCellView {
            cellView = existing
        } else {
            cellView = TwoLineTableCellView(frame: .zero)
            cellView.identifier = cellId
        }

        switch colId {
        case "AccountCol":
            let statusIcon = acc.isCurrent ? "🟢" : "⚪"
            let tierName = acc.subscriptionTier ?? L10n.tr("tier.free")
            let showAlias = ConfigManager.shared.config.showAccountAlias

            if showAlias && !acc.name.isEmpty {
                cellView.titleLabel.stringValue = "\(statusIcon) \(acc.name)"
                cellView.subtitleLabel.stringValue = "\(acc.email)  •  \(tierName)"
            } else {
                cellView.titleLabel.stringValue = "\(statusIcon) \(acc.email)"
                let trimmed = acc.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.lowercased() != acc.email.lowercased() {
                    cellView.subtitleLabel.stringValue = "\(trimmed)  •  \(tierName)"
                } else {
                    cellView.subtitleLabel.stringValue = tierName
                }
            }

            if acc.isCurrent {
                cellView.titleLabel.font = NSFont.boldSystemFont(ofSize: 12.5)
                cellView.titleLabel.textColor = NSColor.labelColor
            } else {
                cellView.titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
                cellView.titleLabel.textColor = NSColor.labelColor
            }
            cellView.subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            cellView.subtitleLabel.textColor = acc.isCurrent ? NSColor.systemBlue : NSColor.secondaryLabelColor

        case "ModelCol":
            let modelTitle = acc.displayModelName
            cellView.titleLabel.stringValue = "🤖 \(modelTitle)"
            cellView.titleLabel.font = acc.isCurrent ? NSFont.boldSystemFont(ofSize: 11.5) : NSFont.systemFont(ofSize: 11.5)
            cellView.titleLabel.textColor = acc.isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor

            if acc.isCurrent {
                cellView.subtitleLabel.stringValue = "● \(L10n.tr("settings.sub_active"))"
                cellView.subtitleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
                cellView.subtitleLabel.textColor = NSColor.systemGreen
            } else {
                cellView.subtitleLabel.stringValue = "○ \(L10n.tr("settings.sub_standby"))"
                cellView.subtitleLabel.font = NSFont.systemFont(ofSize: 10.5)
                cellView.subtitleLabel.textColor = NSColor.secondaryLabelColor
            }

        case "Quota5hCol":
            let pct = acc.gemini5hPercentage ?? acc.remainingPercentage
            if pct < 0 {
                cellView.titleLabel.stringValue = L10n.tr("menu.token_error")
                cellView.titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
                cellView.titleLabel.textColor = NSColor.systemRed
            } else {
                cellView.titleLabel.stringValue = "\(pct)%"
                cellView.titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
                if pct <= ConfigManager.shared.config.thresholdPercentage {
                    cellView.titleLabel.textColor = NSColor.systemRed
                } else if pct <= 30 {
                    cellView.titleLabel.textColor = NSColor.systemOrange
                } else {
                    cellView.titleLabel.textColor = NSColor.systemGreen
                }
            }

            cellView.subtitleLabel.stringValue = L10n.tr("settings.sub_quota_5h")
            cellView.subtitleLabel.font = NSFont.systemFont(ofSize: 10.5)
            cellView.subtitleLabel.textColor = NSColor.secondaryLabelColor

        case "QuotaWkCol":
            if let wk = acc.geminiWeeklyPercentage {
                cellView.titleLabel.stringValue = "\(wk)%"
                cellView.titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                cellView.titleLabel.textColor = NSColor.labelColor
            } else {
                cellView.titleLabel.stringValue = "--"
                cellView.titleLabel.font = NSFont.systemFont(ofSize: 12)
                cellView.titleLabel.textColor = NSColor.tertiaryLabelColor
            }

            cellView.subtitleLabel.stringValue = L10n.tr("settings.sub_quota_week")
            cellView.subtitleLabel.font = NSFont.systemFont(ofSize: 10.5)
            cellView.subtitleLabel.textColor = NSColor.secondaryLabelColor

        default:
            cellView.titleLabel.stringValue = ""
            cellView.subtitleLabel.stringValue = ""
        }

        return cellView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateAccountButtonStates()
    }

    // MARK: - Account Tab Action Handlers

    @objc private func refreshQuotasClicked() {
        onUpdateCallback?()
    }

    @objc private func setActiveAccountClicked() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < accountsData.count else { return }
        switchAccountAtRow(row)
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        guard let tv = tableView else { return }
        let row = tv.clickedRow
        guard row >= 0 && row < accountsData.count else { return }
        switchAccountAtRow(row)
    }

    private func switchAccountAtRow(_ row: Int) {
        let acc = accountsData[row]
        guard !acc.isCurrent else { return }

        AccountRotator.shared.switchToAccount(id: acc.id) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    NotificationManager.shared.sendManualSwitchNotification(account: acc.currentDisplayName, quota: acc.remainingPercentage)
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

    @objc private func editAliasClicked() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < accountsData.count else { return }
        let acc = accountsData[row]

        let alert = NSAlert()
        alert.messageText = L10n.tr("settings.edit_alias_title")
        alert.informativeText = L10n.tr("settings.edit_alias_msg", acc.email)
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = acc.name
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.tr("settings.btn_save"))
        alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let newAlias = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newAlias.isEmpty {
                let res = AccountManager.shared.updateAccountAlias(id: acc.id, newName: newAlias)
                showAlert(
                    title: res.success ? L10n.tr("alert.success") : L10n.tr("alert.error"),
                    message: res.message,
                    style: res.success ? .informational : .warning
                )
                if res.success {
                    self.onUpdateCallback?()
                }
            }
        }
    }

    @objc private func selectModelClicked() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < accountsData.count else { return }
        let acc = accountsData[row]

        let alert = NSAlert()
        alert.messageText = L10n.tr("settings.select_model_title")
        alert.informativeText = L10n.tr("settings.select_model_msg", acc.currentDisplayName)
        alert.alertStyle = .informational

        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
        popUp.font = NSFont.systemFont(ofSize: 12)

        // Option: Auto / System Default
        let autoItem = NSMenuItem(title: L10n.tr("model.auto"), action: nil, keyEquivalent: "")
        autoItem.representedObject = ""
        popUp.menu?.addItem(autoItem)

        // Group: Google Gemini
        popUp.menu?.addItem(NSMenuItem.separator())
        let geminiHeader = NSMenuItem(title: "── Google Gemini ──", action: nil, keyEquivalent: "")
        geminiHeader.isEnabled = false
        popUp.menu?.addItem(geminiHeader)
        for opt in AIModelCatalog.geminiModels {
            let item = NSMenuItem(title: opt.displayName, action: nil, keyEquivalent: "")
            item.representedObject = opt.id
            popUp.menu?.addItem(item)
        }

        // Group: Anthropic Claude
        popUp.menu?.addItem(NSMenuItem.separator())
        let claudeHeader = NSMenuItem(title: "── Anthropic Claude ──", action: nil, keyEquivalent: "")
        claudeHeader.isEnabled = false
        popUp.menu?.addItem(claudeHeader)
        for opt in AIModelCatalog.claudeModels {
            let item = NSMenuItem(title: opt.displayName, action: nil, keyEquivalent: "")
            item.representedObject = opt.id
            popUp.menu?.addItem(item)
        }

        // Group: Other
        popUp.menu?.addItem(NSMenuItem.separator())
        let otherHeader = NSMenuItem(title: "── \(L10n.tr("model.group_other")) ──", action: nil, keyEquivalent: "")
        otherHeader.isEnabled = false
        popUp.menu?.addItem(otherHeader)
        for opt in AIModelCatalog.otherModels {
            let item = NSMenuItem(title: opt.displayName, action: nil, keyEquivalent: "")
            item.representedObject = opt.id
            popUp.menu?.addItem(item)
        }

        // Select current preference
        let currentPref = acc.preferredModelId ?? ""
        var found = false
        for item in popUp.itemArray {
            if (item.representedObject as? String) == currentPref {
                popUp.select(item)
                found = true
                break
            }
        }
        if !found {
            popUp.selectItem(at: 0)
        }

        alert.accessoryView = popUp
        alert.addButton(withTitle: L10n.tr("settings.btn_apply"))
        alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let selectedModelId = (popUp.selectedItem?.representedObject as? String) ?? ""
            let res = AccountManager.shared.updateAccountModel(id: acc.id, modelId: selectedModelId)
            showAlert(
                title: res.success ? L10n.tr("alert.success") : L10n.tr("alert.error"),
                message: res.message,
                style: res.success ? .informational : .warning
            )
            if res.success {
                self.onUpdateCallback?()
            }
        }
    }

    @objc private func deleteAccountClicked() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < accountsData.count else { return }
        let acc = accountsData[row]

        let alert = NSAlert()
        alert.messageText = L10n.tr("alert.delete_confirm_title")
        alert.informativeText = L10n.tr("alert.delete_confirm_msg", acc.email)
        alert.alertStyle = .critical
        let delBtn = alert.addButton(withTitle: L10n.tr("alert.btn_delete"))
        delBtn.hasDestructiveAction = true
        alert.addButton(withTitle: L10n.tr("alert.btn_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let res = AccountManager.shared.deleteAccount(id: acc.id)
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

    @objc private func addBrowserOAuthClicked() {
        OAuthServer.shared.startLoginFlow { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.showAlert(
                    title: success ? L10n.tr("alert.success") : L10n.tr("alert.notice"),
                    message: message,
                    style: success ? .informational : .warning
                )
                if success {
                    self.onUpdateCallback?()
                }
            }
        }
    }

    @objc private func addFromIdeClicked() {
        let res = AccountManager.shared.importFromCurrentIdeLogin()
        showAlert(
            title: res.success ? L10n.tr("alert.success") : L10n.tr("alert.notice"),
            message: res.message,
            style: res.success ? .informational : .warning
        )
        if res.success {
            onUpdateCallback?()
        }
    }

    @objc private func addFromJsonClicked() {
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

    // MARK: - Helpers

    private func createCardBox(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
        box.borderWidth = 1.0
        box.cornerRadius = 8.0
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        return box
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: L10n.tr("alert.btn_close"))
        alert.runModal()
    }

    public func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}

// MARK: - Custom 2-Line Table Cell View

private final class TwoLineTableCellView: NSTableCellView {
    let titleLabel = NSTextField()
    let subtitleLabel = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        for label in [titleLabel, subtitleLabel] {
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])
    }
}
