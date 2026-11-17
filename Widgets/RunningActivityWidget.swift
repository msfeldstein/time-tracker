import SwiftUI
import WidgetKit

struct RunningTimelineEntry: TimelineEntry {
    let date: Date
    let running: [RunningSnapshot]

    static let sample = RunningTimelineEntry(
        date: Date(),
        running: [RunningSnapshot(id: UUID(), name: "Dishes", startedAt: Date().addingTimeInterval(-754))]
    )
}

struct RunningProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunningTimelineEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (RunningTimelineEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(RunningTimelineEntry(date: Date(), running: SharedStoreReader.runningActivities()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunningTimelineEntry>) -> Void) {
        // The app reloads timelines after every change; the timer text updates itself, so a
        // slow refresh is only a safety net.
        let entry = RunningTimelineEntry(date: Date(), running: SharedStoreReader.runningActivities())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

/// Lock Screen widget. Tapping it opens the app straight into listening mode.
struct RunningActivityWidget: Widget {
    let kind = "RunningActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunningProvider()) { entry in
            RunningWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(AppConfig.listenURL)
        }
        .configurationDisplayName("Time Tracker")
        .description("See what's running. Tap to log by voice.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RunningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RunningTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    private var circular: some View {
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
    private var rectangular: some View {
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
    private var inline: some View {
        if let top = entry.running.first {
            Text("\(Image(systemName: "timer")) \(top.name) \(top.startedAt, style: .timer)")
        } else {
            Text("\(Image(systemName: "mic.fill")) Log time")
        }
    }
}
