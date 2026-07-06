import Foundation

/// The phone-side landing point for inbound progression batches (P6) — the one place that
/// composes the three stores: micro-steps apply to `RoutineStore` (as always), every applied
/// change is journaled with its why, and structural proposals are stashed for the confirm
/// card. Package-level so the whole flow runs under `swift test`; the phone's
/// `PhoneConnectivityManager` is a thin caller.
@MainActor
public enum ProgressionIntake {
    /// Handle a received batch: apply the micro lane, journal it, stash the proposal lane.
    /// No-op (and nothing stashed) when the routine is unknown — a proposal against a deleted
    /// routine could never be applied.
    public static func receive(
        _ batch: ProgressionBatch,
        store: RoutineStore,
        journal: ProgressionJournal,
        proposals proposalStore: ProgressionProposalStore,
        library: [Exercise] = ExerciseLibrary.all
    ) {
        guard let routine = store.routines.first(where: { $0.id == batch.routineId }) else { return }

        let applied = store.applyProgressions(batch, broadcast: true)
        if applied {
            journal.append(entries(
                for: batch.updates, runUpdates: batch.runUpdates, kind: .micro,
                routine: routine, effort: batch.perceivedEffort, library: library
            ))
        }

        proposalStore.add(
            batch.proposals.map {
                PendingStructuralProposal(
                    routineId: batch.routineId, date: $0.date,
                    update: $0, perceivedEffort: batch.perceivedEffort
                )
            } +
            batch.runProposals.map {
                PendingStructuralProposal(
                    routineId: batch.routineId, date: $0.date,
                    runUpdate: $0, perceivedEffort: batch.perceivedEffort
                )
            }
        )
    }

    /// Confirm a structural proposal: apply it through the store (which re-broadcasts the new
    /// seed to the watch) and journal the confirmed step. Double-tap safe.
    public static func confirm(
        _ id: PendingStructuralProposal.ID,
        store: RoutineStore,
        journal: ProgressionJournal,
        proposals proposalStore: ProgressionProposalStore,
        library: [Exercise] = ExerciseLibrary.all
    ) {
        guard let proposal = proposalStore.proposals.first(where: { $0.id == id }),
              let routine = store.routines.first(where: { $0.id == proposal.routineId }),
              let batch = proposalStore.confirm(id: id) else { return }
        guard store.applyProgressions(batch, broadcast: true) else { return }
        journal.append(entries(
            for: batch.updates, runUpdates: batch.runUpdates, kind: .confirmed,
            routine: routine, effort: proposal.perceivedEffort, library: library
        ))
    }

    /// Decline a structural proposal: the seed stays where it was (hold), journaled honestly.
    public static func decline(
        _ id: PendingStructuralProposal.ID,
        store: RoutineStore,
        journal: ProgressionJournal,
        proposals proposalStore: ProgressionProposalStore,
        library: [Exercise] = ExerciseLibrary.all
    ) {
        guard let proposal = proposalStore.decline(id: id),
              let routine = store.routines.first(where: { $0.id == proposal.routineId }) else { return }
        journal.append(entries(
            for: proposal.update.map { [$0] } ?? [],
            runUpdates: proposal.runUpdate.map { [$0] } ?? [],
            kind: .declined,
            routine: routine, effort: proposal.perceivedEffort, library: library
        ))
    }

    // MARK: - Rendering

