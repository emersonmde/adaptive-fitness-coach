import SwiftUI
import AdaptiveCore

/// Detail + schedule (P5) for one routine, dark/neon. Edit days, duration, time, toggle the
/// Calendar event, delete. Edits write straight back to the store, which syncs to the watch and
/// updates the routine's recurring Calendar event.
struct RoutineDetailView: View {
    let store: RoutineStore
    let routineID: Routine.ID
    @Environment(\.dismiss) private var dismiss

    /// The default reminder time when a routine has none yet (a neutral morning slot, not "now").
    private static let defaultTime = ScheduleTime(hour: 7, minute: 0)

    /// Local editable copy; committed to the store on each change. Loaded reactively by id.
    @State private var draft: Routine?
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let draft {
                form(for: draft)
            } else {
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
        ScrollView {
            VStack(spacing: 18) {
                if let next = nextDate(for: routine) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(Theme.accent)
                        Text("Next · \(RelativeWhen.string(for: next))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                FieldSection(title: "DAYS") {
                    DayPicker(selection: Binding(
                        get: { draft?.repeatDays ?? [] },
                        set: { setDays($0) }
                    ))
                }

                FieldSection(title: "DURATION") {
                    DurationStepper(minutes: Binding(
                        get: { draft?.durationMinutes ?? 30 },
                        set: { setDuration($0) }
                    ))
                }

                FieldSection(title: "SCHEDULE") {
                    VStack(spacing: 4) {
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .foregroundStyle(Theme.textPrimary)
                        Divider().overlay(Theme.hairline)
                        Toggle("Add to Calendar", isOn: Binding(
                            get: { draft?.reminderEnabled ?? false },
                            set: { setReminders($0) }
                        ))
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.textPrimary)
                        if routine.reminderEnabled {
                            Text("Adds a repeating event to your calendar at this time on the days above, with an alert when it's time to run.")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Text("Delete Routine")
                        .font(.headline)
                        .foregroundStyle(Theme.hot)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.hot.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .confirmationDialog("Delete this routine?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Bindings / state sync

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

    /// Apply an edit, persist it, and reflect it in the Calendar. `promptCalendar` requests
    /// access (only when the user just turned the calendar toggle on).
    private func commit(promptCalendar: Bool = false, _ mutate: (inout Routine) -> Void) {
        guard var routine = draft else { return }
        mutate(&routine)
        draft = routine
        store.update(routine)
        Task { await CalendarService.shared.sync(for: routine, prompt: promptCalendar) }
    }

    private func setDays(_ days: Set<DayOfWeek>) { commit { $0.repeatDays = days } }
    private func setTime(_ time: ScheduleTime) { commit { $0.scheduleTime = time } }
    private func setDuration(_ minutes: Int) { commit { $0.durationMinutes = minutes } }

    private func setReminders(_ on: Bool) {
        commit(promptCalendar: on) {
            $0.reminderEnabled = on
            if on, $0.scheduleTime == nil { $0.scheduleTime = Self.defaultTime }
        }
    }

    private func delete() {
        CalendarService.shared.remove(routineID: routineID)
        store.remove(id: routineID)
        dismiss()
    }

    /// Next fire date for *this* routine, for the "Next · …" echo.
    private func nextDate(for routine: Routine, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !routine.repeatDays.isEmpty else { return nil }
        return routine.repeatDays.compactMap { day -> Date? in
            var c = DateComponents()
            c.weekday = day.rawValue
            let t = routine.scheduleTime ?? Self.defaultTime
            c.hour = t.hour; c.minute = t.minute
            return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}
