import XCTest
@testable import Zest

// The 2026-09-05 energy pass: shared Bluetooth snapshot, Shell.run without a busy-wait,
// and battery health read from the IORegistry dictionary instead of system_profiler.
final class EnergyPassTests: XCTestCase {
    func testBluetoothInventoryFetchesOncePerTTL() {
        var calls = 0
        let inv = BluetoothInventory(ttl: 30) { calls += 1; return ["SPBluetoothDataType": [["n": calls]]] }
        let t0 = Date()
        _ = inv.snapshot(now: t0)
        _ = inv.snapshot(now: t0.addingTimeInterval(1))
        _ = inv.snapshot(now: t0.addingTimeInterval(29))
        XCTAssertEqual(calls, 1, "three callers inside the TTL must share one fetch")
        _ = inv.snapshot(now: t0.addingTimeInterval(31))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(inv.fetchCount, 2)
    }

    func testBluetoothInventoryKeepsLastGoodSnapshotWhenFetchFails() {
        var calls = 0
        let inv = BluetoothInventory(ttl: 30) { calls += 1; return calls == 1 ? ["ok": true] : nil }
        let t0 = Date()
        XCTAssertNotNil(inv.snapshot(now: t0))
        let stale = inv.snapshot(now: t0.addingTimeInterval(60))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(stale?["ok"] as? Bool, true, "a failed refresh returns the previous snapshot")
    }

    func testBluetoothInventorySerializesConcurrentCallers() {
        var calls = 0
        let inv = BluetoothInventory(ttl: 30) { calls += 1; usleep(50_000); return ["n": calls] }
        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async { _ = inv.snapshot(); group.leave() }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(calls, 1, "eight concurrent callers must cost one system_profiler run")
    }

    func testPanelRunnerDoesNotRunWhenNotDemanded() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zest-demand-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("ran")
        let script = dir.appendingPathComponent("vitals.sh")
        try? "#!/bin/bash\ntouch '\(marker.path)'\nprintf '{\"ok\": true}'\n".write(to: script, atomically: true, encoding: .utf8)
        let r = WidgetPanelRunner(scriptName: "vitals.sh", interval: 5, root: dir.path)
        r.demanded = false
        r.start()
        r.refresh()
        let idle = expectation(description: "idle"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { idle.fulfill() }
        wait(for: [idle], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "undemanded panel must not spawn its script")
        // Turning demand on runs it at once.
        r.demanded = true
        let ran = expectation(description: "ran")
        var polls = 0
        func poll() {
            if FileManager.default.fileExists(atPath: marker.path) || polls > 40 { ran.fulfill(); return }
            polls += 1; DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
        }
        poll()
        wait(for: [ran], timeout: 6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "demand on must trigger one run")
        r.stop()
    }

    func testShellRunReturnsOutput() {
        XCTAssertEqual(Shell.run("printf 'hello'", timeout: 5), "hello")
        XCTAssertEqual(Shell.run("echo a; echo b", timeout: 5), "a\nb\n")
    }

    func testShellRunTimesOutPromptly() {
        let t0 = Date()
        _ = Shell.run("sleep 10", timeout: 0.5)
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertLessThan(elapsed, 4.0, "timeout must terminate the child, not wait for it")
    }

    func testShellRunJSONParsesAndRejects() {
        XCTAssertEqual(Shell.runJSON(#"printf '{"a": 1}'"#, timeout: 5)?["a"] as? Int, 1)
        XCTAssertNil(Shell.runJSON("printf 'not json'", timeout: 5))
    }

    func testHealthFromRegistryGivesCyclesAndFallbackRatio() {
        let h = BatteryService.health(fromRegistry: [
            "CycleCount": 53, "DesignCapacity": 8579, "AppleRawMaxCapacity": 8205, "PermanentFailureStatus": 0
        ])
        XCTAssertEqual(h.cycles, 53)
        XCTAssertEqual(h.maxCap, 96)     // 8205 / 8579 = 95.6 -> 96 (fallback only; profiler wins)
        XCTAssertNil(h.condition, "condition is not derivable from the registry; system_profiler owns it")
    }

    func testHealthFromRegistryToleratesMissingKeys() {
        let h = BatteryService.health(fromRegistry: ["CycleCount": 10])
        XCTAssertEqual(h.cycles, 10)
        XCTAssertNil(h.maxCap)
        let none = BatteryService.health(fromRegistry: [:])
        XCTAssertNil(none.cycles)
        XCTAssertNil(none.maxCap)
        let zeroDesign = BatteryService.health(fromRegistry: ["DesignCapacity": 0, "AppleRawMaxCapacity": 100])
        XCTAssertNil(zeroDesign.maxCap, "never divide by a zero design capacity")
    }

    func testHealthParsedFromProfilerText() {
        let text = """
        Power:
            Battery Information:
              Health Information:
                  Cycle Count: 53
                  Condition: Normal
                  Maximum Capacity: 99%
        """
        let h = BatteryService.health(fromProfilerText: text)
        XCTAssertEqual(h.cycles, 53)
        XCTAssertEqual(h.maxCap, 99)
        XCTAssertEqual(h.condition, "Normal")
        let svc = BatteryService.health(fromProfilerText: "      Condition: Service Recommended\n")
        XCTAssertEqual(svc.condition, "Service Recommended")
        let empty = BatteryService.health(fromProfilerText: "")
        XCTAssertNil(empty.cycles); XCTAssertNil(empty.maxCap); XCTAssertNil(empty.condition)
    }
}
