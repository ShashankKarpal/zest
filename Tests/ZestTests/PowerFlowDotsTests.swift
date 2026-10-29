import XCTest
@testable import Zest

// The power flow dots take their place from the clock (2026-10-29). The old animation moved
// `phase` from 0 to 1, which puts every dot in the same place, so the dots never travelled
// and the endless animation only made the dropdown collapse and regrow.
final class PowerFlowDotsTests: XCTestCase {
    private let width: CGFloat = 60
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testDotsTravelAsTimePasses() {
        let a = PowerFlowView.dotX(phase: PowerFlowView.phase(at: t0), width: width, index: 0, reverse: false)
        let b = PowerFlowView.dotX(phase: PowerFlowView.phase(at: t0.addingTimeInterval(0.3)), width: width, index: 0, reverse: false)
        XCTAssertNotEqual(a, b, accuracy: 1, "a dot must move within a quarter cycle")
    }

    func testPositionsRepeatEveryCycle() {
        for dt in stride(from: 0.0, to: 1.2, by: 0.1) {
            let t = t0.addingTimeInterval(dt)
            XCTAssertEqual(PowerFlowView.phase(at: t),
                           PowerFlowView.phase(at: t.addingTimeInterval(PowerFlowView.dotCycle)), accuracy: 1e-6)
        }
    }

    func testPhaseStaysInRangeAndDotsStayOnTheLink() {
        for dt in stride(from: -5.0, to: 5.0, by: 0.05) {
            let p = PowerFlowView.phase(at: t0.addingTimeInterval(dt))
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThan(p, 1)
            for i in 0..<3 {
                for reverse in [false, true] {
                    let x = PowerFlowView.dotX(phase: p, width: width, index: i, reverse: reverse)
                    XCTAssertGreaterThanOrEqual(x, -width / 2 - 1e-9)
                    XCTAssertLessThanOrEqual(x, width / 2 + 1e-9)
                }
            }
        }
    }

    func testDotsAreAThirdApartAndReverseRunsBackwards() {
        let p: CGFloat = 0.1
        let xs = (0..<3).map { PowerFlowView.dotX(phase: p, width: width, index: $0, reverse: false) }
        XCTAssertEqual(xs[1] - xs[0], width / 3, accuracy: 1e-9)
        XCTAssertEqual(xs[2] - xs[1], width / 3, accuracy: 1e-9)

        let forward = PowerFlowView.dotX(phase: 0.2, width: width, index: 0, reverse: false)
            - PowerFlowView.dotX(phase: 0.1, width: width, index: 0, reverse: false)
        let backward = PowerFlowView.dotX(phase: 0.2, width: width, index: 0, reverse: true)
            - PowerFlowView.dotX(phase: 0.1, width: width, index: 0, reverse: true)
        XCTAssertGreaterThan(forward, 0)
        XCTAssertLessThan(backward, 0)
    }
}
