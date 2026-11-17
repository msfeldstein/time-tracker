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

enum RootTab: Hashable {
    case track
    case summary
}

/// Routes the "open and listen" entry points (widget URL, control, Siri, Back Tap) into the mic.
struct RootView: View {
    @Environment(VoiceCaptureController.self) private var voice
    @Environment(\.scenePhase) private var scenePhase
    @State private var listenWhenActive = false
    @State private var didLaunch = false
    @State private var tab: RootTab = RootView.initialTab()

    var body: some View {
        TabView(selection: $tab) {
            Tab("Track", systemImage: "mic.fill", value: RootTab.track) {
                HomeView()
            }
            Tab("Summary", systemImage: "chart.bar.fill", value: RootTab.summary) {
                SummaryView()
            }
        }
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
                        AIWorker.shared.start()
                    }
                    await EntryService.shared.refreshSurfaces()
                }
            }
    }

    /// Debug launch argument used by CI screenshots: `-TTOpenSummary`.
    nonisolated static func initialTab() -> RootTab {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TTOpenSummary") { return .summary }
        #endif
        return .track
    }

    private func requestListen() {
        tab = .track
        if scenePhase == .active {
            voice.start()
        } else {
            listenWhenActive = true
        }
    }
}
