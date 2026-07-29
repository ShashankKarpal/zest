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
        do { try p.run() } catch { return "" }

        let deadline = Date().addingTimeInterval(timeout)
        let handle = out.fileHandleForReading
        var data = Data()
        // Read incrementally so a slow command cannot deadlock the pipe buffer.
        DispatchQueue.global().async {
            data = handle.readDataToEndOfFile()
        }
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()
        // Give the async reader a moment to finish draining.
        var waited = 0
        while data.isEmpty && waited < 50 { usleep(10_000); waited += 1 }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Runs a command and returns parsed JSON as a dictionary, or nil.
    static func runJSON(_ command: String, timeout: TimeInterval = 20) -> [String: Any]? {
        let out = run(command, timeout: timeout)
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}
