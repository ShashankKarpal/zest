import Foundation

// Single-instance guard: a file lock ensures only one Zest runs, no matter how it is
// launched (manual open, LaunchAgent, or login item), so there is never a duplicate menu
// bar icon. When the lock file could not be opened (an unwritable or broken Application
// Support folder), every copy used to run unguarded (audit Z-B13); now the guard falls
// back to asking whether another copy is already running. The same fallback covers a
// lock call that fails for another reason than "already locked" (a filesystem without
// flock support), which used to exit silently as if another copy held it.
enum SingleInstance {
    enum Outcome: Equatable {
        case acquired(Int32)   // this copy holds the lock; keep the descriptor open for life
        case unlocked(Int32)   // open() or flock() failed with this errno and no other copy
                               // was found: run without the lock
        case duplicate         // another copy holds the lock, or is running: step aside
    }

    static func acquire(lockPath: String, otherCopyRunning: () -> Bool,
                        lock: (Int32) -> Int32 = { flock($0, LOCK_EX | LOCK_NB) }) -> Outcome {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            let openError = errno
            return otherCopyRunning() ? .duplicate : .unlocked(openError)
        }
        if lock(fd) == 0 { return .acquired(fd) }
        let lockError = errno
        close(fd)
        if lockError == EWOULDBLOCK { return .duplicate }
        return otherCopyRunning() ? .duplicate : .unlocked(lockError)
    }
}
