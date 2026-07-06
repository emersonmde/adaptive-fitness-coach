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
    @State private var editingCards = false
    @State private var coachLaunch: CoachLaunch?
    /// P6.1 insights: this routine's run history from Health (digest-bearing workouts).
    /// nil while loading or when no history exists yet — the INSIGHTS section then shows
    /// its waiting state (the slot stays visible so the feature is discoverable before the
    /// first digest-bearing run).
    @State private var runTrend: RunTrend?
    private let runHistory = RunHistoryProvider.make()
    /// Name edits buffer in the draft while the field has focus and commit once, on blur or
    /// Return — not per keystroke, which would hammer the store (each `update` persists,
    /// broadcasts to the watch, and re-syncs the Calendar event).
    @FocusState private var nameFocused: Bool

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
            // Insights load for run-bearing routines only; empty history keeps the section out.
            if store.routines.first(where: { $0.id == routineID })?.hasRun == true {
                let history = await runHistory.history(for: routineID)
                runTrend = history.isEmpty ? nil : RunTrend.make(history: history)
            }
        }
        .navigationDestination(isPresented: $editingCards) {
            RoutineBuilderView(initialCards: draft?.cards ?? [], initialRounds: draft?.rounds ?? 1) { cards, rounds in
                commit { $0.cards = cards; $0.rounds = max(1, rounds) }
                editingCards = false
            }
        }
        .sheet(item: $coachLaunch) { launch in
            CoachChatView(store: store, intent: launch.intent)
        }
        // A coach apply rewrites this routine in the store; refresh the local draft when the
        // sheet closes so the screen shows what was applied.
        .onChange(of: coachLaunch == nil) {
            if coachLaunch == nil {
                draft = store.routines.first { $0.id == routineID }
            }
        }
    }

    /// The INSIGHTS section's waiting state: what will appear and when — honest about the
    /// prerequisite (digests are written by runs from this version on, so a pre-existing
    /// runner's history genuinely starts at their NEXT run, not their first ever).
    private var insightsWaiting: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Time, splits, and 28-day trends build from your runs — they'll appear here after your next one.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityIdentifier("routineInsightsWaiting")
    }

    /// The INSIGHTS section body with history: a relative date, up to three quiet stat lines
    /// from the latest run's digest, and the push into Trends.
    private func lastWorkout(for routine: Routine, trend: RunTrend, latest: DatedRunDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RelativeWhen.string(for: latest.date))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(trend.stats.prefix(3), id: \.self) { stat in
                HStack {
                    Text(stat.label).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(stat.value)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(.subheadline)
            }
            NavigationLink {
                RoutineInsightsView(routine: routine, trend: trend)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar")
                    Text("Trends")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
            }
            .padding(.top, 2)
            .accessibilityIdentifier("routineTrends")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("routineLastWorkout")
    }

    /// A read-only summary of the card stack with an Edit button into the builder.
    private func cardSummary(for routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if routine.cards.isEmpty {
                Text("No cards yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(routine.cards.enumerated()), id: \.element.id) { index, card in
                    HStack(spacing: 10) {
                        Image(systemName: RoutineTheme.symbol(forCard: card))
                            .font(.caption)
                            .foregroundStyle(RoutineTheme.tint(forCard: card))
                            .frame(width: 20)
                        Text(cardTitle(card))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Text(cardDetail(card))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if card.id != routine.cards.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
                if routine.rounds > 1 {
                    Text("Repeat × \(routine.rounds) rounds")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 20) {
                Button {
                    editingCards = true
                } label: {
                    Label(routine.cards.isEmpty ? "Add Cards" : "Edit Cards", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Button {
                    coachLaunch = CoachLaunch(intent: .reviseRoutine(routineID))
                } label: {
                    Label("Ask the coach", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("askCoach")
            }
            .padding(.top, 2)
        }
    }

    private func cardTitle(_ card: WorkoutCard) -> String {
        switch card {
        case .run: return "Adaptive Run"
        case let .exercise(item): return ExerciseLibrary.exercise(id: item.exerciseId)?.name ?? item.exerciseId
        case .rest: return "Rest"
        }
    }

    private func cardDetail(_ card: WorkoutCard) -> String {
        switch card {
        // Spell the phases out ("5 warm · 20 run · 5 cool"), not the expert-only "5/20/5" —
        // phone-side rendering only; the watch keeps its own compact strings.
        case let .run(c): return "\(c.warmupMinutes) warm · \(c.durationMinutes) run · \(c.cooldownMinutes) cool"
        case let .exercise(item):
            if item.isHold { return "\(Int(item.holdSeconds ?? 0))s hold" }
            let load = item.seedWeight.map { " · \($0.displayString())" } ?? ""
            return "\(item.reps ?? 0) reps\(load)"
        case let .rest(c): return "\(Int(c.seconds))s"
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
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radiusInset, style: .continuous))
                }

                // The name is editable here because it's more than a label: it's the merge key
                // a coach/Claude import matches on (`RoutineStore.importRoutines`). With no
                // rename affordance, a routine could only be "renamed" by delete + recreate —
                // which would sever its progression history.
                FieldSection(title: "NAME") {
                    TextField("Routine name", text: nameBinding)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(Theme.textPrimary)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) {
                            if !nameFocused { commitName() }
                        }
                        .accessibilityIdentifier("routineNameField")
                }

                FieldSection(title: "DAYS") {
                    DayPicker(selection: Binding(
                        get: { draft?.repeatDays ?? [] },
                        set: { setDays($0) }
                    ))
                }

                FieldSection(title: "WORKOUT") {
                    cardSummary(for: routine)
                }

                // P6.1: last run + trends, straight from Health's digest-bearing workouts.
                // The section is a RESERVED SLOT for every run routine (principle 7): before
                // the first digest-bearing run it says what's coming instead of hiding — an
                // invisible feature reads as a missing one, and nobody re-visits a screen
                // that showed nothing (user feedback, build 18).
                if routine.hasRun {
                    FieldSection(title: "INSIGHTS") {
                        if let trend = runTrend, let latest = trend.latest {
                            lastWorkout(for: routine, trend: trend, latest: latest)
                        } else {
                            insightsWaiting
                        }
                    }
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
                        .background(Theme.hot.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusInset, style: .continuous))
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
        // Mutate the STORE's current copy, not the (possibly stale) draft: a watch
        // progression can land while this screen is open, and writing the cached draft back
        // would silently revert it. The draft is a view cache; the store is the truth.
        guard var routine = store.routines.first(where: { $0.id == routineID }) ?? draft else { return }
        mutate(&routine)
        draft = routine
        store.update(routine)
        Task { await CalendarService.shared.sync(for: routine, prompt: promptCalendar) }
    }

    private func setDays(_ days: Set<DayOfWeek>) { commit { $0.repeatDays = days } }
    private func setTime(_ time: ScheduleTime) { commit { $0.scheduleTime = time } }

    /// Buffers keystrokes in the draft only; `commitName()` persists once editing ends.
    private var nameBinding: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { draft?.name = $0 }
        )
    }

    /// Persist the buffered rename. An empty name would break identity everywhere the app
    /// matches by name (imports, watch sync display) — revert to the stored name instead of
    /// saving it.
    private func commitName() {
        let trimmed = (draft?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft?.name = store.routines.first { $0.id == routineID }?.name ?? ""
            return
        }
        commit { $0.name = trimmed }
    }

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
