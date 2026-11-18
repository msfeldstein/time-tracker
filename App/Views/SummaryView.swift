import Charts
import SwiftData
import SwiftUI
import TimeTrackerCore

struct SummaryView: View {
    @State private var period: SummaryPeriod = .day

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Period", selection: $period) {
                            Text("Today").tag(SummaryPeriod.day)
                            Text("This Week").tag(SummaryPeriod.week)
                        }
                        .pickerStyle(.segmented)

                        SummaryContent(spec: Self.spec(for: period, now: Date()))
                            .id(period)

                        if period == .day {
                            TodayEntriesSection()
                                .id(Self.entriesAnchor)
                        }
                    }
                    .padding(20)
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-TTOpenToday") {
                        try? await Task.sleep(for: .milliseconds(500))
                        proxy.scrollTo(Self.entriesAnchor, anchor: .top)
                    }
                    #endif
                }
            }
            .navigationTitle("Summary")
        }
    }

    private static let entriesAnchor = "todayEntries"

    static func spec(for period: SummaryPeriod, now: Date) -> AIWorker.SummarySpec {
        let calendar = Calendar.current
        let interval: DateInterval
        let label: String
        switch period {
        case .day:
            interval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86400)
            label = "Today, " + now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86400)
            let last = interval.end.addingTimeInterval(-1)
            label = "This week, " + interval.start.formatted(.dateTime.month(.abbreviated).day()) + " to " + last.formatted(.dateTime.month(.abbreviated).day())
        }
        let key = "\(period.rawValue)-\(Int(interval.start.timeIntervalSince1970))"
        return AIWorker.SummarySpec(key: key, period: period, interval: interval, label: label)
    }
}

private struct SummaryContent: View {
    let spec: AIWorker.SummarySpec

    @Query private var entries: [TimeEntry]
    @Query private var cachedNotes: [SummaryCache]
    @Query private var assignments: [CategoryAssignment]

    init(spec: AIWorker.SummarySpec) {
        self.spec = spec
        let kind = EntryKind.activity.rawValue
        let from = spec.interval.start.addingTimeInterval(-86400)
        let to = spec.interval.end
        _entries = Query(filter: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.startedAt >= from && $0.startedAt < to })
        let key = spec.key
        _cachedNotes = Query(filter: #Predicate<SummaryCache> { $0.key == key })
    }

    private var summaryEntries: [SummaryEntry] {
        let cache = Dictionary(assignments.map { ($0.key, $0.category) }, uniquingKeysWith: { first, _ in first })
        return entries.map {
            SummaryEntry(
                name: $0.name,
                category: $0.category ?? cache[CategoryKey.normalize($0.name)],
                startedAt: $0.startedAt,
                endedAt: $0.endedAt
            )
        }
    }

    private var fingerprint: String {
        SummaryCalculator.fingerprint(summaryEntries.filter { $0.endedAt != nil }, in: spec.interval)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let all = summaryEntries
            let totals = SummaryCalculator.categoryTotals(all, in: spec.interval, now: context.date)
            let total = totals.reduce(0) { $0 + $1.seconds }

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(DurationFormatting.short(total))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("\(DurationFormatting.spoken(total)) tracked")
                }

                NoteCard(note: note(totals: totals), isAI: aiNote != nil, isWaiting: aiNote == nil && AISettings.isActive && !totals.isEmpty)

                if totals.isEmpty {
                    Text("Nothing tracked yet. Tap the mic on the Track tab and say what you\u{2019}re starting.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    CategoryChart(totals: totals)
                }
            }
        }
        .task(id: fingerprint) {
            AIWorker.shared.requestSummary(spec)
        }
    }

    /// The AI note, only if it was written from the current data.
    private var aiNote: String? {
        guard let cached = cachedNotes.first, cached.fingerprint == fingerprint, !cached.note.isEmpty else { return nil }
        return cached.note
    }

    private func note(totals: [CategoryTotal]) -> String {
        aiNote ?? SummaryCalculator.localNote(totals: totals, period: spec.period)
    }
}

private struct NoteCard: View {
    let note: String
    let isAI: Bool
    let isWaiting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            if isAI {
                Label("Written by Claude", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isWaiting {
                Label("A friendlier note will appear when you\u{2019}re online", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CategoryChart: View {
    let totals: [CategoryTotal]

    var body: some View {
        Chart(totals) { total in
            BarMark(
                x: .value("Hours", total.seconds / 3600),
                y: .value("Category", total.category == CategoryDefaults.uncategorized ? "Not sorted yet" : total.category)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(6)
            .annotation(position: .trailing, alignment: .leading) {
                Text(DurationFormatting.short(total.seconds))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.body.weight(.medium))
            }
        }
        .chartXScale(domain: 0...(max(totals.map(\.seconds).max() ?? 0, 60) / 3600 * 1.3))
        .frame(height: CGFloat(totals.count) * 48 + 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(totals.map { "\($0.category) \(DurationFormatting.spoken($0.seconds))" }.joined(separator: ", "))
    }
}
