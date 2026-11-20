import Foundation

enum AppConfig {
    /// Read from Info.plist (`TTAppGroupID`), which gets it from `APP_GROUP_ID` in Config/Base.xcconfig.
    static var appGroupID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TTAppGroupID") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static let urlScheme = "timetracker"
    static let listenURL = URL(string: "timetracker://listen")!
    static let homeURL = URL(string: "timetracker://home")!

    static var sharedDefaults: UserDefaults {
        appGroupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
}
