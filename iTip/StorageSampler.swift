import Foundation
import AppKit
import os.log

/// Periodically samples per-app disk storage space (allocated size of the .app bundle)
/// and updates `diskStorageBytes` on existing UsageRecords in the store.
///
/// Implementation note: `kMDItemFSSize` via Spotlight only returns the inode size of
/// the .app directory root entry (~128 bytes), NOT the total bundle size. The correct
/// approach is to enumerate the bundle with `totalFileAllocatedSizeKey`, which sums
/// the actual disk-allocated blocks for every file inside the package.
///
/// Performance: bundle sizes are cached and only recalculated when the bundle's
/// `contentModificationDate` changes, avoiding redundant full-directory traversals
/// of large apps (e.g. Xcode ~35 GB) every sample cycle.
final class StorageSampler {

    private let store: UsageStoreProtocol
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "iTip").storageSampler", qos: .utility)

    /// Cache: bundleURL path → (contentModificationDate, computed size).
    /// Avoids re-enumerating unchanged bundles every cycle.
    private var sizeCache: [String: (modDate: Date, size: Int64)] = [:]

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Start sampling storage space. Less frequent since installed app size rarely changes.
    func start(interval: TimeInterval = 300.0) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: interval)
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
        guard let records = try? store.load() else { return }
        var perBundle: [String: Int64] = [:]
        perBundle.reserveCapacity(records.count)

        for r in records {
            // urlForApplication is documented as thread-safe on NSWorkspace.
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: r.bundleIdentifier) else { continue }
            let size = cachedBundleSize(at: appURL)
            if size > 0 {
                perBundle[r.bundleIdentifier] = size
            }
        }

        guard !perBundle.isEmpty else { return }

        do {
            try store.updateRecords { diskRecords in
                var index: [String: Int] = [:]
                index.reserveCapacity(diskRecords.count)
                for (i, r) in diskRecords.enumerated() {
                    index[r.bundleIdentifier] = i
                }
                for (bundleID, size) in perBundle {
                    if let idx = index[bundleID] {
                        diskRecords[idx].diskStorageBytes = size
                    }
                }
            }
        } catch {
            os_log("StorageSampler: failed to update records: %{public}@", log: AppLog.storageSampler, type: .error, error.localizedDescription)
        }
    }

    /// Returns the cached bundle size, recalculating only when the bundle's
    /// content modification date has changed (e.g. after an app update).
    private func cachedBundleSize(at url: URL) -> Int64 {
        let cacheKey = url.path
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        if let cached = sizeCache[cacheKey],
           let modDate,
           cached.modDate == modDate {
            return cached.size
        }

        let size = bundleSize(at: url)
        sizeCache[cacheKey] = (modDate: modDate ?? .distantPast, size: size)
        return size
    }

    /// Returns the total allocated disk size of an .app bundle by recursively
    /// summing `totalFileAllocatedSizeKey` for each file inside the package.
    /// Files that cannot be stat'd (e.g. system-private entries) are skipped
    /// silently to avoid crashing or returning 0 for the whole bundle.
    ///
    /// Does NOT skip hidden files so the result matches Finder's "Get Info"
    /// and `du -sh` output.
    private func bundleSize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                // Skip files we can't access (permission denied inside .app) and continue
                return true
            }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: keys),
                  resourceValues.isDirectory != true else { continue }
            total += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        return total
    }
}


