import Foundation
import os.log

/// Seeds the UsageStore with recently-used application data from Spotlight metadata
/// on cold start (when the store is empty). Uses kMDItemLastUsedDate and kMDItemUseCount
/// from the Spotlight index to pre-populate the app list.
struct SpotlightSeeder {

    private let store: UsageStoreProtocol

    init(store: UsageStoreProtocol) {
        self.store = store
    }

    /// Seeds the store if it is currently empty.
    /// Queries Spotlight for application bundles with recent usage data.
    func seedIfEmpty() {
        do {
            let records = querySpotlightForRecentApps()
            guard !records.isEmpty else { return }

            try store.updateRecords { existing in
                guard existing.isEmpty else { return }
                existing.append(contentsOf: records)
            }
        } catch {
            os_log("SpotlightSeeder: seedIfEmpty failed: %{public}@", log: AppLog.spotlightSeeder, type: .error, error.localizedDescription)
        }
    }

    // MARK: - Private

    private func querySpotlightForRecentApps() -> [UsageRecord] {
        let queryString = "kMDItemContentType == 'com.apple.application-bundle' && kMDItemLastUsedDate >= $time.today(-30)" as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString, nil, nil) else {
            return []
        }
        // Set a batch size limit to avoid long queries
        MDQuerySetMaxCount(query, 50)

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return []
        }

        let count = MDQueryGetResultCount(query)
        guard count > 0 else { return [] }

        var records: [UsageRecord] = []

        let selfBundleID = Bundle.main.bundleIdentifier ?? ""

        for i in 0..<count {
            guard let rawPtr = MDQueryGetResultAtIndex(query, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(rawPtr).takeUnretainedValue()

            guard let bundleID = MDItemCopyAttribute(item, kMDItemCFBundleIdentifier) as? String,
                  !bundleID.isEmpty,
                  bundleID != selfBundleID else { continue }

            guard let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { continue }

            let displayName = MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? bundleID
            let useCount = MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? Int ?? 1

            // Skip system/background processes that aren't real user apps
            guard useCount > 0 else { continue }

            let record = UsageRecord(
                bundleIdentifier: bundleID,
                displayName: displayName,
                lastActivatedAt: lastUsed,
                activationCount: useCount
            )
            records.append(record)
        }

        return records
    }
}
