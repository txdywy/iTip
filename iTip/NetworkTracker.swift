import Foundation
import AppKit

/// Periodically samples per-process network usage via `nettop` and accumulates
/// download bytes per bundle identifier into the UsageStore.
final class NetworkTracker {

    private let store: UsageStoreProtocol
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.example.iTip.networkTracker", qos: .utility)

    /// Accumulated bytes per bundle ID (in-memory, flushed periodically).
    private var accumulatedBytes: [String: Int64] = [:]

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Start polling nettop every `interval` seconds.
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
        flush()
    }

    // MARK: - Private

    private func sample() {
        guard let output = runNettop() else { return }
        let perPID = parseNettop(output)
        let perBundle = mapToBundleIDs(perPID)

        for (bundleID, bytes) in perBundle where bytes > 0 {
            accumulatedBytes[bundleID, default: 0] += bytes
        }

        flush()
    }

    private func flush() {
        guard !accumulatedBytes.isEmpty else { return }
        let snapshot = accumulatedBytes
        accumulatedBytes.removeAll()

        do {
            var records = try store.load()
            for (bundleID, bytes) in snapshot {
                if let idx = records.firstIndex(where: { $0.bundleIdentifier == bundleID }) {
                    let r = records[idx]
                    records[idx] = UsageRecord(
                        bundleIdentifier: r.bundleIdentifier,
                        displayName: r.displayName,
                        lastActivatedAt: r.lastActivatedAt,
                        activationCount: r.activationCount,
                        totalActiveSeconds: r.totalActiveSeconds,
                        totalBytesDownloaded: r.totalBytesDownloaded + bytes
                    )
                }
                // Only update existing records — don't create new ones just for network data
            }
            try store.save(records)
        } catch {
            // Put bytes back if save failed
            for (k, v) in snapshot {
                accumulatedBytes[k, default: 0] += v
            }
        }
    }

    private func runNettop() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-n"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parse nettop CSV output into [PID: bytesIn].
    private func parseNettop(_ output: String) -> [pid_t: Int64] {
        var result: [pid_t: Int64] = [:]
        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() { // skip header
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 5 else { continue }

            // Column 1: "processName.PID"
            let processField = cols[1].trimmingCharacters(in: .whitespaces)
            guard let dotRange = processField.range(of: ".", options: .backwards),
                  let pid = Int32(processField[dotRange.upperBound...]) else { continue }

            // Column 4: bytes_in
            let bytesIn = Int64(cols[4].trimmingCharacters(in: .whitespaces)) ?? 0
            if bytesIn > 0 {
                result[pid] = bytesIn
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

        for (pid, bytes) in perPID {
            if let bundleID = pidToBundleID[pid] {
                result[bundleID, default: 0] += bytes
            }
        }
        return result
    }
}
