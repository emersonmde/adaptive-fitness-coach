import SwiftUI
import AdaptiveCore

/// P1 — the hub, rebuilt dark/neon. Top to bottom: an "Up Next" hero (what's next), a
/// week-at-a-glance strip, then one card per routine (a routine owns its days, shown once —
/// no more day-section duplication). "New routine" is the focal lime CTA.
struct WeekView: View {
    let store: RoutineStore
    @State private var showingNewRoutine = false

    /// Planned length used by the hero estimate (the P0 session is the beginner run/walk seed).
    private var sessionDuration: TimeInterval { IntervalPlan.beginnerRunWalk().plannedDuration }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if store.routines.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Your Week")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewRoutine = true
                    } label: {
                        Label("New routine", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newRoutineToolbar")
                }
            }
            .sheet(isPresented: $showingNewRoutine) {
                NewRoutineView(store: store)
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(store: store, routineID: routine.id)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let next = store.nextOccurrence() {
                    NavigationLink(value: next.routine) {
                        UpNextCard(routine: next.routine, date: next.date, estimatedDuration: sessionDuration)
                    }
                    .buttonStyle(.plain)
                }

                WeekStrip(store: store)
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("ROUTINES")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)

                    ForEach(store.routines) { routine in
                        NavigationLink(value: routine) {
                            RoutineCard(routine: routine)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition { view, phase in
                            view.opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                        }
                    }
                }

                PrimaryButton(title: "New routine", systemImage: "plus") {
                    showingNewRoutine = true
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("No routines yet")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Build your week. Adaptive runs build themselves from your heart rate.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "New routine", systemImage: "plus") {
                showingNewRoutine = true
            }
            .accessibilityIdentifier("newRoutineEmptyState")
            .padding(.top, 4)
        }
        .padding(32)
    }
}
