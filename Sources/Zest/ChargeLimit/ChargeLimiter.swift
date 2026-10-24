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

    // The helper interface this app expects (zest-smc/main.swift `helperInterface`).
    static let interface = 2

    enum ProbeResult: Equatable { case unavailable, outdated, current }

    // Classifies the output of `sudo -n <helper> probe`. A helper older than v3.1 answers
    // "ok root" with no interface number; it was installed with a grant that allowed it
    // any arguments as root, so it still works but needs a re-install. The helper's answer
    // is the last line: sudo may print a warning line before it (stderr is merged).
    static func probeResult(_ output: String) -> ProbeResult {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let line = lines.last, line.hasPrefix("ok") else { return .unavailable }
        let words = line.split(separator: " ")
        if let i = words.firstIndex(of: "helper"), i + 1 < words.count,
           let n = Int(words[i + 1]), n >= interface {
            return .current
        }
        return .outdated
    }
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
// The helper is used for Low Power Mode (pmset) only, which is verified and reversible.
// Since v3.1 it carries no SMC code at all and its sudoers grant names only `probe` and
// `lowpowermode 0|1`, so charge control could come back only with a new helper command, a
// new grant line, and a re-install.
final class ChargeLimiter: ObservableObject {
    @Published private(set) var helperAvailable = false        // probe ok => Low Power Mode works
    @Published private(set) var helperOutdated = false         // pre-v3.1 helper and grant: re-install
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
            helperOutdated = false
            status = "Low Power Mode toggle needs the one-time helper install (see README)."
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let probe = Shell.run("sudo -n \(ZestHelper.quote(helper)) probe 2>&1", timeout: 4)
            let result = ZestHelper.probeResult(probe)
            DispatchQueue.main.async {
                self.helperAvailable = result != .unavailable
                self.helperOutdated = result == .outdated
                switch result {
                case .current:
                    self.status = "Battery care is managed by macOS (safest). Low Power Mode is available."
                case .outdated:
                    self.status = "The installed helper predates v3.1 and its sudoers entry lets it run as root with any arguments. Re-run zest-smc/install-helper.sh as root from a current clone (see README)."
                case .unavailable:
                    self.status = "Add the sudoers line for zest-smc to enable the Low Power Mode toggle (see README)."
                }
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
    func restoreDefaults() {}
}
