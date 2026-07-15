# Project Status & Handoff

The entry point for picking up this project. Read this, then:
- **`docs/ROADMAP.md`** — the active roadmap (design-review remediation milestones;
  pick the next unchecked milestone when starting a work session).
- **`docs/ADAPTIVE-SYSTEM.md`** — how run & strength adaptation actually work (the
  design reference for any engine/progression/sync change).
- **`docs/adaptive-fitness-coach-spec.md`** — the PRD; §3 non-negotiables N1–N7 bind
  every change.
- **`docs/DESIGN-PRINCIPLES.md`** — binding on any new screen.
- **`docs/calorie-tracking-spec.md`** — the P4 nutrition spec (C1–C7).
- **`docs/NUTRITION-SYSTEM.md`** — how meals are logged and the energy budget adapts (the
  design reference for any target/budget/calibration change; the nutrition analogue of
  ADAPTIVE-SYSTEM.md).
- **`docs/TESTFLIGHT.md`** — the headless release runbook.

Detailed build-by-build history lives in git (`git log` — commit messages are thorough);
this file carries only current state, the active roadmap, and still-open items.

_Last updated 2026-07-14._

## Where things stand

**Shipped:** P0–P6 plus P6.1 (run summary & insights). **Build 22** (the adaptive energy
budget below, plus the build-21 follow-ups) is releasing to TestFlight. The P0–P6.1
roadmap is **complete**.

**Design review (2026-07-14).** A comprehensive whole-app UI/UX review (136-agent
multi-phase workflow over the `design-review/` storyboards, adversarially verified)
produced **`docs/design/DESIGN-REVIEW-2026-07.md`**: 511 findings — 4 blockers (two N6
fabrication points, an unguarded End Workout tap, the bare mixed-session summary), a
scorecard (typography 3/5 is the weakest channel; color system 4.5/5 the strongest), 16
redesign concepts, a 36-item hardware-verify list, and 10 principle/spec decisions that
need the user. Its remediation plan is the **active roadmap: `docs/ROADMAP.md`** —
six work milestones grouped by shared verification workflow (M1 trust & honesty, M2
app-wide sweep, M3 adaptation legibility + mixed, M4 watch session, M5 food loop, M6
phone surfaces), plus M0 (on-body verify, parallel) and an M7+ big-swing menu — each with
finding refs, decisions-needed, and acceptance criteria.

**NEXT (new session): `docs/ROADMAP.md` M2 — app-wide mechanical sweep** (targets ·
type · copy · color; resolve the M2 decision-register rows with the user first). M0
(on-body verification of the review's §7 list) runs whenever the user next has the watch
on-wrist, in parallel — it also picks up the three M1 states the sim can't force (B2
loadFailed gauge, P13 partial-save warning, W22 done-today receipt).

**M1 — trust & honesty: DONE 2026-07-15** (blockers B1/B2 closed; see the ROADMAP status
line for scope; new watch sim args `-simulateStartFailure[Permissions]`/`-simulateMidFailure`
force the failure states for screenshots).

**Adaptive energy budget (2026-07-09 → build 22).** The fixed daily calorie target became a
**live budget** built from Apple Health: basal (Mifflin) banked up front, active energy
**realized as earned** from the watch (never forecast, ×0.80 to counter the watch's ~28%
overestimate), minus a user-chosen **deficit** (the new stored primitive; ±goal chips replaced
by a numeric deficit + presets). A per-user **weight-trend calibration** (`EnergyBalanceCalibrator`,
Bayesian shrinkage) learns how far the textbook estimate is from the user's real metabolism and
migrates from safe default to personal as weigh-ins accrue — folding the whole residual into
`basalTrust` (weight identifies only total TDEE). All pure math in `AdaptiveCore/Nutrition/`
(`EnergyBudget.swift`, `EnergyHistorySource.swift`); phone adds `HealthKitEnergyHistorySource`,
extends `CalorieTargetStore`, reworks `TargetSetupSheet`/`FoodDayView`. Validated by Monte-Carlo
against synthetic ground truth (weight is too slow to hand-check). No migration of pre-22 fixed
targets — the target is a preference, not data. **Full design + invariants: `docs/NUTRITION-SYSTEM.md`.**
**On-device pending: real weigh-in data over weeks to see the calibration converge.**

