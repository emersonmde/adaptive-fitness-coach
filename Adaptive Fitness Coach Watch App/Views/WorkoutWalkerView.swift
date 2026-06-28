import SwiftUI
import AdaptiveCore

/// Walks a mixed routine's workout blocks in sequence, switching Apple workouts automatically:
/// each block runs the same active screen it would on its own (the run pager for a run block, the
/// strength pager for a strength block) and, when it finishes, the next block's workout begins.
/// A single brief "up next" transition masks the session handoff so it reads as intentional.
struct WorkoutWalkerView: View {
    let routineName: String
    let blocks: [WorkoutBlock]

    @State private var phase: Phase = .launch

    private enum Phase: Equatable { case launch, running(Int), done }

    var body: some View {
        switch phase {
        case .launch:
            WalkerLaunchView(name: routineName, blockCount: blocks.count) { phase = .running(0) }
        case let .running(i):
            blockView(blocks[i]) {
                phase = (i + 1 < blocks.count) ? .running(i + 1) : .done
            }
            // Re-create the block view per index so each block gets a fresh manager + session.
            .id(i)
        case .done:
            WalkerDoneView { phase = .launch }
        }
    }

    @ViewBuilder private func blockView(_ block: WorkoutBlock, onComplete: @escaping () -> Void) -> some View {
        switch block.kind {
        case .run:
            let minutes = block.cards.firstRunDurationMinutes ?? 30
            RunBlockView(durationMinutes: minutes, onComplete: onComplete)
        case .strength:
            StrengthBlockView(cards: block.cards, onComplete: onComplete)
        }
    }
}

private extension Sequence where Element == WorkoutCard {
    var firstRunDurationMinutes: Int? {
        for case let .run(c) in self { return c.durationMinutes }
        return nil
    }
}

/// One run block inside a walk: auto-starts a real adaptive run and reuses the run pager, then
/// hands back to the walker when it finishes (the walker shows the shared "done", not a per-block
/// summary — each block is already its own saved Apple workout).
private struct RunBlockView: View {
    let durationMinutes: Int
    let onComplete: () -> Void
    @State private var manager = WorkoutSessionManager()

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle:
                ProgressView().tint(WatchTheme.run)
            case .active:
                WorkoutSessionPager(manager: manager)
            case .complete:
                Color.clear.onAppear(perform: onComplete)
            case .failed:
                BlockFailedView()
            }
        }
        .task {
            guard manager.sessionState == .idle else { return }
            let plan = IntervalPlan.beginnerRunWalk(totalDuration: TimeInterval(durationMinutes * 60))
            manager.start(config: SessionConfig(plan: plan), routineName: "Run")
        }
    }
}

/// One strength block inside a walk: auto-starts a strength workout and reuses the strength pager.
private struct StrengthBlockView: View {
    let cards: [WorkoutCard]
    let onComplete: () -> Void
    @State private var manager = StrengthSessionManager()

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle:
                ProgressView().tint(WatchTheme.strength)
            case .active:
                StrengthSessionPager(manager: manager)
            case .complete:
                Color.clear.onAppear(perform: onComplete)
            case .failed:
                BlockFailedView()
            }
        }
        .task {
            if manager.sessionState == .idle { manager.start(cards: cards, routineName: "Strength") }
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

/// Pre-session for a mixed routine: name + how many workout parts, one Start.
private struct WalkerLaunchView: View {
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

private struct WalkerDoneView: View {
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
