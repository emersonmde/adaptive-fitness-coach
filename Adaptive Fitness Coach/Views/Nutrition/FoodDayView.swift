import SwiftUI
import AdaptiveCore

/// The Food day screen (build 8; regestured build 15) — pushed from the hub's daily line.
/// The gesture grammar, settled on-device (build 14's full-page pager stole horizontal
/// drags from the rows AND animated in SwiftUI's fixed direction):
///   · the SUMMARY ZONE (date header + gauge + active line) is fixed and swipes between
///     days — a horizontal drag we own, so the transition direction is ours: swiping
///     right brings the previous day in from the LEFT, like every calendar;
///   · the entry LIST below scrolls vertically and keeps native row swipe actions
///     (leading = log again, trailing = delete-with-confirm);
///   · chevrons + tap-title-to-today remain the discoverable/accessible day paths.
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
                    .contentShape(Rectangle())
                    .gesture(daySwipe)   // the header is part of the swipeable day chrome
                ZStack {
                    FoodDayContent(
                        day: day(for: selection),
                        isToday: selection == 0,
                        refreshTick: refreshTick,
                        recorder: recorder,
                        targetStore: targetStore,
                        reloggedID: reloggedID,
                        daySwipe: daySwipe,
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

    // MARK: - Day changes (chevrons, title, swipe — all funnel through here)

    /// One entry point so every path gets the same slide: moving into the past enters
    /// from the LEADING edge (yesterday lives to the left), toward today from TRAILING.
    private func changeDay(by delta: Int) {
        let target = min(max(selection + delta, -Self.maxDaysBack), 0)
        guard target != selection else { return }
        slideInEdge = target < selection ? .leading : .trailing
        withAnimation(.easeInOut(duration: 0.28)) { selection = target }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Horizontal-dominant and deliberate, or ignore (buttons/scroll keep working).
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                changeDay(by: dx > 0 ? -1 : 1)   // finger right → reveal the past
            }
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

// MARK: - One day's content

/// A single day: the fixed summary zone (gauge + active line — the day-swipe surface) over
/// the scrolling entry List. Owns its own fetch so the OUTGOING day keeps its data while it
/// slides away (parent-held intake would flash the new day's numbers into the old view).
private struct FoodDayContent<SwipeGesture: Gesture>: View {
    let day: Date
    let isToday: Bool
    let refreshTick: Int
    let recorder: any NutritionRecorder
    var targetStore: CalorieTargetStore
    let reloggedID: UUID?
    let daySwipe: SwipeGesture
    let onEdit: (MealEntry) -> Void
    let onRelog: (MealEntry) -> Void
    let onDeleteRequest: (MealEntry) -> Void
    let onEditTarget: () -> Void

    @State private var intake = DailyIntake()
    @State private var activeKcal: Double?

    var body: some View {
        VStack(spacing: 0) {
            summaryZone
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .gesture(daySwipe)
                // .contain (not a bare identifier): the zone must be a real element for
                // XCUI/VoiceOver *containing* its children — a bare identifier on a stack
                // half-registers and can swallow the gauge's buttons.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("meal.day.summary")
            entryList
        }
        .task(id: refreshTick) { await refresh() }
    }

    // MARK: Summary zone (fixed; the day-swipe surface)

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

    // MARK: Entry list (vertical scroll; rows own their horizontal swipes)

    private var entryList: some View {
        List {
            mealSections
            if otherAppsKcal > 0 {
                plainRow(
                    Text("\(Int(otherAppsKcal.rounded()).formatted()) kcal from other apps")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                )
            }
            if intake.entries.isEmpty && otherAppsKcal == 0 {
                plainRow(
                    Text(isToday ? "Nothing logged yet today." : "Nothing logged this day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// List-as-canvas: every row is chromeless; the Cards supply their own surfaces.
    private func plainRow(_ content: some View, top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealSlot.dayOrder, id: \.self) { slot in
            let entries = intake.entries.filter { $0.meal == slot }
            if !entries.isEmpty {
                plainRow(sectionHeader(slot, entries: entries), top: 12, bottom: 2)
                ForEach(entries) { entry in
                    plainRow(entryRow(entry), top: 4, bottom: 4)
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

    /// Every action, three surfaces: swipe (iOS muscle memory — works now that no pager
    /// steals horizontal drags from rows), tap → edit sheet (the floor every user finds),
    /// long-press → menu (the power path). All three carry the same set.
    private func entryRow(_ entry: MealEntry) -> some View {
        Button {
            onEdit(entry)
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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onRelog(entry)
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Destructive-styled but NOT destructive-behaved: it only raises the
            // confirmation dialog (Health deletion has no undo), so full-swipe is safe.
            Button(role: .destructive) {
                onDeleteRequest(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
        if let fresh = try? await recorder.intake(on: day) {
            intake = fresh
        }
        activeKcal = try? await recorder.activeEnergyBurned(on: day)
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
