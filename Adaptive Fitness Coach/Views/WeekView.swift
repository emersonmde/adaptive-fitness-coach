import SwiftUI
import AdaptiveCore

/// P1 — the hub. The user's routines, grouped by the days they repeat. "New routine" is the
/// primary action. (The AI-draft shortcut from the design is deferred past P0.)
struct WeekView: View {
    let store: RoutineStore
    @State private var showingNewRoutine = false

    var body: some View {
        NavigationStack {
            Group {
                if store.routines.isEmpty {
                    emptyState
                } else {
                    routineList
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

    private var routineList: some View {
        List {
            ForEach(DayOfWeek.weekOrder, id: \.self) { day in
                let routines = store.routines(on: day)
                if !routines.isEmpty {
                    Section(day.fullName) {
                        ForEach(routines) { routine in
                            NavigationLink(value: routine) {
                                RoutineRow(routine: routine)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No routines yet", systemImage: "figure.run")
        } description: {
            Text("Create a routine to schedule your week. Adaptive runs build themselves from your heart rate.")
        } actions: {
            Button("New routine") { showingNewRoutine = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("newRoutineEmptyState")
        }
    }
}

/// A single routine summarized for the week list: icon, name, day badges.
struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        let tint = RoutineTheme.tint(for: routine.type)
        HStack(spacing: 12) {
            Image(systemName: RoutineTheme.symbol(for: routine.type))
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    if let time = routine.scheduleTime {
                        Text(time.formatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if routine.type == .adaptiveRun {
                        Text("Adaptive · HR-driven")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
