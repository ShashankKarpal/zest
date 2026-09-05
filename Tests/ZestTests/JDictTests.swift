import XCTest
@testable import Zest

// JDict is the tolerant accessor every panel reads through; it must never trap on a
// missing or oddly typed field.
final class JDictTests: XCTestCase {
    func testNumbersFromEveryJSONShape() {
        let d = JDict(["a": 1, "b": 2.5, "c": "3.25", "d": NSNumber(value: 4), "e": "nope"])
        XCTAssertEqual(d.d("a"), 1)
        XCTAssertEqual(d.d("b"), 2.5)
        XCTAssertEqual(d.d("c"), 3.25)
        XCTAssertEqual(d.d("d"), 4)
        XCTAssertEqual(d.d("e", 7), 7)
        XCTAssertEqual(d.d("missing"), 0)
        XCTAssertEqual(d.i("b"), 3)   // rounds half up: 2.5 -> 3
    }

    func testMissingNestedValuesAreEmptyNotNil() {
        let d = JDict(["cu": ["sessionPercentage": 42]])
        XCTAssertEqual(d.obj("cu").i("sessionPercentage"), 42)
        XCTAssertTrue(d.obj("absent").isEmpty)
        XCTAssertTrue(d.arr("absent").isEmpty)
        XCTAssertTrue(d.objArr("absent").isEmpty)
        XCTAssertEqual(d.s("absent", "dflt"), "dflt")
        XCTAssertFalse(d.b("absent"))
        XCTAssertTrue(d.has("cu"))
    }

    func testInitFromAnyToleratesNonDictionaries() {
        XCTAssertTrue(JDict(nil).isEmpty)
        XCTAssertTrue(JDict("string" as Any).isEmpty)
        XCTAssertTrue(JDict([1, 2, 3] as Any).isEmpty)
    }
}
