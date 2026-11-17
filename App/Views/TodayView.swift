import SwiftData
import SwiftUI
import TimeTrackerCore

struct TodayView: View {
    @Query private var allEntries: [TimeEntry]
    @Query(filter: #Predicate<CaptureRecord> { $0.aiStatusRaw == "pending" }) private var pendingCaptures: [CaptureRecord]
    @State private var editing: TimeEntry?
    @State private var addingEntry = false

    init(day: Date = Date()) {
        let start = Calendar.current.startOfDay(for: day)
        // Today's entries plus anything still running from earlier (likely forgotten).
        _allEntries = Query(
            filter: #Predicate<TimeEntry> { $0.startedAt >= start || $0.endedAt == nil },
            sort: \TimeEntry.startedAt,
            order: .reverse
        )
    }

    /// Notes replaced by an AI interpretation stay stored but hidden until "Undo".
    private var entries: [TimeEntry] {
        allEntries.filter { $0.supersededByInterpretationID == nil }
    }

    var body: some View {
        let pendingIDs = Set(pendingCaptures.map(\.id))
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                Section {
                    TotalRow(entries: entries, now: context.date)
                }

                if entries.isEmpty {
                    Section {
                        Text("Nothing logged yet today.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(entries) { entry in
                            EntryRow(
                                entry: entry,
                                now: context.date,
                                isAskingAI: entry.captureID.map { pendingIDs.contains($0) } ?? false
                            )
                            .onTapGesture { editing = entry }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await EntryService.shared.delete(entry) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if entry.isRunning {
                                    Button {
                                        let id = entry.id
                                        Task { await EntryService.shared.stop(entryID: id) }
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    } footer: {
                        Text("Tap an entry to fix its name or times. Swipe left to stop or delete.")
                    }
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingEntry = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { entry in
            EditEntryView(entry: entry)
        }
        .sheet(isPresented: $addingEntry) {
            AddEntryView()
        }
    }
}

private struct TotalRow: View {
    let entries: [TimeEntry]
    let now: Date

    var body: some View {
        let start = Calendar.current.startOfDay(for: now)
        let total = entries
            .filter { $0.kind == .activity }
            .reduce(0.0) { sum, entry in
                let from = max(entry.startedAt, start)
                return sum + max(0, (entry.endedAt ?? now).timeIntervalSince(from))
            }
        HStack {
            Text("Tracked today")
                .font(.headline)
            Spacer()
            Text(DurationFormatting.short(total))
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(DurationFormatting.spoken(total))
    }
}

struct EntryRow: View {
    let entry: TimeEntry
    let now: Date
    var isAskingAI = false

    private var forgotten: Bool {
        guard entry.kind == .activity else { return false }
        return entry.activeSuggestion != nil
            || DurationFormatting.isProbablyForgotten(startedAt: entry.startedAt, endedAt: entry.endedAt, now: now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(entry.kind == .note ? .body.italic() : .headline)
                    .lineLimit(entry.kind == .note ? 4 : 2)
                HStack(spacing: 6) {
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let category = entry.category {
                        CategoryChip(name: category)
                    }
                }
                if entry.interpretationID != nil {
                    Label("Understood by AI \u{00B7} tap to undo", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isAskingAI {
                    Label("Asking AI to make sense of this\u{2026}", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if forgotten {
                    Label(entry.isRunning ? "Forgot to stop?" : "Over 3 hours \u{2013} check the end time?", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let suggestion = entry.activeSuggestion {
                    SuggestionFix(entry: entry, suggestion: suggestion)
                }
            }

            Spacer(minLength: 8)

            if entry.kind == .activity {
                Group {
                    if entry.isRunning {
                        Text(entry.startedAt, style: .timer)
                            .foregroundStyle(.red)
                    } else {
                        Text(DurationFormatting.short(entry.duration(now: now)))
                    }
                }
                .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch entry.kind {
        case .note: "text.bubble"
        case .activity: entry.isRunning ? "timer" : "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .note: .secondary
        case .activity: entry.isRunning ? .red : .green
        }
    }

    private var timeText: String {
        let start = entry.startedAt.formatted(date: Calendar.current.isDateInToday(entry.startedAt) ? .omitted : .abbreviated, time: .shortened)
        switch entry.kind {
        case .note:
            return start
        case .activity:
            if let end = entry.endedAt {
                return "\(start) \u{2013} \(end.formatted(date: .omitted, time: .shortened))"
            }
            return "Since \(start)"
        }
    }
}

struct CategoryChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Category \(name)")
    }
}

/// The one-tap fix for a forgotten timer. Suggestions are never applied automatically.
struct SuggestionFix: View {
    let entry: TimeEntry
    let suggestion: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Probably ended around \(suggestion.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline.weight(.semibold))
            if let reason = entry.suggestionReason {
                Label(reason, systemImage: entry.suggestionSource == .ai ? "sparkles" : "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                let id = entry.id
                Task { await EntryService.shared.useSuggestion(entryID: id) }
            } label: {
                Label("Use suggestion", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.orange)
            .accessibilityHint("Stops \(entry.name) at \(suggestion.formatted(date: .omitted, time: .shortened))")
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
