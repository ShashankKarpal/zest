import XCTest
@testable import Zest

// AppleSmartBattery registry layouts (2026-10-29). macOS 27 moved DesignCapacity into
// BatteryData, replaced AppleRawMaxCapacity with BatteryData.FullChargeCapacity and dropped
// Temperature, so Design, Full and Temp showed "--". Values below are from the M4 Pro this
// was found on (`ioreg -rn AppleSmartBattery -a`, macOS 27.0.1), trimmed to the keys read.
final class BatteryRegistryTests: XCTestCase {
    private let macOS27: [String: Any] = [
        "Voltage": 12347, "InstantAmperage": 0, "ExternalConnected": true, "IsCharging": false,
        "FullyCharged": false, "CycleCount": 58, "MaxCapacity": 100,
        "BatteryData": ["DesignCapacity": 8579, "FullChargeCapacity": 8171,
                        "NominalChargeCapacity": 8415, "MaxCapacity": 100] as [String: Any],
    ]
    private let older: [String: Any] = [
        "Voltage": 12500, "InstantAmperage": 1200, "ExternalConnected": true, "IsCharging": true,
        "FullyCharged": false, "CycleCount": 40, "Temperature": 3045,
        "DesignCapacity": 8579, "AppleRawMaxCapacity": 8233,
    ]

    private func snapshot(_ dict: [String: Any]) -> BatterySnapshot {
        var s = BatterySnapshot()
        BatteryService.apply(registry: dict, to: &s)
        return s
    }

    func testMacOS27LayoutFillsDesignAndFull() {
        let s = snapshot(macOS27)
        XCTAssertEqual(s.designCapacityMAh, 8579)
        XCTAssertEqual(s.rawMaxCapacityMAh, 8171, "full charge capacity comes from BatteryData.FullChargeCapacity")
        XCTAssertNil(s.temperatureC, "no registry temperature on macOS 27: the SMC fallback decides")
        XCTAssertEqual(s.voltageV ?? 0, 12.347, accuracy: 0.0001)
    }

    func testOlderLayoutStillReadsTopLevelKeys() {
        let s = snapshot(older)
        XCTAssertEqual(s.designCapacityMAh, 8579)
        XCTAssertEqual(s.rawMaxCapacityMAh, 8233)
        XCTAssertEqual(s.temperatureC ?? 0, 30.45, accuracy: 0.0001)
    }

    func testTopLevelKeysWinWhenBothLayoutsArePresent() {
        var both = older
        both["BatteryData"] = ["DesignCapacity": 1, "FullChargeCapacity": 2]
        let s = snapshot(both)
        XCTAssertEqual(s.designCapacityMAh, 8579)
        XCTAssertEqual(s.rawMaxCapacityMAh, 8233)
    }

    func testMissingEverywhereStaysUnknown() {
        let s = snapshot(["Voltage": 12000])
        XCTAssertNil(s.designCapacityMAh)
        XCTAssertNil(s.rawMaxCapacityMAh)
        XCTAssertNil(s.temperatureC)
        XCTAssertFalse(s.temperatureUnavailable, "only the SMC fallback may declare it unavailable")
    }

    // SMC sensor decoding: bytes as the M4 Pro returned them for TB0T and TB1T.
    func testSMCFloatAndFixedPointDecode() {
        XCTAssertEqual(SMCReader.celsius(type: "flt ", bytes: [48, 51, 7, 66]) ?? 0, 33.80, accuracy: 0.01)
        XCTAssertEqual(SMCReader.celsius(type: "flt ", bytes: [48, 51, 5, 66]) ?? 0, 33.30, accuracy: 0.01)
        XCTAssertEqual(SMCReader.celsius(type: "sp78", bytes: [0x1E, 0x80]) ?? 0, 30.5, accuracy: 0.001)
        XCTAssertNil(SMCReader.celsius(type: "ui16", bytes: [254, 11]), "an unknown type is not guessed")
        XCTAssertNil(SMCReader.celsius(type: "flt ", bytes: [1, 2]), "a short value is rejected")
    }

    func testBatteryTemperatureAveragesPlausibleSensorsOnly() {
        XCTAssertEqual(SMCReader.batteryTemperature([33.8, 33.3, 33.8]) ?? 0, 33.6, accuracy: 1e-9, "rounded to the 0.1 C shown")
        XCTAssertEqual(SMCReader.batteryTemperature([33.0, -40, 150]) ?? 0, 33.0, accuracy: 1e-9)
        XCTAssertEqual(SMCReader.batteryTemperature([31.5, 31.8, 0.0]) ?? 0, 31.7, accuracy: 1e-9, "a key without a sensor reads 0 and is left out")
        XCTAssertNil(SMCReader.batteryTemperature([]))
        XCTAssertNil(SMCReader.batteryTemperature([-100, 400, 0]))
    }

    func testFloatNoiseDoesNotChangeTheTemperature() {
        XCTAssertEqual(SMCReader.batteryTemperature([31.53125]), SMCReader.batteryTemperature([31.546875]))
    }

    func testNotAvailableNeedsThreeMissesAndNoGoodReading() {
        XCTAssertFalse(BatteryService.temperatureUnavailable(everRead: false, misses: 1), "one glitch is not 'not available'")
        XCTAssertFalse(BatteryService.temperatureUnavailable(everRead: false, misses: 2))
        XCTAssertTrue(BatteryService.temperatureUnavailable(everRead: false, misses: 3))
        XCTAssertFalse(BatteryService.temperatureUnavailable(everRead: true, misses: 50), "worked once on this Mac: unknown, not unavailable")
    }
}
