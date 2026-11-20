import Foundation
import SwiftData
import os

/// The single SwiftData container, stored in the App Group so the widget extension reads the same data.
enum SharedStore {
    enum Location: Sendable, Equatable {
        case appGroup
        /// App Group entitlement missing (signing misconfigured). Data is safe but widgets can't see it.
        case appSandbox
        /// Disk store failed to open. Data will NOT survive a restart; shown as a warning in Settings.
        case inMemory
    }

    struct Loaded: Sendable {
        let container: ModelContainer
        let location: Location
    }

    static var schema: Schema { Schema([TimeEntry.self, CaptureRecord.self, CategoryAssignment.self, AIInterpretation.self, SummaryCache.self]) }
    static let loaded: Loaded = load()

    static var container: ModelContainer { loaded.container }

    private static let logger = Logger(subsystem: "TimeTracker", category: "Store")

    private static func load() -> Loaded {
        if let groupID = AppConfig.appGroupID,
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            let url = groupURL.appending(path: "TimeTracker.store")
            do {
                let config = ModelConfiguration("TimeTracker", schema: schema, url: url, cloudKitDatabase: .none)
                DataProtection.allowAccessWhileLocked(store: url)
                let container = try ModelContainer(for: schema, configurations: [config])
                DataProtection.allowAccessWhileLocked(store: url)
                return Loaded(container: container, location: .appGroup)
            } catch {
                logger.error("Failed to open App Group store: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.error("App Group container unavailable; check the App Groups capability and APP_GROUP_ID.")
        }

        do {
            let config = ModelConfiguration("TimeTracker", schema: schema, groupContainer: .none, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            DataProtection.allowAccessWhileLocked(store: config.url)
            return Loaded(container: container, location: .appSandbox)
        } catch {
            logger.fault("Failed to open local store: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let config = ModelConfiguration(
                "TimeTracker", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
            )
            return Loaded(container: try ModelContainer(for: schema, configurations: [config]), location: .inMemory)
        } catch {
            fatalError("Could not create any SwiftData container: \(error)")
        }
    }
}

/// Lock Screen intents read and write the store while the phone is locked, so its files must use
/// `completeUntilFirstUserAuthentication` (readable once she has unlocked after a restart), never
/// `complete`. It's iOS's default class for app files, but it's set explicitly here because the
/// `com.apple.developer.default-data-protection` entitlement can't be used: free Personal Team
/// provisioning profiles reject it. New files (the SQLite -wal/-shm journals) inherit the
/// directory's class.
enum DataProtection {
    private static let logger = Logger(subsystem: "TimeTracker", category: "DataProtection")
    static let lockedAccessClass = FileProtectionType.completeUntilFirstUserAuthentication

    static func allowAccessWhileLocked(store url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let storePath = url.path(percentEncoded: false)
        let paths = [directory.path(percentEncoded: false), storePath, storePath + "-wal", storePath + "-shm"]
        for path in paths where manager.fileExists(atPath: path) {
            do {
                let current = try manager.attributesOfItem(atPath: path)[.protectionKey] as? FileProtectionType
                if current != lockedAccessClass {
                    try manager.setAttributes([.protectionKey: lockedAccessClass], ofItemAtPath: path)
                }
            } catch {
                // Fails only if the file is currently locked away (it'll be retried next launch)
                // or on the simulator, which has no data protection.
                logger.info("Couldn't set protection on \((path as NSString).lastPathComponent, privacy: .public):\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Lightweight, nonisolated reads for the widget extension's timeline provider.
enum SharedStoreReader {
    static func runningActivities() -> [RunningSnapshot] {
        let context = ModelContext(SharedStore.container)
        let activity = EntryKind.activity.rawValue
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.endedAt == nil && $0.kindRaw == activity },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map(RunningSnapshot.init)
    }
}
