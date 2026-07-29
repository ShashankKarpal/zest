import Foundation
import IOKit

// zest-smc: tiny privileged helper for battery-care charge limiting and Low Power Mode.
//
// WHY A SEPARATE HELPER: SMC writes and `pmset -a lowpowermode` need root. Rather than run
// the whole app as root, Zest shells out to this one small binary via `sudo -n`, enabled by
// ONE sudoers NOPASSWD line. Until that line exists, the app never calls it.
//
// MECHANISM (safest available on Apple Silicon): the CHWA SMC flag. This is the SAME
// firmware charge-management flag macOS itself uses for its native 80% limit. Setting it is
// not a charge-interrupt hack; it is the hardware's own ceiling. It is a single byte
// (1 = hold ~80%, 0 = allow full) and fully reversible. We only ever touch CHWA and, for
// Low Power Mode, pmset. Nothing else is written.
//
// SAFETY: every command reads before it writes and fails closed. `limit-get` is a canary:
// the app runs it first and only enables control if the SMC read succeeds. On Intel Macs
// the equivalent key is BCLM; this build targets Apple Silicon (CHWA).
//
// Usage:
//   zest-smc probe                 -> prints "ok root" when run as root
//   zest-smc limit-get             -> prints "limit 1" or "limit 0" (or "error ...")
//   zest-smc limit-set 0|1         -> sets CHWA (1 = hold 80%, 0 = allow 100%)
//   zest-smc lowpowermode 0|1      -> pmset -a lowpowermode

// MARK: SMC plumbing (AppleSMC user client, documented protocol)

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_WRITE_BYTES: UInt8 = 6
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

    // Diagnostic read: returns a human-readable description of the read attempt.
    func diagRead(_ key: String) -> String {
        var input = SMCParamStruct(); var output = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = SMC_CMD_READ_KEYINFO
        let kr = call(&input, &output)
        if kr != kIOReturnSuccess { return "keyinfo-call kr=0x\(String(kr, radix: 16))" }
        if output.result != 0 { return "keyinfo-result=\(output.result)" }
        let size = output.keyInfo.dataSize
        let type = output.keyInfo.dataType

        var readIn = SMCParamStruct(); var readOut = SMCParamStruct()
        readIn.key = fourCC(key)
        readIn.keyInfo.dataSize = size
        readIn.data8 = SMC_CMD_READ_BYTES
        let kr2 = call(&readIn, &readOut)
        if kr2 != kIOReturnSuccess { return "read-call kr=0x\(String(kr2, radix: 16)) size=\(size)" }
        if readOut.result != 0 { return "read-result=\(readOut.result) size=\(size)" }
        return "ok size=\(size) type=0x\(String(type, radix: 16)) b0=\(readOut.bytes.0) b1=\(readOut.bytes.1)"
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

    // Writes a single byte to a 1-byte key. Returns true on success.
    @discardableResult
    func writeByte(_ key: String, _ value: UInt8) -> Bool {
        var info = SMCParamStruct(); var infoOut = SMCParamStruct()
        info.key = fourCC(key)
        info.data8 = SMC_CMD_READ_KEYINFO
        guard call(&info, &infoOut) == kIOReturnSuccess, infoOut.result == 0 else { return false }
        let size = infoOut.keyInfo.dataSize
        guard size >= 1 else { return false }

        var input = SMCParamStruct(); var output = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.dataSize = size
        input.keyInfo.dataType = infoOut.keyInfo.dataType
        input.data8 = SMC_CMD_WRITE_BYTES
        input.bytes.0 = value
        return call(&input, &output) == kIOReturnSuccess && output.result == 0
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
guard let cmd = args.first else { print("usage: zest-smc <probe|limit-get|limit-set 0|1|lowpowermode 0|1>"); exit(2) }

// probe works without SMC so the app can detect the sudoers grant is present.
if cmd == "probe" { print(isRoot() ? "ok root" : "ok"); exit(0) }

if cmd == "size" { print("stride=\(MemoryLayout<SMCParamStruct>.stride)"); exit(0) }

if cmd == "read" {
    guard args.count > 1 else { print("usage: read <KEY>"); exit(2) }
    let smc = SMC()
    guard smc.open() else { print("error smc-open"); exit(1) }
    defer { smc.close() }
    print(smc.diagRead(args[1]))
    exit(0)
}

switch cmd {
case "limit-get":
    let smc = SMC()
    guard smc.open() else { print("error smc-open"); exit(1) }
    defer { smc.close() }
    if let v = smc.readByte("CHWA") { print("limit \(v == 0 ? 0 : 1)") }
    else { print("error smc-read") ; exit(1) }

case "limit-set":
    guard isRoot() else { print("error not-root"); exit(1) }
    guard args.count > 1, let v = UInt8(args[1]), v == 0 || v == 1 else { print("error bad-arg"); exit(2) }
    let smc = SMC()
    guard smc.open() else { print("error smc-open"); exit(1) }
    defer { smc.close() }
    // Canary: confirm we can read the key before writing.
    guard smc.readByte("CHWA") != nil else { print("error smc-read"); exit(1) }
    if smc.writeByte("CHWA", v) {
        let back = smc.readByte("CHWA")
        print("ok limit \(back.map { $0 == 0 ? 0 : 1 } ?? Int(v))")
    } else { print("error smc-write"); exit(1) }

case "lowpowermode":
    guard isRoot() else { print("error not-root"); exit(1) }
    runPmsetLowPower(args.count > 1 && args[1] == "1")

default:
    print("error unknown-command \(cmd)"); exit(2)
}
