import XCTest
@testable import Zest

// Battery snapshot math and the health projection, both pure.
final class BatteryMathTests: XCTestCase {
    func testBatteryWattsSignFollowsAmperage() {
        var s = BatterySnapshot(); s.voltageV = 12.0; s.amperageMA = -1500
        XCTAssertEqual(s.batteryWatts, -18.0, accuracy: 0.001)
        XCTAssertEqual(s.batteryPowerState, "discharging")
        s.amperageMA = 2000
        XCTAssertEqual(s.batteryWatts, 24.0, accuracy: 0.001)
        XCTAssertEqual(s.batteryPowerState, "charging")
        s.amperageMA = 20
        XCTAssertEqual(s.batteryPowerState, "idle")
    }

    func testSystemWattsOnAdapterSubtractsChargeGoingIntoBattery() {
        var s = BatterySnapshot(); s.isACPower = true; s.adapterWatts = 96
        s.voltageV = 12.0; s.amperageMA = 2000       // 24 W into the battery
        XCTAssertEqual(s.systemWatts, 72.0, accuracy: 0.001)
        XCTAssertFalse(s.adapterUnderpowered)
    }

    func testSystemWattsOnBatteryEqualsDischarge() {
        var s = BatterySnapshot(); s.isACPower = false
        s.voltageV = 12.0; s.amperageMA = -1000
        XCTAssertEqual(s.systemWatts, 12.0, accuracy: 0.001)
    }

    func testAdapterUnderpoweredWhenBatteryDrainsOnAC() {
        var s = BatterySnapshot(); s.isACPower = true; s.adapterWatts = 30
        s.voltageV = 12.0; s.amperageMA = -500       // still discharging while plugged in
        XCTAssertTrue(s.adapterUnderpowered)
    }

    func testServiceRecommendedFromConditionOrCapacity() {
        var s = BatterySnapshot()
        XCTAssertFalse(s.serviceRecommended)
        s.condition = "Service Recommended"
        XCTAssertTrue(s.serviceRecommended)
        s.condition = "Normal"; s.maxCapacityPercent = 79
        XCTAssertTrue(s.serviceRecommended)
        s.maxCapacityPercent = 80
        XCTAssertFalse(s.serviceRecommended)
    }

    private func sample(day: String, daysAgo: Double, cap: Int?, cycles: Int?) -> BatteryHistory.Sample {
        BatteryHistory.Sample(day: day, maxCapacity: cap, cycles: cycles, tempC: nil,
                              ts: Date().timeIntervalSince1970 - daysAgo * 86400)
    }

    func testProjectionNeedsTwoCapacityPoints() {
        let p = BatteryHistory.projection(of: [sample(day: "2026-01-01", daysAgo: 10, cap: 95, cycles: 10)])
        XCTAssertNil(p.perMonthCycles)
        XCTAssertNil(p.monthsTo80)
    }

    func testProjectionDecliningCapacityGivesMonthsTo80() {
        // 100 -> 90 over 300 days: 1 point per 30 days, so 10 points to 80 is ~10 months.
        let p = BatteryHistory.projection(of: [
            sample(day: "2025-11-01", daysAgo: 300, cap: 100, cycles: 100),
            sample(day: "2026-09-01", daysAgo: 0, cap: 90, cycles: 200)
        ])
        XCTAssertEqual(p.monthsTo80, 10)
        XCTAssertEqual(p.perMonthCycles ?? -1, 10.0, accuracy: 0.05)
    }

    func testProjectionFlatCapacityHasNoDate() {
        let p = BatteryHistory.projection(of: [
            sample(day: "2026-08-01", daysAgo: 30, cap: 92, cycles: 50),
            sample(day: "2026-09-01", daysAgo: 0, cap: 92, cycles: 60)
        ])
        XCTAssertNil(p.monthsTo80)
        XCTAssertEqual(p.perMonthCycles ?? -1, 10.0, accuracy: 0.05)
    }
}
