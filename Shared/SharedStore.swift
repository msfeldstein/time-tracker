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

    static var schema: Schema { Schema([TimeEntry.self, CaptureRecord.self]) }
    static let loaded: Loaded = load()

    static var container: ModelContainer { loaded.container }

    private static let logger = Logger(subsystem: "TimeTracker", category: "Store")

    private static func load() -> Loaded {
        if let groupID = AppConfig.appGroupID,
           let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            let url = groupURL.appending(path: "TimeTracker.store")
            do {
                let config = ModelConfiguration("TimeTracker", schema: schema, url: url, cloudKitDatabase: .none)
                return Loaded(container: try ModelContainer(for: schema, configurations: [config]), location: .appGroup)
            } catch {
                logger.error("Failed to open App Group store: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.error("App Group container unavailable; check the App Groups capability and APP_GROUP_ID.")
        }

        do {
            let config = ModelConfiguration("TimeTracker", schema: schema, groupContainer: .none, cloudKitDatabase: .none)
            return Loaded(container: try ModelContainer(for: schema, configurations: [config]), location: .appSandbox)
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
