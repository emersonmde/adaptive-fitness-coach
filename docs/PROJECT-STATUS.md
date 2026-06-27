# Project Status & Handoff

The single entry point for picking up this project. Read this, then `docs/adaptive-fitness-coach-spec.md` (PRD) and the design handoffs in `docs/design/`.

_Last updated: end of P0 + senior-review fixes + dark/neon redesign._

---

## Snapshot — what works today

**P0 is complete, reviewed, and visually redesigned.** End to end:
- **Phone (iOS, setup-only):** build run routines, schedule them with reminders, sync to the watch. Dark/neon "Your Week" hub (Up-Next hero, week-at-a-glance strip, one-row-per-routine).
- **Watch (watchOS, the in-workout product):** a real Apple `HKWorkoutSession` outdoor run/walk that adapts run/walk intervals in real time to the user's **Apple-native HR zone**, haptic-first, ending as a native workout in Apple Health. The app records nothing of its own.
- **Engine:** all adaptation logic is in the pure `AdaptiveCore` Swift package (no HealthKit/SwiftUI), consumed identically by both apps.

**Tests: 73 green** — 62 `AdaptiveCore` (logic), 9 watch integration (`WorkoutFlowTests`), 2 phone UI (`RoutineFlowUITests`).

---

## Build & test (IMPORTANT — toolchain)

The watch target's minimum is **watchOS 27**, because it uses Apple's native HealthKit workout-zone APIs (`HKLiveWorkoutBuilderDelegate.didUpdateWorkoutZone`, `HKHealthStore.preferredWorkoutZoneConfiguration`, `HKWorkoutZone.index`). Those ship only in the **watchOS 27 SDK → Xcode 27 beta** at `/Applications/Xcode-beta.app`. The user's default `xcode-select` is Xcode 26.5.

```bash
# Pure logic (default toolchain, no simulator) — fastest feedback loop
cd AdaptiveCore && swift test            # 62 tests

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
AdaptiveCore/                      local Swift package — pure logic, 62 tests, no HealthKit/SwiftUI
  Models/                          Routine, IntervalPlan, SessionConfig, SessionSummary, AdaptationEvent
  Engine/IntervalStateMachine      tick(deltaTime, currentZone:Int?) -> transitions/adaptations
  Engine/AdaptationPolicy          zone-based, bidirectional, hysteresis, asymmetric bias windows
  Connectivity/WCMessageCodec      routine <-> [String:Any] for WatchConnectivity
  Persistence/RoutineStore         @Observable store + nextOccurrence() (drives the phone hero)

Adaptive Fitness Coach Watch App/  the in-workout product (watchOS 27)
  Services/WorkoutBackend          protocol seam: HealthKitWorkoutBackend (real) | SimulatedWorkoutBackend
  Services/WorkoutSessionManager   @Observable device shell: HK lifecycle + tick loop + state for the UI
  Services/HealthKitAuthorization, HapticManager, WatchConnectivityManager, StartRunIntent
  Views/                           SessionContainerView, LaunchView (A1), WorkoutActiveView (A2/A3),
                                   WorkoutControlsView (swipe End), AdaptationCue (A4), WorkoutCompleteView (A5),
                                   WatchComponents (ZoneBarView, HeartRateView), Theme.swift

Adaptive Fitness Coach/            phone setup app (iOS)
  Services/PhoneConnectivityManager, NotificationManager, RoutineStore (shared via AdaptiveCore)
  Views/                           WeekView (hub), NewRoutineView, RoutineDetailView,
                                   Components/{Theme, Card, PrimaryButton, FieldSection, DayBadges,
                                   UpNextCard, WeekStrip, RoutineCard}
```

**Zone contract (subtle, important):** the engine compares `currentZone` to `targetZone` as a **1-based position** (1 = lowest zone, aerobic target = 2). `HealthKitWorkoutBackend` normalizes Apple's raw `HKWorkoutZone.index` (base unspecified) to that position. `SimulatedWorkoutBackend` already emits 1-based positions.

---

## Design system (dark/neon — diverges from the original light-mode handoffs)

