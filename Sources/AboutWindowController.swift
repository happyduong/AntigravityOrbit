import Cocoa

public class AboutWindowController: NSObject, NSWindowDelegate {
    public static let shared = AboutWindowController()

    private var window: NSWindow?

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
            guard let self = self, let win = self.window, win.isVisible else { return }
            win.close()
            self.showWindow()
        }
    }

    public func showWindow() {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let windowWidth: CGFloat = 480
        let windowHeight: CGFloat = 440
        let contentRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("about.title")
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let contentView = NSView(frame: contentRect)
        contentView.wantsLayer = true
        win.contentView = contentView

        // MARK: - 1. Logo (Left Side)
        let iconSize: CGFloat = 90
        let iconView = NSImageView(frame: NSRect(x: 24, y: windowHeight - 24 - iconSize, width: iconSize, height: iconSize))
        iconView.imageScaling = .scaleProportionallyUpOrDown

        if let icon = loadAppIcon() {
            iconView.image = icon
        }
        contentView.addSubview(iconView)

        // MARK: - 2. App Info List (Right Side)
        let rightX: CGFloat = 132
        let rightWidth: CGFloat = windowWidth - rightX - 24
        let topY = windowHeight - 24

        // App Name
        let titleLabel = NSTextField(labelWithString: "Antigravity Orbit")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: rightX, y: topY - 24, width: rightWidth, height: 24)
        contentView.addSubview(titleLabel)

        // Version
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: String(format: L10n.tr("about.version"), versionString))
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.frame = NSRect(x: rightX, y: topY - 46, width: rightWidth, height: 18)
        contentView.addSubview(versionLabel)

        // "Contact Information" Section
        let contactHeader = NSTextField(labelWithString: L10n.tr("about.contact_header"))
        contactHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        contactHeader.textColor = .labelColor
        contactHeader.frame = NSRect(x: rightX, y: topY - 74, width: rightWidth, height: 18)
        contentView.addSubview(contactHeader)

        // Key-Value Rows (Email, Author)
        let labelWidth: CGFloat = 72

        // Email Row
        let emailKey = NSTextField(labelWithString: L10n.tr("about.email"))
        emailKey.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        emailKey.textColor = .labelColor
        emailKey.frame = NSRect(x: rightX, y: topY - 96, width: labelWidth, height: 16)
        contentView.addSubview(emailKey)

        let emailVal = NSTextField(labelWithString: "phucduongqb@gmail.com")
        emailVal.font = NSFont.systemFont(ofSize: 12)
        emailVal.textColor = .secondaryLabelColor
        emailVal.isSelectable = true
        emailVal.frame = NSRect(x: rightX + labelWidth + 4, y: topY - 96, width: rightWidth - labelWidth - 4, height: 16)
        contentView.addSubview(emailVal)

        // Author Row
        let authorKey = NSTextField(labelWithString: L10n.tr("about.author"))
        authorKey.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        authorKey.textColor = .labelColor
        authorKey.frame = NSRect(x: rightX, y: topY - 116, width: labelWidth, height: 16)
        contentView.addSubview(authorKey)

        let authorVal = NSTextField(labelWithString: "Happy Duong")
        authorVal.font = NSFont.systemFont(ofSize: 12)
        authorVal.textColor = .secondaryLabelColor
        authorVal.isSelectable = true
        authorVal.frame = NSRect(x: rightX + labelWidth + 4, y: topY - 116, width: rightWidth - labelWidth - 4, height: 16)
        contentView.addSubview(authorVal)

        // License Row
        let licenseKey = NSTextField(labelWithString: L10n.tr("about.license"))
        licenseKey.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        licenseKey.textColor = .labelColor
        licenseKey.frame = NSRect(x: rightX, y: topY - 136, width: labelWidth, height: 16)
        contentView.addSubview(licenseKey)

        let licenseVal = NSTextField(labelWithString: L10n.tr("about.license_val"))
        licenseVal.font = NSFont.systemFont(ofSize: 12)
        licenseVal.textColor = .secondaryLabelColor
        licenseVal.isSelectable = true
        licenseVal.frame = NSRect(x: rightX + labelWidth + 4, y: topY - 136, width: rightWidth - labelWidth - 4, height: 16)
        contentView.addSubview(licenseVal)

        // MARK: - 3. Introduction & Version Log Section (Bottom)
        let introHeader = NSTextField(labelWithString: L10n.tr("about.intro_header"))
        introHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        introHeader.textColor = .labelColor
        introHeader.frame = NSRect(x: 24, y: 240, width: windowWidth - 48, height: 18)
        contentView.addSubview(introHeader)

        let scrollFrame = NSRect(x: 24, y: 20, width: windowWidth - 48, height: 215)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: scrollFrame.width, height: scrollFrame.height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollFrame.width - 8, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let introDesc = L10n.tr("about.intro_body")
        let fullText = """
\(introDesc)

\(L10n.tr("about.copyright_val"))
"""
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributedLog = NSAttributedString(
            string: fullText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        textView.textStorage?.setAttributedString(attributedLog)

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        self.window = nil
    }

    private func loadAppIcon() -> NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if let icon = NSApp.applicationIconImage {
            return icon
        }
        if let path = Bundle.main.path(forResource: "AppIcon1024", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return nil
    }
}
