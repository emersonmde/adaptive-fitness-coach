# Project Status & Handoff

The single entry point for picking up this project. Read this, then `docs/adaptive-fitness-coach-spec.md` (PRD) and the design handoffs in `docs/design/`.

_Last updated: P0 + dark/neon redesign + TestFlight (build 2 live) + P1 strength sequencing + **generic card-based routines (run/exercise/rest cards, rounds; run+strength unified)**. Sim-verified; device pending._

> **Routines are now a generic card stack.** A `Routine` is `cards: [WorkoutCard]` (`.run` / `.exercise` / `.rest`) plus a `rounds` count that repeats the whole list (= sets; a trailing rest card becomes rest between rounds). The phone builds it from a typed card list; the watch walks it and starts/stops the right Apple workout per card type automatically (`workoutBlocks()`), reusing the existing run and strength screens. The old `type`/`durationMinutes`/`exercises` fields are gone (migrated on decode). WC payload is **v3**. This supersedes the type-branched descriptions below — treat them as history.

---

## Snapshot — what works today

**P0 is complete and P1 (strength sequencing) is implemented end-to-end** (sim-verified; real strength `HKWorkoutSession` on device is the one open check). End to end:
- **Phone (iOS, setup-only):** build **adaptive-run** routines (repeat days in locale order, target duration) **and now strength routines** — pick exercises from a curated library and **arrange them as reorderable cards** (sets/reps/seed-weight per card). Schedule either as recurring **Calendar events** (EventKit), sync to the watch. Dark/neon "Your Week" hub.
- **Watch (watchOS, the in-workout product):** a real Apple `HKWorkoutSession` — an outdoor run/walk that adapts intervals to the user's **Apple-native HR zone**, **or** (P1) a Traditional Strength Training session that walks the user **card by card** through the exercise sequence with a form diagram, a proposed weight (± adjust), and per-set/hold progression. Haptic-first, ending as a native workout in Apple Health. The app records nothing of its own.
- **Engine:** all logic is in the pure `AdaptiveCore` Swift package (no HealthKit/SwiftUI), consumed identically by both apps. P1 adds the `Exercise`/`ExerciseLibrary`/`StrengthPlan` model; **strength has no real-time adaptation yet (P2)** — it's a static authored sequence with seed weights.

**Tests green** — 87 `AdaptiveCore` (logic, incl. card model / workout-block grouping / migration), watch integration (`WorkoutFlowTests` + `StrengthFlowTests` walking a card block), 3 phone UI (`RoutineFlowUITests`, create run + strength from cards).

---

## Build & test (IMPORTANT — toolchain)

The watch target's minimum is **watchOS 27**, because it uses Apple's native HealthKit workout-zone APIs (`HKLiveWorkoutBuilderDelegate.didUpdateWorkoutZone`, `HKHealthStore.preferredWorkoutZoneConfiguration`, `HKWorkoutZone.index`). Those ship only in the **watchOS 27 SDK → Xcode 27 beta** at `/Applications/Xcode-beta.app`. The user's default `xcode-select` is Xcode 26.5.

```bash
# Pure logic (default toolchain, no simulator) — fastest feedback loop
cd AdaptiveCore && swift test            # 84 tests

# Watch / iOS (need the beta; target a watchOS 27 sim by UDID, name collides with 26.5)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project "Adaptive Fitness Coach.xcodeproj" \
  -scheme "Adaptive Fitness Coach Watch App" \
  -destination 'id=<watchOS-27-sim-UDID>' build   # or: test

# iOS scheme builds the embedded watch app too, so it also needs the beta.
# Phone UI tests are flaky in PARALLEL (clone contention) — run serially:
#   -only-testing:"Adaptive Fitness CoachUITests/RoutineFlowUITests" -parallel-testing-enabled NO
```
`xcrun simctl list devices available | grep "watchOS 27"` to find a sim UDID.

**Simulator launch args** (the sim can't generate HR/zone data, and `simctl` can't grant HealthKit/notification auth, so these make the apps demoable/testable):
- Watch `-simulateWorkout` → scripted HR/zones via `SimulatedWorkoutBackend`, short plan, auto-starts, skips the HealthKit prompt. The only way to see the adaptive loop in the sim.
- Phone `-uiTesting` → throwaway store, skips the notification prompt (used by the XCUITests).
- Phone `-seedDemo` → throwaway store seeded with demo routines (QA/screenshots).