    /// What the confirm card shows for one pending proposal — subject ("Goblet Squat"),
    /// the old → new change, and the policy's reason. Falls back gracefully when the
    /// routine has since been deleted.
    public static func display(
        for proposal: PendingStructuralProposal,
        store: RoutineStore,
        library: [Exercise] = ExerciseLibrary.all
    ) -> (routineName: String, subject: String, changeText: String, reason: String?) {
        let routine = store.routines.first { $0.id == proposal.routineId }
        if let update = proposal.update {
            let subject = library.first { $0.id == update.exerciseId }?.name ?? update.exerciseId
            let change = routine.map { changeText(for: update, in: $0) }
                ?? "→ \(update.weight?.displayString() ?? "\(update.reps ?? 0) reps")"
            return (routine?.name ?? "Removed routine", subject, change, update.reason)
        }
        if let runUpdate = proposal.runUpdate {
            let change = routine.map { changeText(for: runUpdate, in: $0) }
                ?? "→ \(shortTime(runUpdate.runSeconds)) run · \(shortTime(runUpdate.walkSeconds)) walk"
            return (routine?.name ?? "Removed routine", "Run intervals", change, runUpdate.reason)
        }
        return (routine?.name ?? "Removed routine", "Progression", "", nil)
    }

    /// Journal rows for a batch slice, with old → new change text read from the routine
    /// *before* the slice is applied (caller order matters for `.micro`/`.confirmed`).
    static func entries(
        for updates: [ProgressionUpdate],
        runUpdates: [RunProgressionUpdate],
        kind: ProgressionJournalEntry.Kind,
        routine: Routine,
        effort: Int?,
        library: [Exercise]
    ) -> [ProgressionJournalEntry] {
        let strength = updates.map { update in
            ProgressionJournalEntry(
                date: update.date,
                routineId: routine.id,
                routineName: routine.name,
                subject: library.first { $0.id == update.exerciseId }?.name ?? update.exerciseId,
                changeText: changeText(for: update, in: routine),
                reason: update.reason,
                kind: kind,
                perceivedEffort: effort
            )
        }
        let run = runUpdates.map { update in
            ProgressionJournalEntry(
                date: update.date,
                routineId: routine.id,
                routineName: routine.name,
                subject: "Run intervals",
                changeText: changeText(for: update, in: routine),
                reason: update.reason,
                kind: kind,
                perceivedEffort: effort
            )
        }
        return strength + run
    }

    /// "12 → 13 reps", "20 → 25 lb · reps reset to 8", "45 → 50s hold" — old values read from
    /// the routine's first card for the exercise (the one-move-one-seed rule).
    static func changeText(for update: ProgressionUpdate, in routine: Routine) -> String {
        let old = routine.cards.compactMap(\.exercise).first { $0.exerciseId == update.exerciseId }
        var parts: [String] = []
        if let weight = update.weight {
            if let oldWeight = old?.seedWeight, oldWeight != weight {
                parts.append("\(oldWeight.displayString()) → \(weight.displayString())")
            } else {
                parts.append("→ \(weight.displayString())")
            }
            if let reps = update.reps, let oldReps = old?.reps, reps < oldReps {
                parts.append("reps reset to \(reps)")
            } else if let reps = update.reps {
                parts.append("\(reps) reps")
            }
        } else if let reps = update.reps {
            if let oldReps = old?.reps, oldReps != reps {
                parts.append("\(oldReps) → \(reps) reps")
            } else {
                parts.append("→ \(reps) reps")
            }
        }
        if let hold = update.holdSeconds {
            if let oldHold = old?.holdSeconds, oldHold != hold {
                parts.append("\(Int(oldHold)) → \(Int(hold))s hold")
            } else {
                parts.append("→ \(Int(hold))s hold")
            }
        }
        return parts.isEmpty ? "no change" : parts.joined(separator: " · ")
    }

    /// "2:00 → 2:30 run · 1:45 walk", or "→ continuous" once the seed covers the block.
    static func changeText(for update: RunProgressionUpdate, in routine: Routine) -> String {
        let old: RunCard? = routine.cards.compactMap { card in
            if case let .run(runCard) = card, runCard.id == update.cardId { return runCard }
            return nil
        }.first

        if let block = update.blockSeconds, update.runSeconds >= block || update.walkSeconds <= 0 {
            return "→ continuous"
        }
        let new = "\(shortTime(update.runSeconds)) run · \(shortTime(update.walkSeconds)) walk"
        guard let old else { return "→ \(new)" }
        return "\(shortTime(old.runSeconds)) → \(new)"
    }

    private static func shortTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