The implemented visual language is **dark + neon**, decided with the user (the `docs/design/*.html` handoffs define screen FLOWS but predate this and were light-mode). Two-tier color:
- **Brand accent = Electric Lime `#C6FF3D`**, phone identity only (CTAs, selected states, today-ring, hero glow). The primary CTA is a **dark glowing-outline capsule**, deliberately not a flat neon fill.
- **Workout-state semantics** (green=run `#34E27A`, amber=walk `#FFB23E`, blue=strength `#4C8DFF`, hot=`#FF5A4D`) are a separate language, tied to the watch's haptics and learned mid-run (N5). The watch never uses the brand accent.
- Tokens in `Theme.swift` (one per target). Modern SwiftUI used selectively: `MeshGradient` (hero depth), `glassEffect` (hero chip + adaptation cue only), `symbolEffect`, `scrollTransition`. Reduce-Motion paths everywhere.

Watch in-workout screen is pure glance: HR · progress · clock / verb + timer / zone bar. End is a swipe-away controls page. Adaptations show as a brief directional cue (chevron + 1 word), never a sentence over the metrics.

---

## Milestones

### P0 — Adaptive run/walk ✅ DONE
Shipped, reviewed, redesigned. See snapshot above.

### P1 — Strength sequencing (NEXT) — static, no adaptation
Bring the user's full routine in as guided card sequences. From the PRD §5 / design handoff (phone P3/P4, watch B1/B2):
- **Phone:** a curated **exercise library** (id, name, muscle/pattern tags, looping form-animation asset, "good for" line, default sets/reps, dumbbell-range default, and a **biomechanical archetype tag** — press/OHP/row/curl/isometric/stationary — that P2's IMU heuristics will key off). An **arrange-as-cards** builder (reorderable list of `{exerciseId, sets, reps, seedWeight}`; iOS 27 **reorderable containers** are the natural fit). App-proposed conservative **seed weights** (a forward-looking seed per N1/N7, not a log).
- **Watch:** strength `HKWorkoutSession`; a **card sequence** per strength day (B1 with form demo, B2 compact once learned); proposed weight with ± adjust.
- **Data model:** extend `Routine` for strength (currently `RoutineType.strength` exists but is disabled in the picker). Add `Exercise`, the library, and the ordered card list to `AdaptiveCore`.
- **No** session-to-session progression or IMU yet.
- Where to start: the `AdaptiveCore` model for exercises + library, then the phone library/arrange screens, then the watch card sequence.

### P2 — Deterministic strength adaptation — no trained model
Session-to-session progression from **set outcome** (toward ~1–3 RIR) + deterministic **IMU heuristics** grouped by archetype (velocity-loss for wrist-tracks-load; stability-envelope for isometric/plank), set-outcome-only fallback where the wrist has no clean read (N6). Self-labeling, no surveys.

### P3 — Learned, personalized adaptation
Fatigue/effort model on a HAR-encoder backbone, trained overnight on the phone from free labels (set outcome + optional one-tap "too easy / about right / too hard"), deployed to the watch via WatchConnectivity. Core ML updatable models. Personalized-from-day-one is the whole point (generic fatigue models generalize poorly).

---

## Open items / TODOs (carried forward)

- **Device-only verification:** real HR→zone→adapt loop, haptics feel, Action Button auto-start, workout appearing in Apple Health, notification→watch launch handoff. The sim can't cover these.
- **`StartRunIntent`** opens the app to A1 but does not auto-start the session (documented stub) — finish the Action Button flow on device.
- **HealthKit end sequence** uses `session.end()` → `endCollection` → `finishWorkout` in sequence (common pattern); consider driving finalize off the `.ended` state on device.
- **Phone UI tests are parallel-flaky** — pin `-parallel-testing-enabled NO` (or a test plan) for CI.
- **Signing:** no development team set (simulator-only builds work; device/TestFlight needs a team).
- The `docs/design/*.html` handoffs are light-mode and predate the dark/neon redesign — treat them as flow/spec references, not visual truth.

---

## Resuming in a fresh session
1. Read this file, then the PRD (`docs/adaptive-fitness-coach-spec.md`) and design handoffs (`docs/design/`).
2. Confirm Xcode 27 beta is installed; build the watch scheme with `DEVELOPER_DIR=…Xcode-beta…` against a watchOS 27 sim.
3. `cd AdaptiveCore && swift test` should be 62 green instantly.
4. Pick up at **P1** (strength sequencing) — start with the `AdaptiveCore` exercise/library model.
