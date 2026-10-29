import AppKit

// Zest: a personal Mac battery command center. Menu bar app (LSUIElement). Builds and
// runs from Command Line Tools via SwiftPM, assembled into Zest.app by build.sh.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        state = AppState()
        statusController = StatusItemController(state: state)
        state.startPanels()

        // When the last visible window closes, drop back to accessory (no Dock icon).
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let anyVisible = NSApp.windows.contains { $0.isVisible && $0.className.contains("NSWindow") && ($0.styleMask.contains(.titled)) }
                if !anyVisible { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.shutdown()
    }
}

// Only one Zest runs (SingleInstance). The lock's descriptor stays open for the process
// lifetime.
func otherZest() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.shanky.zest")
        .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
}
let lockPath = AppConfig.dir.appendingPathComponent("zest.lock").path
switch SingleInstance.acquire(lockPath: lockPath, otherCopyRunning: { otherZest() != nil }) {
case .duplicate:
    // Another instance is already running; bring it forward and exit.
    otherZest()?.activate(options: [])
    exit(0)
case .unlocked(let openError):
    NSLog("Zest: could not open \(lockPath) (errno \(openError)); running without the single-instance lock")
case .acquired:
    break
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// launchd stops the agent with SIGTERM (bootout, logout, shutdown). By default that kills
// the process without applicationWillTerminate, so the energy history tail and the
// zest_stop event were lost on every reload. Route the signal into a normal terminate.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()

app.run()
