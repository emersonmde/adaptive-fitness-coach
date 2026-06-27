import SwiftUI
import AdaptiveCore

/// Detail + schedule (P5) for one routine: set the time, toggle reminders, edit days, delete.
/// Edits write straight back to the store, which syncs to the watch and reschedules reminders.
struct RoutineDetailView: View {
    let store: RoutineStore
    let routineID: Routine.ID
    @Environment(\.dismiss) private var dismiss

    /// Local editable copy; committed to the store on each change.
    @State private var draft: Routine?
    @State private var timeSelection = Date()

    var body: some View {
        Group {
            if let draft {
                form(for: draft)
            } else {
                // Routine was deleted out from under us.
                ContentUnavailableView("Routine unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(draft?.name ?? "Routine")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraft)
    }

    private func form(for routine: Routine) -> some View {
        Form {
            Section("Days") {
                DayPicker(selection: Binding(
                    get: { draft?.repeatDays ?? [] },
                    set: { setDays($0) }
                ))
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            Section("Schedule") {
                DatePicker("Time", selection: $timeSelection, displayedComponents: .hourAndMinute)
                    .onChange(of: timeSelection) { _, newValue in setTime(newValue) }

                Toggle("Reminders", isOn: Binding(
                    get: { draft?.reminderEnabled ?? false },
                    set: { setReminders($0) }
                ))

                if routine.reminderEnabled {
                    Text("A reminder launches the session on your watch — leave your phone behind.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete Routine", role: .destructive, action: delete)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - State sync

    private func loadDraft() {
        guard let routine = store.routines.first(where: { $0.id == routineID }) else {
            draft = nil
            return
        }
        draft = routine
        if let t = routine.scheduleTime {
            var c = DateComponents(); c.hour = t.hour; c.minute = t.minute
            timeSelection = Calendar.current.date(from: c) ?? Date()
        }
    }

    /// Mutate the draft and commit to the store, which triggers watch sync + reminder reschedule.
    private func commit(_ mutate: (inout Routine) -> Void) {
        guard var routine = draft else { return }
        mutate(&routine)
        draft = routine
        store.update(routine)
        NotificationManager.shared.reschedule(for: routine)
    }

    private func setDays(_ days: Set<DayOfWeek>) {
        commit { $0.repeatDays = days }
    }

    private func setTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        commit { $0.scheduleTime = ScheduleTime(hour: c.hour ?? 0, minute: c.minute ?? 0) }
    }

    private func setReminders(_ on: Bool) {
        // Default a time if none set yet, so a reminder has something to fire on.
        commit {
            $0.reminderEnabled = on
            if on && $0.scheduleTime == nil {
                let c = Calendar.current.dateComponents([.hour, .minute], from: timeSelection)
                $0.scheduleTime = ScheduleTime(hour: c.hour ?? 7, minute: c.minute ?? 0)
            }
        }
    }

    private func delete() {
        NotificationManager.shared.cancel(routineID: routineID)
        store.remove(id: routineID)
        dismiss()
    }
}
