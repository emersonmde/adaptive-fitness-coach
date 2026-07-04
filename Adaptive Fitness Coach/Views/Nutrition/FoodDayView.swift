import SwiftUI
import AdaptiveCore

/// The Food day screen (build 8) — pushed from the hub's daily line. One day at a time:
/// pager → gauge (the dominant element) → quiet active-energy line → meal sections →
/// add affordances. Trends stay in Apple Health (linked); this screen is a day, not a
/// dashboard (C6).
struct FoodDayView: View {
    @Bindable var controller: MealLogController
    let recorder: any NutritionRecorder
    @Bindable var targetStore: CalorieTargetStore
    let bodyProfileSource: any BodyProfileSource
    let onScan: () -> Void
    let onType: () -> Void

    @State private var anchorDay = Calendar.current.startOfDay(for: Date())
    @State private var intake = DailyIntake()
    @State private var activeKcal: Double?
    @State private var editingEntry: MealEntry?
    @State private var showingTargetSheet = false
    @State private var reloggedID: UUID?
    @State private var deleteError: String?
    @State private var refreshTick = 0

    private var calendar: Calendar { .current }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    dayPager
                    gaugeSlot
                    activeEnergyLine
                    mealSections
                    addButtons
                }
                .padding(16)
            }
        }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshTick) { await refresh() }   // appear + every bump (one fetch, not two)
        .onChange(of: anchorDay) { refreshTick += 1 }
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
        .sheet(isPresented: $showingTargetSheet) {
            TargetSetupSheet(targetStore: targetStore, bodyProfileSource: bodyProfileSource)
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(entry: entry, recorder: recorder) { refreshTick += 1 }
        }
    }

    // MARK: - Pager

    private var isToday: Bool { calendar.isDateInToday(anchorDay) }

    private var dayPager: some View {
        HStack {
            Button {
                anchorDay = calendar.date(byAdding: .day, value: -1, to: anchorDay) ?? anchorDay
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityIdentifier("meal.day.prev")

            Spacer()
            Text(dayTitle)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("meal.day.title")
            Spacer()

            // Reserved slot: disabled-at-today, never removed (principle 7).
            Button {
                anchorDay = min(
                    calendar.date(byAdding: .day, value: 1, to: anchorDay) ?? anchorDay,
                    calendar.startOfDay(for: Date())
                )
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
        if isToday { return "Today" }
        if calendar.isDateInYesterday(anchorDay) { return "Yesterday" }
        return anchorDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Gauge (fixed-height slot with or without a target)

    private var gaugeSlot: some View {
        VStack(spacing: 8) {
            if let budget = targetStore.budget(consumedKcal: intake.totalKcal) {
                CalorieGaugeView(budget: budget)
                Button {
                    showingTargetSheet = true
                } label: {
                    Text("Target \(budget.targetKcal.formatted()) kcal")
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
                    Button("Set a daily target") { showingTargetSheet = true }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("meal.day.setTarget")
                }
            }
        }
        .frame(height: 208)   // same slot either way — no jump when a target appears
    }

    // MARK: - Active energy (informational, never budget)

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
            if let url = URL(string: "x-apple-health://") {
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

    // MARK: - Meal sections

    private var mealSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MealSlot.dayOrder, id: \.self) { slot in
                let entries = intake.entries.filter { $0.meal == slot }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slot.displayName.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 4)
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
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
    }

    private var otherAppsKcal: Double {
        let ours = intake.entries.reduce(0) { $0 + $1.facts.energy.midpointKcal * Double($1.quantity) }
        return max(0, intake.totalKcal - ours)
    }

    private func entryRow(_ entry: MealEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.quantity > 1 ? "\(entry.name) ×\(entry.quantity)" : entry.name)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(entry.provenance.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("meal.day.entry.\(entry.name)")
        .contextMenu {
            Button {
                Task { await logAgain(entry) }
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
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

    private func logAgain(_ entry: MealEntry) async {
        let fresh = entry.relogged()
        if (try? await recorder.record(fresh)) != nil {
            reloggedID = fresh.id   // badge exactly the new entry, not every same-named row
            anchorDay = calendar.startOfDay(for: Date())   // the new entry lives today
            refreshTick += 1
        }
    }

    // MARK: - Add affordances

    private var addButtons: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Scan a meal", systemImage: "camera.viewfinder", action: onScan)
                .accessibilityIdentifier("meal.day.scan")
            Button(action: onType) {
                Label("Type it instead", systemImage: "keyboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("meal.day.type")
        }
        .padding(.top, 6)
    }

    private func refresh() async {
        if let fresh = try? await recorder.intake(on: anchorDay) {
            intake = fresh
        }
        activeKcal = try? await recorder.activeEnergyBurned(on: anchorDay)
    }
}
