import SwiftUI
import Combine
import AdaptiveCore

/// The Food day screen (build 8; regestured builds 15–16) — pushed from the hub's daily
/// line. The gesture grammar, settled on-device across three iterations (full-page pager
/// → zone-scoped swipe → this): day-swiping is GONE — the pager stole row swipes, the
/// zoned hybrid felt janky, and a gesture that has to be defended isn't premium. What
/// remains is deliberate:
///   · CHEVRONS (+ tap-title-to-today) change days, with one owned directional slide:
///     going to the past enters from the LEFT, toward today from the right;
///   · entry rows use native List swipe actions — leading = log again, trailing =
///     delete-with-confirm (the dialog anchors to the row; even a full swipe only asks).
/// Day data is cached and neighbors prefetched so an incoming day slides in already
/// populated (an empty active-energy line used to sit visually still mid-transition).
/// Trends stay in Apple Health (linked); this screen is a day, not a dashboard (C6).
struct FoodDayView: View {
    let controller: MealLogController
    let recorder: any NutritionRecorder
    let targetStore: CalorieTargetStore
    let bodyProfileSource: any BodyProfileSource
    /// Capture entry points carry the VIEWED day — adding while browsing Tuesday means
    /// backfilling Tuesday, not silently logging to today.
    let onScan: (Date) -> Void
    let onType: (Date) -> Void

