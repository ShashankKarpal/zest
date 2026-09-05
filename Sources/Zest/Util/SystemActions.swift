import Foundation
import ServiceManagement
import ApplicationServices
import AppKit

// Launch at login via SMAppService.
enum LoginItem {
    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Zest: login item toggle failed: \(error.localizedDescription)")
        }
    }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}

// Low Power Mode. Reading the state is a ProcessInfo call (no shell; the old
// `pmset -g | grep powermode` ran on the main thread inside a SwiftUI body on every redraw,
// and on current macOS `pmset -g` no longer prints that key at all, so it always read Off).
// Changes arrive through NSProcessInfoPowerStateDidChange; ChargeLimiter republishes them.
// Toggling still needs root (`pmset -a lowpowermode`) through the zest-smc sudoers path and
// runs off the main thread. No-op without the grant.
enum LowPowerMode {
    static func current() -> Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static func toggle(completion: ((Bool) -> Void)? = nil) {
        guard let helper = ZestHelper.path else { completion?(false); return }
        let target = current() ? "0" : "1"
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Shell.run("sudo -n \(ZestHelper.quote(helper)) lowpowermode \(target) 2>&1", timeout: 4)
            let ok = out.contains("ok")
            DispatchQueue.main.async { completion?(ok) }
        }
    }
}

// Auto-dismiss the default macOS battery notifications. Requires Accessibility. Best-effort:
// it walks the Notification Center UI over AX and presses Close on notifications whose text
// mentions battery, charge, or low power. It only ever presses a close button on a matching
// notification, nothing else. macOS notification internals change between versions, so this
// is a genuine attempt rather than a guarantee.
enum MacAlertDismisser {
    static func trusted() -> Bool { AXIsProcessTrusted() }

    // Prompts for Accessibility and opens the pane.
    static func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Exact macOS battery notification phrases only. The earlier list matched any
    // notification containing "charge", which dismissed bank and receipt banners
    // ("your card was charged") as a side effect (audit 2026-09-02).
    private static let keywords = ["low battery", "battery low", "your mac will sleep soon",
                                   "connected to power", "not charging", "low power mode"]

    static func dismissBatteryNotifications() {
        guard trusted() else { return }
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        for window in windows {
            if elementMentionsBattery(window, depth: 0), let close = findCloseButton(window, depth: 0) {
                AXUIElementPerformAction(close, kAXPressAction as CFString)
            }
        }
    }

    private static func stringValue(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let kids = ref as? [AXUIElement] else { return [] }
        return kids
    }
    private static func elementMentionsBattery(_ el: AXUIElement, depth: Int) -> Bool {
        if depth > 6 { return false }
        for attr in [kAXValueAttribute as String, kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
            if let s = stringValue(el, attr)?.lowercased(), keywords.contains(where: { s.contains($0) }) { return true }
        }
        for c in children(el) { if elementMentionsBattery(c, depth: depth + 1) { return true } }
        return false
    }
    private static func findCloseButton(_ el: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 6 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""
        if role == (kAXButtonRole as String) {
            let label = ((stringValue(el, kAXTitleAttribute as String) ?? "") + " " + (stringValue(el, kAXDescriptionAttribute as String) ?? "")).lowercased()
            if label.contains("close") || label.contains("clear") { return el }
        }
        for c in children(el) { if let f = findCloseButton(c, depth: depth + 1) { return f } }
        return nil
    }
}
