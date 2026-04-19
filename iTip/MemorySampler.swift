import Foundation
import AppKit
import os.log

/// Periodically samples per-process Resident Set Size (RSS) via `ps` and
/// updates `residentMemoryBytes` on existing UsageRecords in the store.
final class MemorySampler {

    private let store: UsageStoreProtocol
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").memorySampler", qos: .utility)

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Start sampling memory every `interval` seconds.
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
    }

    // MARK: - Private

    private func sample() {
        let output = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,rss="]
        )
        guard let output else {
            os_log("MemorySampler: failed to run ps command", log: AppLog.memorySampler, type: .error)
            return
        }
        let perPID = parsePS(output)
        let perBundle = ProcessUtils.mapToBundleIDs(perPID)

        guard !perBundle.isEmpty else { return }

        do {
            try store.updateRecords { records in
                var index: [String: Int] = [:]
                index.reserveCapacity(records.count)
                for (i, r) in records.enumerated() {
                    index[r.bundleIdentifier] = i
                }
                for (bundleID, rss) in perBundle {
                    if let idx = index[bundleID] {
                        records[idx].residentMemoryBytes = rss
                    }
                    // Only update existing records — don't create new ones just for memory data
                }
            }
        } catch {
            os_log("MemorySampler: failed to update records: %{public}@", log: AppLog.memorySampler, type: .error, error.localizedDescription)
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
}
