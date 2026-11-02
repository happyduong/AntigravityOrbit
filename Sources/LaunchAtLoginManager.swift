import Foundation
import ServiceManagement
import AppKit

public class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    private init() {
        cleanLegacyLaunchAgents()
    }

    /// Whether launch at login is currently active
    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled || status == .requiresApproval {
                return true
            }
            if checkAppleScriptLoginItem() {
                return true
            }
            return false
        } else {
            return checkAppleScriptLoginItem()
        }
    }

    /// Remove legacy LaunchAgent plists without unloading running process
    public func cleanLegacyLaunchAgents() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let orbitPlist = launchAgentsDir.appendingPathComponent("com.antigravity.orbit.plist")
        if FileManager.default.fileExists(atPath: orbitPlist.path) {
            try? FileManager.default.removeItem(at: orbitPlist)
        }
    }

    /// Toggle or set launch at login state
    @discardableResult
    public func setEnabled(_ enable: Bool) -> Bool {
        cleanLegacyLaunchAgents()

        var success = false

        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status == .enabled {
                        success = true
                    } else {
                        try SMAppService.mainApp.register()
                        success = (SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)
                        print("[LaunchAtLoginManager] Registered SMAppService.mainApp (status: \(SMAppService.mainApp.status.rawValue))")
                    }
                } else {
                    if SMAppService.mainApp.status != .notRegistered && SMAppService.mainApp.status != .notFound {
                        try SMAppService.mainApp.unregister()
                        print("[LaunchAtLoginManager] Unregistered SMAppService.mainApp")
                    }
                    success = true
                }
            } catch {
                print("[LaunchAtLoginManager] SMAppService error: \(error). Falling back to AppleScript login items...")
                success = setAppleScriptLoginItem(enabled: enable)
            }
        } else {
            success = setAppleScriptLoginItem(enabled: enable)
        }

        // Always ensure AppleScript login item is deleted when disabling
        if !enable {
            _ = setAppleScriptLoginItem(enabled: false)
        }

        ConfigManager.shared.setLaunchAtLogin(enable)
        return success
    }

    /// Sync system login item state on app launch with configured preference
    public func syncWithConfig() {
        cleanLegacyLaunchAgents()
        let shouldLaunch = ConfigManager.shared.config.launchAtLogin
        if shouldLaunch != isEnabled {
            setEnabled(shouldLaunch)
        }
    }

    // MARK: - AppleScript Fallback for System Events Login Items

    private func checkAppleScriptLoginItem() -> Bool {
        let appName = "Antigravity Orbit"
        let script = """
        tell application "System Events"
            return (exists (login item "\(appName)"))
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if error == nil {
            return result.booleanValue
        }
        return false
    }

    private func setAppleScriptLoginItem(enabled: Bool) -> Bool {
        let appName = "Antigravity Orbit"
        let appPath: String
        if Bundle.main.bundlePath.hasSuffix(".app") {
            appPath = Bundle.main.bundlePath
        } else {
            appPath = "/Applications/Antigravity Orbit.app"
        }

        let script: String
        if enabled {
            script = """
            tell application "System Events"
                if not (exists (login item "\(appName)")) then
                    make login item at end with properties {name:"\(appName)", path:"\(appPath)", hidden:false}
                end if
                return (exists (login item "\(appName)"))
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                delete (every login item whose name is "\(appName)")
                return not (exists (login item "\(appName)"))
            end tell
            """
        }

        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            print("[LaunchAtLoginManager] AppleScript error: \(error)")
            return false
        }
        return result.booleanValue
    }
}
