import SwiftUI
import TimeTrackerCore

struct EditEntryView: View {
    let entry: TimeEntry

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var startedAt: Date
    @State private var isRunning: Bool
    @State private var endedAt: Date
    @State private var confirmingDelete = false

    init(entry: TimeEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _startedAt = State(initialValue: entry.startedAt)
        _isRunning = State(initialValue: entry.isRunning)
        _endedAt = State(initialValue: entry.endedAt ?? Date())
    }

    private var isNote: Bool { entry.kind == .note }

    var body: some View {
        NavigationStack {
            Form {
                Section(isNote ? "Note" : "Activity") {
                    TextField(isNote ? "Note" : "Name", text: $name, axis: .vertical)
                        .font(.title3)
                        .lineLimit(1...5)
                }

                if isNote {
                    Section {
                        DatePicker("Time", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                    }
                } else {
                    Section("When") {
                        DatePicker("Started", selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        Toggle("Still running", isOn: $isRunning.animation())
                        if !isRunning {
                            DatePicker("Ended", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                            LabeledContent("Duration", value: DurationFormatting.short(max(0, endedAt.timeIntervalSince(startedAt))))
                        }
                    }

                    if entry.isRunning {
                        Section {
                            quickStop("Stopped just now", end: Date())
                            quickStop("30 minutes after it started", end: startedAt.addingTimeInterval(30 * 60))
                            quickStop("1 hour after it started", end: startedAt.addingTimeInterval(60 * 60))
                        } header: {
                            Text("Forgot to stop it?")
                        }
                    }
                }

                if !entry.rawTranscript.isEmpty, entry.rawTranscript != entry.name {
                    Section("What you said") {
                        Text("\u{201C}\(entry.rawTranscript)\u{201D}")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Delete", role: .destructive) {
                        confirmingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isNote ? "Edit Note" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await EntryService.shared.delete(entry)
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickStop(_ title: String, end: Date) -> some View {
        Button(title) {
            isRunning = false
            endedAt = min(max(end, startedAt), Date())
            save()
        }
    }

    private func save() {
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.startedAt = startedAt
        if isNote {
            entry.endedAt = startedAt
        } else {
            entry.endedAt = isRunning ? nil : max(endedAt, startedAt)
        }
        Task {
            await EntryService.shared.commitEdits()
            dismiss()
        }
    }
}

/// For something she did but forgot to log at all.
struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startedAt = Date().addingTimeInterval(-30 * 60)
    @State private var endedAt = Date()
    @State private var stillRunning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("What did you do?", text: $name)
                        .font(.title3)
                }
                Section("When") {
                    DatePicker("Started", selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Toggle("Still going", isOn: $stillRunning.animation())
                    if !stillRunning {
                        DatePicker("Ended", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await EntryService.shared.addManualEntry(
                                name: name,
                                startedAt: startedAt,
                                endedAt: stillRunning ? nil : max(endedAt, startedAt)
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
