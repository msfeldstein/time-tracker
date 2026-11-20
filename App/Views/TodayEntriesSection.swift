import SwiftData
import SwiftUI
import TimeTrackerCore

/// Today's entries with fix-ups (edit, stop, delete, add a forgotten one). Shown in Summary › Today.
struct TodayEntriesSection: View {
    @Query private var allEntries: [TimeEntry]
    @Query(filter: #Predicate<CaptureRecord> { $0.aiStatusRaw == "pending" }) private var pendingCaptures: [CaptureRecord]
    @State private var editing: TimeEntry?
    @State private var addingEntry = false
    @State private var deleting: TimeEntry?

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today\u{2019}s entries")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    addingEntry = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Add something you forgot to log")
            }

            if entries.isEmpty {
                Text("Nothing logged yet today.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 8) {
                        ForEach(entries) { entry in
                            EntryRow(
                                entry: entry,
                                now: context.date,
                                isAskingAI: entry.captureID.map { pendingIDs.contains($0) } ?? false
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture { editing = entry }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = entry }
                                if entry.isRunning {
                                    Button("Stop now", systemImage: "stop.fill") {
                                        let id = entry.id
                                        Task { await EntryService.shared.stop(entryID: id) }
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                            }
                        }
                    }
                }
                Text("Tap an entry to fix its name, category or times. Touch and hold to stop or delete.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { entry in
            EditEntryView(entry: entry)
        }
        .sheet(isPresented: $addingEntry) {
            AddEntryView()
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deleting {
                    Task { await EntryService.shared.delete(entry) }
                }
                deleting = nil
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            if let suggestion = entry.activeSuggestion {
                SuggestionFix(entry: entry, suggestion: suggestion)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var mainRow: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
