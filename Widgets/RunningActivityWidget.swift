import SwiftUI
import WidgetKit

struct RunningTimelineEntry: TimelineEntry {
    let date: Date
    let running: [RunningSnapshot]

    static let sample = RunningTimelineEntry(
        date: Date(),
        running: [RunningSnapshot(id: UUID(), name: "Dishes", startedAt: Date().addingTimeInterval(-754))]
    )

    /// Nothing running: the mic and "Log time". Contains no private data.
    static var generic: RunningTimelineEntry {
        RunningTimelineEntry(date: Date(), running: [])
    }

    /// Reads the file the app writes after every change; never opens the SwiftData store, so it
    /// works (or quickly falls back to `generic`) while the phone is locked.
    static var current: RunningTimelineEntry {
        RunningTimelineEntry(date: Date(), running: RunningSnapshotFile.read())
    }
}

struct RunningProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunningTimelineEntry {
        .generic
    }

    func getSnapshot(in context: Context, completion: @escaping (RunningTimelineEntry) -> Void) {
        completion(context.isPreview ? .sample : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunningTimelineEntry>) -> Void) {
        // The app reloads timelines after every change; the timer text updates itself, so a
        // slow refresh is only a safety net.
        completion(Timeline(entries: [.current], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

/// Lock Screen widget. Tapping it runs `LogByVoiceIntent`, which listens from the Lock Screen
/// without unlocking or opening the app.
struct RunningActivityWidget: Widget {
    let kind = "RunningActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunningProvider()) { entry in
            Button(intent: LogByVoiceIntent()) {
                RunningWidgetView(entry: entry)
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Time Tracker")
        .description("See what's running. Tap to log by voice, no unlock needed.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RunningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: RunningTimelineEntry

    var body: some View {
        if redactionReasons.isEmpty {
            content(entry)
        } else {
            // The system asks for a redacted render for the locked Lock Screen and for
            // placeholders. Show the generic mic and "Log time" instead of gray boxes: it has no
            // private data, and tapping it still runs LogByVoiceIntent without unlocking.
            content(.generic)
                .privacySensitive(false)
                .unredacted()
        }
    }

    @ViewBuilder
    private func content(_ entry: RunningTimelineEntry) -> some View {
        switch family {
        case .accessoryCircular:
            circular(entry)
        case .accessoryInline:
            inline(entry)
        default:
            rectangular(entry)
        }
    }

    private func circular(_ entry: RunningTimelineEntry) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "mic.fill")
                    .font(.title2.weight(.semibold))
                if !entry.running.isEmpty {
                    Text("\(entry.running.count)")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .widgetAccentable()
        .accessibilityLabel(entry.running.isEmpty ? "Log time by voice" : "\(entry.running.count) running. Log time by voice")
    }

    @ViewBuilder
    private func rectangular(_ entry: RunningTimelineEntry) -> some View {
        if let top = entry.running.first {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(top.name)
                        .font(.headline)
                        .lineLimit(1)
                        .widgetAccentable()
                }
                Text(top.startedAt, style: .timer)
                    .font(.title3.weight(.semibold).monospacedDigit())
                if entry.running.count > 1 {
                    Text("+\(entry.running.count - 1) more running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time Tracker")
                        .font(.headline)
                    Text("Tap to log by voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func inline(_ entry: RunningTimelineEntry) -> some View {
        if let top = entry.running.first {
            Text("\(Image(systemName: "timer")) \(top.name) \(top.startedAt, style: .timer)")
        } else {
            Text("\(Image(systemName: "mic.fill")) Log time")
        }
    }
}
