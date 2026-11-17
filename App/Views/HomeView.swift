import SwiftData
import SwiftUI
import TimeTrackerCore

enum HomeRoute: Hashable {
    case today
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
                StatusPanel(phase: voice.phase, transcript: voice.transcript)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)

                MicButton(phase: voice.phase) {
                    voice.toggle()
                }

                RunningList(entries: running)
                    .frame(maxHeight: .infinity, alignment: .top)

                Button {
                    path.append(.today)
                } label: {
                    Label("Today", systemImage: "list.bullet.rectangle")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .navigationTitle("Time Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .today: TodayView()
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
    /// Debug launch arguments used by CI screenshots: `-TTOpenToday`, `-TTOpenSettings`.
    nonisolated static func initialPath() -> [HomeRoute] {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-TTOpenToday") { return [.today] }
        if arguments.contains("-TTOpenSettings") { return [.settings] }
        #endif
        return []
    }
}

private struct StatusPanel: View {
    let phase: VoiceCaptureController.Phase
    let transcript: String

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Text("Tap the mic and say\n\u{201C}starting dishes\u{201D} or \u{201C}done with dishes\u{201D}")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
        if entries.isEmpty {
            Text("Nothing running")
                .font(.headline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        } else {
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
