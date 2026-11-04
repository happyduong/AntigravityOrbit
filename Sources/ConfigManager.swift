import Foundation

public struct RotatorConfig: Codable {
    public var thresholdPercentage: Int
    public var checkIntervalSeconds: Int
    public var autoRotateEnabled: Bool
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var launchAtLogin: Bool
    public var language: String
    public var showAccountAlias: Bool
    public var popoverLayoutStyle: PopoverLayoutStyle

    public static let `default` = RotatorConfig(
        thresholdPercentage: 10,
        checkIntervalSeconds: 60,
        autoRotateEnabled: true,
        notificationsEnabled: true,
        soundEnabled: true,
        launchAtLogin: true,
        language: "vi",
        showAccountAlias: false,
        popoverLayoutStyle: .streamlined
    )

    enum CodingKeys: String, CodingKey {
        case thresholdPercentage
        case checkIntervalSeconds
        case autoRotateEnabled
        case notificationsEnabled
        case soundEnabled
        case launchAtLogin
        case language
        case showAccountAlias
        case popoverLayoutStyle
    }

    public init(
        thresholdPercentage: Int,
        checkIntervalSeconds: Int,
        autoRotateEnabled: Bool,
        notificationsEnabled: Bool,
        soundEnabled: Bool,
        launchAtLogin: Bool,
        language: String = "vi",
        showAccountAlias: Bool = false,
        popoverLayoutStyle: PopoverLayoutStyle = .streamlined
    ) {
        self.thresholdPercentage = thresholdPercentage
        self.checkIntervalSeconds = checkIntervalSeconds
        self.autoRotateEnabled = autoRotateEnabled
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
        self.language = language
        self.showAccountAlias = showAccountAlias
        self.popoverLayoutStyle = popoverLayoutStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.thresholdPercentage = try container.decodeIfPresent(Int.self, forKey: .thresholdPercentage) ?? 10
        self.checkIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .checkIntervalSeconds) ?? 60
        self.autoRotateEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRotateEnabled) ?? true
        self.notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "vi"
        self.showAccountAlias = try container.decodeIfPresent(Bool.self, forKey: .showAccountAlias) ?? false
        self.popoverLayoutStyle = try container.decodeIfPresent(PopoverLayoutStyle.self, forKey: .popoverLayoutStyle) ?? .streamlined
    }
}

public class ConfigManager {
    public static let shared = ConfigManager()

    private let orbitDir: URL
    private let configPath: URL

    public private(set) var config: RotatorConfig

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.orbitDir = home.appendingPathComponent(".antigravity_orbit")
        self.configPath = orbitDir.appendingPathComponent("rotator_config.json")

        self.config = RotatorConfig.default
        try? FileManager.default.createDirectory(at: orbitDir, withIntermediateDirectories: true)
        load()
    }

    public func load() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configPath)
            self.config = try JSONDecoder().decode(RotatorConfig.self, from: data)
        } catch {
            print("[ConfigManager] Error loading config, using default: \(error)")
            self.config = RotatorConfig.default
            save()
        }
    }

    public func save() {
        do {
            let dir = configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)
        } catch {
            print("[ConfigManager] Error saving config: \(error)")
        }
    }

    public func updateLanguage(_ language: String) {
        config.language = language
        save()
    }

    public func updateThreshold(_ threshold: Int) {
        config.thresholdPercentage = threshold
        save()
    }

    public func updateCheckInterval(_ interval: Int) {
        config.checkIntervalSeconds = interval
        save()
    }

    public func toggleAutoRotate() {
        config.autoRotateEnabled.toggle()
        save()
    }

    public func toggleNotifications() {
        config.notificationsEnabled.toggle()
        save()
    }

    public func toggleSound() {
        config.soundEnabled.toggle()
        save()
    }

    public func toggleLaunchAtLogin() {
        config.launchAtLogin.toggle()
        save()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        config.launchAtLogin = enabled
        save()
    }

    public func toggleShowAccountAlias() {
        config.showAccountAlias.toggle()
        save()
    }

    public func setShowAccountAlias(_ enabled: Bool) {
        config.showAccountAlias = enabled
        save()
    }

    public func updatePopoverLayoutStyle(_ style: PopoverLayoutStyle) {
        config.popoverLayoutStyle = style
        save()
        NotificationCenter.default.post(name: .popoverLayoutDidChange, object: nil)
    }
}
