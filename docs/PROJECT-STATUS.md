# Project Status & Handoff

The entry point for picking up this project. Read this, then:
- **`docs/ADAPTIVE-SYSTEM.md`** — how run & strength adaptation actually work (the
  design reference for any engine/progression/sync change).
- **`docs/adaptive-fitness-coach-spec.md`** — the PRD; §3 non-negotiables N1–N7 bind
  every change.
- **`docs/DESIGN-PRINCIPLES.md`** — binding on any new screen.
- **`docs/calorie-tracking-spec.md`** — the P4 nutrition spec (C1–C7).
- **`docs/TESTFLIGHT.md`** — the headless release runbook.

Detailed build-by-build history lives in git (`git log` — commit messages are thorough);
this file carries only current state, the active roadmap, and still-open items.

_Last updated 2026-07-06._

## Where things stand

**Shipped:** P0–P6 plus P6.1 (run summary & insights). TestFlight **build 18**
(P6.1 + the quick-log always-pending rework) is `IN_BETA_TESTING`.

**On `main`, unreleased (queued for build 19):** five small changes from the user's
build-18 on-device session — context re-push on watch reinstall, watch quick-log button
copy ("Save for iPhone"), in-sheet delete for pending review items, the "Log a Meal"
watch complication + `LogMealIntent`, and the reserved INSIGHTS slot with a waiting
state before digest history exists.

**Run-convergence milestone (2026-07-07, branch `run-convergence` → build 19):** from
the user's first real run — the live HR loop was right but the timers lied, the session
shrank, and the policy punished a well-regulated session. Shipped: in-session
bidirectional future-segment convergence (timers turn truthful within an interval or
two), cooldown backfill to the planned session length, the cross-session **converged
path + overload probe** (back-offs with healthy recovery now match seeds to the
demonstrated durations and probe one notch beyond, instead of regressing; struggle
requires degraded recovery), HR-derived effort **prefill** (suggestion writes to Health;
only user-touched ratings gate progression — feeding our own guess back would
double-count), and 10 s phase-bounded easing cues. PID controller considered and
rejected (recorded in ADAPTIVE-SYSTEM.md §7). A high-effort multi-agent review found 9
defects pre-ship (defied-walk convergence, effort feedback loop, endedEarly/degradation
gates, honest reasons/stats, sim grid scaling) — all fixed and test-pinned.
**On-device pending: the next real run** — convergence feel, backfilled cooldown,
prefill accuracy, cue duration; convergence bounds are literature-seeded
(ADAPTIVE-SYSTEM.md §7 tuning debt).

**NEXT:** strength-adaptation feedback from the user (details TBD — parked out of the
run milestone), then on-device validation of build 19.

**Package tests:** ~478 (`cd AdaptiveCore && swift test`). Phone UI suites
(`RoutineFlowUITests`, `CoachFlowUITests`, `MealFlowUITests`) run **serially**; watch
in-workout flows verify via manager-level unit tests + manual sim (watchOS XCUI can't
tap in-workout paged views).

## What the product is today

- **Phone (iOS 27, setup + food):** routine building (typed card stacks: run / exercise
  / rest cards × rounds), exercise library, AI coach (`CoachEngine` seam; scripted in
  sim via `-simulateCoach`; the invested path is the manual **Export-to-Claude context
  packs** → validated JSON import), calorie tracking (scan/type → lookup ladder → Apple
  Health as the record), per-routine run Trends (Swift Charts), progression journal +
  structural-confirm cards, Calendar scheduling (EventKit), widgets + App Intents.
- **Watch (watchOS 27, the in-workout product):** real `HKWorkoutSession`s. Runs adapt
  intervals to Apple-native HR zones live and end walks on heart-rate recovery; strength
  walks card-by-card with crown-recorded reps, adaptive rest, and double-progression
  seeds. Haptic-first, glanceable, phone-optional. Quick-log for meals (always-pending →
  phone review queue). Complications for next-workout and Log-a-Meal.
- **Engine:** everything adaptive is the pure `AdaptiveCore` package — see
  `docs/ADAPTIVE-SYSTEM.md`.

## Architecture pointers (details in CLAUDE.md + ADAPTIVE-SYSTEM.md)

- `AdaptiveCore/` — pure logic package (models, engines, policies, codecs, stores).
- `Adaptive Fitness Coach/` — phone app (services: connectivity, Calendar, HealthKit
  nutrition recorder, health snapshot builder; views per feature).
- `Adaptive Fitness Coach Watch App/` — watch app (session managers, backends,
  connectivity, haptics; run/strength/quick-log views).
- Widget targets: `AdaptiveFitnessWidgets` (phone), `AdaptiveFitnessWatchWidgets`.
- Key seams: `WorkoutBackend` (real vs simulated sensors), `CoachEngine` (AI providers),
  `MealPipeline` (nutrition lookup), `RunHistoryProviding` (insights),
  `QuickLogService` (watch meal logging brain).

## Standing decisions (durable, not derivable from code)