**Also in build 22 — three follow-up passes** from the user's build-21 on-device session, each
screenshot-verified:

1. **Edit-sheet layout polish.** Build 21's edit sheet shipped visibly broken (floating
   keyboard Done colliding with the pinned Save bar; QUANTITY as a giant empty input
   card). Fixed: inline Done on the kcal field (keyboard-placement toolbars render as
   stray floating capsules on iOS 27), Save bar hides while typing, QUANTITY as a
   settings-style row, the lookup cluster (provenance → Look up again → alternates)
   regrouped under CALORIES, "WHEN" label, distinct lookup/relog icons.
   *Process fix that must outlive this entry: UI-test-green is NOT visually-verified —
   review screenshots of every changed state (temp screenshot-grab XCUITest on phone;
   `-startPage` + `simctl io screenshot` on watch).*
2. **Watch strength screens.** Exercise page: ± adjusters now lead (the 84 pt form-demo
   placeholder pushed the REPS buttons under the page dots on every watch size — labels
   fold between the − / + buttons); demo + how-to text are the scrollable reference
   below. Controls pages (strength AND run): session header + **Water Lock** + End,
   mirroring the native Workout app.
3. **Food-day trust fixes (the "all my meals are gone" scare).** `FoodDayView` re-anchors
   its "today" on every appearance and shifts selection at midnight (NavigationStack
   keeps destination `@State` alive across presentations — the screen resumed a stale
   day frame, mislabeling yesterday as Today and mis-dating captures). A failed
   HealthKit read renders "Couldn't read this day from Health — Try again" (one
   automatic retry), never the empty-day text, and failed fetches never write the day
   cache — the neighbor prefetcher was caching fabricated-empty snapshots, making the
   whole history look deleted after a cold-launch read failure. **Binding standard from
   the user: a failed read must never render as absence. Data / genuinely-empty /
   failed-to-load are three distinct UI states, everywhere.**

**Still pending on-device:** build-22 verification — set a deficit on a real device,
confirm the live budget banks active energy through the day, and (over weeks, with a scale
reporting to Health) watch the calibration note appear and the target tune. Then the deferred
"lose X lb/week" view over the deficit (dynamic model, never the 3500-kcal rule — see
`NUTRITION-SYSTEM.md` §Deferred).

**Food-UX overhaul (2026-07-08 → build 21):** from the user's build-20 field notes.
(1) **Day rollover** — an app left open overnight kept yesterday's date everywhere;
`WeekView` now refreshes a `today` state on `NSCalendarDayChanged` (+ foregrounding)
and passes it into `WeekStrip`/`nextOccurrence()` explicitly. (2) **Food day rows
migrated to a native `List` + `swipeActions`** (custom `SwipeableRow` deleted; its
`PressableCardStyle` survives in its own file); delete confirms via a row-owned
**`.alert`** — centered, AX-complete, no more popping over the gauge. (3) **Edit
sheet rework:** fresh state per entry (`.id(entry.id)` — `sheet(item:)` reuses @State
storage otherwise), quantity editing (shared `QuantityStepper` + `edited(quantity:)`),
kcal-focused-only keyboard Done via `@FocusState`, pinned Save bar, dirty-guarded
"Log again"/swipe-dismiss with a discard confirm, digit-filtered kcal input.
(4) **Confirmation sheet:** themed `QuantityStepper` replaces the stock `Stepper`,
worded "Delete" toolbar button, conditional dismiss lock, 44 pt tap targets.
(5) **Scan de-jank:** live `.text()` recognition removed from `DataScannerViewController`
(OCR runs on the captured still — the roaming highlight/"hold still" guidance served
nothing and made hand-held receipts uncapturable); shutter haptic on tap + an honest
miss toast when `capturePhoto()` fails. (6) `WhenRow` chips overflow-safe at
accessibility sizes; `textTertiary` lightened to clear AA at caption sizes.
**On-device pending: a real receipt/plate scan** (the sim can't drive DataScanner).

**Run-convergence milestone (2026-07-07 → builds 19/20):** from
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

**Still parked:** strength-adaptation feedback from the user (details TBD — parked out of
the run milestone), and on-device validation of builds 20/21.

**Package tests:** ~517 (`cd AdaptiveCore && swift test`). Phone UI suites
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
- App Intent descriptions **can't contain Apple trademark words** (ITMS-90626 — bounced
  build 9 on "apple" and build 19 on "iPhone"). The rejection is **email-only**: the
  upload reports success, then the build silently never appears in the ASC API (not even
  PROCESSING) — hours of apparent ingest stall. Before any release, grep every
  `IntentDescription`/intent title for `apple|iphone|ipad|siri|watch os`; when a build
  vanishes post-upload, check email first.
