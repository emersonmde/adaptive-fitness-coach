import Foundation
import AdaptiveCore

/// Post-strength read-back (the strength analogue of `SessionSummary`). Acknowledgement, not a
/// log: the session is already a native Apple workout in Health (N1/N2). `progressionNotes`
/// is the one quietly-perceivable adaptation moment ("Goblet Squat → 25 lb").
struct StrengthSummary: Sendable, Hashable {
    var totalDuration: TimeInterval
    var exercisesCompleted: Int
    var setsCompleted: Int = 0
    var averageHeartRate: Double?
    var progressionNotes: [String] = []
}

/// Drives one **strength block** — a flat run of exercise and rest cards (already expanded by the
/// routine's rounds) — over the shared `WorkoutBackend`. Hybrid drive: sets are user-driven
/// ("Done set"), while rests and holds are ticked by the manager (P2 — rests are heart-rate
/// bounded via `RestRecoveryModel`, holds count down and record their actual duration). Every
/// set lands in a `StrengthSetRecord`; at finish the session outcome runs through
/// `StrengthProgressionPolicy` so prescriptions progress automatically (double progression,
/// ACSM 2009). Reuses the run side's `SessionState`, `WorkoutTotals`, and `HealthSaveState`.
///
/// Testability mirrors `WorkoutSessionManager`: inject a backend and `autoTick: false`, call
/// `begin`, then drive `tick(delta:)`/`receiveHeartRate(_:)`/`completeSet()` directly — no
/// clock, no HealthKit.
@MainActor
@Observable
final class StrengthSessionManager {
    /// What the current card is — drives which screen the view shows.
    enum Activity: Equatable { case exercise, rest }

    private(set) var sessionState: SessionState = .idle
    private(set) var routineName: String = "Strength"
    /// The routine being worked out, when this is a real (non-demo) session — the key any recorded
    /// weight/rep progression reports against. `nil` for the scripted demo (nothing to persist).
    private(set) var routineId: UUID?
    /// Latest heart rate (bpm), 0 until the first sample. Ambient, not a load signal (N3).
    private(set) var currentHeartRate: Double = 0
    private(set) var sessionStartDate: Date?
    private(set) var summary: StrengthSummary?
    /// Where HealthKit finalization stands after the session ends (same contract as the run
    /// side: never claim "Saved" before the OS confirms it, never freeze the UI waiting).
    private(set) var healthSaveState: HealthSaveState = .saving

    /// The block's cards (exercise/rest), with unknown-id exercise cards dropped (N6).
    private(set) var cards: [WorkoutCard] = []
    private var exerciseMeta: [Int: Exercise] = [:]   // resolved library entry per exercise card
    private(set) var currentIndex = 0
    /// Weight adjustments keyed by exercise id, so a change applies to every round of that move.
    private var weightOverrides: [String: Weight] = [:]
    /// Rep adjustments keyed by exercise id, mirroring `weightOverrides` (applies to every round).
    private var repsOverrides: [String: Int] = [:]

    // MARK: Set capture (P2)

    /// The reps about to be credited for the current set. Starts at the prescription each
    /// set; the Digital Crown adjusts it *before* "Done set" — hitting the prescription costs
    /// zero extra interactions, falling short is a couple of crown clicks.
    var repsPending: Int = 0
    /// Every completed set/hold, in order — the session's outcome raw material.
    private(set) var setLog: [StrengthSetRecord] = []
    /// Original card seeds per exercise id (pre-override), for progression comparison.
    private var originalSeeds: [String: StrengthPrescription] = [:]
    /// Peak heart rate during the current set — seeds the rest model's recovery math.
    private var setPeakHeartRate: Double?

    // MARK: Rest (manager-owned, heart-rate bounded)

