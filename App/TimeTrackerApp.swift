import SwiftData
import SwiftUI

@main
struct TimeTrackerApp: App {
    @State private var voice = VoiceCaptureController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(voice)
        }
        .modelContainer(SharedStore.container)
    }
}

/// Routes the "open and listen" entry points (widget URL, control, Siri, Back Tap) into the mic.
struct RootView: View {
    @Environment(VoiceCaptureController.self) private var voice
    @Environment(\.scenePhase) private var scenePhase
    @State private var listenWhenActive = false
    @State private var didLaunch = false

    var body: some View {
        HomeView()
            .onOpenURL { url in
                guard url.scheme == AppConfig.urlScheme else { return }
                if url.host() == "listen" {
                    requestListen()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ListenRequest.notification)) { _ in
                if ListenRequest.consume() {
                    requestListen()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                if ListenRequest.consume() {
                    listenWhenActive = true
                }
                if listenWhenActive {
                    listenWhenActive = false
                    voice.start()
                }
                Task {
                    if !didLaunch {
                        didLaunch = true
                        await EntryService.shared.reprocessPendingCaptures()
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-TTDemoData") {
                            await EntryService.shared.seedDemoDataIfEmpty()
                        }
                        #endif
                    }
                    await EntryService.shared.refreshSurfaces()
                }
            }
    }

    private func requestListen() {
        if scenePhase == .active {
            voice.start()
        } else {
            listenWhenActive = true
        }
    }
}
