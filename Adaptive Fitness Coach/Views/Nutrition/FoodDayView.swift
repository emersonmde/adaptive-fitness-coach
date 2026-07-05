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
    @Bindable var controller: MealLogController
    let recorder: any NutritionRecorder
    @Bindable var targetStore: CalorieTargetStore
    let bodyProfileSource: any BodyProfileSource
    /// Capture entry points carry the VIEWED day — adding while browsing Tuesday means
    /// backfilling Tuesday, not silently logging to today.
    let onScan: (Date) -> Void
    let onType: (Date) -> Void

    /// Day position relative to today: 0 = today, negative = past (floor: one year —
    /// beyond that, Health's own trends are the archive, not day-by-day paging).
    @State private var selection = 0
    /// Frozen at push time (the same lifetime anchorDay had) — days are offsets from here.
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

    private var calendar: Calendar { .current }
    private static let maxDaysBack = 365

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                dayPager
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                ZStack {
                    FoodDayContent(
                        day: day(for: selection),
                        isToday: selection == 0,
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
                    .transition(.asymmetric(
                        insertion: .move(edge: slideInEdge),
                        removal: .move(edge: slideInEdge == .leading ? .trailing : .leading)
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
                Task {
                    do {
                        try await recorder.delete(entryID: entry.id)
                    } catch {
                        // An entry that silently stays after "Delete" reads as a bug —
                        // failure must be as visible as success (principle 13).
                        deleteError = "Health couldn't delete that entry. Try again."
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
                onSaved: { refreshTick += 1 },
                onRelogged: { noteRelog(newID: $0) }
            )
        }
    }

    private func day(for offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
    }

    /// Warm the cache for the days a swipe can reach next, so they slide in populated.
    private func prefetchNeighbors() async {
        for offset in [selection - 1, selection + 1]
        where offset <= 0 && offset >= -Self.maxDaysBack {
            let target = day(for: offset)
            guard dayCache[target] == nil else { continue }
            let intake = (try? await recorder.intake(on: target)) ?? DailyIntake()
            let active = try? await recorder.activeEnergyBurned(on: target)
            dayCache[target] = DaySnapshot(intake: intake, activeKcal: active)
        }
    }

    // MARK: - Day changes (chevrons, title, swipe — all funnel through here)

    /// One entry point so every path gets the same slide: moving into the past enters
    /// from the LEADING edge (yesterday lives to the left), toward today from TRAILING.
    private func changeDay(by delta: Int) {
        let target = min(max(selection + delta, -Self.maxDaysBack), 0)
        guard target != selection else { return }
        slideInEdge = target < selection ? .leading : .trailing
        withAnimation(.easeInOut(duration: 0.28)) { selection = target }
    }

    // MARK: - Pager header

    private var isToday: Bool { selection == 0 }

    private var dayPager: some View {
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
        reloggedID = newID   // badge exactly the new entry, not every same-named row
        refreshTick += 1
        guard !isToday else { return }   // on today the badge itself is the confirmation
        withAnimation { showingRelogToast = true }
        relogToastTask?.cancel()
        relogToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { showingRelogToast = false }
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityIdentifier("meal.day.editTarget")
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                        Text("\(Int(intake.totalKcal.rounded()).formatted()) kcal")
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
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
                    .foregroundStyle(Theme.textTertiary)
                Text("\(Int(activeKcal.rounded()).formatted()) kcal active")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
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
                    .foregroundStyle(Theme.textTertiary)
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
                        .foregroundStyle(Theme.textTertiary)
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
                .foregroundStyle(Theme.textTertiary)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { openRowID = nil }
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
        let fresh = (try? await recorder.intake(on: day)) ?? intake
        let active = try? await recorder.activeEnergyBurned(on: day)
        intake = fresh
        activeKcal = active
        onFetched(day, DaySnapshot(intake: fresh, activeKcal: active))
    }
}

// MARK: - Notification-style swipe row

/// Custom swipe actions styled like the row itself (native `swipeActions` renders
/// full-bleed slabs that fight the floating-card look, and only works in a List).
/// The mechanics mirror Notification Center: a short drag reveals a card-styled button
/// that stretches with the finger; past the commit threshold a haptic fires and release
/// performs the action. Leading = log again, trailing = delete (which only *requests* —
/// the confirm dialog stays between a flick and a permanent Health deletion).
private struct SwipeableRow<Content: View>: View {
    let id: UUID
    @Binding var openRowID: UUID?
    let onRelog: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    /// Offset when the current drag began (an open row drags from its parked position).
    @State private var dragStart: CGFloat?
    /// Crossing the commit threshold mid-drag → one haptic tick (and back off = another).
    @State private var pastCommit = false
    /// Decided on the first movement: horizontal-dominant → ours; vertical → the scroll
    /// view's (we run simultaneous with it, so we must self-reject or scrolls would
    /// drag rows sideways).
    @State private var horizontalLatch: Bool?

    private let buttonWidth: CGFloat = 68
    private let gap: CGFloat = 8
    private var revealWidth: CGFloat { buttonWidth + gap }
    private let commitDistance: CGFloat = 180

    var body: some View {
        ZStack {
            // Leading action (revealed by dragging right).
            actionButton(
                title: "Log again", systemImage: "arrow.counterclockwise",
                tint: Theme.accent, alignment: .leading, revealed: offset
            ) {
                close()
                onRelog()
            }
            // Trailing action (revealed by dragging left).
            actionButton(
                title: "Delete", systemImage: "trash",
                tint: Theme.hot, alignment: .trailing, revealed: -offset
            ) {
                close()
                onDelete()
            }
            content
                .offset(x: offset)
        }
        // highPriority: plain and simultaneous variants both silently lose the recognizer
        // race to the ScrollView+Button stack (verified via hierarchy dump — the drag never
        // fired). The 18pt minimum keeps taps routing to the Button; the latch hands
        // vertical movement back to the scroll view.
        .highPriorityGesture(drag)
        .sensoryFeedback(.impact(weight: .medium), trigger: pastCommit) { _, crossed in crossed }
        .onChange(of: openRowID) {
            // Someone else opened (or everything was told to close) — park back at zero.
            if openRowID != id, offset != 0 { close() }
        }
    }

    /// One action, styled like the Card it hides behind: same corner radius and border,
    /// tinted icon+label, and it STRETCHES with the drag past its resting width.
    private func actionButton(
        title: String, systemImage: String, tint: Color,
        alignment: Alignment, revealed: CGFloat, action: @escaping () -> Void
    ) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 0) }
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .frame(width: max(buttonWidth, revealed - gap))
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .opacity(revealed > 8 ? min(1, Double((revealed - 8) / 40)) : 0)
        .accessibilityHidden(revealed < revealWidth * 0.6)   // VoiceOver uses the row's actions
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if horizontalLatch == nil {
                    horizontalLatch = abs(value.translation.width) > abs(value.translation.height)
                }
                guard horizontalLatch == true else { return }
                if dragStart == nil {
                    dragStart = offset
                    openRowID = id   // opening this row closes any other
                }
                let proposed = (dragStart ?? 0) + value.translation.width
                // Rubber-band past the commit point — the action is armed, not "more armed".
                if abs(proposed) > commitDistance {
                    let sign: CGFloat = proposed > 0 ? 1 : -1
                    offset = sign * (commitDistance + (abs(proposed) - commitDistance) * 0.22)
                } else {
                    offset = proposed
                }
                pastCommit = abs(proposed) > commitDistance
            }
            .onEnded { value in
                let wasOurs = horizontalLatch == true && dragStart != nil
                let landed = (dragStart ?? 0) + value.translation.width
                horizontalLatch = nil
                dragStart = nil
                pastCommit = false
                guard wasOurs else { return }
                if landed < -commitDistance {
                    close()
                    onDelete()          // long swipe left commits (delete still confirms)
                } else if landed > commitDistance {
                    close()
                    onRelog()           // long swipe right commits
                } else if landed < -revealWidth * 0.6 {
                    park(at: -revealWidth)   // short swipe + release → buttons stay exposed
                } else if landed > revealWidth * 0.6 {
                    park(at: revealWidth)
                } else {
                    close()
                }
            }
    }

    private func park(at position: CGFloat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = position }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = 0 }
        if openRowID == id { openRowID = nil }
    }
}

/// The rows never *looked* tappable — this makes them *feel* tappable: a brief dim+settle
/// on touch teaches "these respond" after one tap, without adding chrome to every card.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