    /// Day position relative to today: 0 = today, negative = past (floor: one year —
    /// beyond that, Health's own trends are the archive, not day-by-day paging).
    @State private var selection = 0
    /// The anchor days are offsets from. NOT push-time-frozen: NavigationStack keeps this
    /// view's @State alive across presentations, so a screen last opened yesterday resumed
    /// with yesterday as "Today" (and, opened from there, prefilled captures with the wrong
    /// day). Realigned on appear and at midnight — see `realignToday`.
    @State private var todayStart = Calendar.current.startOfDay(for: Date())
    /// Which edge the INCOMING day slides from (set before every day change).
    @State private var slideInEdge: Edge = .leading
    /// Last-known intake/active per day: the incoming page renders from this while its
    /// own fetch runs, so the slide carries real numbers, not blanks.
    @State private var dayCache: [Date: DaySnapshot] = [:]
    @State private var editingEntry: MealEntry?
    @State private var showingTargetSheet = false
    @State private var reloggedID: UUID?
    @State private var deleteError: String?
    @State private var refreshTick = 0
    /// "Added to Today" notice after relogging from a past day (the entry lands on a day
    /// the user isn't looking at — say so instead of teleporting them there).
    @State private var showingRelogToast = false
    @State private var relogToastTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { .current }
    private static let maxDaysBack = 365

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                dayHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                ZStack {
                    FoodDayContent(
                        day: day(for: selection),
                        isToday: isToday,
                        refreshTick: refreshTick,
                        recorder: recorder,
                        targetStore: targetStore,
                        reloggedID: reloggedID,
                        initial: dayCache[day(for: selection)],
                        onFetched: { day, snapshot in dayCache[day] = snapshot },
                        onEdit: { editingEntry = $0 },
                        onRelog: { entry in Task { await logAgain(entry) } },
                        onDeleteConfirmed: { entry in Task { await performDelete(entry) } },
                        onEditTarget: { showingTargetSheet = true }
                    )
                    .id(selection)   // day change replaces the content → the slide transition
                    .transition(Theme.Motion.slideTransition(
                        .asymmetric(
                            insertion: .move(edge: slideInEdge),
                            removal: .move(edge: slideInEdge == .leading ? .trailing : .leading)
                        ),
                        reduceMotion: reduceMotion
                    ))
                }
                .clipped()
            }
        }
        .safeAreaInset(edge: .bottom) { addBar }
        .overlay(alignment: .bottom) { relogToast }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Trends live in Apple Health (this screen is a day, not a dashboard — C6). Moved
            // off the summary panel so it stops competing with the budget arithmetic.
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: "x-apple-health://browse/nutrition") {
                    Link(destination: url) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityLabel("Trends in Health")
                }
            }
        }
        .task {
            // The stream ends when this task is cancelled on disappear — no leaked observers.
            for await _ in recorder.changes() { refreshTick += 1 }
        }
        .task {
            // First run: offer the target once, skippable (a target is opt-in — C6).
            if !targetStore.hasTarget && !targetStore.wasOffered {
                targetStore.markOffered()
                showingTargetSheet = true
            }
        }
        .task {
            // Learn/refresh the per-user TDEE correction from the Health weight trend. Throttled
            // to once a day inside the store — weight moves over weeks, not minutes.
            await targetStore.refreshCalibration()
        }
        .task(id: "\(selection)/\(refreshTick)") { await prefetchNeighbors() }
        .onChange(of: refreshTick) { dayCache = [:] }   // Health changed → nothing cached is safe
        .onAppear { realignToday(preservingViewedDay: false) }
        .onReceive(NotificationCenter.default
            .publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)) { _ in
            // Midnight while the screen is up: keep the user on the day they were reading —
            // the content under them must not silently become a different day's.
            realignToday(preservingViewedDay: true)
        }
        .onChange(of: controller.phase) { refreshTick += 1 }
        .alert("Couldn't delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(isPresented: $showingTargetSheet) {
            TargetSetupSheet(targetStore: targetStore, bodyProfileSource: bodyProfileSource)
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(
                entry: entry,
                recorder: recorder,
                onSaved: { Theme.Haptics.success(); refreshTick += 1 },
                onRelogged: { noteRelog(newID: $0) }
            )
            // Fresh @State per entry: sheet(item:) reuses the presentation's storage, so
            // without distinct identity editing row B showed row A's half-remembered fields.
            .id(entry.id)
        }
    }

    /// The row (or its context menu) already confirmed — this is the commit. Permanent:
    /// Health deletion has no undo, which is why failure must be as visible as success
    /// (principle 13).
    private func performDelete(_ entry: MealEntry) async {
        Theme.Haptics.warning()   // a permanent Health deletion is the moment to be felt
        do {
            try await recorder.delete(entryID: entry.id)
        } catch {
            deleteError = "Health couldn't delete that entry. Try again."
            Theme.Haptics.warning()
        }
        refreshTick += 1
    }

    private func day(for offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
    }

    /// Re-anchor `todayStart` to the actual calendar day. On (re)appear the screen opens on
    /// today (fresh-open semantics); at midnight mid-session the selection shifts so the
    /// VIEWED day stays the same. The cache survives either way — it's keyed by absolute date.
    private func realignToday(preservingViewedDay: Bool) {
        let now = calendar.startOfDay(for: Date())
        guard now != todayStart else { return }
        if preservingViewedDay {
            let delta = calendar.dateComponents([.day], from: todayStart, to: now).day ?? 0
            selection = max(selection - delta, -Self.maxDaysBack)
        } else {
            selection = 0
        }
        todayStart = now
    }

    /// Warm the cache for the neighbor days the chevrons reach, so they slide in populated.
    private func prefetchNeighbors() async {
        for offset in [selection - 1, selection + 1]
        where offset <= 0 && offset >= -Self.maxDaysBack {
            let target = day(for: offset)
            guard dayCache[target] == nil else { continue }
            let (intake, active) = await DaySnapshot.fetch(recorder: recorder, day: target)
            // A failed prefetch caches NOTHING: substituting an empty DailyIntake seeded
            // every neighboring day with fabricated "nothing logged" (the day's own
            // fetch then failing too made the whole history look deleted).
            guard let intake else { continue }
            dayCache[target] = DaySnapshot(intake: intake, activeKcal: active)
        }
    }

    // MARK: - Day changes (chevrons, title, relog toast — all funnel through here)

    /// One entry point so every path gets the same slide: moving into the past enters
    /// from the LEADING edge (yesterday lives to the left), toward today from TRAILING.
    private func changeDay(by delta: Int) {
        let target = min(max(selection + delta, -Self.maxDaysBack), 0)
        guard target != selection else { return }
        slideInEdge = target < selection ? .leading : .trailing
        Theme.Haptics.selection()
        withAnimation(Theme.Motion.slide(reduceMotion: reduceMotion)) { selection = target }
    }

    // MARK: - Day header

    private var isToday: Bool { selection == 0 }

    private var dayHeader: some View {
        HStack {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(selection == -Self.maxDaysBack
                        ? Theme.textTertiary.opacity(0.4) : Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .disabled(selection == -Self.maxDaysBack)
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier("meal.day.prev")

            Spacer()
            // On a past day the title is the way home: tap it to jump straight back to today.
            if isToday {
                Text(dayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("meal.day.title")
            } else {
                Button {
                    changeDay(by: -selection)
                } label: {
                    HStack(spacing: 5) {
                        Text(dayTitle)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "arrow.uturn.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal.day.title")
                .accessibilityHint("Jump back to today")
            }
            Spacer()

            // Reserved slot: disabled-at-today, never removed (principle 7).
            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(isToday ? Theme.textTertiary.opacity(0.4) : Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
            .accessibilityIdentifier("meal.day.next")
        }
    }

    private var dayTitle: String {
        let day = day(for: selection)
        if isToday { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Relog (never teleports)

    private func logAgain(_ entry: MealEntry) async {
        let fresh = entry.relogged()
        if (try? await recorder.record(fresh)) != nil {
            noteRelog(newID: fresh.id)
        }
    }

    private func noteRelog(newID: UUID) {
        Theme.Haptics.success()   // the log landed — the core action deserves to be felt
        reloggedID = newID   // badge exactly the new entry, not every same-named row
        refreshTick += 1
        guard !isToday else { return }   // on today the badge itself is the confirmation
        withAnimation(Theme.Motion.slide(reduceMotion: reduceMotion)) { showingRelogToast = true }
        relogToastTask?.cancel()
        relogToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.slide(reduceMotion: reduceMotion)) { showingRelogToast = false }
        }
    }

    @ViewBuilder
    private var relogToast: some View {
        if showingRelogToast {
            Button {
                relogToastTask?.cancel()
                showingRelogToast = false
                changeDay(by: -selection)
            } label: {
                Label("Added to Today", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .transition(Theme.Motion.slideTransition(
                .move(edge: .bottom).combined(with: .opacity), reduceMotion: reduceMotion))
            .accessibilityIdentifier("meal.day.relogToast")
            .accessibilityHint("Jump to today")
        }
    }

    // MARK: - Pinned add bar

    /// The screen's primary action never scrolls away. Adding from a past day logs to that
    /// day (the when-row prefills it, still editable on the confirmation screen).
    private var addBar: some View {
        HStack(spacing: 10) {
            PrimaryButton(title: "Scan a meal", systemImage: "camera.viewfinder") {
                onScan(viewedCaptureDate)
            }
            .accessibilityIdentifier("meal.day.scan")
            Button {
                onType(viewedCaptureDate)
            } label: {
                Image(systemName: "keyboard")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 54, height: 54)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Type a meal")
            .accessibilityIdentifier("meal.day.type")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Theme.bg)
    }

    /// The viewed day carrying the current time-of-day — so the meal-slot heuristic still
    /// suggests sensibly ("dinner time" on Tuesday, not midnight-snack).
    private var viewedCaptureDate: Date {
        let viewed = day(for: selection)
        guard !calendar.isDateInToday(viewed) else { return Date() }
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        return calendar.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: viewed
        ) ?? viewed
    }
}

/// Last-known numbers for one day — what an incoming page renders while its fetch runs.
private struct DaySnapshot {
    var intake: DailyIntake
    var activeKcal: Double?

    /// The one fetch both the prefetcher and a day's own refresh use. `nil` intake means
    /// the query failed — callers choose their own fallback (empty vs keep-what-we-had).
    static func fetch(
        recorder: any NutritionRecorder, day: Date
    ) async -> (intake: DailyIntake?, activeKcal: Double?) {
        let intake = try? await recorder.intake(on: day)
        let active = try? await recorder.activeEnergyBurned(on: day)
        return (intake, active)
    }
}

// MARK: - One day's content

/// A single day: the fixed summary zone (gauge + active line) over the scrolling entry
/// stack. Owns its own fetch (seeded from the parent's cache) so the OUTGOING day keeps
/// its data while it slides away.
private struct FoodDayContent: View {
    let day: Date
    let isToday: Bool
    let refreshTick: Int
    let recorder: any NutritionRecorder
    var targetStore: CalorieTargetStore
    let reloggedID: UUID?
    let onFetched: (Date, DaySnapshot) -> Void
    let onEdit: (MealEntry) -> Void
    let onRelog: (MealEntry) -> Void
    let onDeleteConfirmed: (MealEntry) -> Void
    let onEditTarget: () -> Void

    @State private var intake: DailyIntake
    @State private var activeKcal: Double?
    /// The last fetch THREW (cold-launch reads can race the Health daemon). Rendering that
    /// as "Nothing logged" reads as data loss — the one thing this screen must never fake.
    @State private var loadFailed = false

    init(
        day: Date,
        isToday: Bool,
        refreshTick: Int,
        recorder: any NutritionRecorder,
        targetStore: CalorieTargetStore,
        reloggedID: UUID?,
        initial: DaySnapshot?,
        onFetched: @escaping (Date, DaySnapshot) -> Void,
        onEdit: @escaping (MealEntry) -> Void,
        onRelog: @escaping (MealEntry) -> Void,
        onDeleteConfirmed: @escaping (MealEntry) -> Void,
        onEditTarget: @escaping () -> Void
    ) {
        self.day = day
        self.isToday = isToday
        self.refreshTick = refreshTick
        self.recorder = recorder
        self.targetStore = targetStore
        self.reloggedID = reloggedID
        self.onFetched = onFetched
        self.onEdit = onEdit
        self.onRelog = onRelog
        self.onDeleteConfirmed = onDeleteConfirmed
        self.onEditTarget = onEditTarget
        // Seed from the cache so the slide-in carries real numbers, not blanks.
        _intake = State(initialValue: initial?.intake ?? DailyIntake())
        _activeKcal = State(initialValue: initial?.activeKcal)
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryZone
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
                // .contain (not a bare identifier): the zone must be a real element for
                // XCUI/VoiceOver *containing* its children — a bare identifier on a stack
                // half-registers and can swallow the gauge's buttons.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("meal.day.summary")
            entryScroll
        }
        .task(id: refreshTick) {
            await refresh()
            if loadFailed {
                // One automatic retry — the common failure is transient (daemon warmup
                // right after launch); the visible Try-again handles anything persistent.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    // MARK: Summary zone (fixed above the scrolling entries)

    private var summaryZone: some View {
        gaugeSlot
    }

    @ViewBuilder
    private var gaugeSlot: some View {
        VStack(spacing: 8) {
            if let dynamic = targetStore.dynamicBudget(
                consumedKcal: intake.totalKcal, activeEarnedKcal: activeKcal ?? 0
            ) {
                dynamicGauge(dynamic)
            } else if let budget = targetStore.budget(consumedKcal: intake.totalKcal) {
                fixedGauge(budget)
            } else {
                noTargetPrompt
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 236)   // won't shrink below the no-target prompt (no jump when a target appears)
    }

    /// Deficit mode. Three tiers, each derived from the one above so the arithmetic is
    /// self-evident: the ring center is what's eaten of the budget; the remaining line is the
    /// decision number; the breakdown proves it (base + active − eaten == remaining, always).
    private func dynamicGauge(_ dynamic: DynamicDayBudget) -> some View {
        VStack(spacing: 8) {
            CalorieGaugeView(budget: dynamic.budget)
            remainingLine(dynamic.remainingSignedKcal)   // A — decision, signed, never "Target"
            breakdownLine(dynamic)                        // B — proof, sums to A exactly
            if let note = dynamicNote(dynamic) {          // C — floor / calibration, only if present
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
                    .accessibilityIdentifier("meal.day.calibrationNote")
            }
        }
    }

    /// Fixed manual target (Health lacked body data) — same remaining line, no adaptive breakdown.
    private func fixedGauge(_ budget: DayBudget) -> some View {
        VStack(spacing: 8) {
            CalorieGaugeView(budget: budget)
            remainingLine(budget.targetKcal - Int(budget.consumedKcal.rounded()))
        }
    }

    /// The decision number: "N left" (or "N over" in amber when negative). Tapping edits the goal.
    private func remainingLine(_ remaining: Int) -> some View {
        let over = remaining < 0
        return Button(action: onEditTarget) {
            (Text("\(abs(remaining).formatted()) ").foregroundColor(over ? Theme.heat : Theme.textPrimary)
                + Text(over ? "over" : "left").foregroundColor(over ? Theme.heat : Theme.textSecondary))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .accessibilityIdentifier("meal.day.editTarget")
        .accessibilityLabel(over ? "\(abs(remaining)) calories over budget" : "\(remaining) calories left")
    }

    /// The proof: `base + active [− eaten]`, or `floor [− eaten]` when pinned. Sums to remaining.
    private func breakdownLine(_ d: DynamicDayBudget) -> some View {
        let op = Theme.textTertiary.opacity(0.55)
        var text: Text
        if d.isAtFloor {
            text = Text("\(d.targetKcal.formatted()) floor").foregroundColor(Theme.textTertiary)
        } else {
            text = Text("\(d.baseKcal.formatted()) base").foregroundColor(Theme.textTertiary)
                + Text(" + ").foregroundColor(op)
                + Text("\(d.earnedTodayKcal.formatted()) active").foregroundColor(Theme.accent)
        }
        if d.consumedRoundedKcal > 0 {
            text = text
                + Text(" − ").foregroundColor(op)
                + Text("\(d.consumedRoundedKcal.formatted()) eaten").foregroundColor(Theme.textTertiary)
        }
        return text
            .font(.caption.monospacedDigit())
            .accessibilityIdentifier("meal.day.breakdown")
    }

    /// The optional C line: the floor explainer when pinned, else the calibration note when tuned.
    private func dynamicNote(_ d: DynamicDayBudget) -> String? {
        if d.isAtFloor {
            return "Held at the \(d.targetKcal.formatted()) safe minimum · moving adds on top"
        }
        return calibrationNote
    }

    private var noTargetPrompt: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                Text("\(Int(intake.totalKcal.rounded()).formatted()) kcal")
                    .font(Theme.metricNumber)
                    .foregroundStyle(Theme.textPrimary)
            }
            Button("Set a daily target", action: onEditTarget)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("meal.day.setTarget")
        }
    }

    /// "10% under" — only once the calibration is confident. Short: it rides under the breakdown.
    private var calibrationNote: String? {
        guard let cal = targetStore.calibration, cal.isConfident,
              let deviation = cal.deviationPercent, deviation != 0 else { return nil }
        return "Tuned to your weigh-ins · \(abs(deviation))% \(deviation < 0 ? "under" : "over")"
    }

    // MARK: Entry list (a real List: native swipe actions, and the delete confirm anchors
    // to the row it came from instead of popping over the gauge)

    private var entryScroll: some View {
        List {
            mealSections
            if otherAppsKcal > 0 {
                Text("\(Int(otherAppsKcal.rounded()).formatted()) kcal from other apps")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)   // honesty string — legible tier
                    .padding(.horizontal, 4)
                    .plainDayRow()
            }
            if intake.entries.isEmpty && otherAppsKcal == 0 {
                if loadFailed {
                    // Failure must be as visible as success (principle 13) — an empty day
                    // we couldn't verify is NOT "nothing logged".
                    VStack(spacing: 8) {
                        Text("Couldn't read this day from Health.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Try again") { Task { await refresh() } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meal.day.retryLoad")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .plainDayRow()
                } else {
                    Text(isToday ? "Nothing logged yet today." : "Nothing logged this day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .plainDayRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealSlot.dayOrder, id: \.self) { slot in
            let entries = intake.entries.filter { $0.meal == slot }
            if !entries.isEmpty {
                sectionHeader(slot, entries: entries)
                    .plainDayRow()
                    .padding(.top, 8)
                ForEach(entries) { entry in
                    EntryRow(
                        entry: entry,
                        relogged: reloggedID == entry.id,
                        onEdit: { onEdit(entry) },
                        onRelog: { onRelog(entry) },
                        onDeleteConfirmed: { onDeleteConfirmed(entry) }
                    )
                    .plainDayRow()
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sectionHeader(_ slot: MealSlot, entries: [MealEntry]) -> some View {
        HStack {
            Text(slot.displayName.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            // Quiet subtotal — "dinner is where the calories went" at a glance.
            Text("\(Int(entries.reduce(0) { $0 + $1.facts.energy.midpointKcal * Double($1.quantity) }.rounded()).formatted())")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)   // a number the user reads, not a label
        }
        .padding(.horizontal, 4)
    }

    private var otherAppsKcal: Double {
        let ours = intake.entries.reduce(0) { $0 + $1.facts.energy.midpointKcal * Double($1.quantity) }
        return max(0, intake.totalKcal - ours)
    }

    private func refresh() async {
        let (fetched, active) = await DaySnapshot.fetch(recorder: recorder, day: day)
        if let fetched {
            loadFailed = false
            intake = fetched
            activeKcal = active
            onFetched(day, DaySnapshot(intake: fetched, activeKcal: active))
        } else {
            // Failed query ≠ empty day. Keep whatever numbers we had (N6), flag the
            // failure, and NEVER seed the parent cache — a fabricated empty snapshot
            // used to poison every day it prefetched ("all my meals are gone").
            loadFailed = true
            activeKcal = active ?? activeKcal
        }
    }
}

/// One entry: tap → edit sheet (the floor every user finds), native swipes (leading = log
/// again, trailing = delete), long-press → menu (the power path). The row owns its delete
/// confirmation so the dialog anchors HERE — attached at the screen level it presented as
/// a popover over the calorie gauge.
private struct EntryRow: View {
    let entry: MealEntry
    let relogged: Bool
    let onEdit: () -> Void
    let onRelog: () -> Void
    let onDeleteConfirmed: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onEdit) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.quantity > 1 ? "\(entry.name) ×\(entry.quantity)" : entry.name)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            // "Saladworks · verified · saladworks.com" — who sold it and
                            // where the number came from, not just "database".
                            Text([entry.seller?.name, entry.provenance.detailLabel]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            if relogged {
                                Text("· logged again")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    Spacer()
                    Text(energyText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("meal.day.entry.\(entry.name)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onRelog) {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Even a full swipe only REQUESTS — the confirm stays between a flick and a
            // permanent Health deletion. Deliberately NOT role .destructive: that makes
            // the List animate the row away on tap (it assumes the action deleted), which
            // also tears down this row's alert before it can present. Red tint carries
            // the meaning instead (and keeps the app accent from painting delete green).
            Button {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.hot)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                onRelog()
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                confirmingDelete = true   // confirm first — there is no undo
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // An alert, not a confirmationDialog: centered and unmissable for an action with
        // no undo — and the row-anchored dialog popover ships AX-empty on iOS 27 (its
        // buttons are invisible to VoiceOver and UI tests alike).
        .alert("Delete \"\(entry.name)\"?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDeleteConfirmed)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from Apple Health. There's no undo.")
        }
    }

    private var energyText: String {
        let servings = Double(max(1, entry.quantity))
        switch entry.facts.energy {
        case .exact(let kcal):
            return "\(Int((kcal * servings).rounded())) kcal"
        case .range(let low, let high):
            return "\(Int((low * servings).rounded()))–\(Int((high * servings).rounded())) kcal"
        }
    }
}

private extension View {
    /// The List is chrome-free: the Card look survives, the List contributes only scroll,
    /// native swipe actions, and row-anchored presentation.
    func plainDayRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

// PressableCardStyle lives in Components/PressableCardStyle.swift.
