# The Adaptive System — how run & strength adaptation work

The design reference for the app's adaptive machinery: the in-session run engine, the
strength progression engine, and the plumbing that carries their results between watch,
phone, and Apple Health. Read this before changing anything under `AdaptiveCore/Engine/`,
the session managers, or the progression sync path.

**How to keep this doc current (drift policy).** This doc anchors on *type names,
constant identifiers, invariants, and contracts* — never line numbers or code quotes.
The durable truth here is the *relationships* (e.g. "the back-off window is shorter than
the extend window"; "structural moves are proposed, never auto-applied"). Numeric
defaults appear in tables explicitly marked as snapshots — when tuning a constant, update
its table cell and nothing else; when adding/removing a mechanism, update its section.
Everything named here is greppable; if a grep for an identifier fails, the doc has
drifted and the code wins.

---

## 1. The shape of the system

**All intelligence is a pure, clock-free value type in the `AdaptiveCore` package**
(Foundation only — no HealthKit, no SwiftUI, no `Date.now`). The device apps are thin
shells that own clocks, sensors, haptics, and OS persistence, and drive the pure core
with `deltaTime` + signal values. This is what makes ~all adaptive behavior unit-testable
on macOS with `swift test` and demoable in the simulator via scripted backends.

Both run and strength follow the same **three-layer pattern**:

1. **In-session engine** (pure struct, ticked): reacts to live signals second-by-second.
   Run: `IntervalStateMachine` + `AdaptationPolicy`. Strength: `RestRecoveryModel`
   (rests are the only live-adapted strength element; sets are user-paced).
2. **Session summary → outcome**: the engine's counters fold into a summary
   (`SessionSummary` / the strength set log), which becomes an outcome value
   (`RunSessionOutcome` / `StrengthSessionOutcome`).
3. **Cross-session progression policy** (pure, evaluated once at session end):
   turns the outcome into next session's seeds. Run: `RunProgressionPolicy`.
   Strength: `StrengthProgressionPolicy`. Both return an `Evaluation` carrying the next
   prescription, a `Decision`, a `ProgressionReason` (the journal's "why"), and a
   structural flag.

**The governing biases** (from the PRD non-negotiables, enforced structurally):

- **Bias toward backing off** (N7): every asymmetry errs toward easier. Advancing needs
  a *fully clean* session; easing needs *clear struggle evidence*; anything ambiguous
  holds. Suspicion signals (high effort, unrecovered rests) can only block an advance —
  they never manufacture an ease.
- **Never fabricate a signal** (N6): a missing signal means "don't adapt", never a
  default value. Enforced per-field: nil zone → run holds plan; nil HR → walk/rest holds
  its timer; `restRecovered: nil` is not evidence; skipped segments earn no credit.
- **The OS is the record** (N2): run history persists as `RunDigest` metadata *on the
  saved HKWorkout* — no private history store. Effort writes the real
  `HKWorkoutEffortScore`.
- **Structural vs micro** (P6): micro seed moves (±1 rep, run-length steps, easing)
  apply automatically; *structural* moves (band-topped load step, walk shrink,
  continuous-run graduation) are **proposed** and wait for phone confirmation. Backing
  off is never structural by construction — easing is never gated behind a confirm.

---

## 2. Run adaptation

### 2.1 Plan model

`IntervalPlan` (Models/) is an ordered list of `IntervalSegment`s, each an
`IntervalPhase` (`warmupWalk` / `run` / `walk` / `cooldownWalk`) with a target duration.
Only `.run` and `.walk` are ever adapted; warmup/cooldown always run their seed duration.

`IntervalPlan.plan(for: RunCard)` → `runWalk(...)` builds the session: optional warmup,
a block of whole run/walk cycles sized to land near the card's block duration, optional
cooldown. Exactness doesn't matter — the engine adapts every segment live (N7).
**Continuous graduation:** when the run seed reaches/exceeds the block (or walk seed
≤ 0), the block collapses to a single continuous run **capped at the block duration,
never the raw seed** — a large calibration sentinel seed must not produce an
uncompletable segment that reads as a bail.

`RunCard` carries the persisted seeds (`runSeconds`/`walkSeconds` as `RunSeeds`) plus
the block shape (warmup/duration/cooldown minutes) and the one-shot `seedsCalibrated`
flag. `RunSeeds.factoryDefault` is the **single source of truth** for the untouched
default — `RunCard` defaults, decode fallbacks, `needsCalibration`, and
`FitnessCalibration` all reference it; drift here silently breaks calibration gating.

### 2.2 `IntervalStateMachine` — the per-session driver

A pure `Sendable` struct. Owns a **working copy** of the plan's segments, so live
adaptation never mutates the seed plan. Driven by `tick(deltaTime:sample:)` where
`WorkoutSample{zone, heartRate}` fields degrade independently (either may be nil).
A convenience `tick(deltaTime:currentZone:)` wraps it. Non-positive deltas are inert;
ticks after completion are inert.

Per tick, in order: advance clocks → accrue phase totals (`timeInTargetZone` accrues
only on run ticks whose fresh zone *equals* the target) → observe HR (peak tracking +
recovery sampling) → consult the policy (`adapt`) → otherwise natural transition when
the segment's target elapses.

**Output:** `TickResult{transition?, adaptation?, isComplete}`. A single tick can carry
both a transition and an adaptation (a shortened run ends *and* switches to walk).
`TransitionEvent{from,to}` drives haptics; `AdaptationEvent{action, atSessionTime, zone,
message}` drives the calm UI cue. Actions: `shortenedRun`, `extendedRun`,
`lengthenedWalk`, `shortenedWalk`; `increasesEffort` marks the higher-risk directions.
**Banner-once invariant:** stretch-type adaptations (extend/lengthen) announce at most
once per segment (`announcedThisSegment`); later qualifying ticks keep stretching
silently.

**Counters** (feed summary → outcome → progression): `intervalsCompleted` (run segments
*reached* — a cut-short run still counts; struggle is the separate `runBackOffCount`),
`walksCompleted` (natural recovery walks only), `runBackOffCount`, `walksHitCap`,
`fastRecoveries`, `recoveryDrops`/`meanRecoveryDrop`, `longestRunInterval`,
`timeInTargetZone`, plus phase totals.

**Recovery sampling:** during a run the machine tracks `peakRunHeartRate`; during a walk
it records `max(0, peak − lastHR)` into `recoveryDrops` at the fixed 60s HRR mark
(`recoverySampleTime` — the clinical one-minute HRR construct, Cole et al. NEJM 1999;
deliberately *not* a tunable, and separate from the walk-shortening decision). The
record is gated on having actually seen HR *during this walk* — a stale pre-walk reading
across a sensor gap can never fabricate a drop.

**`skipCurrentSegment()`** (used by the cadence warmup skip and the manual "Start Run"
pill) emits the same `TickResult` shape as a natural transition — the caller's
haptic/UI path is identical — but the skipped segment earns no interval/walk credit and
records no recovery (nothing was demonstrated, N6).

**`currentRunIsExtended`** marks a run segment that has been stretched by the policy —
the shell uses it so manually ending during an extended run reads as "finished a long
run", not a bail (the same rule applies to ending during any cooldown — every planned
run is behind the user by then).

**Future-segment convergence (in-session).** Adaptation events also retarget the
*upcoming* segments of the working plan so the countdown turns truthful within an
interval or two — the seed stops lying once the body has demonstrated what it can do:

- **Downward, one jump, immediate**: a back-off retargets all future runs to the
  demonstrated length (elapsed at the back-off, rounded *down* to `convergenceRounding`,
  floored at `minRunDuration`); a recovery-shortened walk retargets future walks to the
  observed duration (rounded *up* — longer walks are the safe direction, floored at
  `minWalkDuration`).
- **Upward, slew-limited, on completed demonstration only**: a policy-extended run that
  completes *naturally* raises future runs by at most min(+25%,
  `maxUpwardConvergenceStep`) per event, with the step quantized to the grid so targets
  never land off it — single-session load spikes are the injury driver, so upward never
  jumps; a walk that rode to the cap unrecovered raises future walks to the cap in one
  jump (easing) — **unless the walk was defied** (`markCurrentWalkDefied()`, called by
  the shell when the compliance monitor accepts): a run-through walk's cap-ride is a
  choice, never recovery evidence.
- **Silent**: convergence emits no `AdaptationEvent` — the current-segment events already
  announced the felt change; retargeting only fixes the upcoming countdowns.
  Down-after-up always wins (min rules); skipped segments demonstrate nothing and
  converge nothing; warmup/cooldown are never retargeted.
- `convergedRunSeconds` / `convergedWalkSeconds` record the settled values — the *only*
  honest input for the cross-session converged path (never derived from averages, N6).
  A demonstration on the session's **final** segment records only downward: an upward
  record with no future segment to slew-limit against would bypass the injury cap (the
  long run is already captured by `longestRunInterval` for the snap path).

**Cooldown backfill.** The machine captures the planned total at init; on entering the
cooldown it extends the cooldown target by the adaptation-driven shortfall, capped at
min(authored + 10 min, authored × 2) — a planned 30-minute session still delivers ~30
minutes of volume, filled with easy walking (safe) rather than more running (the wrong
direction on a back-off day). Time the user *skipped* is subtracted from the backfill
budget — a skip is a choice, and the cooldown never re-adds it (same philosophy as
`walksDefied`). `backfilledCooldownSeconds` records the planned extension;
`deliveredCooldownBackfill` clamps it to what was actually walked (an end mid-cooldown
never claims undelivered volume, N6) and is what reaches the summary — the complete
screen explains it when it exceeds a minute. It is deliberately *not* in `RunDigest`.

The engine also tracks `timeAboveTargetZone` (run ticks, fresh zone only — mirrors
`timeInTargetZone`) for the effort suggestion (§3.4).

### 2.3 `AdaptationPolicy` — leaky-integrator hysteresis

Four sustained-time accumulators (`timeAboveTarget`, `timeAtOrBelowTarget`,
`timeFarAboveTarget`, `timeRecovered`), all advanced by one rule: the active side
**accrues** `deltaTime`, the opposite side **decays** by `deltaTime` floored at zero —
never a hard reset. A brief zone blip costs a couple of seconds off a nearly-full
window instead of wiping it; a genuinely sustained excursion still drains the opposite
side. `resetAccumulators()` runs at every segment boundary.

**Run decisions** (`RunDecision`: `keepGoing` / `shorten` / `extend`), in priority order:

1. **Hard ceiling** (redline fast path): sustained *far* above target
   (≥ `hardBackOffZoneDelta` zones over) for `hardBackOffWindow`, after
   `hardBackOffMinRun` → shorten.
2. **Standard back-off**: sustained above target for `backOffWindow`, after
   `minRunDuration` → shorten.
3. **Extend**: only if extension is enabled (`allowRunExtension`, **off by default** —
   HR lag reads as false comfort in deconditioned runners) *or* unlocked in-session by
   demonstrated recovery (`extensionUnlocked`, see below); only *at/after the planned
   end*; and only after sustained comfort for `extendWindow`. Each qualifying tick then
   grows the segment by `runExtendIncrement`.

**Walk decisions** (`WalkDecision`: `keepGoing` / `lengthen` / `shorten`). Recovery is
`Bool?`: HRR drop ≥ `recoveryDropBPM` from the run's peak, *or* zone below target; nil
when no signal exists (→ fixed-interval fallback; a signal gap also *leaks* accumulated
recovery credit so pre-gap credit can't end the walk on one post-gap tick). Shorten
(raises effort) needs sustained recovery for `recoverWindow` *and* the `minWalkDuration`
floor; lengthen (conservative) fires immediately at the planned end when not recovered,
up to `maxWalkDuration` — at the cap the walk ends anyway (never trap the user) and
`walksHitCap` records the struggle.

**The in-session evidence gate:** the state machine passes
`extensionUnlocked: fastRecoveries > 0`. A `fastRecovery` is a walk that ended at the
recovery floor (shortened as early as the rules allow) — demonstrated recovery, not
comfort, is what unlocks run extension for the rest of the session. This lets a
mis-seeded fit runner converge toward continuous running within one session while a
struggling one never extends.

**`AdaptationConfig` defaults** *(snapshot — verify in code when tuning)*:

| Identifier | Default | Role |
|---|---|---|
| `backOffWindow` | 20 s | sustained-above → shorten run |
| `hardBackOffWindow` | 8 s | far-above redline fast path |
| `hardBackOffZoneDelta` | 2 | zones over target = "far above" |
| `hardBackOffMinRun` | 15 s | run floor before hard ceiling |
| `allowRunExtension` | false | global extension gate |
| `extendWindow` | 45 s | sustained-comfort → extend |
| `runExtendIncrement` | 30 s | growth per qualifying tick |
| `recoverWindow` | 10 s | sustained-recovered → shorten walk |
| `recoveryDropBPM` | 20 | HRR drop = recovered (Cole et al.) |
| `minRunDuration` | 20 s | run floor before back-off |
| `minWalkDuration` | 60 s | walk floor before shorten |
| `walkLengthenIncrement` | 15 s | growth per lengthen |
| `maxWalkDuration` | 300 s | live walk cap |
| `convergenceRounding` | 15 s | future-segment convergence grid |
| `maxUpwardConvergenceStep` | 30 s | slew cap on upward convergence |

The asymmetries are the point: back-off confirms faster than extension
(`backOffWindow < extendWindow`), easing fires immediately at segment end while
effort-raising needs floors + confirm windows, and extension is opt-in/evidence-gated.

### 2.4 Cadence: warmup skip & walk compliance

Both consume the same live cadence stream (CMPedometer on device — chosen over the HK
builder's step count because it reports every ~2.5 s, fast enough for a ~10 s detection
window; unavailable/denied → the fixed timers stand, N6).

- **`RunningCadenceDetector`**: one-shot "the user started running" detector for the
  warmup — sustained cadence ≥ its running threshold for its sustain window (stale-gap
  aware) → the shell calls `skipCurrentSegment()`.
- **`WalkComplianceMonitor`**: detects "cue said WALK, feet still running". Deliberately
  **one-directional** — only the overdoing direction ever nudges. `assess(at:)` needs a
  fresh cadence sample at/above the running threshold, past a grace period (decelerating
  isn't defiance). Nudges are rate-limited and capped (`maxNudges`); after the cap plus
  an acceptance delay the monitor *concedes* (`accepted`) — the screen calms, haptics
  stop, and the shell counts the walk as **defied** (`walksDefied`). Defied walks are
  excused from the struggle math (`isClean` uses `walksHitCap − walksDefied`), so
  deliberately running through walks can never regress the seeds — the loop informs, it
  never fights the human.

### 2.5 Cross-session progression

**Cold start — `FitnessCalibration`:** an untouched factory-default `RunCard`
(`needsCalibration` = not-yet-calibrated *and* seeds still `.factoryDefault`) silently
maps 90 days of Health running history + latest VO2max to one of three seed tiers
(beginner = factory default / intermediate / continuous). "Real run" filtering excludes
short or walk-pace workouts. Calibration never touches hand-edited seeds.

**Per-session — `RunProgressionPolicy.evaluate(current:outcome:blockSeconds:)`** turns a
`RunSessionOutcome` into `Evaluation{seeds, reason, isStructural}`:

- **`isClean`**: not ended early, all planned run intervals reached, zero back-offs,
  zero *non-defied* cap-hit walks.
- **`isStrong`**: clean *and* every planned walk ended at the recovery floor
  (`fastRecoveries >= plannedRunIntervals`).
- **`isStruggle`**: repeated back-offs (`regressBackOffCount`) *with degraded recovery*
  (`hasDegradedRecovery`: net cap-hit walks ≥ 1), or bailed before half the planned
  intervals. Back-offs alone are the live loop calibrating a too-long seed — they route
  to the converged path, never a regress. The regress reason is `.recoveryNotReturning`.
- **`isHighEffort`**: `perceivedEffort >= highEffortThreshold` — the subjective signal
  that catches "HR in zone but gassed" fatigue-blindness. It only ever converts an
  advance into a hold (and suppresses the snap and the probe); it never eases.

**The converged path** (back-offs ≥ 1, **not ended early**, not a struggle,
`convergedRunSeconds` present):
next seeds start from the engine's demonstrated values. The run seed becomes the
converged length — capped at the seed the user *ran with*: a back-off session can ease
or hold the run seed, never raise it. The walk seed follows `convergedWalkSeconds` in
**both directions automatically** (user decision: converged walk shrink is
evidence-matched, not structural), clamped to [`minWalkSeconds`, `maxWalkSeconds`].
**The overload probe**: with *positive* recovery evidence (`hasHealthyRecovery`: ≥1 fast
recovery or mean HRR drop ≥ `healthyRecoveryDropBPM` — absence of trouble is not
evidence, N6), **no degraded recovery anywhere in the session** (an early fast recovery
must not outvote a later cap-ridden walk), and no high-effort rating, the run seed gets
one notch (`advanceNotch`, shared with the clean advance) past the converged length —
still capped at the ran-with seed. The stimulus stays just beyond the demonstrated limit
instead of settling into a comfortable medium. Reasons: `.converged` /
`.convergedWithProbe`. Back-offs with *no* converged value (old summary, signal-blind
session) hold — never fabricate a demonstrated length. The struggle regress journals
`.recoveryNotReturning` only when recovery demonstrably degraded; a bail with healthy or
unmeasured recoveries reads `.endedEarly` — never a fabricated recovery claim.

Seed math elsewhere: struggle → regress the run seed by `regressStep` (never below
`minRunSeconds`) and lengthen the walk (never *shortening* an already-long walk seed);
clean → advance 1 notch (2 if strong), each notch = a quarter of the current run seed
bounded to [15 s, `maxAdvanceStep`] — fast early, gentler later; once runs reach
`walkShrinkThreshold` the walk seed shrinks by `walkShrinkStep` toward `minWalkSeconds`.
**Snap to demonstrated capacity:** fires only with **zero back-offs** (a snap and a
back-off can't honestly coexist; the converged path owns back-off sessions), no
struggle, no high effort, when the longest run reached `snapRatio` × the seed *the user
ran with* — snaps the seed up to the demonstrated length (rounded down to 15 s; never
downward). Continuous running is reached when seeds grow past the block and the plan
factory emits a single run segment.

**`isStructural`** is true only for advance-direction *shape* changes: the walk seed
shrank on the *advance* path, or the run seed crossed the block into continuous. The
converged path is never structural (its run seed is capped at current, and its walk
move is evidence-matched). Structural moves ride the proposal lane (§4.3) instead of
auto-applying.

`RunProgressionPolicy` defaults *(snapshot)*: `maxAdvanceStep 60`, `regressStep 15`,
`minRunSeconds 30`, `minWalkSeconds 60`, `maxWalkSeconds 180` (seed cap — distinct from
the live 300 s walk cap), `walkShrinkThreshold 180`, `walkShrinkStep 15`,
`regressBackOffCount 2`, `snapRatio 1.5`, `snapWalkCeiling 90`,
`healthyRecoveryDropBPM 20`, `highEffortThreshold 8`.

`RunSeeds.progressionNote(from:to:blockSeconds:)` renders the one quiet "Next run: …"
line, nil when nothing changed (Q5 — silence when nothing moved).

### 2.6 Persistence & insights: `RunDigest`, `RunComparison`, `RunTrend`

`RunDigest` rides the saved `HKWorkout` as custom metadata — **Health itself is the
history store** (no private file, no TTL; deleting the workout deletes its digest). It's
an all-string codec (`AFC*` keys) gated by `AFCDigestVersion`: a version mismatch reads
as *no digest*, never a misread; `meanRecoveryDrop` is omitted when nil so a sensor gap
never round-trips into a fabricated zero. It carries the seeds run with, interval
counts, longest run, time-in-zone, recovery stats, back-offs, fast recoveries, and the
`routineId` for attribution.

`RunComparison` (watch summary "vs last run / vs 28-day baseline") and `RunTrend`
(phone per-routine Trends chart) are pure and share the same honesty gates so both
surfaces tell one truth: the 28-day window mirrors the 7:28 acute:chronic workload
construct (Gabbett; Apple Training Load uses the same window), and the baseline stays
silent until `baselineMinimumRuns` in-window runs spread over
`baselineMinimumSpreadDays` *(snapshot: 4 runs / 21 days / 28-day window; ±15 s reads
"even")*. Deltas are facts, never grades — no red, downward is neutral.
`HealthRunDigestReader` (watch) and `HealthRoutineRunHistory` behind `RunHistoryProviding`
(phone) read digests back from workout queries, excluding the just-finished workout.

---

## 3. Strength adaptation

### 3.1 Data model

- `StrengthSetRecord` — one set/hold as lived: prescribed vs completed reps (or hold
  seconds), the weight actually in effect, and `restRecovered: Bool?` (nil = no HR
  signal; absence is never evidence).
- `StrengthExerciseOutcome` — one exercise aggregated across all its card occurrences
  and rounds (**one move = one seed**), with `unrecoveredRests` and three
  manual-intervention flags (`weightManuallyLowered` / `weightManuallyRaised` /
  `repsManuallyChanged`).
- `StrengthSessionOutcome` — the session: outcomes + `endedEarly` + `perceivedEffort`.

Rep bands, weight steps, and rest seeds are `ExerciseLibrary` metadata on `Exercise`
(`repRange`, `weightStepPounds`, rest seed) — zero per-card configuration, so AI-built
or imported routines inherit progression for free. `StrengthExerciseItem` seeds new
cards at `repRange.lowerBound` and the library's conservative seed weight; sets come
from `Routine.rounds` repeating the card list, not a per-item field.

### 3.2 `StrengthProgressionPolicy` — tri-state double progression

**Decision precedence** (exact): struggle → `.ease`; else clean → (`perceivedEffort >=
highEffortThreshold` ? `.hold` : `.advance`); else `.hold`.

- **`isClean`**: not ended early, all planned sets done, every logged set met its
  prescription, and fewer than `suspicionUnrecoveredRests` cap-hit rests.
- **`isStruggle`**: manual weight lowering, or ≥ `struggleShortSets` sets short by
  ≥ `shortfallReps`, or bailed with under half the sets done. Unattempted sets are not
  failures — ending early with most sets done is a hold, not an ease.

**The transform** (`evaluate` → `Evaluation{next, decision, reason, steppedLoad}`):

1. Clamp first, regardless of decision: reps into the exercise's `repRange`, holds into
   `[holdFloor, holdCap]`.
2. **Advance**: hold movements gain `holdStep` seconds. Rep movements gain +1 rep per
   clean session *while below the band top* — unless the user manually changed that
   dimension this session (a manual raise *is* the progression; the policy freezes the
   dimension rather than stacking on top). **Topping the band converts to a load step**:
   weight steps by `weightStepPounds`, reps reset to the band bottom, and `steppedLoad`
   is flagged — this is the *structural* move (§4.3). Bodyweight at the band top holds
   (no heavier step exists; a harder variation is an AI/coach suggestion, not a policy
   move). Grounding: reps-through-band then load-step ≈ ACSM 2009 progression; topping
   an 8–12 band takes ≥4 clean sessions — deliberately stricter than NSCA's 2-for-2.
3. **Ease**: −1 rep, or a weight step down at the band bottom; holds lose `holdStep`.
4. **Trailing grid snap, every path including hold**: the output weight lands on the
   `Weight` 5-lb grid, floored at the smallest dumbbell for loaded movements (easing may
   never produce a phantom 0-lb exercise). `Weight.stepped` moves off-grid legacy values
   to the *adjacent* grid point in the delta direction; `snappedToGrid` rounds nearest.

**`steppedLoad` is a branch flag, not a weight comparison** — the trailing grid snap can
move a legacy off-grid load on *any* path (including a plain hold), and that must never
read as a structural load step.

**`reason(for:)`** mirrors the precedence and renders the journal clause via
`ProgressionReason.summary` ("clean session", "topped the rep band", "felt all-out
(effort 9)", "rests ran long", …). The enum never crosses the wire — only its rendered
string does, so new reasons can't break decode.

`StrengthProgressionConfig` defaults *(snapshot)*: `shortfallReps 2`,
`struggleShortSets 2`, `suspicionUnrecoveredRests 2`, `holdStep 5 s`, `holdFloor 15 s`,
`holdCap 120 s`, `minWeightPounds = Weight.gridPounds` (5), `highEffortThreshold 8`.

### 3.3 In-session: `StrengthSessionManager` + `RestRecoveryModel`

The watch shell is **hybrid**: sets are user-paced ("Done set"), rests and holds are
manager-ticked (same `autoTick`/`tick(delta:)` test seam as the run manager).

- **Rep truth via the Digital Crown**: the glance's rep hero starts at the prescription
  and crown-adjusts before "Done set" — hitting the prescription costs zero interactions
  (N1/N5). Every set lands in a `StrengthSetRecord`.
- **Manual ± overrides** are keyed by `exerciseId` (apply to every round), grid-snapped,
  and compared against an `originalSeeds` snapshot so progression can tell manual moves
  from policy moves.
- **`RestRecoveryModel`** (pure, ticked): rest is *time-based per the evidence* (PCr
  resynthesis is unobservable); HR only refines within a band around the seed —
  floor `max(floorSeconds, floorFraction × seed)` (never above the seed), cap
  `min(seed + extensionSeconds, capSeconds)`. Recovery uses the same construct as the
  run side (drop ≥ `recoveryDropBPM` from the set's peak, leaky `recoverWindow`
  accumulator). Outcomes: early end `recovered: true`, cap hit `recovered: false`
  (→ `unrecoveredRests`), no HR → exactly the authored timer and `recovered: nil`.
  Rest cards carry an `adaptive` toggle; fixed rests never consult HR. Skipping a rest
  records nil — a skip says nothing about recovery.
  Defaults *(snapshot)*: `recoveryDropBPM 20`, `recoverWindow 10 s`, `floorFraction
  0.75`, `floorSeconds 45`, `extensionSeconds 60`, `capSeconds 180`.
- **Holds** tick down in the manager and record *actual* seconds held (auto-complete or
  early Done).

### 3.4 Effort capture — emitted once, on Done

Progression is deliberately **not** computed at `end()`. `end()` builds the summary
instantly from local state and finalizes HealthKit in a background task; the effort
rating (`EffortRatingControl` → coarse `EffortLevel`: Easy/Moderate/Hard/All-out,
scores 2/5/8/10, skippable, no crown so the summary stays scrollable) is captured on
the complete screen, and tapping **Done** runs `finalizeProgression(perceivedEffort:)` —
the session's *only* progression emission.

**Effort prefill (runs).** `EffortPredictor.suggestedLevel(from: SessionSummary)` (pure,
`Engine/EffortPrediction.swift`) pre-selects a level from the objective signals —
grounded in the session-RPE literature (whole-session RPE correlates r ≈ 0.75–0.9 with
HR-derived load). Ordered explainable rules over back-offs, net cap-hits, above-zone
fraction, fast recoveries, and mean HRR drop; returns **nil for a signal-blind session**
(no zone dwell, no recovery data — a prefill from nothing would fabricate a signal, N6).
The control renders an untouched suggestion visibly *as* a suggestion ("Suggested —
adjust if it felt different", secondary tint). At Done, an untouched suggestion **writes
to Health** (the user's prefill decision — the visible pre-selection is the confirmation
surface) but **never gates progression**: the suggestion is derived from the same
objective signals the policy already consumes, so feeding it into the high-effort gate
would double-count them (an auto-suggested "Hard" — score 8, exactly
`highEffortThreshold` — would suppress the very probe a back-off session was designed to
earn). Only a rating the user actually touched reaches the policy and the journal; the
"Next run" note previews the same rule. The informative signal is the user's deviation
from the suggestion — exactly the fatigue-blindness case the rating exists for. Rationale: an advance emitted at `end()`
could never be retracted by a later "that was all-out" rating, since a hold produces no
update. `EffortLevel.hard.score` is pinned by tests to equal both policies'
`highEffortThreshold`, so Hard *and* All-out hold progression (user decision). The
rating also writes `HKWorkoutEffortScore` (awaiting the HealthKit finalize so it can
relate to the saved workout) — the same field Apple Fitness feeds Training Load from.

The same emit-on-Done pattern applies to runs: `RunSessionContainerView.recordOutcome`
builds the outcome + effort, evaluates the policy, and emits one `ProgressionBatch`.

---

## 4. The plumbing (watch shell, backends, sync)

### 4.1 `WorkoutSessionManager` and the `WorkoutBackend` seam

`WorkoutSessionManager` (`@MainActor @Observable`) owns the run session lifecycle
through a `WorkoutBackend` protocol — it never touches HealthKit directly. The backend
produces signals (`onHeartRate` / `onZoneChange` / `onCadence` / `onFailure`) and
persists the workout (`start` / `end(metadata:)` / `writeEffortScore`).
`HealthKitWorkoutBackend` is production; `SimulatedWorkoutBackend` replays a scripted
`[Step(at:zone:hr:cadence:)]` timeline (the `-simulateWorkout` path).

**The zone contract (subtle, load-bearing):** the engine consumes zones as a **1-based
position** within the user's zone configuration (1 = lowest; aerobic target
`targetZone = 2`). Apple's raw `HKWorkoutZone.index` base is unspecified;
`HealthKitWorkoutBackend.normalizedPosition` absorbs that ambiguity at the boundary by
sorting the configuration's zones and returning position-in-sorted-order + 1. Nothing
downstream may assume Apple's index base.

Shell mechanics worth knowing before touching:

- **Tick loop**: a 1 s sleep loop computing wall-clock deltas, capped at `maxTickDelta`
  (3 s) so a resume after suspension can't fast-forward through intervals and burst
  haptics.
- **Staleness expiry (N6)**: `sampleStalenessLimit` (15 s) of total signal silence nils
  the zone/HR state — a loose band's last reading can't drive adaptation forever. A
  *fresh nil* zone report is distinct from silence (it resets the clock).
- **Value-type write-back**: the engine is a struct — every mutation must be written
  back (`self.machine = machine`) or it's lost.
- **`isBeginning` / `isFinishing` guards** against double-start (orphaned
  `HKWorkoutSession`) and double-finalize; **`sessionGeneration`** token prevents a slow
  background finalize from writing totals into a later session; the finished backend is
  retained past `end()` so the post-summary effort write can relate to the saved
  workout.
- **Instant end**: the summary renders immediately from engine state; distance/avg-HR
  fill in when the background finalize returns, behind an honest `HealthSaveState` line
  ("Saving… → Saved" / "Check Health" on failure — never a false "Saved").
- **`endManually()`** sets `endedEarly` only when the session isn't complete, the
  current run isn't policy-extended, *and* the phase isn't a cooldown — ending during an
  extended run or any cooldown (authored or backfilled) is finishing, not bailing.
- **Adaptation cues are duration-tiered and phase-bounded**
  (`WorkoutSessionManager.cueDuration(for:)`): the easing cues that changed the timer
  under the user (`shortenedRun`, `lengthenedWalk`) linger 10 s so "why did that end
  early?" gets answered; the pushing cues keep the brief 4 s flash. A *later* phase
  transition dismisses a still-showing cue (EASING never survives into the next run),
  but the transition that *carries* the adaptation keeps it — that walk is exactly what
  the cue explains.
- Cadence is phase-routed: warmup → `RunningCadenceDetector`; walk →
  `WalkComplianceMonitor`. Compliance drives `gaitMismatch` (the UI pulse) and the
  nudge haptic; acceptance increments `walksDefied` once per walk.

Haptic vocabulary (`HapticManager`): →run = triple `.notification`, →walk = triple
`.directionDown` (bursts ~350 ms apart so one lands between footfalls), walk nudge =
double `.directionDown`, rest-ready = double `.notification`, complete = `.success`.
Direction is always distinguishable by feel (N5).

### 4.2 Sync: three channels, one fixed point

All wire formats live in `WCMessageCodec` (package) with **independent version
constants per channel** (routines / progression / quick-log) so bumping one never
forces peers to reject the others. The codec envelope is **exact-version** — mismatch
or missing version → reject → receiver keeps last-known-good. (The `ProgressionBatch`
*body* decoder is tolerant — missing lanes decode empty — so the strict envelope is the
only compatibility gate.)

- **Phone → watch (routines)**: `updateApplicationContext` — latest-state-wins,
  OS-queued, survives the counterpart being absent (N4). The phone re-pushes on
  activation and on watch (re)install (a reinstall drops the OS-held context). The
  watch applies via `replaceFromSync` with `broadcast: false` — **the watch never
  echoes routines**.
- **Watch → phone (progression)**: `transferUserInfo` — FIFO guaranteed delivery, so
  every finished session's batch survives unreachability (latest-wins would drop
  earlier sessions). Pre-activation sends buffer in `pendingTransfers`, **persisted to
  disk** (the buffer is the only copy of results the UI already called saved;
  flush hands over before clearing = at-least-once, applies are idempotent).
- **No ping-pong (the fixed-point contract)**: the watch applies micro lanes locally
  without broadcasting; the phone is the *sole re-broadcaster*.
  `RoutineStore.applyProgressions` is idempotent latest-value with a no-op
  short-circuit (no change → no write → no broadcast), so the round trip converges in
  one pass: watch applies → phone applies + re-broadcasts → watch's `replaceFromSync`
  sees identical values → silence.
- **Seed apply is shape-guarded** (`Routine.applyingProgressions`): nil fields mean "no
  change", and a dimension applies only where the card has it — a progression can never
  turn a bodyweight card into a weighted one or a hold into reps. Last-write-wins per
  `exerciseId`; an exercise on multiple cards advances everywhere at once.
- **Claude/exchange round trips**: the exchange schema deliberately omits progression
  state; `RoutineStore.importRoutines` grafts existing run-card ids/seeds/calibration
  onto imported cards (name-matched, folded case). Strength seeds ride inside imported
  cards directly. This graft is the load-bearing invariant that lets AI propose routines
  without ever writing progression.

### 4.3 Phone landing: journal, proposals, confirm cards

`ProgressionIntake` (package) is the phone's single landing point for a
`ProgressionBatch`:

1. Unknown routine → no-op (a proposal against a deleted routine can never apply).
2. Micro lanes apply through the untouched `applyProgressions` path (re-broadcasting).
3. Every applied change is journaled to `ProgressionJournal` (App Group file,
   newest-first, capped, corrupt-file sidecar) with old→new text + the wire `reason` +
   effort.
4. Structural proposals land in `ProgressionProposalStore` (persist until acted on; a
   newer proposal for the same exercise/card supersedes). The WeekView
   `PendingProposalCard` renders change + reason; **Confirm** applies + re-broadcasts +
   journals `confirmed` (idempotent — double-tap safe); **Hold** declines + journals
   `declined`. No expiry, no nag — an unanswered proposal just keeps the old seed.

On the watch, structural moves are *never applied locally*; the complete screen notes
"confirm on iPhone" and the confirmed seed returns through normal routine sync.

---

## 5. Cross-cutting invariants (check changes against these)

1. Advance needs a fully clean session; ease needs clear struggle; ambiguity holds.
   Suspicion signals only downgrade advance→hold.
2. Missing signal ⇒ no adaptation, ever — per-field, at every layer (engine, rest
   model, digest codec, comparison gates, UI slots, the effort-prefill nil gate, the
   converged path's nil-hold, and the probe's positive-evidence requirement).
3. Structural = advance-direction shape changes only (load step / advance-path walk
   shrink / continuous graduation), flagged by branch not by value comparison; easing is
   never structural and never confirm-gated. In-session convergence and the cross-session
   converged path (including its walk moves) are never structural — matching the seed to
   a demonstration is evidence, not a probe.
4. Progression emits exactly once per session, on Done, so effort can gate it.
5. One move = one seed: progression aggregates and applies by `exerciseId`.
6. Every emitted strength load lands on the 5-lb `Weight` grid, floored at the smallest
   dumbbell for loaded movements; reps stay in band; holds stay in [floor, cap];
   single-step deltas per session (pinned by a property sweep test).
7. Manual overrides freeze their dimension for that session and become the new seed.
8. The watch never broadcasts routines; the phone is the sole re-broadcaster; applies
   are idempotent with a no-op short-circuit — no ping-pong.
9. Zones are 1-based positions everywhere past the backend boundary.
10. Health is the record: digests in HKWorkout metadata, effort as
    `HKWorkoutEffortScore`, no private metrics store.
11. Defied walks are the user's choice, not a struggle signal — closed-loop cues have
    grace, a cap, and acceptance, and the choice is never punished by progression.
12. `RunSeeds.factoryDefault` is the single seed constant; calibration only touches
    untouched defaults.

## 6. Where the behavior is pinned (test map)

Package (`AdaptiveCore/Tests`, run with `swift test`): `AdaptationPolicyTests`
(hysteresis math, asymmetries, recovery signals), `IntervalStateMachineTests` (the
whole-session flow suite — there is no separate "WorkoutFlowTests" for runs),
`WalkComplianceMonitorTests`, `RunProgressionTests` (+ calibration + plan-factory
cases), `StrengthProgressionTests` (incl. the grid property sweep),
`EffortProgressionTests` (evaluation reasons, structural flags, batch v4 round-trip),
`EffortLevelTests` (score↔threshold pins), `EffortPredictionTests`, `RestRecoveryTests`,
`ProgressionJournalStoreTests`, `ProgressionIntakeTests`, `WCMessageCodecTests`,
`RoutineStoreTests` (graft/apply). Watch target: manager-level integration tests driven
through `autoTick: false` + the simulated backend (watchOS XCUI can't tap in-workout
paged views, so logic is pinned at the manager level).

## 7. Known tuning debt

The literature-seeded defaults awaiting on-body validation: `recoveryDropBPM` (20),
the cadence running threshold (140 spm), `hardBackOffWindow` (8 s), the convergence
bounds (`convergenceRounding`, `maxUpwardConvergenceStep`), the effort-predictor
thresholds, and the strength rest band. Deferred signal ideas (documented, not built):
pace-decay / running-power fatigue, VO2max-trend gating, IMU movement heuristics.

**Controller-design note (decided 2026-07, user-confirmed):** a PID controller was
considered and rejected — the in-session actuator is binary (run/walk), where PID
degenerates to flapping and hysteresis bang-bang is the correct class; the leaky
integrator already provides integral action with anti-windup; the convergence loop has
too few actuation cycles for feedback gains, so it converges deadbeat-down /
slew-limited-up; the cross-session loop is iterative learning control with an overload
bias. If the app ever gains a *continuous* actuator (pace guidance, treadmill control),
that inner loop would be a legitimate PID candidate.