    private var restModel: RestRecoveryModel?
    /// Remaining rest seconds (time-based readout; may shrink early on recovery).
    private(set) var restRemaining: TimeInterval = 0
    /// 0…1 recovery-ring progress (HR mode) or time progress (fallback).
    private(set) var restReadiness: Double = 0
    /// Latched when the rest ended recovered/expired — drives the READY moment.
    private(set) var restIsReady = false
    /// False → the view renders the plain countdown ring (fixed card or no HR — N6).
    private(set) var restUsesHeartRate = false
    /// Seconds since READY latched; auto-advances after `readyGraceSeconds`.
    private var readyGraceElapsed: TimeInterval = 0
    private let readyGraceSeconds: TimeInterval = 2

    // MARK: Hold (manager-owned)

    private(set) var holdRemaining: TimeInterval = 0
    private(set) var holdRunning = false
    private var holdPlanned: TimeInterval = 0

    // MARK: Ticking (run-manager pattern)

    private let autoTick: Bool
    private var tickTask: Task<Void, Never>?
    private var lastTickDate: Date?
    /// Cap on background catch-up per tick, mirroring the run manager.
    private let maxTickDelta: TimeInterval = 3

    /// Fired on finish with the routine's id and the progressions recorded this session (one per
    /// adjusted exercise). Empty/absent when nothing was changed or this is a demo. A closure so the
    /// manager stays free of WatchConnectivity/store (same purity discipline as the run manager).
    var onProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?

    private let injectedBackend: WorkoutBackend?
    private var backend: WorkoutBackend?
    /// Retained past `end()` so a post-summary effort rating can relate its score to the saved
    /// workout (build 9). Cleared on `reset()`.
    private var finishedBackend: WorkoutBackend?
    private let now: () -> Date
    private var isFinishing = false
    /// Guards `begin` across its suspension points (see `WorkoutSessionManager.isBeginning`).
    private var isBeginning = false
    /// Generation token for the background finalize (see `WorkoutSessionManager`).
    private var sessionGeneration = 0
    /// The in-flight background finalize — the deterministic test seam.
    private(set) var finalizeTask: Task<Void, Never>?

    private let haptics = HapticManager()

    init(backend: WorkoutBackend? = nil, now: @escaping () -> Date = Date.init, autoTick: Bool = true) {
        self.injectedBackend = backend
        self.now = now
        self.autoTick = autoTick
    }

    // MARK: - Derived state (the view reads these)

