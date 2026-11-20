import SwiftData
import SwiftUI
import TimeTrackerCore

enum HomeRoute: Hashable {
    case settings
}

struct HomeView: View {
    @Environment(VoiceCaptureController.self) private var voice
    @Query(
        filter: #Predicate<TimeEntry> { $0.endedAt == nil },
        sort: \TimeEntry.startedAt,
        order: .reverse
    )
    private var running: [TimeEntry]
    @State private var path: [HomeRoute] = HomeView.initialPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                StatusPanel(phase: voice.phase, transcript: voice.transcript, overBackground: AppBackground.isPresent)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)

                MicButton(phase: voice.phase) {
                    voice.toggle()
                }

                RunningList(entries: running)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HomeRoute.settings) {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .sensoryFeedback(trigger: voice.phase) { _, new in
                switch new {
                case .listening: .start
                case .done: .success
                case .failed: .error
                default: nil
                }
            }
        }
    }
}

extension HomeView {
    /// Debug launch argument used by CI screenshots: `-TTOpenSettings`.
    nonisolated static func initialPath() -> [HomeRoute] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TTOpenSettings") { return [.settings] }
        #endif
        return []
    }
}

/// Optional full-bleed image from the "AppBackground" asset. The asset ships empty; drop an image
/// into App/Assets.xcassets/AppBackground.imageset and it fills the screen behind the content.
struct AppBackground: View {
    static let isPresent = UIImage(named: "AppBackground") != nil

    var body: some View {
        if let image = UIImage(named: "AppBackground") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(Color(uiColor: .systemBackground).opacity(0.15))
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }
}

private struct StatusPanel: View {
    let phase: VoiceCaptureController.Phase
    let transcript: String
    let overBackground: Bool

    var body: some View {
        content
            .padding(.horizontal, overBackground && phase != .idle ? 16 : 0)
            .padding(.vertical, overBackground && phase != .idle ? 10 : 0)
            .background {
                if overBackground && phase != .idle {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                }
            }
    }

    private var content: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .preparing:
                Label("Getting ready\u{2026}", systemImage: "ellipsis")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            case .listening:
                Text(transcript.isEmpty ? "Listening\u{2026}" : transcript)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(transcript.isEmpty ? Color.secondary : Color.primary)
                    .contentTransition(.opacity)
            case .saving:
                VStack(spacing: 8) {
                    Text(transcript).font(.title2.weight(.semibold))
                    ProgressView()
                }
            case .done(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .minimumScaleFactor(0.6)
        .animation(.easeInOut(duration: 0.2), value: phase)
        .accessibilityElement(children: .combine)
    }
}

private struct RunningList: View {
    let entries: [TimeEntry]

    var body: some View {
        if !entries.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        RunningCard(entry: entry)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct RunningCard: View {
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(entry.startedAt, style: .timer)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if DurationFormatting.isProbablyForgotten(startedAt: entry.startedAt, endedAt: nil, now: context.date) {
                        Label("Forgot to stop?", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                let id = entry.id
                Task { await EntryService.shared.stop(entryID: id) }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .accessibilityLabel("Stop \(entry.name)")
        }
        .padding(14)
        .background(AppBackground.isPresent ? Material.regular : Material.thin, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
