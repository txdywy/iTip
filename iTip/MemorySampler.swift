import Foundation
import AppKit

/// Periodically samples per-process Resident Set Size (RSS) via `ps` and
/// updates `residentMemoryBytes` on existing UsageRecords in the store.
final class MemorySampler {

    private let store: UsageStoreProtocol
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.example.iTip.memorySampler", qos: .utility)

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Start sampling memory every `interval` seconds.
    func start(interval: TimeInterval = 10.0) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            self?.sample()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Private

    private func sample() {
        guard let output = runPS() else { return }
        let perPID = parsePS(output)
        let perBundle = mapToBundleIDs(perPID)

        guard !perBundle.isEmpty else { return }

        do {
            try store.updateRecords { records in
                for (bundleID, rss) in perBundle {
                    if let idx = records.firstIndex(where: { $0.bundleIdentifier == bundleID }) {
                        records[idx].residentMemoryBytes = rss
                    }
                    // Only update existing records — don't create new ones just for memory data
                }
            }
        } catch {
            // Silent — will retry next sample
        }
    }

    /// Run `ps -axo pid=,rss=` to get PID and RSS (in KB) for all processes.
    private func runPS() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parse `ps` output into [PID: rssBytes].
    /// Input format: lines of "  PID  RSS" (RSS in KB).
    private func parsePS(_ output: String) -> [pid_t: Int64] {
        var result: [pid_t: Int64] = [:]
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2,
                  let pid = Int32(parts[0]),
                  let rssKB = Int64(parts[1]) else { continue }
            let rssBytes = rssKB * 1024  // Convert KB → bytes
            if rssBytes > 0 {
                result[pid] = rssBytes
            }
        }
        return result
    }

    /// Map PIDs to bundle identifiers using NSRunningApplication.
    private func mapToBundleIDs(_ perPID: [pid_t: Int64]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        let runningApps = NSWorkspace.shared.runningApplications

        // Build PID → bundleID lookup
        var pidToBundleID: [pid_t: String] = [:]
        for app in runningApps {
            if let bid = app.bundleIdentifier {
                pidToBundleID[app.processIdentifier] = bid
            }
        }

        for (pid, rss) in perPID {
            if let bundleID = pidToBundleID[pid] {
                // Aggregate per bundle ID (a single app may have multiple processes/PIDs)
                result[bundleID, default: 0] += rss
            }
        }
        return result
    }
}
