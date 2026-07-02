import SwiftUI
import AdaptiveCore

/// Plays a multi-block routine's workout blocks in sequence, switching Apple workouts
/// automatically: each block runs the same active screen it would on its own (the adaptive-run
/// pager for a run block, the strength pager for a strength block) and, when it finishes, the next
/// block's workout begins. A brief "up next" launch masks the session handoff.
///
/// "Adaptive run" is the run block — it alternates running and walking by heart rate — and is
/// distinct from a future steady-walk workout; this view never confuses the two, it just sequences
/// whatever blocks the routine produced.
struct WorkoutSequenceView: View {
    let routineName: String
    let blocks: [WorkoutBlock]
    /// When true, blocks run against scripted backends (Simulator/UITest) and auto-start.
    var simulate = false
    /// The routine these blocks came from, so a strength block can persist its weight/rep bumps.
    /// `nil` under simulate (a scripted demo isn't a saved routine).
    var routineId: UUID?
    var recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?
    var recordRunProgression: (@MainActor (UUID, [RunProgressionUpdate]) -> Void)?
    /// Skip this view's own launch screen and start immediately — the crown picker already launched.
    var autostart = false
    /// Called from the done screen when launched by the picker, to return to it.
    var onExit: (() -> Void)?

    @State private var phase: Phase = .launch

    private enum Phase: Equatable { case launch, running(Int), done }

    var body: some View {
        switch phase {
        case .launch:
            SequenceLaunchView(name: routineName, blockCount: blocks.count) { phase = .running(0) }
                .task { if simulate || autostart { phase = .running(0) } }
        case let .running(i):
            blockView(blocks[i]) {
                phase = (i + 1 < blocks.count) ? .running(i + 1) : .done
            }
            .id(i) // fresh manager + session per block
        case .done:
            SequenceDoneView { if let onExit { onExit() } else { phase = .launch } }
        }
    }

    @ViewBuilder private func blockView(_ block: WorkoutBlock, onComplete: @escaping () -> Void) -> some View {
        switch block.kind {
        case .run:
            RunBlockView(card: block.cards.firstRunCard ?? RunCard(), simulate: simulate,
                         routineId: routineId, recordRunProgression: recordRunProgression,
                         onComplete: onComplete)
        case .strength:
            StrengthBlockView(cards: block.cards, simulate: simulate,
                              routineId: routineId, recordProgressions: recordProgressions,
                              onComplete: onComplete)
        }
    }
}

private extension Sequence where Element == WorkoutCard {
    var firstRunCard: RunCard? {
        for case let .run(c) in self { return c }
        return nil
    }
}

/// One run block inside a sequence: auto-starts an adaptive run and reuses the run pager, then
/// hands back when it finishes (each block is already its own saved Apple workout, so the sequence
/// shows the shared "done", not a per-block summary).
private struct RunBlockView: View {
    let card: RunCard
    let simulate: Bool
    let routineId: UUID?
    let recordRunProgression: (@MainActor (UUID, [RunProgressionUpdate]) -> Void)?
    let onComplete: () -> Void
    @State private var manager: WorkoutSessionManager

    init(card: RunCard, simulate: Bool, routineId: UUID?,
         recordRunProgression: (@MainActor (UUID, [RunProgressionUpdate]) -> Void)?,
         onComplete: @escaping () -> Void) {
        self.card = card
        self.simulate = simulate
        self.routineId = routineId
        self.recordRunProgression = recordRunProgression
        self.onComplete = onComplete
        _manager = State(initialValue: simulate
            ? WorkoutSessionManager(backend: SimulatedWorkoutBackend())
            : WorkoutSessionManager())
    }

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle: ProgressView().tint(WatchTheme.run)
            case .active: WorkoutSessionPager(manager: manager)
            case .complete: Color.clear.onAppear { recordOutcome(); onComplete() }
            case .failed: BlockFailedView()
            }
        }
        .task {
            guard manager.sessionState == .idle else { return }
            if simulate {
                // A short scripted run so a sequence plays through quickly.
                let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 4, walkDuration: 3, cycles: 1, cooldown: 2)
                manager.start(config: SessionConfig(plan: plan), routineName: "Run",
                              adaptationConfig: AdaptationConfig(backOffWindow: 3, minRunDuration: 2))
            } else {
                manager.start(config: SessionConfig(plan: IntervalPlan.plan(for: card)), routineName: "Run")
            }
        }
    }

    /// Persist the block's outcome as next time's seeds — same rule as the standalone run flow.
    /// Fires exactly once, on the `.complete` transition, before handing to the next block.
    private func recordOutcome() {
        guard !simulate,
              let record = recordRunProgression, let routineId,
              let summary = manager.summary else { return }
        let current = RunSeeds(runSeconds: card.runSeconds, walkSeconds: card.walkSeconds)
        let next = RunProgressionPolicy().nextSeeds(current: current, outcome: RunSessionOutcome(summary: summary))
        guard next != current else { return }
        record(routineId, [RunProgressionUpdate(cardId: card.id, runSeconds: next.runSeconds, walkSeconds: next.walkSeconds)])
    }
}

/// One strength block inside a sequence: auto-starts a strength workout and reuses the strength pager.
private struct StrengthBlockView: View {
    let cards: [WorkoutCard]
    let simulate: Bool
    let routineId: UUID?
    let recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?
    let onComplete: () -> Void
    @State private var manager: StrengthSessionManager

    init(cards: [WorkoutCard], simulate: Bool, routineId: UUID?,
         recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?,
         onComplete: @escaping () -> Void) {
        self.cards = cards
        self.simulate = simulate
        self.routineId = routineId
        self.recordProgressions = recordProgressions
        self.onComplete = onComplete
        _manager = State(initialValue: simulate
            ? StrengthSessionManager(backend: SimulatedStrengthBackend())
            : StrengthSessionManager())
    }

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle: ProgressView().tint(WatchTheme.strength)
            case .active: StrengthSessionPager(manager: manager)
            case .complete: Color.clear.onAppear(perform: onComplete)
            case .failed: BlockFailedView()
            }
        }
        .task {
            manager.onProgressions = recordProgressions
            if manager.sessionState == .idle {
                manager.start(cards: cards, routineId: routineId, routineName: "Strength")
            }
        }
    }
}

private struct BlockFailedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't start", systemImage: "exclamationmark.triangle")
        } description: {
            Text("That part of the workout couldn't start. Nothing was saved.")
        }
    }
}

/// Pre-session for a multi-block routine: name + how many workout parts, one Start.
private struct SequenceLaunchView: View {
    let name: String
    let blockCount: Int
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "figure.mixed.cardio")
                .font(.title3)
                .foregroundStyle(WatchTheme.run)
            VStack(spacing: 3) {
                Text("UP NEXT").font(.caption2).foregroundStyle(.secondary)
                Text(name).font(.title3.bold()).multilineTextAlignment(.center)
                Text("\(blockCount) workouts, back to back")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onStart) {
                Text("Start").font(.title3.bold()).frame(maxWidth: .infinity)
            }
            .tint(WatchTheme.run)
        }
        .padding(.horizontal, 4)
    }
}

private struct SequenceDoneView: View {
    let onDone: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(WatchTheme.run)
                    .symbolEffect(.bounce, options: .nonRepeating)
                Text("Done").font(.title3.bold())
                Text("Saved to Health")
                    .font(.caption2).foregroundStyle(WatchTheme.run)
                Text("Each part was saved as its own workout.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done", action: onDone).tint(WatchTheme.run).padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
    }
}
