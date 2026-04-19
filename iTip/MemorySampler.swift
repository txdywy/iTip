import Foundation
import AppKit
import os.log

/// Periodically samples per-process Resident Set Size (RSS) via `proc_pidinfo`
/// Mach API and updates `residentMemoryBytes` on existing UsageRecords in the store.
/// Uses direct kernel calls instead of forking a `ps` subprocess, avoiding the
/// process-creation overhead every sample interval.
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
        // Query RSS directly via Mach proc_pidinfo — no subprocess fork required.
        let apps = NSWorkspace.shared.runningApplications
        var perBundle: [String: Int64] = [:]

        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            var taskInfo = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.stride
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
            guard ret == Int32(size) else { continue }
            let rss = Int64(taskInfo.pti_resident_size)
            if rss > 0 {
                perBundle[bundleID] = rss
            }
        }

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
}
