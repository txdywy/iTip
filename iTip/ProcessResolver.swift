import Foundation
import AppKit

/// Resolves any process PID to its ancestor application PID and bundle identifier
/// by walking the process tree via `ps`.
final class ProcessResolver {

    private static let queueKey = DispatchSpecificKey<Void>()

    private var ppidMap: [Int: Int] = [:]
    private var appPIDToBundleID: [Int: String] = [:]
    private let queue = DispatchQueue(label: "com.example.iTip.processResolver")

    init() {
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    /// Refreshes the internal process tree and running-app mapping.
    func refresh() {
        let ppidMap = samplePPIDs()
        let appMap = sampleRunningApps()

        withQueueAccess {
            self.ppidMap = ppidMap
            self.appPIDToBundleID = appMap
        }
    }

    /// Given a PID, returns the bundle identifier of the ancestor app process.
    func bundleIdentifier(for pid: Int) -> String? {
        withQueueAccess {
            var current = pid
            for _ in 0..<100 { // safety limit
                if let bundleID = appPIDToBundleID[current] {
                    return bundleID
                }
                guard let parent = ppidMap[current], parent != current else {
                    return nil
                }
                current = parent
            }
            return nil
        }
    }

    private func withQueueAccess<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }

    // MARK: - Sampling

    private func samplePPIDs() -> [Int: Int] {
        guard let data = runPS(),
              let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [Int: Int] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = Int(fields[0]),
                  let ppid = Int(fields[1]) else { continue }
            result[pid] = ppid
        }
        return result
    }

    private func sampleRunningApps() -> [Int: String] {
        var result: [Int: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            result[Int(app.processIdentifier)] = bundleID
        }
        return result
    }

    private func runPS() -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,ppid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
