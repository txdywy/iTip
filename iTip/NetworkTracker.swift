import Foundation
import AppKit
import os.log

/// Periodically samples per-process network usage via `nettop` and accumulates
/// download bytes per bundle identifier into the UsageStore.
final class NetworkTracker {

    private let store: UsageStoreProtocol
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").networkTracker", qos: .utility)

    private static let maxAccumulatedEntries = 500

    /// Accumulated bytes per bundle ID (in-memory, flushed periodically).
    private var accumulatedBytes: [String: Int64] = [:]

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Start polling nettop every `interval` seconds.
    func start(interval: TimeInterval = 10.0) {
        timer?.cancel()
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
        let output = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/nettop"),
            arguments: ["-P", "-L", "1", "-x", "-n"]
        )
        guard let output else { return }
        let perPID = parseNettop(output)
        let perBundle = ProcessUtils.mapToBundleIDs(perPID)

        for (bundleID, bytes) in perBundle where bytes > 0 {
            accumulatedBytes[bundleID, default: 0] += bytes
        }

        flush()
    }

    func flush() {
        guard !accumulatedBytes.isEmpty else { return }
        let snapshot = accumulatedBytes
        accumulatedBytes.removeAll()

        do {
            try store.updateRecords { records in
                var index: [String: Int] = [:]
                index.reserveCapacity(records.count)
                for (i, r) in records.enumerated() {
                    index[r.bundleIdentifier] = i
                }
                for (bundleID, bytes) in snapshot {
                    if let idx = index[bundleID] {
                        records[idx].totalBytesDownloaded += bytes
                    }
                    // Only update existing records — don't create new ones just for network data
                }
            }
        } catch {
            os_log("NetworkTracker: flush failed: %{public}@", log: AppLog.networkTracker, type: .error, error.localizedDescription)
            if accumulatedBytes.count < Self.maxAccumulatedEntries {
                for (k, v) in snapshot {
                    accumulatedBytes[k, default: 0] += v
                }
            } else {
                os_log("NetworkTracker: accumulated entries exceeded cap (%d), dropping data", log: AppLog.networkTracker, type: .fault, Self.maxAccumulatedEntries)
            }
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
}