- SwiftUI Menu items surface to XCUI **by label, not accessibilityIdentifier**; a bare
  `.accessibilityIdentifier` on a stack can swallow child buttons — use
  `.accessibilityElement(children: .contain)`.
- Inside ScrollView+Button stacks, `.gesture`/`.simultaneousGesture` lose the recognizer
  race — `.highPriorityGesture` + minimum distance + horizontal latch was the working
  custom-swipe recipe (the component itself was retired for native `List.swipeActions`
  in build 21).
- In `List.swipeActions`, a `role: .destructive` button **optimistically animates the
  row away on tap** even if the action only opens a confirmation — and tears down any
  presentation attached to that row. Confirm-first delete buttons must be role-less with
  `.tint` red (the global accent otherwise paints them green).
- A row-anchored `confirmationDialog` popover ships **AX-empty on iOS 27** (visible on
  screen; its buttons invisible to VoiceOver and XCUITest). Use `.alert` for row-level
  confirms.
- XCUITest taps land at an element's coordinates **even when it's covered** (e.g. under
  a pinned `safeAreaInset` bar → the tap hits whatever is on top), and `isHittable`
  reports true through material backgrounds — scroll by frame geometry, not hittability,
  before tapping near pinned bars.
- WC: `transferUserInfo` on an unactivated session is **silently dropped** (hence the
  persisted pending-transfers buffer); a watch-app reinstall **drops the OS-held
  application context** (hence re-push on `sessionWatchStateDidChange`).
- **NavigationStack destinations keep their `@State` alive across presentations** —
  "recreated on each open" is false. Any pushed screen anchoring itself to push-time
  facts (dates especially) must realign `.onAppear`.
- **Failed reads must never render as empty states** (binding user standard, 2026-07-09):
  HealthKit reads can fail transiently on cold launch (daemon warmup); surface
  data / genuinely-empty / failed-to-load as three distinct states with a retry, and
  never cache a value fabricated from a failure.
- Keyboard-placement toolbar items render as a **floating glass capsule** on iOS 27 (not
  an attached accessory bar) — scope Done buttons inline in the field instead.
- watchOS screenshot recipe: `-simulateStrength`/`-simulateWorkout` +
  `-startPage=controls|exercise`, then `simctl io <UDID> screenshot` — the only way to
  visually review watch screens (sim XCUI can't tap or swipe).

## Open items

**On-device validation pending (the user's job, standing list):**
- **Design-review hardware-verify list** (`DESIGN-REVIEW-2026-07.md` §7, 36 items =
  roadmap M0): safe-area renders, Always-On dimming, sunlight legibility of the tinted
  state fields, End-Workout false-touch rate, haptic discriminability, real-model
  latency/compliance checks.
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
