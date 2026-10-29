import Foundation
import IOKit

// Read-only access to the AppleSMC sensor keys, as the logged-in user (no root, no helper).
// Used for the battery temperature: macOS 27 dropped the `Temperature` key from the
// AppleSmartBattery registry entry, and no other registry key carries a live value
// (2026-10-29). The battery sensors TB0T, TB1T and TB2T are typed floats in degrees
// Celsius on Apple Silicon (sp78 fixed point on older Macs). Only the two read commands
// are ever sent; this file has no write path.
final class SMCReader {
    // Mirrors the kernel's SMCKeyData_t (80 bytes). The explicit padding after the key
    // info matters: without it Swift packs `result` into the tuple's tail and every call
    // is rejected.
    private struct KeyData {
        var key: UInt32 = 0
        var vers = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt16(0))
        var pLimit = (UInt16(0), UInt16(0), UInt32(0), UInt32(0), UInt32(0))
        var keyInfo = (UInt32(0), UInt32(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
    private static let kernelIndex: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9

    static let batteryTemperatureKeys = ["TB0T", "TB1T", "TB2T"]

    private var connection: io_connect_t = 0
    // Fixed per key; a key that does not exist is kept as size 0, so it is asked about once
    // per reader.
    private var keyInfo: [UInt32: (size: UInt32, type: UInt32)] = [:]

    init?() {
        guard MemoryLayout<KeyData>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    // Mean of the battery sensors that answer with a plausible value; nil when none do.
    func batteryTemperature() -> Double? {
        Self.batteryTemperature(Self.batteryTemperatureKeys.compactMap { key in
            read(key).flatMap { Self.celsius(type: $0.type, bytes: $0.bytes) }
        })
    }

    // Rounded to the 0.1 C the tile shows, so float noise does not republish the snapshot on
    // every refresh. A key that exists without a sensor reads 0, hence the lower bound.
    static func batteryTemperature(_ readings: [Double]) -> Double? {
        let ok = readings.filter { (1...90).contains($0) }
        guard !ok.isEmpty else { return nil }
        return (ok.reduce(0, +) / Double(ok.count) * 10).rounded() / 10
    }

    // Decodes a temperature reading. Unknown types give nil rather than a guess.
    static func celsius(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let v = Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
            return v.isFinite ? v : nil
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard key.utf8.count == 4 else { return nil }
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        if keyInfo[code] == nil {
            var ask = KeyData(); ask.key = code; ask.data8 = Self.readKeyInfo
            let info = call(&ask)
            keyInfo[code] = info.map { ($0.keyInfo.0, $0.keyInfo.1) } ?? (0, 0)
        }
        guard let info = keyInfo[code] else { return nil }
        let size = Int(info.size)
        guard size > 0, size <= 32 else { return nil }
        var get = KeyData(); get.key = code; get.keyInfo.0 = info.size; get.data8 = Self.readBytes
        guard let out = call(&get) else { return nil }
        let type = String(bytes: [24, 16, 8, 0].map { UInt8((info.type >> $0) & 0xff) }, encoding: .ascii) ?? ""
        let all = withUnsafeBytes(of: out.bytes) { Array($0) }
        return (type, Array(all.prefix(size)))
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.stride
        let r = IOConnectCallStructMethod(connection, Self.kernelIndex, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
        return r == KERN_SUCCESS && output.result == 0 ? output : nil
    }
}
