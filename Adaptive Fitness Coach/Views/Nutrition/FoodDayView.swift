import SwiftUI
import AdaptiveCore

/// The Food day screen (build 8; regestured builds 15–16) — pushed from the hub's daily
/// line. The gesture grammar, settled on-device across three iterations (full-page pager
/// → zone-scoped swipe → this): day-swiping is GONE — the pager stole row swipes, the
/// zoned hybrid felt janky, and a gesture that has to be defended isn't premium. What
/// remains is deliberate:
///   · CHEVRONS (+ tap-title-to-today) change days, with one owned directional slide:
///     going to the past enters from the LEFT, toward today from the right;
///   · entry rows swipe like Notification Center rows: a short drag reveals card-styled
///     buttons that stretch with the finger, a long drag commits with a haptic at the
///     threshold — leading = log again, trailing = delete-with-confirm.
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
    /// Frozen at push time — days are offsets from here.
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
    /// Delete confirms first — Health deletion has no undo.
    @State private var pendingDelete: MealEntry?
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
                        onDeleteRequest: { pendingDelete = $0 },
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
        .task {
            // The stream ends when this task is cancelled on disappear — no leaked observers.
            for await _ in recorder.changes() { refreshTick += 1 }
        }
        .task {
            // First run: offer the target once, skippable (a target is opt-in — C6).
            if targetStore.target == nil && !targetStore.wasOffered {
                targetStore.markOffered()
                showingTargetSheet = true
            }
        }
        .task(id: "\(selection)/\(refreshTick)") { await prefetchNeighbors() }
        .onChange(of: refreshTick) { dayCache = [:] }   // Health changed → nothing cached is safe
        .onChange(of: controller.phase) { refreshTick += 1 }
        .alert("Couldn't delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let entry = pendingDelete else { return }
                Theme.Haptics.warning()   // a permanent Health deletion is the moment to be felt
                Task {
                    do {
                        try await recorder.delete(entryID: entry.id)
                    } catch {
                        // An entry that silently stays after "Delete" reads as a bug —
                        // failure must be as visible as success (principle 13).
                        deleteError = "Health couldn't delete that entry. Try again."
                        Theme.Haptics.warning()
                    }
                    refreshTick += 1
                }
            }
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
        }
    }

    private func day(for offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
    }

    /// Warm the cache for the neighbor days the chevrons reach, so they slide in populated.
    private func prefetchNeighbors() async {
        for offset in [selection - 1, selection + 1]
        where offset <= 0 && offset >= -Self.maxDaysBack {
            let target = day(for: offset)
            guard dayCache[target] == nil else { continue }
            let (intake, active) = await DaySnapshot.fetch(recorder: recorder, day: target)
            dayCache[target] = DaySnapshot(intake: intake ?? DailyIntake(), activeKcal: active)
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
    let onDeleteRequest: (MealEntry) -> Void
    let onEditTarget: () -> Void

    @State private var intake: DailyIntake
    @State private var activeKcal: Double?
    /// The one open swipe row (Notification Center behavior: opening one closes the rest).
    @State private var openRowID: UUID?

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
        onDeleteRequest: @escaping (MealEntry) -> Void,
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
        self.onDeleteRequest = onDeleteRequest
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
        .task(id: refreshTick) { await refresh() }
    }

    // MARK: Summary zone (fixed above the scrolling entries)

    private var summaryZone: some View {
        VStack(spacing: 8) {
            gaugeSlot
            activeEnergyLine
        }
    }

    private var gaugeSlot: some View {
        VStack(spacing: 8) {
            if let budget = targetStore.budget(consumedKcal: intake.totalKcal) {
                CalorieGaugeView(budget: budget)
                Button(action: onEditTarget) {
                    // The decision-driving number: what's LEFT (the center already says
                    // "of 1,600" — repeating the target here wasted the slot). When over,
                    // the center says "N over", so the target is the informative line again.
                    Text(budget.remainingKcal.map { "\($0.formatted()) kcal left" }
                        ?? "Target \(budget.targetKcal.formatted()) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)   // decision-driving number — legible tier
                }
                .accessibilityIdentifier("meal.day.editTarget")
            } else {
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 208)   // same slot either way — no jump when a target appears
    }

    private var activeEnergyLine: some View {
        HStack(spacing: 6) {
            if let activeKcal, activeKcal > 0 {
                Image(systemName: "flame")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)   // decorative — the text says "active"
                Text("\(Int(activeKcal.rounded()).formatted()) kcal active")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("meal.day.active")
            }
            Spacer()
            // browse/nutrition is undocumented but community-established; an unrecognized
            // path degrades to just opening Health (exactly the old behavior), so this is
            // a free attempt at landing on the Nutrition room directly.
            if let url = URL(string: "x-apple-health://browse/nutrition") {
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Text("Trends in Health")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)   // interactive — keep it legible
                }
            }
        }
        .frame(height: 18)
    }

    // MARK: Entry stack (vertical scroll; rows own their horizontal swipes)

    private var entryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                mealSections
                if otherAppsKcal > 0 {
                    Text("\(Int(otherAppsKcal.rounded()).formatted()) kcal from other apps")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)   // honesty string — legible tier
                        .padding(.horizontal, 4)
                }
                if intake.entries.isEmpty && otherAppsKcal == 0 {
                    Text(isToday ? "Nothing logged yet today." : "Nothing logged this day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealSlot.dayOrder, id: \.self) { slot in
            let entries = intake.entries.filter { $0.meal == slot }
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(slot, entries: entries)
                    ForEach(entries) { entry in
                        SwipeableRow(
                            id: entry.id,
                            openRowID: $openRowID,
                            onRelog: { onRelog(entry) },
                            onDelete: { onDeleteRequest(entry) }
                        ) {
                            entryRow(entry)
                        }
                    }
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

    /// Every action, three surfaces: swipe (Notification-Center style), tap → edit sheet
    /// (the floor every user finds), long-press → menu (the power path).
    private func entryRow(_ entry: MealEntry) -> some View {
        Button {
            // A tap while a row is open closes it (Notification Center behavior) —
            // never opens the editor underneath the user's cleanup gesture.
            if openRowID != nil {
                withAnimation(Theme.Motion.gesture) { openRowID = nil }
            } else {
                onEdit(entry)
            }
        } label: {
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
                            if reloggedID == entry.id {
                                Text("· logged again")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    Spacer()
                    Text(energyText(entry))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("meal.day.entry.\(entry.name)")
        .accessibilityAction(named: "Log again") { onRelog(entry) }
        .accessibilityAction(named: "Delete") { onDeleteRequest(entry) }
        .contextMenu {
            Button {
                onEdit(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                onRelog(entry)
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                onDeleteRequest(entry)   // confirm first — there is no undo
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func energyText(_ entry: MealEntry) -> String {
        let servings = Double(max(1, entry.quantity))
        switch entry.facts.energy {
        case .exact(let kcal):
            return "\(Int((kcal * servings).rounded())) kcal"
        case .range(let low, let high):
            return "\(Int((low * servings).rounded()))–\(Int((high * servings).rounded())) kcal"
        }
    }

    private func refresh() async {
        let (fetched, active) = await DaySnapshot.fetch(recorder: recorder, day: day)
        let fresh = fetched ?? intake   // failed query keeps the numbers we had (N6)
        intake = fresh
        activeKcal = active
        onFetched(day, DaySnapshot(intake: fresh, activeKcal: active))
    }
}

// SwipeableRow + PressableCardStyle moved to Components/SwipeableRow.swift (P5).
