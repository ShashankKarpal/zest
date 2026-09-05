import Foundation
import Combine
import AppKit

// Resolves the privileged helper: the root-owned install written by
// zest-smc/install-helper.sh. That is the only path the sudoers grant names, so a copy
// anywhere else (the old build-tree fallback) could never have passed `sudo -n` anyway.
enum ZestHelper {
    static let candidates = ["/usr/local/libexec/zest/zest-smc"]
    static var path: String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

// Battery-care controller.
//
// IMPORTANT SAFETY DECISION: on this M4 Pro / macOS 26, the documented Apple Silicon charge
// key (CHWA) is not present, and the keys that are present (CHTE, CHSC, CHBI, ACLC) do not
// have verified public semantics for this model. Writing an unverified battery key is unsafe
// and against the no-guessing rule, so Zest does NOT write charge SMC keys here. Battery care
// is deferred to macOS (System Settings > Battery, which the user already runs at 80%). That
// is the safest option and requires no writes. Zest never touches the charge state.
//
// The helper is still used for Low Power Mode (pmset), which is verified and reversible.
// The SMC read/write plumbing in the helper works (verified via the #KEY canary); if the
// correct, verified M4 charge key is identified later, control can be re-enabled with no app
// changes beyond pointing at that key.
final class ChargeLimiter: ObservableObject {
    @Published private(set) var helperAvailable = false        // probe ok => Low Power Mode works
    @Published private(set) var chargeControlSupported = false // never true on this model in this build
    @Published private(set) var status = "Battery care is managed by macOS (safest)."
    // Live Low Power Mode state, kept current by NSProcessInfoPowerStateDidChange so no view
    // ever has to ask the system (let alone a shell) while it renders.
    @Published private(set) var lowPowerOn = ProcessInfo.processInfo.isLowPowerModeEnabled

    private let config: AppConfig
    private var battery: BatteryService?
    private var powerStateObserver: NSObjectProtocol?

    init(config: AppConfig) {
        self.config = config
        detectHelper()
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPowerOn = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
    deinit { if let o = powerStateObserver { NotificationCenter.default.removeObserver(o) } }

    func bind(battery: BatteryService) { self.battery = battery }

    // Probes the helper off the main thread; the probe is a sudo round trip that used to
    // block app launch for up to 4 s.
    func detectHelper() {
        guard let helper = ZestHelper.path else {
            helperAvailable = false
            status = "Low Power Mode toggle needs the one-time helper install (see README)."
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let probe = Shell.run("sudo -n \(ZestHelper.quote(helper)) probe 2>&1", timeout: 4)
            let ok = probe.contains("ok")
            DispatchQueue.main.async {
                self.helperAvailable = ok
                self.status = ok
                    ? "Battery care is managed by macOS (safest). Low Power Mode is available."
                    : "Add the sudoers line for zest-smc to enable the Low Power Mode toggle (see README)."
            }
        }
    }

    func toggleLowPower() {
        LowPowerMode.toggle { [weak self] _ in
            // The notification normally lands first; this covers a missed one.
            self?.lowPowerOn = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // Opens the macOS Battery settings pane where the native 80% limit lives.
    func openMacOSBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // No-ops kept so the rest of the app compiles; Zest does not write charge keys here.
    func topUpToFull() { openMacOSBatterySettings() }
    func restoreDefaults() {}
}
