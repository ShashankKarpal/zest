import Foundation

// Thin wrapper around Process for running shell commands. Used by the ported widget
// panels (which shell out to the exact same pipelines the Ubersicht widgets use) and by
// a handful of system_profiler / ps reads.
enum Shell {
    @discardableResult
    static func run(_ command: String, timeout: TimeInterval = 15) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", command]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()

        // Block on semaphores instead of polling: the old loop woke every 20 ms for the
        // whole life of the child, which for a 3 s panel script was 150 wakeups per run.
        let exited = DispatchSemaphore(value: 0)
        let drained = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return "" }

        let box = OutputBox()
        let handle = out.fileHandleForReading
        // Read to EOF on a background thread so a chatty child can never fill the pipe
        // buffer and deadlock against our wait.
        DispatchQueue.global(qos: .utility).async {
            box.set(handle.readDataToEndOfFile())
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            // Give the child a moment to die; SIGKILL if it ignores SIGTERM.
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL); _ = exited.wait(timeout: .now() + 2) }
        }
        // EOF arrives when every writer closes; a grandchild holding the pipe open would
        // otherwise pin us here, so cap the drain wait like the old code did. If the drain
        // has not finished, the box is still empty and we return "" rather than racing it.
        _ = drained.wait(timeout: .now() + 1)
        return String(data: box.get(), encoding: .utf8) ?? ""
    }

    private final class OutputBox {
        private var data = Data()
        private let lock = NSLock()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    // Runs a command and returns parsed JSON as a dictionary, or nil.
    static func runJSON(_ command: String, timeout: TimeInterval = 20) -> [String: Any]? {
        let out = run(command, timeout: timeout)
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}