Real HR/zone adaptation only runs on a **physical Apple Watch** (verified by construction + the engine's tests, not yet observed on-device).

---

## Architecture & key files

```
AdaptiveCore/                      local Swift package — pure logic, 84 tests, no HealthKit/SwiftUI
  Models/                          Routine (now carries `exercises`), IntervalPlan, SessionConfig,
                                   SessionSummary, AdaptationEvent
  Models/ (P1 strength)            Exercise + ExerciseKind, ExerciseLibrary (curated catalog),
                                   StrengthPlan + StrengthExerciseItem, MovementArchetype (P2 IMU key),
                                   FormDemo (asset abstraction), Weight (lb-canonical value type)
  Engine/IntervalStateMachine      tick(deltaTime, currentZone:Int?) -> transitions/adaptations  (run only)
  Engine/AdaptationPolicy          zone-based, bidirectional, hysteresis, asymmetric bias windows
  Connectivity/WCMessageCodec      routine <-> [String:Any] for WatchConnectivity (v2: + exercises)
  Persistence/RoutineStore         @Observable store + nextOccurrence() (drives the phone hero)

Adaptive Fitness Coach Watch App/  the in-workout product (watchOS 27)
  Services/WorkoutBackend          run seam: HealthKitWorkoutBackend (real) | SimulatedWorkoutBackend
  Services/WorkoutSessionManager   run shell: HK lifecycle + tick loop + state for the UI
  Services/StrengthWorkoutBackend  strength seam: HealthKitStrengthBackend | SimulatedStrengthBackend
  Services/StrengthSessionManager  strength shell: user-driven card progression (no tick), summary
  Services/HealthKitAuthorization, HapticManager, WatchConnectivityManager, StartRunIntent
  Views/  (run)                    SessionContainerView (router by type), RunSessionContainerView,
                                   LaunchView (A1), WorkoutActiveView (A2/A3), WorkoutControlsView,
                                   AdaptationBannerView (A4), WorkoutCompleteView (A5), WatchComponents
  Views/  (strength)               StrengthSessionContainerView + StrengthLaunchView (B0),
                                   StrengthActiveView (B1/B2 card + pager + hold timer),
                                   StrengthCompleteView, FormDemoView

Adaptive Fitness Coach/            phone setup app (iOS)
  Services/PhoneConnectivityManager, CalendarService, RoutineStore (shared via AdaptiveCore)
  Views/                           WeekView (hub), NewRoutineView (branches run/strength),
                                   RoutineDetailView (strength: exercises section), RoutineDetailView,
                                   ExerciseLibraryView (P3 picker), RoutineBuilderView (P4 arrange),
                                   Components/{Theme, Card, PrimaryButton, FieldSection, DayBadges,
                                   UpNextCard, WeekStrip, RoutineCard}
```

**Zone contract (subtle, important):** the engine compares `currentZone` to `targetZone` as a **1-based position** (1 = lowest zone, aerobic target = 2). `HealthKitWorkoutBackend` normalizes Apple's raw `HKWorkoutZone.index` (base unspecified) to that position. `SimulatedWorkoutBackend` already emits 1-based positions.

---

## Design system (dark/neon — diverges from the original light-mode handoffs)

The implemented visual language is **dark + neon**, decided with the user (the `docs/design/*.html` handoffs define screen FLOWS but predate this and were light-mode). Two-tier color:
- **Brand accent = emerald `#34E27A`** (was Electric Lime `#C6FF3D`; user preferred the truer green and to collapse the two greens into one), phone identity only (CTAs, selected states, today-ring, hero glow, app icon). Intentionally the **same hex as the `run` semantic**. The primary CTA is a **dark glowing-outline capsule**, deliberately not a flat neon fill.
- **Workout-state semantics** (green=run `#34E27A`, amber=walk `#FFB23E`, blue=strength `#4C8DFF`, hot=`#FF5A4D`) are a separate language, tied to the watch's haptics and learned mid-run (N5). The watch never uses the brand accent.
- Tokens in `Theme.swift` (one per target). Modern SwiftUI used selectively: `MeshGradient` (hero depth), `glassEffect` (hero chip + adaptation cue only), `symbolEffect`, `scrollTransition`. Reduce-Motion paths everywhere.

Watch in-workout screen is pure glance: HR · progress · clock / verb + timer / zone bar. End is a swipe-away controls page. Adaptations show as a brief directional cue (chevron + 1 word), never a sentence over the metrics.

---

## Milestones

### P0 — Adaptive run/walk ✅ DONE
Shipped, reviewed, redesigned. See snapshot above.

### P1 — Strength sequencing ✅ IMPLEMENTED (sim-verified; device pending) — static, no adaptation
Brings the user's full routine in as guided card sequences. Shipped this milestone (PRD §5 / handoff phone P3/P4, watch B1/B2):
- **AdaptiveCore:** `Exercise` (+ `ExerciseKind` rep-vs-hold), curated `ExerciseLibrary` (~11 dumbbell/bodyweight movements with conservative seed weights), `StrengthPlan`/`StrengthExerciseItem`, `MovementArchetype` (press/OHP/row/curl/isometric/stationary — the **P2 IMU key, ships unused**), `FormDemo` (asset abstraction, `.symbol` placeholders for now), `Weight` (lb-canonical value type). `Routine` gained `exercises` (backward-compat decode → `[]`); `WCMessageCodec` → v2.
- **Phone:** `RoutineType.strength` is now selectable. `NewRoutineView` branches: strength → **arrange-as-cards** builder (`RoutineBuilderView`, reorderable List + per-card sets/reps/seed-weight steppers) fed by the **exercise library** picker (`ExerciseLibraryView`). `RoutineDetailView` shows/edits the sequence and hides duration for strength.
- **Watch:** `SessionContainerView` routes by `RoutineType`. Strength runs a real `.traditionalStrengthTraining` `HKWorkoutSession` (`HealthKitStrengthBackend`), walking the user **card by card** (`StrengthActiveView` B1/B2: form diagram, ± weight, rep set or **hold timer** for isometrics) via the user-driven `StrengthSessionManager`. Demoable in the sim with **`-simulateStrength`**.
- **No** session-to-session progression or IMU yet (P2). Seed weights are fixed conservative defaults (no equipment profile); form demos are SF Symbol placeholders (`FormDemo` swaps to real assets with no model change).
- **Open for P1:** real strength `HKWorkoutSession` recording to Apple Health, observed on device (sim can't); real form-demo assets.

### P1.5 — Adaptive run v2 (recovery-driven coaching) ✅ IMPLEMENTED (sim-verified; on-body tuning pending)
Redesign after the first real-world run (user's HR sat *in* the target zone while they were gassed — HR-lag read as comfort and the old `.extend` stretched runs; zone-holding can't see beginner fatigue):
- **Engine:** `tick` now takes a `WorkoutSample {zone, heartRate}`. Run extension is **gated off by default** (`AdaptationConfig.allowRunExtension`); a hard back-off ceiling fires in 8s sustained at zone ≥ target+2. **Walks end on recovery, not a timer**: HR must drop `recoveryDropBPM` (20) from the run's peak (heart-rate recovery, Cole et al. NEJM 1999) or the zone must fall *below* target, with a 60s walk floor and the 300s cap unchanged. Per-walk HRR drops, back-off counts, and cap hits are tracked into `SessionSummary`.
- **Cross-session progression (the "adaptive" in the name, now real):** `RunCard` carries persisted seeds `runSeconds`/`walkSeconds` (start 90/120). `RunProgressionPolicy` turns each session outcome into next session's seeds — clean session → run +25% (15–60s, walk shrinks once runs ≥3 min), repeated back-offs or an early bail → regress, ambiguous → hold. Watch applies locally + `transferUserInfo`s a `RunProgressionUpdate` (progression channel **v2**); phone applies and re-broadcasts (same no-ping-pong fixed point as strength). Continuous running = the seeds grow until the plan factory emits a single run segment.
- **Configurable shape:** `RunCard` = `warmupMinutes`/`durationMinutes` (run block)/`cooldownMinutes` (default 5/20/5), three steppers in `RunCardEditor`; `IntervalPlan.plan(for:)`/`runWalk(...)` replace `beginnerRunWalk` at real call sites. Routines payload **v4** (`durationMinutes` semantics changed).
- **Warmup ends when running is detected:** `CMPedometer` cadence → `WorkoutBackend.onCadence` → pure `RunningCadenceDetector` (≥140 spm sustained 10s, stale-gap reset) → `skipCurrentSegment()`; plus a "Start Run" pill in the warmup glance (N6 fallback: no cadence → fixed timer). `NSMotionUsageDescription` added to the watch Info.plist.
- **On-body tuning pending:** `recoveryDropBPM` 20, cadence threshold 140, hard-ceiling 8s are literature-seeded defaults — validate on the next real run. Deferred: pace-decay/running-power fatigue signals, VO2max-trend gating.

**P1.5c — unmissable cues, cadence compliance, recover-blue (post-build-6, not yet shipped):** Real-run feedback: the single walk tap vanished under footstrike and a glance misread amber WALK as RUN. Fixes: (1) **transition haptics are now triple bursts** ~350ms apart (`HapticManager.burst` — run `.notification`×3, walk `.directionDown`×3; at running cadence at least one pulse lands between footfalls); (2) **cadence-verified compliance** — `WalkComplianceMonitor` (AdaptiveCore; grace 8s to decelerate, stale-gap aware, re-nudge every 6s capped at 3/walk — never nags, Q5) detects "still running after the WALK cue" from the same CMPedometer stream as warmup detection; the manager exposes `gaitMismatch`, replays a two-pulse walk nudge, and `WorkoutActiveView` throbs the WALK word/arrow + the zone bar (`ZoneBarView(emphasize:)`) until the feet comply. **Design decision: color stays the instruction** (green=run/amber=walk, the learned language); compliance is signaled by *motion*, never by re-mapping hue — a "green when aligned" scheme was considered and rejected because it would make green ambiguous between "run" and "correct". Only the overdoing direction nudges (bias toward backing off — never prod a tired user to run harder). (3) **Walk phase is now cool sky-blue `#3EC5FF`** (`WatchTheme.recover`/`recoverField`): green↔amber was the glance-failure axis (sunlight, motion blur, red-green CVD); warm=effort/cool=recover, cyan-leaning so it never reads as strength's royal blue. Amber keeps its gradient jobs (zone-ladder threshold, strength rest ring); easing adaptation cues are recover-blue too. (4) **Experienced runners are respected by design**: after the 3-nudge budget + 10s the monitor *accepts* continued running — the screen calms, haptics stay quiet, and the walk is counted as `walksDefied` (SessionSummary/RunSessionOutcome) so its dragged-out recovery is excluded from the cap-based struggle signal (`isClean` uses `walksHitCap - walksDefied`) — running through walks can never regress the seeds.

**P1.5b — zero-config adaptation + instant end (build 6):** No experience selector, ever — the app observes: (1) **cold start** — an uncalibrated run card silently reads 90d of running workouts + latest VO2max at first session start (`FitnessCalibration` pure mapping / `HealthFitnessCalibrator` HK plumbing; `RunCard.seedsCalibrated` one-shot flag) → continuous / 5-min-interval / 90-120 default seeds; (2) **in-session evidence gate** — a walk ending at the recovery floor (`fastRecoveries`) unlocks run extension for the rest of the session (comfort alone never extends under HR lag; demonstrated recovery does); (3) **progression** — strong sessions jump two notches, a run sustained ≥1.5× the seed *snaps* the next seed to `longestRunSeconds`, and ending during an extended run isn't a bail. **Instant end:** the summary appears the moment the workout stops (engine data); HealthKit finalizes in the background, distance/avg HR fill in, and `HealthSaveState` drives an honest "Saving… → Saved to Health" line (same fix in the strength manager). The summary shows a quiet "Next run: …" line when seeds move.

### P2 — Deterministic strength adaptation — no trained model
Session-to-session progression from **set outcome** (toward ~1–3 RIR) + deterministic **IMU heuristics** grouped by archetype (velocity-loss for wrist-tracks-load; stability-envelope for isometric/plank), set-outcome-only fallback where the wrist has no clean read (N6). Self-labeling, no surveys.

### P3 — Learned, personalized adaptation
Fatigue/effort model on a HAR-encoder backbone, trained overnight on the phone from free labels (set outcome + optional one-tap "too easy / about right / too hard"), deployed to the watch via WatchConnectivity. Core ML updatable models. Personalized-from-day-one is the whole point (generic fatigue models generalize poorly).

---

## Open items / TODOs (carried forward)

- **Device-only verification:** real HR→zone→adapt loop, haptics feel, Action Button auto-start, run **and now the strength `HKWorkoutSession`** appearing in Apple Health (Traditional Strength Training), and the **Calendar event flow** (`CalendarService` needs full calendar access — the sim can't grant it reliably). The sim can't cover these.
- **Strength form demos** are SF Symbol placeholders (`FormDemo.symbol`). Replace with real static diagrams / tap-to-play animations later — purely a data + render swap, no model change (`FormDemo` already has `.diagram`/`.animation` cases).
- **TestFlight:** build **1.0 (3)** (the card-model rearchitecture) is **live for internal testing** (export compliance cleared; `internalBuildState: IN_BETA_TESTING`). The whole headless pipeline — archive → API-key export/upload → compliance — is documented in **`docs/TESTFLIGHT.md`**. Credentials live in the **git-ignored `.env`** (issuer id, key id, the *path* to the `.p8`, app/team ids); the key material is never committed or read. **Release only significant milestones** (a redesign, the end of a phase), not every commit. New builds now declare `ITSAppUsesNonExemptEncryption = NO`, so they skip the "Missing Compliance" stall.
- **`StartRunIntent`** opens the app to A1 but does not auto-start the session (documented stub) — finish the Action Button flow on device.
- **HealthKit end sequence** uses `session.end()` → `endCollection` → `finishWorkout` in sequence (common pattern); consider driving finalize off the `.ended` state on device.
- **Phone UI tests are parallel-flaky** — pin `-parallel-testing-enabled NO` (or a test plan) for CI.
- **Duration → plan:** `IntervalPlan.beginnerRunWalk(totalDuration:)` scales the seed to the routine's `durationMinutes`; lands within one cycle of target (it's a seed, adapts). Watch reads `nextRoutine.durationMinutes`.
- The `docs/design/*.html` handoffs are light-mode and predate the dark/neon redesign — treat them as flow/spec references, not visual truth.
- **After P2 — watch snapshot tests:** add `pointfreeco/swift-snapshot-testing` and pin the key watch screens (strength glance, rest ring, hold ring, run active, complete) as reference images. This is the pro substitute for the manual screenshots: watchOS doesn't deliver XCUI taps into the in-workout paged `TabView` (`PUICPageViewController`), so the in-workout flow is verified by the manager-level integration tests for logic + snapshot tests for pixels, with XCUI reserved for launch/run-to-summary smoke and the full phone tap-through. (Do after P2 so the screens have settled.)

---

## Resuming in a fresh session
1. Read this file, then the PRD (`docs/adaptive-fitness-coach-spec.md`) and design handoffs (`docs/design/`).
2. Confirm Xcode 27 beta is installed; build the watch scheme with `DEVELOPER_DIR=…Xcode-beta…` against a watchOS 27 sim. Demo: `-simulateWorkout` (run), `-simulateStrength` (strength), `-simulateMixed` (run→strength sequence). Phone: `-seedDemo`.
3. `cd AdaptiveCore && swift test` should be 87 green instantly.
4. **Next: a planning session for Phase 3** (PRD §5 — learned/personalized adaptation). Note **P2** (deterministic strength adaptation: set-outcome progression + IMU heuristics keyed by `MovementArchetype`) is still open per the PRD — confirm P2-vs-P3 sequencing at the start of that session. Also open: P1 device-only checks (real strength workout in Health, real form-demo assets) and the post-P2 watch snapshot tests (see TODOs).
5. Releasing to TestFlight (significant milestones only): see **`docs/TESTFLIGHT.md`**.
