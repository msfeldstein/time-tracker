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
/// `complete`. It's set explicitly here because the `com.apple.developer.default-data-protection`
/// entitlement can't be changed: free Personal Team provisioning profiles pin it to
/// `NSFileProtectionComplete` and fail the build for any other value. New files (the SQLite
/// -wal/-shm journals) inherit the directory's class.
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

/// What's running, as a small JSON file in the App Group, for the widget's timeline provider.
///
/// The widget never opens the SwiftData store: WidgetKit runs the provider while the phone is
/// locked, and Personal Team provisioning profiles give both targets
/// `default-data-protection = NSFileProtectionComplete`, so files that don't have an explicit class
/// can be unreadable then. This file is always written with an explicit
/// `completeUntilFirstUserAuthentication` class, and any read failure just means "nothing running".
enum RunningSnapshotFile {
    private static let logger = Logger(subsystem: "TimeTracker", category: "RunningSnapshotFile")

    private static var url: URL? {
        guard let groupID = AppConfig.appGroupID,
              let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return groupURL.appending(path: "RunningSnapshot.json")
    }

    static func write(_ running: [RunningSnapshot]) {
        guard let url else { return }
        do {
            let data = try JSONEncoder().encode(running)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Couldn't write running snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func read() -> [RunningSnapshot] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RunningSnapshot].self, from: data)) ?? []
    }
}
