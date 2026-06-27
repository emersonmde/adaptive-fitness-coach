import SwiftUI
import AdaptiveCore

/// Detail + schedule (P5) for one routine: edit days, set the time, toggle reminders, delete.
/// Edits write straight back to the store, which syncs to the watch and reschedules reminders.
struct RoutineDetailView: View {
    let store: RoutineStore
    let routineID: Routine.ID
    @Environment(\.dismiss) private var dismiss

    /// The default reminder time when a routine has none yet (a neutral morning slot, not "now").
    private static let defaultTime = ScheduleTime(hour: 7, minute: 0)

    /// Local editable copy; committed to the store on each change. Loaded reactively by id.
    @State private var draft: Routine?

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
        // `.task(id:)` runs once per routine id and won't clobber an in-flight edit on a
        // re-appearance the way `onAppear` would; it only (re)loads when the id actually changes.
        .task(id: routineID) {
            draft = store.routines.first { $0.id == routineID }
        }
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
                // Single source of truth: the picker reads/writes the draft's scheduleTime,
                // displaying the default time when none is set yet.
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)

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

    // MARK: - Bindings / state sync

    /// Bridges the `Date`-based picker to the model's `ScheduleTime`, defaulting the display.
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let t = draft?.scheduleTime ?? Self.defaultTime
                return Calendar.current.date(from: DateComponents(hour: t.hour, minute: t.minute)) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                setTime(ScheduleTime(hour: c.hour ?? Self.defaultTime.hour, minute: c.minute ?? 0))
            }
        )
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

    private func setTime(_ time: ScheduleTime) {
        commit { $0.scheduleTime = time }
    }

    private func setReminders(_ on: Bool) {
        commit {
            $0.reminderEnabled = on
            // Ensure an explicit default time exists so a reminder has something to fire on.
            if on, $0.scheduleTime == nil {
                $0.scheduleTime = Self.defaultTime
            }
        }
    }

    private func delete() {
        NotificationManager.shared.cancel(routineID: routineID)
        store.remove(id: routineID)
        dismiss()
    }
}
