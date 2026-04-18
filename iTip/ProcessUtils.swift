import Foundation
import AppKit

/// Runs a subprocess with an optional timeout, returning its stdout.
struct ProcessRunner {

    /// Default timeout for subprocess execution.
    static let defaultTimeout: TimeInterval = 8.0

    /// Runs a process at the given URL with the specified arguments.
    /// - Parameters:
    ///   - executableURL: Path to the executable.
    ///   - arguments: Command-line arguments.
    ///   - timeout: Maximum seconds to wait before terminating the process.
    /// - Returns: The stdout output as a String, or nil on failure.
    static func run(executableURL: URL, arguments: [String] = [], timeout: TimeInterval = defaultTimeout) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Safety-net termination on a separate queue so the timeout
            // can fire even while waitUntilExit() blocks the caller.
            let terminationWork = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: terminationWork)

            process.waitUntilExit()
            terminationWork.cancel()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Shared utilities for mapping process-level data to bundle identifiers.
enum ProcessUtils {

    /// Builds a PID → bundleIdentifier lookup from currently running applications.
    static func pidToBundleIDMap() -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier {
                result[app.processIdentifier] = bid
            }
        }
        return result
    }

    /// Maps per-PID data to per-bundleIdentifier data by aggregating values
    /// for processes belonging to the same application.
    static func mapToBundleIDs(_ perPID: [pid_t: Int64]) -> [String: Int64] {
        let lookup = pidToBundleIDMap()
        var result: [String: Int64] = [:]
        for (pid, value) in perPID {
            if let bundleID = lookup[pid] {
                result[bundleID, default: 0] += value
            }
        }
        return result
    }
}
