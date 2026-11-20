import Foundation

/// Hand-off from "open the app and listen" entry points (Shortcuts, Back Tap, Control Center,
/// Siri) to the UI. A timestamp in shared defaults survives a cold launch; the notification
/// covers the case where the app is already open.
@MainActor
enum ListenRequest {
    static let notification = Notification.Name("TimeTracker.listenRequested")
    private static let key = "pendingListenRequest"
    private static let maxAge: TimeInterval = 60

    static func post() {
        AppConfig.sharedDefaults.set(Date().timeIntervalSince1970, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// Returns true (once) if a recent request is pending.
    static func consume() -> Bool {
        let defaults = AppConfig.sharedDefaults
        let timestamp = defaults.double(forKey: key)
        guard timestamp > 0 else { return false }
        defaults.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - timestamp < maxAge
    }
}