- **The Claude export loop is the invested AI path.** The on-device Apple model is
  usable for meal-NLP only; it fails at routine building (user verdict, build 16). The
  FoundationModels coach stays wired behind the seam but is not the investment.
  **PCC-dependent items are pushed** pending the Apple grant (Small Business Program
  application filed 2026-07-03): agentic lookup rung 3 (`agent: nil` at both
  construction sites; the 4K on-device window is the proven blocker) and coach quality
  re-evaluation. On grant: re-add the `com.apple.developer.private-cloud-compute`
  entitlement — do NOT auto-reinvest beyond that; re-judge deliberately. (Instantiating
  PCC without the entitlement is a **fatal error**, guarded by `PCCEntitlement`.)
- **Watch quick-log is always-pending by design** (2026-07-06): the pocket case is the
  primary scenario, and a locked phone can't run the lookup ladder inside WCSession's
  reply deadline — so every watch log parks via `transferUserInfo` into the phone's
  pending-REVIEW flow. The phone's live handler survives only for build-≤17 watches;
  delete once always-pending is the installed floor. Background prewarm-on-delivery was
  designed and deliberately deferred.
- **Strength/run thresholds are literature-seeded and tuned observationally** from real
  workouts — no settings surface. Known tuning debt is listed in ADAPTIVE-SYSTEM.md §7.
- **Live Activities deferred** — cross-target `ActivityAttributes` fights the
  file-system-synchronized groups; value marginal. Cleanest standalone follow-up.
- **Watch snapshot tests** remain the intended substitute for in-workout XCUI
  (pointfreeco/swift-snapshot-testing) — still not adopted.
- **Naming:** the food surface is called "Food" (deliberate; "Diary" rejected for
  MFP-guilt register).
- **TestFlight:** ship significant milestones only, confirm with the user first
  (`docs/TESTFLIGHT.md`). Builds declare `ITSAppUsesNonExemptEncryption = NO`.

## Hard-won platform gotchas (verified, keep)

- **Toolchain:** watch target needs the Xcode 27 beta via `DEVELOPER_DIR`; watchOS-27
  sim names collide with 26.5 — target by UDID. (Commands in CLAUDE.md.)
- **Phone UI tests are parallel-flaky** — always `-parallel-testing-enabled NO`; split
  `build-for-testing` / `test-without-building` for iteration.
- The Xcode **template UI tests wedge the sim's UI configuration** and silently break
  `fullScreenCover` app-wide — never re-add them.
- watchOS-sim **XCUI taps don't fire watch `Button`s**; `simctl openurl` can't drive
  watch deep links (`widgetURL` is a special WidgetKit path; `CFBundleURLTypes` is dead
  config on watchOS).
- The **simulator underrenders the watch bottom safe-area inset** — paged views need
  `containerBackground(_, for: .tabView)`; verify layout by screenshot on real-device
  sims by UDID.
- `HKCorrelationType` must **not** appear in HealthKit authorization request sets
  (runtime exception; contained quantity types carry the auth).
- App Intent descriptions **can't contain the word "apple"** (ITMS-90626).
- SwiftUI Menu items surface to XCUI **by label, not accessibilityIdentifier**; a bare
  `.accessibilityIdentifier` on a stack can swallow child buttons — use
  `.accessibilityElement(children: .contain)`.
- Inside ScrollView+Button stacks, `.gesture`/`.simultaneousGesture` lose the recognizer
  race — `.highPriorityGesture` + minimum distance + horizontal latch is the working
  swipe-row recipe (`SwipeableRow`).
- WC: `transferUserInfo` on an unactivated session is **silently dropped** (hence the
  persisted pending-transfers buffer); a watch-app reinstall **drops the OS-held
  application context** (hence re-push on `sessionWatchStateDidChange`).

## Open items

**On-device validation pending (the user's job, standing list):**
- Build 18/19 checklist: quick-log dictation feel; locked-phone → "Saved for iPhone"
  ~1s; review card + 4h notification + in-sheet trash; cold-launch quick-log
  pre-activation; "Log a Meal" complication tap (incl. mid-workout no-sheet case);
  crown scrolls the complete screens; `addMetadata` after `endCollection` on hardware;
  run comparison lines appear from the second post-feature run.
- Older standing items: effort score in Apple Fitness/Training Load; widget +
  complication render; Siri flows; Health deep-link URL probes (Nutrition room, Active
  Energy) — tap once, hardcode winners; LookupLab coverage numbers on real network.

**Deferred backlog (each documented at its seam):** Live Activities; IMU/archetype
heuristics; HR-zone circuit mode; watch snapshot tests; sequence-block finalize handoff;
Claude-API/user-key coach engines + settings backend picker; coach conversation
persistence; full CoreSpotlight index; real strength form-demo assets (`FormDemo` is
SF-Symbol placeholders); `StartRunIntent` auto-start; background prewarm for quick-log.

## Resuming in a fresh session

1. Read this file; for adaptive work read `docs/ADAPTIVE-SYSTEM.md`; for anything
   product-shaped check the PRD's non-negotiables.
2. `cd AdaptiveCore && swift test` — all green, fast, no simulator.
3. Device targets: build/test commands and simulator launch args
   (`-simulateWorkout` / `-simulateStrength` / `-simulateCoach` / `-simulateMealScan` /
   `-simulateQuickLog` / `-seedDemo` / `-uiTesting`) are in CLAUDE.md.
4. Release: `docs/TESTFLIGHT.md`, significant milestones only, ask first.
