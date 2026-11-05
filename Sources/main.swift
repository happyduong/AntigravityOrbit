import Foundation
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private static var lockFd: Int32 = -1

    static func main() {
        setlinebuf(stdout)
        setlinebuf(stderr)

        // 1. Enforce single instance via file lock
        let orbitDir = ("~/.antigravity_orbit" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: orbitDir, withIntermediateDirectories: true)
        let lockPath = "\(orbitDir)/orbit.lock"
        lockFd = open(lockPath, O_CREAT | O_WRONLY, 0o644)
        if lockFd >= 0 {
            if flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
                print("[AntigravityOrbit] Another instance is already running. Exiting immediately.")
                exit(0)
            }
        }

        // 2. Cross-check running applications
        let currentPid = getpid()
        let bundleId = Bundle.main.bundleIdentifier ?? "com.antigravity.orbit"
        let otherApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).filter { $0.processIdentifier != currentPid }
        if !otherApps.isEmpty {
            print("[AntigravityOrbit] Detected running app with bundleID \(bundleId) (PID: \(otherApps.first?.processIdentifier ?? 0)). Exiting.")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Show tooltips instantly without default delay
        UserDefaults.standard.register(defaults: [
            "NSInitialToolTipDelay": 0
        ])

        // Sync launch at login status with user configuration
        LaunchAtLoginManager.shared.syncWithConfig()

        statusBarController = StatusBarController()
        print("[AntigravityOrbit] Started successfully.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if AppDelegate.lockFd >= 0 {
            flock(AppDelegate.lockFd, LOCK_UN)
            close(AppDelegate.lockFd)
        }
        print("[AntigravityOrbit] Terminated.")
    }
}
