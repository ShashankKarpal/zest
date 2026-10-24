import Foundation
import IOKit

// zest-smc: tiny privileged helper for the Low Power Mode toggle.
//
// WHY A SEPARATE HELPER: `pmset -a lowpowermode` needs root. Rather than run the whole app
// as root, Zest shells out to this one small binary via `sudo -n`, enabled by sudoers lines
// that name the exact argument vectors the app sends (install-helper.sh). Until those lines
// exist, the app never calls it.
//
// SCOPE: Low Power Mode only. Charge control was dropped by owner decision (2026-07-13:
// charge care stays with macOS), so the SMC write command (`limit-set`) and the diagnostic
// `read` and `size` commands are gone; this binary writes no SMC key. `limit-get` is a
// read-only SMC canary the app no longer calls; the sudoers grant does not cover it, so it
// can only ever run as the invoking user.
//
// Usage:
//   zest-smc probe                 -> prints "ok root" when run as root (grant check)
//   zest-smc limit-get             -> prints "limit 1" or "limit 0" (or "error ...")
//   zest-smc lowpowermode 0|1      -> pmset -a lowpowermode 0|1 (root only)

// MARK: SMC plumbing (AppleSMC user client, documented protocol)

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

private struct SMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
private struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

// 32-byte payload as a fixed tuple to match the kernel struct ABI.
private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

private final class SMC {
    private var conn: io_connect_t = 0

    func open() -> Bool {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        return IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess
    }
    func close() { if conn != 0 { IOServiceClose(conn); conn = 0 } }

    private func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for ch in s.utf8.prefix(4) { r = (r << 8) | UInt32(ch) }
        return r
    }

    private func call(_ input: inout SMCParamStruct, _ output: inout SMCParamStruct) -> kern_return_t {
        var inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &input, inSize, &output, &outSize)
    }

    // Returns the byte value of a 1-byte key, or nil on failure.
    func readByte(_ key: String) -> UInt8? {
        var input = SMCParamStruct(); var output = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = SMC_CMD_READ_KEYINFO
        guard call(&input, &output) == kIOReturnSuccess, output.result == 0 else { return nil }
        let size = output.keyInfo.dataSize
        guard size >= 1 else { return nil }

        var readIn = SMCParamStruct(); var readOut = SMCParamStruct()
        readIn.key = fourCC(key)
        readIn.keyInfo.dataSize = size
        readIn.data8 = SMC_CMD_READ_BYTES
        guard call(&readIn, &readOut) == kIOReturnSuccess, readOut.result == 0 else { return nil }
        return readOut.bytes.0
    }
}

// MARK: Commands

func isRoot() -> Bool { getuid() == 0 }

func runPmsetLowPower(_ on: Bool) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-a", "lowpowermode", on ? "1" : "0"]
    try? p.run(); p.waitUntilExit()
    print(p.terminationStatus == 0 ? "ok" : "error pmset exit \(p.terminationStatus)")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print("usage: zest-smc <probe|limit-get|lowpowermode 0|1>"); exit(2) }

// probe works without SMC so the app can detect the sudoers grant is present.
if cmd == "probe" { print(isRoot() ? "ok root" : "ok"); exit(0) }

switch cmd {
case "limit-get":
    let smc = SMC()
    guard smc.open() else { print("error smc-open"); exit(1) }
    defer { smc.close() }
    if let v = smc.readByte("CHWA") { print("limit \(v == 0 ? 0 : 1)") }
    else { print("error smc-read") ; exit(1) }

case "lowpowermode":
    // Exactly "0" or "1", checked before the root check so a bad argument never reaches pmset.
    guard args.count == 2, args[1] == "0" || args[1] == "1" else { print("error bad-arg"); exit(2) }
    guard isRoot() else { print("error not-root"); exit(1) }
    runPmsetLowPower(args[1] == "1")

default:
    print("error unknown-command \(cmd)"); exit(2)
}