    var currentCard: WorkoutCard? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }

    var activity: Activity {
        if case .rest = currentCard { return .rest }
        return .exercise
    }

    var currentExercise: Exercise? { exerciseMeta[currentIndex] }

    /// The current exercise card's prescription, with any weight/rep overrides applied.
    var currentItem: StrengthExerciseItem? {
        guard case let .exercise(item) = currentCard else { return nil }
        var adjusted = item
        if let weight = weightOverrides[item.exerciseId] { adjusted.seedWeight = weight }
        if let reps = repsOverrides[item.exerciseId] { adjusted.reps = reps }
        return adjusted
    }

    var currentRestSeconds: TimeInterval? {
        if case let .rest(c) = currentCard { return c.seconds }
        return nil
    }

    /// 1-based set position for the *current exercise* (its card occurrences across rounds) —
    /// drives the set pips: real information, "set 2 of 3 of goblet squats".
    var currentExerciseSetPosition: (current: Int, total: Int) {
        guard case let .exercise(item) = currentCard else { return (0, 0) }
        var total = 0, current = 0
        for (index, card) in cards.enumerated() {
            guard case let .exercise(other) = card, other.exerciseId == item.exerciseId else { continue }
            total += 1
            if index <= currentIndex { current += 1 }
        }
        return (max(1, current), max(1, total))
    }

    /// 1-based position among **exercise** cards, and the total — the glance's "n of N".
    var exercisePosition: (current: Int, total: Int) {
        let total = cards.reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
        let done = cards.prefix(currentIndex).reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
        // While on an exercise card, count it as the current one.
        let current = min(done + (activity == .exercise ? 1 : 0), total)
        return (max(1, current), max(1, total))
    }

    // MARK: - Start

    func start(cards: [WorkoutCard], routineId: UUID? = nil, routineName: String) {
        guard sessionState == .idle else { return }
        Task { await begin(cards: cards, routineId: routineId, routineName: routineName) }
    }

    /// Resolve the block, start the backend, go active. A block with no coachable exercise fails
    /// rather than starting an empty workout (N6).
    func begin(cards: [WorkoutCard], routineId: UUID? = nil, routineName: String) async {
        guard sessionState == .idle, !isBeginning else { return }
        isBeginning = true
        defer { isBeginning = false }
        self.routineId = routineId
        self.routineName = routineName

        var resolved: [WorkoutCard] = []
        var meta: [Int: Exercise] = [:]
        for card in cards {
            switch card {
            case let .exercise(item):
                guard let ex = ExerciseLibrary.exercise(id: item.exerciseId) else { continue } // drop unknown (N6)
                meta[resolved.count] = ex
                resolved.append(card)
            case .rest:
                resolved.append(card)
            case .run:
                continue // a run never appears in a strength block
            }
        }
        guard meta.values.contains(where: { _ in true }) else {
            sessionState = .failed
            return
        }
        self.cards = resolved
        self.exerciseMeta = meta
        currentIndex = 0

        let backend = injectedBackend ?? HealthKitStrengthBackend()
        self.backend = backend
        backend.onHeartRate = { [weak self] hr in self?.receiveHeartRate(hr) }
        backend.onFailure = { [weak self] in self?.handleFailure() }

        do {
            try await backend.start()
        } catch {
            self.backend = nil
            sessionState = .failed
            return
        }

        // Original seeds per exercise — the pre-session baseline progression compares against.
        for card in resolved {
            if case let .exercise(item) = card, originalSeeds[item.exerciseId] == nil {
                originalSeeds[item.exerciseId] = StrengthPrescription(
                    reps: item.reps, weight: item.seedWeight, holdSeconds: item.holdSeconds
                )
            }
        }

        // Skip any leading rest cards — a block shouldn't open on a rest.
        while case .rest = currentCard { currentIndex += 1 }
        sessionStartDate = now()
        sessionState = .active
        didLandOnCard()
        lastTickDate = now()
        if autoTick { startTicking() }
    }

    // MARK: - Signal intake & ticking (test seams)

    /// Latest heart rate: display value plus per-set peak tracking (the rest model's anchor).
    func receiveHeartRate(_ hr: Double) {
        currentHeartRate = hr
        if activity == .exercise, sessionState == .active {
            setPeakHeartRate = max(setPeakHeartRate ?? hr, hr)
        }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.sessionState != .active { return }
                let nowDate = self.now()
                let elapsed = nowDate.timeIntervalSince(self.lastTickDate ?? nowDate)
                self.lastTickDate = nowDate
                self.tick(delta: min(elapsed, self.maxTickDelta))
            }
        }
    }

    /// Advance manager-owned time by `delta`: the rest model, the READY grace, and the hold
    /// countdown. Sets are user-paced and unaffected. Internal so tests drive it directly.
    func tick(delta: TimeInterval) {
        guard sessionState == .active, delta > 0 else { return }

        if activity == .rest {
            if restIsReady {
                readyGraceElapsed += delta
                if readyGraceElapsed >= readyGraceSeconds { advance() }
                return
            }
            guard var model = restModel else { return }
            let decision = model.tick(heartRate: restUsesHeartRate ? currentHeartRate : nil, deltaTime: delta)
            restModel = model
            restRemaining = model.remaining
            restReadiness = restUsesHeartRate ? (model.recoveryProgress ?? model.timeProgress) : model.timeProgress
            if case let .endRest(recovered) = decision {
                recordRestOutcome(recovered)
                restIsReady = true
                restReadiness = 1
                readyGraceElapsed = 0
                haptics.playRestReady()
            }
        } else if holdRunning {
            holdRemaining = max(0, holdRemaining - delta)
            if holdRemaining <= 0 {
                recordHold(completedSeconds: holdPlanned)
                holdRunning = false
                advance()
            }
        }
    }

    /// Reset per-card state when a new card becomes current: reps pending back to the
    /// prescription, peak HR fresh for the new set, rest model built for rest cards.
    private func didLandOnCard() {
        switch currentCard {
        case .exercise:
            repsPending = currentItem?.reps ?? 0
            setPeakHeartRate = currentHeartRate > 0 ? currentHeartRate : nil
            holdRunning = false
            holdRemaining = currentItem?.holdSeconds ?? 0
            holdPlanned = currentItem?.holdSeconds ?? 0
        case let .rest(rest):
            // Adaptive rests are heart-rate bounded around the authored seed; fixed rests
            // (card toggle off) and rests with no observed set peak run the plain timer (N6).
            let peak = rest.adaptive ? setPeakHeartRate : nil
            let model = RestRecoveryModel(seedDuration: rest.seconds, peakHeartRate: peak)
            restModel = model
            restUsesHeartRate = peak != nil
            restRemaining = model.remaining
            restReadiness = 0
            restIsReady = false
            readyGraceElapsed = 0
        default:
            break
        }
    }

    private func handleFailure() {
        guard sessionState == .active else { return }
        let failedBackend = backend
        backend = nil
        Task { _ = await failedBackend?.end() } // wind down whatever survives (fire-and-forget)
        sessionState = .failed
    }

    // MARK: - Progression (test seams)

    /// Adjust the current exercise's proposed weight by a delta in pounds (clamped at zero). A
    /// no-op on bodyweight/hold/rest cards. Applies to every round of the exercise (N7 seed).
    func adjustWeight(byPounds delta: Double) {
        guard sessionState == .active, case let .exercise(item) = currentCard,
              let weight = currentItem?.seedWeight ?? item.seedWeight else { return }
        // Grid-stepped: from a legacy off-grid load (22.5) the first tap snaps to the
        // adjacent multiple of 5 in the tapped direction (20 or 25), then steps in 5s.
        weightOverrides[item.exerciseId] = weight.stepped(byPounds: delta)
    }

    /// Adjust the current exercise's proposed reps by a delta (clamped at 1 — a set is ≥ 1 rep). A
    /// no-op on hold/rest cards (no rep count). Applies to every round of the exercise (N7 seed).
    func adjustReps(by delta: Int) {
        guard sessionState == .active, case let .exercise(item) = currentCard,
              let reps = currentItem?.reps ?? item.reps else { return }
        repsOverrides[item.exerciseId] = max(1, reps + delta)
    }

    /// The progressions recorded this session — one `ProgressionUpdate` per adjusted exercise,
    /// carrying whichever of weight/reps was changed (the other stays `nil` = "no change").
    /// Manual-only path, kept as the fallback when no sets were logged.
    func pendingProgressions(now: Date) -> [ProgressionUpdate] {
        let ids = Set(weightOverrides.keys).union(repsOverrides.keys)
        return ids.map { id in
            ProgressionUpdate(exerciseId: id, weight: weightOverrides[id], reps: repsOverrides[id], date: now)
        }
    }

    // MARK: - Set / rest / hold completion (P2)

    /// "Done set": credit `repsPending` (crown-adjusted; defaults to the prescription) into
    /// the set log and move on.
    func completeSet() {
        guard sessionState == .active, case let .exercise(item) = currentCard, !item.isHold else {
            advance()
            return
        }
        let adjusted = currentItem
        setLog.append(StrengthSetRecord(
            exerciseId: item.exerciseId,
            prescribedReps: adjusted?.reps,
            completedReps: max(0, repsPending),
            weight: adjusted?.seedWeight
        ))
        advance()
    }

    /// User skipped the rest. A skip says nothing about recovery — recorded as nil (N6).
    func skipRest() {
        guard sessionState == .active, activity == .rest else { return }
        recordRestOutcome(nil)
        advance()
    }

    func startHold() {
        guard sessionState == .active, currentItem?.isHold == true, !holdRunning else { return }
        holdPlanned = currentItem?.holdSeconds ?? 0
        holdRemaining = holdPlanned
        holdRunning = true
    }

    /// End the hold before the timer: the actual seconds held are what progression sees.
    func completeHoldEarly() {
        guard sessionState == .active, holdRunning else { return }
        recordHold(completedSeconds: max(0, holdPlanned - holdRemaining))
        holdRunning = false
        advance()
    }

    private func recordHold(completedSeconds: TimeInterval) {
        guard case let .exercise(item) = currentCard else { return }
        setLog.append(StrengthSetRecord(
            exerciseId: item.exerciseId,
            prescribedHoldSeconds: currentItem?.holdSeconds,
            completedHoldSeconds: completedSeconds
        ))
    }

    /// Attach how the rest ended to the set it followed (the last logged set).
    private func recordRestOutcome(_ recovered: Bool?) {
        guard let last = setLog.indices.last else { return }
        setLog[last].restRecovered = recovered
    }

    /// Advance to the next card. "Done set"/rest completion route through their recording
    /// wrappers; calling this directly is a skip (nothing recorded). Plays a haptic for the
    /// kind of thing coming next.
    func advance() {
        guard sessionState == .active else { return }
        currentIndex += 1
        if currentIndex >= cards.count {
            finish()
            return
        }
        didLandOnCard()
        switch currentCard {
        case .rest: haptics.playSetComplete()
        default: haptics.playExerciseChange()
        }
    }

    // MARK: - End

    func finish() {
        guard sessionState == .active, !isFinishing else { return }
        isFinishing = true
        Task { await end() }
    }

    func endManually() { finish() }

    /// Complete immediately from local state; HealthKit finalizes in the background and the
    /// average HR fills in when it returns (same instant-end contract as the run manager —
    /// never freeze the UI on OS bookkeeping).
    private func end() async {
        tickTask?.cancel()
        tickTask = nil
        let duration = sessionStartDate.map { now().timeIntervalSince($0) } ?? 0
        let exercisesDone = min(currentIndex, cards.count).reduceExerciseCount(in: cards)

        // Progression is NOT computed/emitted here — it's deferred to `finalizeProgression`
        // on Done so the effort rating can actually gate it. (Emitting an advance here and a
        // "hold" later can't retract the advance, since a hold produces no update — build 9.)
        // The complete screen previews notes live via `previewNotes(effort:)`.
        summary = StrengthSummary(
            totalDuration: duration,
            exercisesCompleted: exercisesDone,
            setsCompleted: setLog.count,
            averageHeartRate: nil,
            progressionNotes: []
        )

        healthSaveState = .saving
        sessionState = .complete
        haptics.playComplete()

        let finishingBackend = backend
        let generation = sessionGeneration
        backend = nil
        finishedBackend = finishingBackend   // survives for the effort rating
        finalizeTask = Task { [weak self] in
            let totals = await finishingBackend?.end() ?? WorkoutTotals()
            guard let self, self.sessionGeneration == generation, self.sessionState == .complete else { return }
            if var filled = self.summary {
                filled.averageHeartRate = totals.averageHeartRate
                self.summary = filled
            }
            self.healthSaveState = totals.savedToHealth ? .saved : .unconfirmed
        }
    }

    /// Run every logged exercise through the progression policy and produce both the sync
    /// updates and the summary's "next time" notes. When nothing was logged (a bailed or
    /// legacy-style session) manual overrides still persist via the fallback path.
    /// Compute progression with the user's effort rating, emit it (the session's *only*
    /// emission — deferred from `end()` so the rating gates it), refresh the summary notes,
    /// and write the effort score to Health (build 9). Called from the complete screen on
    /// Done (rate or skip → nil effort).
    func finalizeProgression(perceivedEffort: Int?) async {
        let (progressions, notes) = computeProgressions(perceivedEffort: perceivedEffort)
        if var filled = summary { filled.progressionNotes = notes; summary = filled }
        if let routineId, !progressions.isEmpty {
            onProgressions?(routineId, progressions)
        }
        if let perceivedEffort {
            await finalizeTask?.value   // the workout must be finalized before relating a score
            await finishedBackend?.writeEffortScore(perceivedEffort)
        }
    }

    /// The "next time" notes a given effort rating would produce — for the live preview on the
    /// complete screen (pure; no emit).
    func previewNotes(perceivedEffort: Int?) -> [String] {
        computeProgressions(perceivedEffort: perceivedEffort).notes
    }

    private func computeProgressions(perceivedEffort: Int?) -> (updates: [ProgressionUpdate], notes: [String]) {
        guard !setLog.isEmpty else { return (pendingProgressions(now: now()), []) }

        // Manual-change signals derive from overrides vs the original card seeds.
        var lowered = Set<String>(), raised = Set<String>(), repsChanged = Set<String>()
        for (id, weight) in weightOverrides {
            guard let seedWeight = originalSeeds[id]?.weight else { continue }
            if weight.pounds < seedWeight.pounds { lowered.insert(id) }
            if weight.pounds > seedWeight.pounds { raised.insert(id) }
        }
        for (id, reps) in repsOverrides where originalSeeds[id]?.reps != reps {
            repsChanged.insert(id)
        }

        var plannedSets: [String: Int] = [:]
        for card in cards {
            if case let .exercise(item) = card { plannedSets[item.exerciseId, default: 0] += 1 }
        }
        let endedEarly = currentIndex < cards.count
        let outcome = StrengthSessionOutcome(
            setLog: setLog,
            plannedSetsByExercise: plannedSets,
            loweredWeight: lowered,
            raisedWeight: raised,
            changedReps: repsChanged,
            endedEarly: endedEarly,
            perceivedEffort: perceivedEffort
        )

        let policy = StrengthProgressionPolicy()
        var updates: [ProgressionUpdate] = []
        var notes: [String] = []
        let stamp = now()
        for exerciseOutcome in outcome.exercises {
            let id = exerciseOutcome.exerciseId
            guard let exercise = ExerciseLibrary.exercise(id: id),
                  let seed = originalSeeds[id] else { continue }
            // Base = seed with this session's manual overrides folded in (manual wins).
            var base = seed
            if let weight = weightOverrides[id] { base.weight = weight }
            if let reps = repsOverrides[id] { base.reps = reps }

            let next = policy.nextPrescription(current: base, exercise: exercise,
                                               outcome: exerciseOutcome, endedEarly: endedEarly,
                                               perceivedEffort: perceivedEffort)
            guard next != seed else { continue }
            updates.append(ProgressionUpdate(
                exerciseId: id,
                weight: next.weight != seed.weight ? next.weight : nil,
                reps: next.reps != seed.reps ? next.reps : nil,
                holdSeconds: next.holdSeconds != seed.holdSeconds ? next.holdSeconds : nil,
                date: stamp
            ))
            if let note = StrengthPrescription.progressionNote(exerciseName: exercise.name, from: seed, to: next) {
                notes.append(note)
            }
        }
        return (updates, notes)
    }

    func reset() {
        sessionGeneration += 1
        finalizeTask = nil
        healthSaveState = .saving
        isFinishing = false
        tickTask?.cancel(); tickTask = nil
        lastTickDate = nil
        backend = nil
        finishedBackend = nil
        cards = []
        exerciseMeta = [:]
        weightOverrides = [:]
        repsOverrides = [:]
        routineId = nil
        currentIndex = 0
        currentHeartRate = 0
        summary = nil
        sessionStartDate = nil
        repsPending = 0
        setLog = []
        originalSeeds = [:]
        setPeakHeartRate = nil
        restModel = nil
        restRemaining = 0
        restReadiness = 0
        restIsReady = false
        restUsesHeartRate = false
        readyGraceElapsed = 0
        holdRemaining = 0
        holdRunning = false
        holdPlanned = 0
        sessionState = .idle
    }
}

private extension Int {
    /// Count exercise cards in the first `self` cards — exercises completed at end.
    func reduceExerciseCount(in cards: [WorkoutCard]) -> Int {
        cards.prefix(self).reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
    }
}
