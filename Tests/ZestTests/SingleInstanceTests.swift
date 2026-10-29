import XCTest
@testable import Zest

// Audit Z-B13: when the lock file could not be opened, the guard let every copy run, so a
// second launch drew a second menu bar icon.
final class SingleInstanceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("zest-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testUnopenableLockStillStopsASecondCopy() throws {
        // A path below a regular file cannot be opened (ENOTDIR).
        let file = dir.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        let path = file.appendingPathComponent("zest.lock").path

        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { true }), .duplicate,
                       "another copy is running: step aside even without a lock")
        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { false }), .unlocked(ENOTDIR),
                       "no other copy: run, and report why the lock is missing")
    }

    // Review round 1: a lock call that fails for another reason than "already locked" (a
    // filesystem without flock support) used to exit as if another copy held the lock.
    func testOnlyAHeldLockMeansADuplicateWithoutAsking() {
        let path = dir.appendingPathComponent("zest.lock").path
        let unsupported: (Int32) -> Int32 = { _ in errno = ENOTSUP; return -1 }
        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { false }, lock: unsupported), .unlocked(ENOTSUP))
        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { true }, lock: unsupported), .duplicate)
        var asked = false
        let held: (Int32) -> Int32 = { _ in errno = EWOULDBLOCK; return -1 }
        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { asked = true; return false }, lock: held), .duplicate)
        XCTAssertFalse(asked, "a held lock decides on its own")
    }

    func testTheLockDecidesWhileItCanBeOpened() {
        let path = dir.appendingPathComponent("zest.lock").path
        var asked = false
        guard case .acquired(let fd) = SingleInstance.acquire(lockPath: path, otherCopyRunning: { asked = true; return true }) else {
            return XCTFail("the first copy takes the lock")
        }
        XCTAssertFalse(asked, "the running-app list is only a fallback")
        XCTAssertEqual(SingleInstance.acquire(lockPath: path, otherCopyRunning: { false }), .duplicate,
                       "a held lock stops a second copy")
        close(fd)
        guard case .acquired(let again) = SingleInstance.acquire(lockPath: path, otherCopyRunning: { false }) else {
            return XCTFail("the lock is free again once its holder is gone")
        }
        close(again)
    }
}
