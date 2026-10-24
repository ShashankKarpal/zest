import Foundation

// zest-smc: tiny privileged helper for the Low Power Mode toggle.
//
// WHY A SEPARATE HELPER: `pmset -a lowpowermode` needs root. Rather than run the whole app
// as root, Zest shells out to this one small binary via `sudo -n`, enabled by sudoers lines
// that name the exact argument vectors the app sends (install-helper.sh). Until those lines
// exist, the app never calls it.
//
// SCOPE: Low Power Mode only. Charge control was dropped by owner decision (2026-07-13:
// charge care stays with macOS), so v3.1 removed every SMC command (`limit-get`,
// `limit-set`, `read`, `size`) together with the SMC client; this binary opens no IOKit
// connection and writes nothing but the pmset setting.
//
// Usage:
//   zest-smc probe              -> prints "ok root helper <interface>" when run as root
//   zest-smc lowpowermode 0|1   -> pmset -a lowpowermode 0|1 (root only)

// Raised whenever the command set or the sudoers grant changes. The app reads it from
// `probe`: a helper without it was installed by an older install-helper.sh, whose grant
// allowed this binary with any arguments, and the app asks for a re-install.
let helperInterface = 2

func isRoot() -> Bool { getuid() == 0 }

func runPmsetLowPower(_ on: Bool) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-a", "lowpowermode", on ? "1" : "0"]
    try? p.run(); p.waitUntilExit()
    print(p.terminationStatus == 0 ? "ok" : "error pmset exit \(p.terminationStatus)")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print("usage: zest-smc <probe|lowpowermode 0|1>"); exit(2) }

switch cmd {
case "probe":
    // Lets the app detect that the sudoers grant is present, and which helper answers.
    print(isRoot() ? "ok root helper \(helperInterface)" : "ok helper \(helperInterface)")

case "lowpowermode":
    // Exactly "0" or "1", checked before the root check so a bad argument never reaches pmset.
    guard args.count == 2, args[1] == "0" || args[1] == "1" else { print("error bad-arg"); exit(2) }
    guard isRoot() else { print("error not-root"); exit(1) }
    runPmsetLowPower(args[1] == "1")

default:
    print("error unknown-command \(cmd)"); exit(2)
}
