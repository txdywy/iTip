import XCTest
import SwiftCheck
@testable import iTip

final class ActivationMonitorPropertyTests: XCTestCase {

    // MARK: - Property 2: recordActivation updating existing records

    /// **Validates: Requirements 2.3**
    ///
    /// Property 2: recordActivation 更新已有记录
    /// For any existing UsageRecord in the store (activationCount >= 1, any timestamp),
    /// calling recordActivation with the same bundleIdentifier SHALL increment
    /// activationCount by exactly 1 and update lastActivatedAt to the injected timestamp.
    func testRecordActivationUpdatesExistingRecord() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)
        property("recordActivation increments count by 1 and updates timestamp for existing records", arguments: args) <- forAll { (existingRecord: UsageRecord) in
            let store = InMemoryUsageStore(records: [existingRecord])
            let fixedDate = Date(timeIntervalSinceReferenceDate: 999_999_999)
            let monitor = ActivationMonitor(
                store: store,
                notificationCenter: NotificationCenter(),
                dateProvider: { fixedDate },
                selfBundleIdentifier: "com.test.self"
            )

            monitor.recordActivation(
                bundleIdentifier: existingRecord.bundleIdentifier,
                displayName: existingRecord.displayName
            )

            guard let records = try? store.load(), records.count == 1 else {
                return false
            }
            let updated = records[0]
            return updated.activationCount == existingRecord.activationCount + 1
                && updated.lastActivatedAt == fixedDate
                && updated.bundleIdentifier == existingRecord.bundleIdentifier
        }
    }

    // MARK: - Property 3: recordActivation creating new records

    /// **Validates: Requirements 2.4**
    ///
    /// Property 3: recordActivation 创建新记录
    /// For any store state and a bundleIdentifier not in the store,
    /// calling recordActivation SHALL create a new record with activationCount == 1
    /// and correct timestamp, and all pre-existing records SHALL remain unchanged.
    func testRecordActivationCreatesNewRecord() {
        let args = CheckerArguments(maxAllowableSuccessfulTests: 100)

        property("recordActivation creates new record with count 1 and preserves existing records", arguments: args) <- forAll { (existingRecords: [UsageRecord]) in
            // Create a bundleIdentifier guaranteed not in the existing records
            let usedIds = Set(existingRecords.map { $0.bundleIdentifier })
            var newBundleId = "com.new.app.\(arc4random())"
            while usedIds.contains(newBundleId) {
                newBundleId = "com.new.app.\(arc4random())"
            }

            let store = InMemoryUsageStore(records: existingRecords)
            let fixedDate = Date(timeIntervalSinceReferenceDate: 888_888_888)
            let monitor = ActivationMonitor(
                store: store,
                notificationCenter: NotificationCenter(),
                dateProvider: { fixedDate },
                selfBundleIdentifier: "com.test.self"
            )

            monitor.recordActivation(bundleIdentifier: newBundleId, displayName: "New App")

            guard let records = try? store.load() else { return false }

            // Should have one more record than before
            guard records.count == existingRecords.count + 1 else { return false }

            // Find the new record
            guard let newRecord = records.first(where: { $0.bundleIdentifier == newBundleId }) else {
                return false
            }
            guard newRecord.activationCount == 1 && newRecord.lastActivatedAt == fixedDate else {
                return false
            }

            // All pre-existing records should be unchanged
            for existing in existingRecords {
                guard let found = records.first(where: { $0.bundleIdentifier == existing.bundleIdentifier }) else {
                    return false
                }
                if found != existing { return false }
            }
            return true
        }
    }
}
