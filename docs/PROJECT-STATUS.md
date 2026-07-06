# Project Status & Handoff

The single entry point for picking up this project. Read this, then `docs/adaptive-fitness-coach-spec.md` (PRD) and the design handoffs in `docs/design/`.

_Last updated 2026-07-06 (later): **the build-17 watch quick-log bug is ROOT-CAUSED and FIXED on `quicklog-always-pending` — see "P6 Phase 3 rework" below.** The live draft/confirm round trips ran the whole lookup ladder synchronously inside the WC reply handler; a locked, backgrounded phone can't finish inside WCSession's reply deadline → minutes of spinner, then the honest fallback. Fix (user-decided): the watch is now **always-pending** — every quick-log goes straight to the guaranteed-delivery review queue; the live channel is deleted from the watch (phone handler kept for build-≤17 compatibility). Background prewarm-on-delivery was designed and deliberately deferred. **NEXT: ship build 18 = P6.1 run insights + this fix.**_

_Previous update 2026-07-06: **P6.1 (run summary & insights) MERGED to `main` — see its milestone section** (coarse effort + crown-scroll fix, engine metrics, run digest as HKWorkout metadata with Health as the store, watch comparisons on the evidence-backed 28-day ACWR window, phone per-routine Trends with the first Swift Charts use). TestFlight build 18 was HELD for the quick-log bug (now fixed, above). Previous: P6 shipped as build 17 (IN_BETA_TESTING) — the P6 on-device validation lists still stand, EXCEPT Phase 3's (superseded by the always-pending rework's own checklist)._

_Previous update 2026-07-05 (late): **P6 SHIPPED — TestFlight build 17 uploaded, processed VALID, `internalBuildState: IN_BETA_TESTING` (compliance auto-cleared). NEXT = the on-device validation lists in each P6 milestone section (Phase 3 quick-log is the hardware-heavy one).** ALL FOUR P6 PHASES merged to `main` — see their milestone sections (Phase 1: progression channel v4, reasons on the wire, watch proposal lane, phone journal + confirm cards. Phase 2: ContextPackComposer + ExportPackSheet + one-time health disclosure + return-from-break card. Phase 3: watch quick-log — first live WC channel, QuickLogService, pending-REVIEW flow + one notification, `-simulateQuickLog`. Phase 4: multi-candidate adjudication + edit-sheet alternates). 449 package tests; all phone suites + watch unit green. **Next: merge `p6` → `main` and ship ONE TestFlight build (17) — confirm with the user first**; then the on-device validation list (each phase's section). The 5 lb weight-grid fix is COMMITTED to main. String Catalogs adopted on both app targets (P6 step 0)._

_Previous update 2026-07-05 (night): **P0–P5 shipped; TestFlight build 16 = the P5 polish deep dive + the post-15 gesture settlement (chevrons-only day nav + Notification-style SwipeableRow + day snapshot cache).** P5 (see its section): one motion vocabulary + Reduce-Motion gap closed, deliberate phone haptics (`Theme.Haptics`), token compliance both targets (watch gray drift, `info`/`heat`/`metricNumber`/radius scale), honest states (watch "Syncing from iPhone…" first launch, exit-ful wrap-up), accessibility pass (DailyIntakeLine container bug, labels, contrast floor), dark-mode declared to the OS, iPhone-only portrait, AccentColor populated, FoodDayView structural cleanup + SwipeableRow extraction. **NEXT = P6, RESHAPED 2026-07-05 after the user's build-16 verdict (on-device model: meal-NLP only, fails at routine building; the Claude export loop is the invested path — read the P6 Roadmap section):** progression journal + structural-confirm gate, **"Export to Claude" context packs** (fitness snapshot / check-in / meal planning / plateau / constraint rework; scope picker + honest health-export disclosure), watch quick-log, entry refresh/alternates; agentic rung 3 + FoundationModels-coach investment PUSHED pending the PCC grant. **On the tree UNRELEASED: the 5 lb weight-grid fix** (`Weight.stepped`/`snappedToGrid`, curl/lateral-raise seeds+steps on-grid, progression exits through a grid snap — fixes the stuck-22.5; 393 package + watch unit + phone build green, awaiting ship-or-hold). Also the confirm-on-device list (Health deep-link probes, LookupLab, PCC flow). Build 15 was the hybrid gesture split (summary zone swipes days), retired same-day by on-device feel; build 14's full-page pager stole row swipes and animated backwards. Build 14 carried the rest of the repage (pinned add bar, past-day backfill via when-row prefill, relog toast instead of teleport, full action set on tap/long-press). Build 13 carried the typed-meal parsing fixes (mid-sentence seller extraction — model-primary, parser as hint; clarification answers rendered as text in lookup prompts; inert question chips hidden after a stated override). Build 12 carried build 11 (meal-flow rework: pre-Log numbers/provenance/override, first-Log HealthKit crash fix, four-area hardening) plus the build-12 design sweep (see that section: watch crown/rest/countdown fixes, pinned meal commit bar, week-strip done-marks from Health, routine rename/search/discard-guard, import-sheet parity, contrast + VoiceOver pass) and the typed-seller pipeline (deterministic "from X" parse + model hint, graded seller→generic adjudication fallback, seller on entries end-to-end, edit-sheet rescan). Working tree clean. **Pending on-device validation (rides build 13, the user's job):** typed meal entry (mid-sentence seller → seller-first lookup, "How many eggs?"-style answers moving the estimate), meal flow end-to-end (edit-sheet rescan, pinned Log bar), watch summary crown behavior + rest-exit swipe + countdown on a real run/lift, week-strip done-marks after granting the updated Health read, Siri warm-start, P2 thresholds, P3 coach real-model. **Deferred:** Live Activities (build-9 section). **On grant:** Small Business Program → PCC = one-line switch to Apple's 32K server model._

> **Routines are now a generic card stack.** A `Routine` is `cards: [WorkoutCard]` (`.run` / `.exercise` / `.rest`) plus a `rounds` count that repeats the whole list (= sets; a trailing rest card becomes rest between rounds). The phone builds it from a typed card list; the watch walks it and starts/stops the right Apple workout per card type automatically (`workoutBlocks()`), reusing the existing run and strength screens. The old `type`/`durationMinutes`/`exercises` fields are gone (migrated on decode). WC payload is **v4** (progression channel v2). This supersedes the type-branched descriptions below — treat them as history.

---

## Snapshot — what works today

**P0 is complete and P1 (strength sequencing) is implemented end-to-end** (sim-verified; real strength `HKWorkoutSession` on device is the one open check). End to end:
- **Phone (iOS, setup-only):** build **adaptive-run** routines (repeat days in locale order, target duration) **and now strength routines** — pick exercises from a curated library and **arrange them as reorderable cards** (sets/reps/seed-weight per card). Schedule either as recurring **Calendar events** (EventKit), sync to the watch. Dark/neon "Your Week" hub.
- **Watch (watchOS, the in-workout product):** a real Apple `HKWorkoutSession` — an outdoor run/walk that adapts intervals to the user's **Apple-native HR zone**, **or** (P1) a Traditional Strength Training session that walks the user **card by card** through the exercise sequence with a form diagram, a proposed weight (± adjust), and per-set/hold progression. Haptic-first, ending as a native workout in Apple Health. The app records nothing of its own.
- **Engine:** all logic is in the pure `AdaptiveCore` Swift package (no HealthKit/SwiftUI), consumed identically by both apps. P1 adds the `Exercise`/`ExerciseLibrary`/`StrengthPlan` model; **strength has no real-time adaptation yet (P2)** — it's a static authored sequence with seed weights.

**Tests green** — 194 `AdaptiveCore` (logic, incl. card model / workout-block grouping / migration), watch integration (`WorkoutFlowTests` + `StrengthFlowTests` walking a card block), 3 phone UI (`RoutineFlowUITests`, create run + strength from cards).

---

## Build & test (IMPORTANT — toolchain)

The watch target's minimum is **watchOS 27**, because it uses Apple's native HealthKit workout-zone APIs (`HKLiveWorkoutBuilderDelegate.didUpdateWorkoutZone`, `HKHealthStore.preferredWorkoutZoneConfiguration`, `HKWorkoutZone.index`). Those ship only in the **watchOS 27 SDK → Xcode 27 beta** at `/Applications/Xcode-beta.app`. The user's default `xcode-select` is Xcode 26.5.

```bash
# Pure logic (default toolchain, no simulator) — fastest feedback loop
cd AdaptiveCore && swift test            # ~194 tests

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
- Phone `-uiTesting` → throwaway store so runs start clean (used by the XCUITests).
- Phone `-seedDemo` → throwaway store seeded with demo routines (QA/screenshots).
- Phone `-simulateCoach` → the P3 coach runs on the deterministic `ScriptedCoachEngine` (scripted intake → canned proposal). The only way to see the coach flow in the sim (Apple Intelligence can't be granted there); used by `CoachFlowUITests`.

Real HR/zone adaptation only runs on a **physical Apple Watch** (verified by construction + the engine's tests, not yet observed on-device).

---

## Architecture & key files

```
AdaptiveCore/                      local Swift package — pure logic, ~194 tests, no HealthKit/SwiftUI
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

### P6.1 — Run summary & insights ✅ IMPLEMENTED (2026-07-06, on `run-insights`)
Driven by the user's first real run on build 17 (crown trapped by the effort rater; 1–10
scale unloved; summary too thin; wants improvement made visible). Five phases:
- **Engine metrics:** `IntervalStateMachine` gained `walksCompleted` (natural recovery-walk
  transitions only — skips and warmup/cooldown excluded, mirroring `intervalsCompleted`)
  and `timeInTargetZone` (run-phase dwell, fresh zone readings only — stale/nil adds
  nothing, N6); both on `SessionSummary` with defaulted params.
- **Coarse effort + crown fix:** `EffortRatingControl` DROPPED `digitalCrownRotation`
  entirely (the tap-to-focus rater never released the crown, trapping scrolling for wet
  fingers — with no focusable child the crown scrolls both complete screens again). Input
  is −/+ buttons over the new `EffortLevel` (Easy 2 / Moderate 5 / Hard 8 / All-out 10 on
  the unchanged 1–10 internal scale; **Hard AND All-out hold progression** — user decision,
  pinned by a test against both policies' `highEffortThreshold`). Journal shows "felt hard".
- **Run digest → Health metadata (the storage decision):** `RunDigest` (pure all-string
  codec, `AFC*` keys + `AFCDigestVersion`) rides the saved `HKWorkout` as custom metadata —
  **Health itself is the history store**: self-maintaining, no TTL, deleting the workout
  deletes the digest (N2 by the book). `WorkoutBackend.end(metadata:)` (pass-through
  default; only the HK backend overrides — best-effort `try? addMetadata` between
  `endCollection` and `finishWorkout`, never failing the workout save). `routineId` threads
  from both run launch paths for attribution.
- **Watch summary rework + comparisons:** hero = **time running** (engine-owned, instant)
  + "6 runs · 5 walks · 62% running" sub-line + a reserved async slot for "vs last run" /
  "vs 28-day baseline" + new stat rows (longest run, in-zone, recovery drop — only when
  real). `RunComparison` (package): the 28-day window is the evidence-backed choice (7:28
  ACWR, Gabbett et al.; Apple Training Load uses the same and hides until 28d — we mirror
  the honesty gate: ≥4 runs spread ≥21d, else silence); deltas are facts (up = run-green
  tint, down = neutral, ±15s = "even", no red ever). `HealthRunDigestReader` (watch
  plumbing, calibrator query shape) excludes the just-finished workout; slot loads via
  `awaitBestEffort(3s)`. `-simulateWorkout` shows canned lines; `-simulateNoHistory` demos
  the empty slot. Summary visually verified in the sim.
- **Phone per-routine insights:** `RunTrend` (package) reuses `RunComparison`'s gates so
  both surfaces tell one truth; `RoutineRunHistory` behind a `RunHistoryProviding` seam
  (`-uiTestInsights` = canned five-session history); `RoutineDetailView` grows a LAST
  WORKOUT section (run routines with history only — absence is silent, no "0 workouts"
  guilt) pushing `RoutineInsightsView`: the project's **first Swift Charts use** — one hero
  bar chart (time running/session, 28d, single accent hue, hairline grid, no legend,
  dataviz-validated) over quiet baseline-suffixed stat lines; 1 session = honest no-chart
  state. Chart screen screenshot kept in the test bundle.
- **Testing:** 478 package tests (29 new across
  EffortLevel/RunDigest/RunComparison/RunTrend/IntervalStateMachine), watch unit green
  (metadata-spy pin), RoutineFlowUITests 8/8. **On-device pending:** crown scrolls the
  real complete screens; `addMetadata` post-`endCollection` on hardware (fallback order
  documented in the backend); digest → phone Health sync lag; comparison lines appear from
  the SECOND real run (post-feature runs only — say so in release notes).

### P6 Phase 1 — Progression journal + structural confirms ✅ IMPLEMENTED (2026-07-05, on `p6`)
The first P6 slice (see the P6 Roadmap section): adaptation made legible and consented.
- **Policies expose their reasoning.** `StrengthProgressionPolicy.evaluate(...)` /
  `RunProgressionPolicy.evaluate(current:outcome:blockSeconds:)` return `Evaluation`
  (next prescription/seeds + `Decision` + `ProgressionReason` + the structural flag);
  `nextPrescription`/`nextSeeds` are wrappers, zero test churn. `ProgressionReason`
  (Models/) renders the journal clause ("clean session", "felt all-out (effort 9)").
  Structural = the band-topped load-step **branch** (a flag set inside it — never a weight
  comparison, because the trailing grid snap moves legacy 22.5 loads on ANY path) and
  advance-direction run-shape changes (walk shrink / continuous crossing). **Easing is
  never structural** — backing off stays automatic by construction (PRD bias).
- **Progression channel v4** (`WCMessageCodec.currentProgressionVersion = 4`): updates
  carry `reason: String?` (a string on the wire so future reasons can't break decode) +
  run updates carry `blockSeconds`; `ProgressionBatch` gained `proposals`/`runProposals`
  (structural moves awaiting confirm) + `perceivedEffort`/`sessionDate` — the first time
  effort crosses to the phone (feeds Phase 2's check-in pack).
- **Watch partitions micro vs structural.** Micro (+1 rep, ±5s hold, run-length steps)
  applies locally + syncs as before (N3 intact). Structural moves are NOT applied on
  watch; they ride the batch's proposal lane; complete-screen note says "… — confirm on
  iPhone". One unified callback (`recordProgression: (ProgressionBatch) -> Void` →
  `WatchConnectivityManager.record`) replaced the two per-kind closures.
- **Phone is the single journal writer.** `ProgressionIntake` (package) is the landing
  point: applies micro via the untouched `applyProgressions` path, journals every change
  with old → new text + reason + effort, stashes proposals. `ProgressionJournal` (App
  Group file, newest-first, cap 500, `.corrupt` sidecar) + `ProgressionProposalStore`
  (persists until acted; newer proposal for the same exercise/card supersedes).
  Confirm → apply + re-broadcast + journal "CONFIRMED"; decline → journal "HELD" (= the
  policy's first-class hold; no expiry, no nag).
- **UI:** `PendingProposalCard` on WeekView ("STEP UP?" · change · reason · Confirm/Hold,
  accent confirm, `Theme.Haptics`); `ProgressionJournalView` pushed from a new toolbar
  icon (day-grouped rows, quiet micro entries, badges only for CONFIRMED/HELD).
- **Testing:** 421 package tests (28 new: evaluation reasons/structural flags, v4
  round-trip + v3 reject, journal persistence/cap/corrupt, proposal supersede/idempotent
  confirm/decline, intake end-to-end); watch unit incl.
  `bandToppedLoadStepIsProposedNotApplied`; phone `-seedProposal` launch arg seeds a real
  v4 batch through the intake for 2 new RoutineFlowUITests (confirm applies + journals;
  hold declines). All suites green 2026-07-05.
- **On-device pending:** the real watch→phone v4 round trip + a real band-top session
  producing the card (rides the end-of-P6 build 17).

### P6 Phase 2 — "Export to Claude" context packs ✅ IMPLEMENTED (2026-07-05, on `p6`)
The invested path made first-class: engine-agnostic packs = prompt + scoped context +
response-format, clipboard → Claude app today, a future Claude-API `CoachEngine` consumes
the same packs unchanged.
- **`ContextPackComposer` (AdaptiveCore/Coach/ContextPack.swift, pure).** Six use cases
  (`programDesign / checkIn / mealPlanning / plateau / constraintRework / returnFromBreak`),
  each with a scope preset; `ContextPackScope` = routines (all/subset) · fitness snapshot ·
  progression-journal window (30/90d) · recent meals; `includesHealthData` drives the
  disclosure. **Response format forks:** the three import-capable cases end with the
  exchange vocabulary + schema rules (same contract as `primingPrompt` — replies come back
  through the validated ImportRoutinesSheet → graft path untouched); check-in/meal-planning/
  plateau explicitly ask for prose (honest about what the app can ingest). Sections reuse
  `RoutineExchange.exportJSON` + `CoachContextBuilder.progressionSummary`; the journal
  section renders Phase 1's reasons + effort ("Goblet Squat 10 → 11 reps — clean session
  (effort 5)", declined entries say "[held by me]"). `HealthSnapshot`/`NutritionDigest` are
  plain value types — nil fields render as omitted lines (N6), all composition unit-tested
  on macOS.
- **Phone plumbing (thin):** `HealthSnapshotBuilder` (new HK reads — VO2max ml/kg·min per
  the calibrator, resting HR, respiratory rate, weight + 30d delta, our-bundle workout
  frequency 90d, `daysSinceLastWorkout(windowDays:)`; deferred-contextual auth, `toShare:
  []`, every field independent); `NutritionDigestBuilder` (loops `recorder.intake(on:)`,
  recurring sellers only). Phone Health share-usage string broadened in both pbxproj
  configs.
- **UI:** `ExportPackSheet` (use-case cards → scope toggles incl. per-routine checklist →
  **always-visible includes-line** → pinned Copy/Share bar; builds the pack at export time
  with a progress state); `HealthExportDisclosureSheet` — one-time, plain-words,
  Oura/Whoop-register, gates only health-inclusive exports (UserDefaults flag; per-launch
  under `-uiTesting`). Entry: claudeMenu → "Export to Claude…"; plus a quiet dismissible
  **return-from-break card** on WeekView when `daysSinceLastWorkout ≥ 10`.
- **Testing:** 432 package tests (11 new ContextPackTests: every case renders, JSON-ask
  only on import-capable cases, scope subsetting, nil-field omission, journal window,
  nutrition section, includes-line honesty); RoutineFlowUITests 7/7 (2 new: disclosure →
  copy → no-second-disclosure; health-free scope skips disclosure). XCUI gotcha recorded:
  SwiftUI Menu items surface by LABEL, not accessibilityIdentifier.
- **On-device pending:** real HK aggregate values in a pack; an actual paste-into-Claude
  round trip (user judgment on pack quality); the broadened Health prompt.

### P6 Phase 3 — Watch quick-log ✅ IMPLEMENTED (2026-07-05, on `p6`)
Meal logging reaches the wrist. The phone stays the brain (the model never runs on watch —
the existing split); the watch gets dictation in, one glanceable confirm out.
- **First live WC channel.** `WCMessageCodec` quick-log channel v1 (`Key.quickLog`, one
  version constant, `QuickLogMessage` envelope discriminated inside the blob:
  request/draft/confirm/outcome — `Connectivity/QuickLog.swift`). Reachable path =
  `sendMessage` round trips (watch `sendQuickLog`/`confirmQuickLog`, `isReachable`-guarded,
  error → nil); phone implements `didReceiveMessage:replyHandler:` (empty reply = "couldn't
  draft", the watch's honest fallback trigger). Offline = `transferUserInfo` of the raw
  request (same pre-activation buffering as progression); `didReceiveUserInfo` now demuxes
  quick-log vs progression by payload key.
- **`QuickLogService` (package, headless).** identify → resolve via the standard pipeline
  seams; holds what it drafted so confirm records EXACTLY the numbers the wrist showed;
  commit mirrors `MealLogController.commit`'s durability contract (enqueue-all → record →
  remove; `saved` true only when every write confirmed). Deliberately not the controller —
  its phases present phone UI, and a watch log must never pop a phone sheet.
  `MealPipelineProvider.sharedQueue` is now ONE queue per launch (controller + coordinator
  + review UI; two instances over one file would hold stale copies).
- **Pending-REVIEW, never auto-commit.** `PendingMealQueue.PendingItem` gained
  `needsReview`/`sourceText` (tolerant decode; pre-P6 rows = retry rows);
  `resumePending()` skips review rows. Phone `QuickLogCoordinator` (@Observable) surfaces
  them as **WeekView cards** ("From your watch — needs review" — deliberately the hub, not
  buried in FoodDayView; also rendered on the empty state for meal-only use); tap → the
  NORMAL typed-capture confirmation via `beginCapture(typedText:, preferredDate:)`; commit
  clears the row (cancel keeps it). **First UNUserNotificationCenter use:** one
  non-repeating nudge ~4h after arrival ("Meal waiting for review"), deferred-contextual
  auth at first arrival, denial degrades to the card alone, cleared when nothing waits.
- **Watch UI.** `QuickLogView` behind a `QuickLogTransport` seam (live | scripted):
  TextField (dictation/scribble) → "Looking up…" → draft (name · **kcal hero** ·
  provenance line · ✓/✗) → "Logged" only after the phone confirmed the write; unreachable
  → "Save for iPhone" (queue) → honest "finish it there" state. Entry: a quiet
  `fork.knife` toolbar door on the routine launch picker. **`-simulateQuickLog`** forces
  the flow on a canned transport — the only way to see it without hardware.
- **Testing:** 444 package tests (12 new: codec round-trip/version-reject/demux,
  QuickLogService draft/commit/decline/failed-write/replay-safety/offline-park,
  resumePending-skips-review, pre-P6 row decode); MealFlowUITests 16/16 (new:
  `-seedNeedsReview` → review card → standard sheet → commit clears); watch unit suite
  green; both targets build.
- **On-device pending — SUPERSEDED by the always-pending rework (next section).** The
  original list (live `sendMessage` feel, draft/confirm on the wrist) validates a deleted
  flow; the current hardware checklist lives in the "Phase 3 rework" section below.

### P6 Phase 3 rework — quick-log goes always-pending ✅ FIXED (2026-07-06, on `quicklog-always-pending`)
Build-17 field report: spinner comes and goes for minutes (watchOS wrist-down suspension made
it flicker), then the lookup "fails" and offers the phone fallback — with the phone paired,
locked, in a pocket. **Root cause:** the live path ran the entire lookup ladder
(FoundationModels identify + Parallel Search w/ 30s URLSession timeout + adjudicator)
*synchronously inside the phone's `didReceiveMessage` reply handler*; a locked, backgrounded
phone is throttled far past the foreground <10s, WCSession's opaque reply deadline expires
first, and the watch reads `errorHandler` as "unreachable". The watch itself runs no model —
that hypothesis was checked and excluded.
- **Fix (user-decided):** the pocket case IS the primary watch-logging scenario, so the live
  round trips were removed rather than budgeted. `QuickLogView` is now `.input → .saved`
  ("Saved for iPhone" in under a second, no spinner, no failure branches);
  `QuickLogTransport` shrank to `queueOffline` only; `sendQuickLog`/`confirmQuickLog` are
  deleted from `WatchConnectivityManager`. Every log rides `transferUserInfo` into the
  existing pending-REVIEW flow (card + notification + normal confirmation sheet on tap).
- **Compatibility:** wire format untouched (quickLog codec stays v1 — the park is exactly the
  old offline path). The phone's `handleLive` is KEPT and commented as build-≤17 watch
  compatibility; delete once always-pending watches are the installed floor.
  `QuickLogService.draft`/`commit` + their package tests stay (that path's brain).
- **Considered and deferred:** (a) park-first + live upgrade with a bounded resolver budget —
  unverifiable benefit in the pocket case; (b) background prewarm on userInfo delivery
  (same identify/resolve calls started at arrival, review sheet seeded with finished
  results, estimate-grade ones re-resolved in foreground) — clean isolated follow-up, no
  wire changes needed, deferred by user choice. Lookup happens on card tap, foreground speed.
- **Review hardening (same day, code + UI/UX review passes):** (1) the pre-activation
  `pendingTransfers` buffer (now the quick-log's ONLY channel, also carries progressions)
  **persists to disk** (`pending-transfers.plist`, injectable URL, load-at-init,
  hand-to-WCSession-before-clear = at-least-once) — an app death can no longer discard a
  meal the wrist already confirmed (N6); covered by new `WatchPendingTransferTests`.
  (2) Review cards gained their only non-committing exit: long-press → "Dismiss — don't
  save" (the wrist no longer previews drafts, so junk dictations land on the phone;
  context-menu precedent from the food rows) — covered by
  `testWatchQuickLogReviewCardDismisses`. (3) Card polish: relative dictation-time line
  (items pool for days by design), `Theme.info` stroke so "waiting on you" reads against
  the passive Food row, VoiceOver reads the card as one element. (4) Watch subtitle made
  the user the actor ("Review it on your iPhone to finish logging" — passive "it'll be
  looked up" over-promised automation). (5) `QuickLogTransport` (one closure post-rework)
  dissolved into a plain `queueOffline:` param. (6) Blue-outside-workout documented as the
  deliberate info-accent exception on `WatchTheme.recover`. Stale live-path docs fixed
  (`QuickLogHandling`, codec key, `QuickLog.swift` header, this file's Phase 3 list).
- **On-device validation (replaces the Phase 3 list):** dictation input feel; phone locked
  in pocket → "Saved for iPhone" within ~1s; review card (with timestamp) appears exactly
  once, tap → lookup at foreground speed → commit → Health write, card + notification
  clear; long-press dismiss; cold-launch quick-log before activation completes still
  reaches the phone (the persistence fix); 4h notification fires while something waits.

### P6 Phase 4 — Entry refresh / alternates ✅ IMPLEMENTED (2026-07-05, on `p6`)
The "wrong item / wrong size" fix: the edit sheet's "Look up again" now also surfaces the
OTHER defensible matches as pickable rows.
- **One model call, multiple candidates.** `CandidateAdjudicator` (refines
  `ExcerptAdjudicator`): the same single pass over the same excerpts reports up to 3
  distinct adjudicated matches (first = best) — never raw excerpts in the UI (unadjudicated
  numbers would violate N6). `MealResolver.resolveWithAlternates` engages it **opt-in
  only** (`resolve` keeps the lean single-answer call — the heavier schema never taxes
  everyday lookups on the 4K on-device model); dedupe by (name, kcal), cap 3; alternates
  are transient, never persisted on `MealEntry`. Every non-search rung stays single-answer
  by construction (stated number, printed label, barcode product, estimate).
- **Production:** `GenerableLookupCandidates`/`GenerableLookupCandidate` mirrors (order
  preserved, hollow rows dropped at the funnel, provenance graded per candidate);
  `FoundationModelsAdjudicator` conforms. **Scripted:** `Script.alternatesByName`
  (name-keyed — a rescan builds a fresh-id item) + `ScriptedAdjudicator` conformance; the
  `-simulateMealScan` demo scripts cola size/variant candidates.
- **UI:** `EntryEditSheet` renders "NOT THIS? PICK ANOTHER MATCH" rows (name · provenance ·
  kcal) after a re-lookup; picking adopts the candidate wholesale (name + number +
  provenance preview, recorded on Save through the existing `recorder.replace` path).
- **Testing:** 449 package tests (5 new `MealResolverAlternatesTests`: dedupe/cap,
  plain-resolve-never-runs-candidates spy, empty-fallthrough, stated-no-alternates,
  scripted name-keyed rescan); `MealSchemaDriftTests` +1 (candidates funnel);
  `testEditRescanReLooksUp` upgraded — the scripted ladder now FINDS the item and the test
  picks the 20 oz variant end-to-end (its old "estimate" expectation was an artifact of the
  id-keyed scripted gap). On-device pending: candidate quality/dedupe from the real model.

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

**P1.5c — unmissable cues, cadence compliance, recover-blue (post-build-6, not yet shipped):** Real-run feedback: the single walk tap vanished under footstrike and a glance misread amber WALK as RUN. Fixes: (1) **transition haptics are now triple bursts** ~350ms apart (`HapticManager.burst` — run `.notification`×3, walk `.directionDown`×3; at running cadence at least one pulse lands between footfalls); (2) **cadence-verified compliance** — `WalkComplianceMonitor` (AdaptiveCore; grace 8s to decelerate, stale-gap aware, re-nudge every 6s capped at 3/walk — never nags, Q5) detects "still running after the WALK cue" from the same CMPedometer stream as warmup detection; the manager exposes `gaitMismatch`, replays a two-pulse walk nudge, and `WorkoutActiveView` throbs the WALK word/arrow + the zone bar (`ZoneBarView(emphasize:)`) until the feet comply. **Design decision: color stays the instruction** (green=run/amber=walk, the learned language); compliance is signaled by *motion*, never by re-mapping hue — a "green when aligned" scheme was considered and rejected because it would make green ambiguous between "run" and "correct". Only the overdoing direction nudges (bias toward backing off — never prod a tired user to run harder). (3) **Walk phase is now cool sky-blue `#3EC5FF`** (`WatchTheme.recover`/`recoverField`): green↔amber was the glance-failure axis (sunlight, motion blur, red-green CVD); warm=effort/cool=recover, cyan-leaning so it never reads as strength's royal blue. Amber keeps its gradient jobs (zone-ladder threshold, strength rest ring); easing adaptation cues are recover-blue too. (4) **Experienced runners are respected by design**: after the 3-nudge budget + 10s the monitor *accepts* continued running — the screen calms, haptics stay quiet, and the walk is counted as `walksDefied` (SessionSummary/RunSessionOutcome) so its dragged-out recovery is excluded from the cap-based struggle signal (`isClean` uses `walksHitCap - walksDefied`) — running through walks can never regress the seeds. (5) **Top-row hierarchy fixed**: the workout clock was grey and sat in the same corner as the unremovable system clock ("two clocks" misread). Now `SessionClockView` (stopwatch-glyph-anchored, full white weight, mirroring `HeartRateView`) sits top-LEFT, HR top-right, "n of N" stays quiet center — glyphs identify each number before it's read.

**P1.5b — zero-config adaptation + instant end (build 6):** No experience selector, ever — the app observes: (1) **cold start** — an uncalibrated run card silently reads 90d of running workouts + latest VO2max at first session start (`FitnessCalibration` pure mapping / `HealthFitnessCalibrator` HK plumbing; `RunCard.seedsCalibrated` one-shot flag) → continuous / 5-min-interval / 90-120 default seeds; (2) **in-session evidence gate** — a walk ending at the recovery floor (`fastRecoveries`) unlocks run extension for the rest of the session (comfort alone never extends under HR lag; demonstrated recovery does); (3) **progression** — strong sessions jump two notches, a run sustained ≥1.5× the seed *snaps* the next seed to `longestRunSeconds`, and ending during an extended run isn't a bail. **Instant end:** the summary appears the moment the workout stops (engine data); HealthKit finalizes in the background, distance/avg HR fill in, and `HealthSaveState` drives an honest "Saving… → Saved to Health" line (same fix in the strength manager). The summary shows a quiet "Next run: …" line when seeds move.

**P1.6 — cleanup / launch-prep (senior review pass):** Fixed before P2: (1) **Claude round-trip no longer wipes run progression** — `RoutineStore.importRoutines` grafts existing run-card id/seeds/`seedsCalibrated` onto imported cards (the exchange schema still deliberately omits seeds); (2) **continuous plans target the block, not the raw seed** (a 3600s calibration sentinel made every continuous run read as a bail and regress the fittest tier); (3) manager races hardened — `isBeginning` reentrancy guard (double-tap Start can't spawn two HKWorkoutSessions), `sessionGeneration` token (a slow HealthKit finalize can't resurrect old totals into a new session), `finalizeTask` exposed as the deterministic test seam (yield-loops deleted); (4) `StrengthWorkoutBackend` merged into `WorkoutBackend` (one protocol, P2 gets HR signals for free); strength gained `HealthSaveState` (honest Saving→Saved) and the RestView back-to-back identity fix; `BlockFailedView` is no longer a dead end (Skip/End); (5) phone: activation-complete re-sync (first-install watch emptiness), CalendarService re-anchors only on schedule *change* (was erasing series history every launch), RoutineDetail commits against the store copy (stale-draft revert), MiniStepper is a VoiceOver-adjustable element with test identifiers; (6) progression polish — snap gate compares the seed the user *ran with*, regress never shortens a long walk seed, stale-HR walks record no recovery (N6), `RunSeeds.factoryDefault` is the single seed constant. **Design system captured in `docs/DESIGN-PRINCIPLES.md`** — hold every new screen (P2 strength redesign first) to it.

**Known deferred (P2 kickoff list):** move strength rest/hold timers from view `@State` into `StrengthSessionManager` (tick-driven, adaptable, testable — the P2 rest-adaptation enabler); `StrengthSessionOutcome` + `StrengthProgressionPolicy` mirroring the run three-layer pattern (engine counters → summary → outcome → policy); sequence-block handoff still starts the next `HKWorkoutSession` while the previous finalizes (recoverable now via BlockFailedView, but await the finalize handoff properly); extract the duplicated calibration+outcome code in `RunSessionContainerView`/`RunBlockView` into a shared launcher.

### P2 — Adaptive strength ✅ IMPLEMENTED (sim-verified; on-body pending) — evidence-based, zero-config
Strength now adapts like the run side, grounded in citable research (citations live in code comments):
- **Double progression** (`Engine/StrengthProgression.swift`): reps climb +1 per clean session through each exercise's band (8–12 compounds, 10–15 isolation — Schoenfeld dose-response; 12–30 bodyweight; holds 15–120s ±5s); topping the band converts to a load step (+5 lb compound / +2.5 lb isolation ≈ the ACSM 2009 Position Stand's 2–10%; stricter than NSCA's 2-for-2 rule by construction). Tri-state hold-is-default: advance needs a fully clean session (all sets ≥ prescription, <2 unrecovered rests, not ended early, no manual change to that dimension), ease needs ≥2 sets short by ≥2 reps / manual weight lowering / early bail. Manual ± overrides fold into the base and always win. Rep bands + weight steps + rest seeds are `ExerciseLibrary` metadata (`ExerciseKind.reps(repRange:seedWeight:)`, `weightStepPounds`, `restSeedSeconds`) — zero per-card config, and P3's AI-built routines inherit progression for free.
- **Rep truth via the Digital Crown**: the glance's rep hero IS the result — starts at the prescription, crown-adjusts down/up before "Done set" (zero friction when the prescription was hit). Every set lands in a `StrengthSetRecord` (prescribed vs completed, actual weight, rest recovery).
- **Adaptive rest, honestly bounded** (`Engine/RestRecovery.swift`): rest is *time-based per the evidence* (≥2 min compounds — Schoenfeld 2016/Grgic 2017; 60–90s isolation/beginners — de Salles & Simão 2009; PCr resynthesis, the true driver, is unobservable — Harris 1976). HR recovery (Cole 1999, same construct as the run side) only refines within a band: floor max(45s, ¾×seed) — never above the seed; cap min(seed+60s, 180s). Rest cards carry an `adaptive` toggle (default on; routines codec v5). No HR → exactly the authored timer (N6). The rest screen is the new signature: a strength-blue recovery ring fills as HR falls (falling bpm is the hero), READY haptic (double burst — distinct from the run triple), 2s grace → auto-advance; fixed/no-HR rests render the classic amber time ring (blue=recovery fills, amber=time drains, never both — one variable, one channel).
- **Manager is hybrid tick + user-driven** (`StrengthSessionManager`): sets user-paced, rests/holds manager-ticked (autoTick seam, per-set peak HR, `RestRecoveryModel`); holds record actual seconds (auto-complete or Done-early). Summary gains Sets + "NEXT TIME" progression notes (the quietly-perceivable adaptation moment). Progression syncs via `ProgressionUpdate` (+`holdSeconds`, progression codec v3) through the existing no-ping-pong path.
- **Deferred**: IMU/archetype heuristics (original P2 idea — set-outcome + rest-recovery covers the need without motion-classification risk; revisit post-P3), HR-zone-governed circuit/"cardio-strength" mode, bodyweight harder-variation suggestions (P3's AI can propose). On-body validation of thresholds pending next real workout.

### P3 — AI routine building (phone) ✅ IMPLEMENTED (sim-verified on the scripted engine; real-model on-device validation pending)
The native trainer conversation replacing the RoutineExchange copy-paste loop. Subtle by design — invoked flows, not a chatbot tab:
- **The seam (`AdaptiveCore/Coach/`)**: `CoachEngine`/`CoachSession` protocols — messages in, `CoachEvent` stream out (`textDelta` / validated `proposal` / `finishedTurn`) — the `WorkoutBackend` pattern lifted to AI. Engines are swappable (`CoachEngineProvider`): production is **Apple FoundationModels** (`FoundationModelsCoachEngine`: **`PrivateCloudComputeLanguageModel` default** — Apple's server model, 32K ctx, free tier, no keys; on-device `SystemLanguageModel` fallback; honest `CoachAvailability` reasons otherwise). A Claude-API / user-key / Gemini-via-Firebase engine is another conformance — nothing downstream changes. **Note: the earlier "cloud Gemini" phrasing here was wrong** — PCC runs Apple's own foundation model; Apple's Siri-Gemini deal is internal, and developer Gemini access is a separate Firebase `LanguageModel` conformance. `CoachMessage.Content.image` is the reserved P4 (multimodal) extension point.
- **Three intents**: `.buildNewPlan` (equipment → starting point → goals → days intake), `.reviseRoutine(id)` (name kept stable so the store's name-merge grafts progression back), `.reviseAll` (whole week; import can't delete — removal stays a manual act). `CoachPromptBuilder` (persona + vocabulary grouped by `Equipment` + exchange card rules + honesty rules), `CoachContextBuilder` (exports routines as exchange JSON + renders earned progression as read-only prose — the model sees seeds, structurally can't write them).
- **Every proposal passes the pinned path**: model output → `@Generable` mirror DTOs (`GenerableRoutinePlan`, `@Guide`-constrained to library slugs) → exchange JSON → `CoachProposalValidator` → `RoutineExchange.importRoutinesDetailed` (drops counted, surfaced honestly in the UI) → user confirms in `ImportRoutinesSheet` → `store.importRoutines` (graft invariant untouched). The model proposes via a `propose_plan` tool call (`ProposePlanTool`) when it judges intake complete; validation failures return corrective text to the model, not an error to the user.
- **UI**: `CoachChatView` sheet (dominant element = current coach message, history recedes; streaming folds without reflow; failures retry; unavailable state points to the manual loop). Entry points: WeekView sparkles menu ("Plan my week" / "Rework my routines" + the manual Claude items retained under "Manual (Claude app)" as fallback), empty-state quiet secondary CTA, RoutineDetailView "Ask the coach".
- **Deterministic testing**: `ScriptedCoachEngine` in the package (unit tests drive `CoachConversation`); phone `-simulateCoach` launch arg runs the same script for demos and `CoachFlowUITests` (intake → proposal → apply → week screen). Library expanded to ~36 movements with `Equipment` tags (barbell/kettlebell/bands/pull-up bar/machines) so the equipment intake has teeth. **Phone deployment target is now iOS 27.0** (FoundationModels' `LanguageModel` abstraction needs it).
- **Pending**: real-model behavior on device (sim can't grant Apple Intelligence) — persona quality, tool-call reliability (fallback design: explicit `respond(generating:)` on "Draft" if tool-proposing is flaky), PCC quota/latency feel.

### P4 — Calorie tracking (phone) ✅ IMPLEMENTED (sim-verified; on-device spike + validation pending)
Spec: `docs/calorie-tracking-spec.md` (C1–C7 binding). Identification + retrieval, never photo
guessing; Apple Health is the record (C5 — no private food store). Implemented in one pass
(slices 0/A/B/C/D), all suites green in the sim:
- **The seam (`AdaptiveCore/Nutrition/`)**: `MealPipeline` — a *sibling* of `CoachEngine`,
  deliberately non-conversational (three async funcs: `identify` stages 1–3 / `resolve` stage 4,
  fresh context per item / `estimate` stage 5). `CoachMessage.Content.image` stays reserved;
  images travel in `MealCapture {barcodes, ocrLines, imageData}`.
- **The lookup ladder (`MealResolver`, CQ1/CQ3 resolved free-first)**: rungs injected as
  protocols, cost-ordered — (1) barcode → **Open Food Facts** REST (keyless, no LLM);
  (2) **Parallel Search MCP** (`search.parallel.ai/mcp`, keyless, plain URLSession JSON-RPC —
  no MCP framework) → one PCC structured call adjudicating excerpts; (3) agentic tool loop
  (`web_search`/`fetch_page` FoundationModels Tools + SwiftSoup→`ReducedBlock`→`PageReducer`
  §5 context discipline, PDFKit for PDFs) — **wired but ships `nil` until the LookupLab spike
  justifies it**; (4) honest estimate range. A parsed nutrition label short-circuits the whole
  ladder as `.verified` (`NutritionLabelParser` — deterministic, no model). The resolver never
  throws to the UI; the bottom rung always answers. `ProvenanceGrader` encodes C3
  (seller-domain → verified; aggregators → database — the spike showed aggregators dominate
  even for `site:` queries, so *database* is the normal good case).
- **Flow state (`MealLogController`, @Observable)**: capture → identify → confirm → commit;
  generation-token guard; sequential post-commit fan-out with honest per-item statuses
  ("Looking up…" → "Saved" only after the recorder confirms — N6); deferred-contextual Health
  auth at first Log; `PendingMealQueue` (the only file — in-flight rows deleted on write
  confirm, C5) resumes interrupted lookups at launch.
- **Health as the record**: `HealthKitNutritionRecorder` (first phone HealthKit code +
  entitlement) writes `HKCorrelation(.food)` with provenance/source-URL/range/quantity in
  metadata; daily line reconstructs entries from Health queries; estimates store the midpoint
  scalar with the range in metadata (ranges re-render as ranges in the app, C3).
- **UI**: `MealCaptureView` (VisionKit DataScanner — live barcode auto-fires with zero shutter
  taps; still → Vision OCR), `MealConfirmationSheet` (checkbox rows, inline rename, qty, C4
  tap-only chips with pre-selected defaults, one Log CTA, **no kcal pre-commit** — lookups run
  after Log, §5), `DailyIntakeLine` on WeekView (quiet glyph-anchored line, one reserved status
  slot, hidden until first use — C6), `TodayEntriesSheet` (swipe-to-delete = Health delete).
  Plate photos → deterministic fallback draft (inline-nameable + portion chips) → estimate
  range. `CaptureMealIntent` (Action Button/Siri/Shortcuts → camera); widget extension +
  LongRunningIntent/Live Activity deferred to the next build.
- **Testing**: `-simulateMealScan` (scripted pipeline + in-memory recorder; receipt / barcode /
  label / plate demo captures) — the sim path, used by `MealFlowUITests` (5 tests, serial).
  ~53 new package tests (codecs, reducer, grader, ladder, label parser, controller);
  `MealSchemaDriftTests` + `SwiftSoupBlockParserTests` in the phone unit target.
  **SwiftSoup 2.13.6** = the project's first remote SPM dep (exact-pinned, phone target only;
  AdaptiveCore stays zero-dependency).
- **`LookupLabView` (`-lookupLab`)**: the CQ1 spike instrument — ~10 real items × each rung
  independently. **SPIKE RUN 2026-07-03 on the user's iPhone 17 Pro (iOS 27.0) — CQ1 closed:**
  - **barcode → OFF: 2/2, ~0.3s** — flawless.
  - **search+adjudicate (on-device model): 8/10, ~4.3s/item** — every chain/deli item
    resolved with plausible kcal + honest sources (Starbucks graded *verified* — the search
    hit starbucks.com itself). The 2 misses were **transport, not model**: instant
    `DecodeError` on consecutive items = keyless-tier rate limiting under a 10-item burst
    (client now retries once with a fresh session + 700ms backoff; real per-meal usage
    doesn't burst like the lab).
  - **agentic tool loop: 0/9 → 1/9 across runs (~36s avg)** — a tool loop's transcript
    (instructions + schemas + tool results + turns) cannot reliably fit the local model's
    fixed 4,096-token window; the one success (Wendy's, 7.2s) proves the mechanism, the
    other eight overflowed. **Verdict: rung 3 ships disabled (`agent: nil`); revisit only
    when the PCC grant lands (32K).** Confirmation run (round 3, after budget tightening +
    rate-limit retry): barcode 2/2, search+adjudicate 8/10 @ ~5.3s (misses: one dropped
    network connection + the homemade item that *should* miss), agentic 1/9.
  - **Two hard-won platform facts:** (1) instantiating `PrivateCloudComputeLanguageModel`
    without `com.apple.developer.private-cloud-compute` is a **fatal error**, not
    `.unavailable` — and the entitlement is a *gated Apple grant* (Small Business Program,
    <2M downloads; request at developer.apple.com/private-cloud-compute). `PCCEntitlement`
    guards every touch in BOTH the P4 pipeline and the **P3 coach** (which would otherwise
    have crashed on first device use — spike caught it). (2) All context budgets must be
    sized to the *running* model (`ExcerptBudget.onDevice` 3,600 chars vs `.privateCloud`),
    reduced query-aware by `ExcerptReducer` (keep item-term/nutrition lines only).
  - User applied to the Small Business Program 2026-07-03 (the PCC prerequisite; the PCC
    access request itself follows at developer.apple.com/private-cloud-compute). On grant:
    re-add `com.apple.developer.private-cloud-compute` to the phone entitlements — PCC
    (32K + reasoning) then engages automatically via `PCCEntitlement.isGranted`.
- **Pending on-device**: LookupLab coverage numbers; real UPC → Apple Health write; receipt
  OCR→extraction quality; salad-benchmark timing (<10s, C1); HealthKit auth prompt;
  HKCorrelation delete semantics; DataScanner capture quality.

### P4.1 — Food UX expansion (build 8) ✅ IMPLEMENTED (sim-green; shipping as build 8)
First-real-use feedback (no camera-less logging, no backdating, no in-app history/edit, no
target) answered in one build. All on existing seams; AdaptiveCore still zero-dep.
- **Food day screen** (`FoodDayView`, pushed from the hub's daily line — deliberately NO tab
  bar): `‹ Today ›` day pager (Calendar math, forward-disabled-at-today), **calorie gauge**
  as the dominant element (`CalorieGaugeView`: one ring, one variable = consumed/target;
  over-target = full ring + one tint shift to gradient-amber + plain "230 over" — the
  consciously amended C6, see spec §3), quiet active-energy line (informational only — fixed
  budget by decision), meal-grouped entries (`MealSlot`, hour-auto-assigned, metadata
  `AFCMeal`), tap-to-edit (`EntryEditSheet` → `recorder.replace` = delete+rewrite; kcal edits
  honestly become `.userStated` "your number"), context-menu **Log again** (`relogged()` —
  fresh identity, re-slotted), "n kcal from other apps" honesty footer, Scan + Type buttons,
  first-run **target sheet** (`TargetSetupSheet`: Mifflin-St Jeor suggestion from Health body
  data via `HealthKitBodyProfileSource` — any missing datum → manual entry, never a silent
  constant; user override always wins; stored in `CalorieTargetStore` UserDefaults — a
  setting, not food data).
- **Typed/dictated entry**: "Type it instead" pill on the capture screen + Type on the Food
  screen + **`LogMealIntent`** (Siri: "Log a meal" → dictate; one-shot parameter fill where
  the new Siri manages it). Deterministic pre-pass strips **stated calories**
  (`StatedCalorieParser` — trailing clause only; the stated number wins as the new
  `.userStated` ladder rung above even printed labels) and **date/meal words**
  (`TypedDatePhraseParser`: yesterday/last night/for lunch…); the model only normalizes
  spelling/branding and can never touch either.
- **When-row** on the confirmation sheet: meal chips (auto-defaulted, manual choice sticks) +
  Today/Yesterday/picker date control, clamped to the past; **receipt printed dates**
  (`ReceiptDateParser`, deterministic + sanity-clamped) prefill it, labeled "From the capture".
- **`NextWorkoutIntent`**: Siri answers "when is my next workout" from
  `RoutineStore.nextOccurrence()`, no app foregrounding.
- **Widget extension** (`AdaptiveFitnessWidgets` — the project's first app-extension target):
  two static small/lock-screen tiles (Scan / Type) deep-linking `afcoach://log/scan|type`
  through the generalized `MealCaptureRequest` (same funnel as the intents; URL scheme in the
  phone's merged Info.plist).
- **Codable evolution guarded**: build-7 PendingMealQueue rows decode (custom `MealEntry`
  decoder derives the meal slot; fixture-pinned); `Provenance.userStated` is additive.
- **Roadmap: P5 = full Siri/Apple-Intelligence integration** — routines + meals as
  AppEntities, iOS 27 App Schemas, Spotlight semantic index, onscreen-context references,
  multi-turn follow-ups, watch-coordinated "start my workout". Build 8 deliberately shipped
  only the two intents.
- Tests: ~36 new package tests (parsers, target math, slots, Codable fixtures, recorder
  evolution, controller when-state) → 339 total; MealFlowUITests grew 5 → 10 (typed+stated,
  backdate, target+gauge, edit, log again).

### Build 10 on-device feedback fixes (2026-07-03, shipped in build 11)
First real-device meal-logging session surfaced three issues; all fixed:
- **Crash on Log (fixed)**: `HealthKitNutritionRecorder.requestAuthorization` had
  `HKCorrelationType(.food)` in its *read* set — correlation types are disallowed in
  authorization requests and raise `NSInvalidArgumentException` the moment the first commit
  asks for Health access (before anything was queued/written, hence "nothing logged" after
  relaunch). Correlations need no grant of their own; the contained quantity types carry
  authorization. The sim never hit it because `-simulateMealScan` uses the in-memory recorder.
- **Continuous flow surface**: the confirmation sheet now presents the moment identify starts
  (progress state), not seconds later — previously the typed/capture sheet closed into
  silence while the model ran. Identify failure is a new `Phase.failed` shown in-sheet with
  Try Again (was: silent drop to idle with the error invisible).
- **Numbers before Log (supersedes C2's "no calories on confirmation")**: user verdict from
  on-device use — seller/calories/source are needed *before* confirming, particularly to
  adjust them. `MealLogController` now pre-resolves checked items sequentially while the
  confirmation screen is open (`resolutions`, epoch-guarded invalidation on rename/answer);
  each row shows "460 kcal · Open Food Facts"-style number+provenance (or "Looking up…"),
  tappable to override → `statedFacts`/`.userStated` (macros kept, same semantics as the
  post-hoc edit). A checked-set total shows once every number is in. Commit records exactly
  what the screen showed (no re-lookup); §5's rule survives — unchecked items still never
  spend a lookup. ~6 new controller tests (incl. a counting-adjudicator reuse pin) → 355.

### Build 11 — senior-engineer review sweep (2026-07-03, whole project; shipped)
A four-area review (package nutrition / package engine+coach / phone / watch) surfaced and
fixed, all pinned by new tests where the seam allows (369 package tests):
- **Meal logging**: commit re-entrancy (double-tap Log recorded every item twice — now an
  `isCommitting` latch); the Log tap now queues ALL checked items up front (an abort
  mid-commit no longer loses unreached items); `statedFacts` + chosen meal slot survive the
  pending-queue round trip (a crash no longer replaces the user's number with a lookup);
  stale auth error cleared on success; itemStatuses reset per session; capture-date prefill
  clamped to now; resolve loops chain strictly sequentially (PCC-rate); rename drops the
  override's inherited macros; "Calories from Fat" can't parse as energy.
- **Recorder/HealthKit (phone)**: `observeChanges` closure API → `changes() AsyncStream`
  (the old one executed a fresh never-stopped HKObserverQuery per screen appearance); one
  lazy observer query fans out to auto-cancelling streams. Delete failures now surface.
- **Phone**: warm-start Siri/App-Intent routing read `@Published` during willSet and dropped
  the request (deferred one main-actor turn); Vision OCR continuation could double-resume
  (crash) — one-shot latch; coach proposal "Review & apply" now keyed per transcript entry
  (was: one apply hid the button on every later proposal); `afcoach://start/<id>` now
  navigates to the routine; range-estimate entries no longer silently become `.userStated`
  on unrelated edits; capture Cancel cancels an in-flight OCR forward; inline editors commit
  on focus loss; coach stream gains `textReplace` for snapshot rewrites.
- **Engine/coach (package)**: rest countdown no longer flaps ±60s on instantaneous HR
  (seed-based until the seed); a walk's recovery credit now leaks across signal dropouts
  (N6 — was frozen); `importRoutines` matches names folded (trimmed/case-insensitive — the
  graft contract the coach prompt promises); `CoachConversation.cancel()` clears the
  streaming slot + bumps the turn token; exchange decode failures in our own schema surface
  as `malformedRoutines(detail)` instead of "isn't JSON".
- **Watch**: see the watch-fixes summary in this section's companion commit — session
  recovery after a crash (recover-and-finalize), leaked-session guard on failed starts,
  zone/HR staleness expiry (N6), endCollection retry, complication invalidation on sync,
  effort-write timeout, pre-activation progression buffering, launch-request re-match.
- **Deferred knowingly**: record→remove at-least-once window (rare duplicate beats a lost
  meal — documented in commit()); watch context-vs-userInfo seed regression window
  (converges; needs seed versioning); expandedCards/WorkoutBlock identity traps documented
  instead of re-keyed; engine elapsed-clamp drift vs HKWorkout duration (deliberate,
  documented).

### Post-build-11 on-device feedback: typed seller extraction + graded lookup fallback (2026-07-03)
"chicken ceaser salad from salad works" logged with NO seller (the on-device model silently
dropped it) and a generic eatthismuch.com hit. Two changes, both user-directed:
- **`TypedSellerParser`** (package): trailing "from/at <seller>" clauses parse
  deterministically. Division of labor (refined after user review): the MODEL stays the
  primary seller extractor (branding, spelling, domain — and the only reader of
  receipts/labels; its `sellerName` guide was receipt-biased "as printed", likely the real
  root cause of the drop); the parser's candidate now goes INTO the typed prompt as a hint
  the model confirms/corrects/rejects, and code floors on it only when the model returns no
  seller (accepted trade: omission ≫ deliberate rejection from a small model; a wrong
  seller is visible+editable, a dropped one silently degrades the lookup). Wired in both
  typed paths; blocklist covers home/preparation sources ("from scratch/a mix/powder/…");
  last-marker-wins ("deli counter at Wegmans" → Wegmans).
- **Graded adjudication fallback** (user decision): source preference in strict order —
  seller's own site → this seller's item in a database/aggregator → a clearly comparable
  GENERIC dish when the seller publishes nothing (many restaurants don't) → only then fail
  to the estimate rung. Previously a seller match was all-or-nothing: no seller data meant
  skipping a usable generic number and landing on the wide estimate range.
Pinned: TypedSellerParserTests (7 cases), typed-seller controller test, prompt-ladder pin
in ExcerptReducerTests.

Second feedback round (same session):
- **`MealEntry.seller`** (additive Codable + AFCSellerName/Domain HK metadata): the seller
  now survives to the day rows ("Saladworks · verified · saladworks.com") and the edit
  sheet. `Provenance.detailLabel` names the actual source everywhere — the bare word
  "database" answered nothing.
- **Edit sheet: restaurant field + "Look up again"** — edit name/seller and re-run the
  ladder (`MealPipelineProvider.makeResolver()`, scripted in the sim); the fresh
  facts/provenance record on Save unless the user types over the kcal (→ `.userStated`,
  macros kept). This is the "fix the seller, find MY salad" loop.
- **Day pager: tap the title on a past day to jump back to Today** (was: page one day at a
  time). "Trends in Health" now tries `x-apple-health://browse/nutrition` (undocumented but
  community-established; unrecognized paths degrade to just opening Health — verify the
  room actually opens on device).
→ 379 package tests; MealFlowUITests 12 (rescan flow + title jump).

### P5 — polish deep dive ✅ IMPLEMENTED (2026-07-05, ships as build 16)
Six parallel audits (motion, tokens, haptics, states, accessibility, code polish/missed
areas) over both targets, then one implementation pass. No new features; no behavior
changes without a pinning test. What shipped:
- **One motion vocabulary.** `Theme.Motion` (phone) / `WatchTheme.Motion` (watch):
  `settle` (easeInOut 0.28 — the app's dominant curve, absorbing the 0.2/0.25/0.3 sprawl),
  `snap` (easeOut 0.15 — direct-manipulation ticks; retired the watch's `.snappy`),
  `gentle`/`gentleLinear` (0.6 fills — gauge, rest/hold rings), `pulse` (the reserved
  compliance channel), and phone-only `gesture` (the swipe-row spring — a spring is earned
  only where a finger was) + `slide(reduceMotion:)`. **Reduce Motion gap closed**: FoodDayView
  (day slide → opacity, toast, swipe springs) had ZERO RM handling; WeekView's scroll scale
  and the adaptation banner's scale component now degrade too. Bare `withAnimation`/
  `.default` resets are all explicit tokens now.
- **A deliberate phone haptic vocabulary.** `Theme.Haptics` — commitTick (lighter rigid,
  arm-only)/capture/success/warning/selection — replacing three ad-hoc `.medium` impacts.
  Added the missing conventional moments: success on relog/save/commit, warning on the
  no-undo delete + failures, selection tick on day changes. (Watch vocabulary audited clean —
  everything already routes through `HapticManager`.)
- **Token compliance.** Watch: ~20 `.secondary` → `WatchTheme.textSecondary` (two grays for
  one role, sometimes in the same file); `zoneTempo` token for the last raw zone-ladder hex.
  Phone: `Theme.info` decouples the coach/import "UPDATES" chrome from the learned `recover`
  instruction hue (same value today, no longer structurally shared); `Theme.heat` (the amber
  the gauge duplicated); `Theme.metricNumber` (the 34pt kcal hero font, was pasted twice);
  radius scale `radiusInset/Card/Hero` (12/18/24) settling the 12-vs-14 panels and the
  three-radius chat bubbles.
- **States.** Watch first launch: empty-store-before-first-sync now shows "Syncing from
  iPhone…" (10s fallback to the true empty state) instead of falsely asserting "Create a
  routine on your iPhone" (N6) — `WatchConnectivityManager.hasReceivedInitialContext`,
  pinned by 4 new WatchSyncStateTests; nil-summary-at-complete got a labeled "Wrapping up…"
  with a Done exit after 5s (principle 13 — was an exit-less bare spinner); forced-session
  spinners labeled "Starting…"; meal confirmation sheet's default branch can no longer
  render a dark void; long routine names clamp on the watch launch screens + phone cards.
- **Accessibility.** DailyIntakeLine had the build-15 container bug (bare identifier on a
  stack swallowing the total/camera buttons) → `.contain`; labels on the day chevrons,
  coach send, capture cancel; the confirm sheet's rename tap-target is now a real VoiceOver
  button; decorative glyphs hidden; caption+tertiary stragglers under the Theme's 13pt floor
  promoted to secondary (incl. two honesty strings); UpNext hero wraps at 2 lines instead of
  shrink-then-truncate.
- **Missed-areas findings fixed** (from the code-polish audit): **dark mode is now declared
  to the OS** (`INFOPLIST_KEY_UIUserInterfaceStyle = Dark` — light-mode users used to get a
  light launch frame/system chrome around the forced-dark app; the five per-sheet
  `preferredColorScheme` dupes deleted); **iPhone-only portrait** (was `1,2` + full iPad/
  landscape, entirely undesigned); **AccentColor asset populated** with the emerald (was
  empty → system-blue fallback in system surfaces); target sheet's numberPad got the Done
  toolbar (the trap EntryEditSheet had already fixed); error-copy retry phrasing unified
  ("… Try again."); WeekView's large title is declared intentional; ExerciseInfoSheet +
  TypedEntryView present at `.medium` detents; the one raw `print` → os.Logger.
- **Code polish.** FoodDayView structural read post-three-gesture-rewrites: `dayPager`→
  `dayHeader` + stale swipe/anchorDay/simultaneous-gesture comments fixed, leftover
  `@Bindable`s dropped, day-fetch logic deduped (`DaySnapshot.fetch`), and **SwipeableRow +
  PressableCardStyle extracted to `Views/Components/SwipeableRow.swift`** (self-contained,
  zero coupling). Zero TODO/FIXMEs, no dead types found (diffed against build 14).
- **Deferred knowingly**: settings surface (P6 decision), String Catalog adoption (do
  before P6 adds strings), MealCaptureView material-over-camera contrast hardening
  (scene-dependent; needs on-device judgment), rest-ready vs exercise-change haptic
  similarity (250ms vs 150ms double `.notification` — judge on-body).
→ Verified: 387 package, 68 watch unit (4 new), phone unit + all three UI suites serially.

### Post-15 gesture settlement (2026-07-05, on the tree — rides the P5 build 16)
Build 15's zoned hybrid also failed on-device ("janky, not premium") — the user's verdict
ended the day-swiping experiment entirely. Three iterations bought this settled grammar:
- **Chevrons + tap-title-to-today are THE day navigation** (no swipe anywhere). The owned
  directional slide stays (past enters from the left), and a **per-day snapshot cache +
  neighbor prefetch** means an incoming day slides in populated (fixes: the active-energy
  line looked frozen mid-transition because the incoming page rendered nil active kcal
  under an identical "Trends in Health" link).
- **Rows swipe Notification-Center style** via a custom `SwipeableRow` (native
  `swipeActions` = unstylable full-bleed slabs, List-only): short drag parks a
  card-matched button (same 18pt continuous corners/surface, tinted icon+label, 8pt gap);
  the button STRETCHES with the finger; ≥180pt arms a haptic tick and release commits.
  Leading = log again, trailing = delete → the no-undo confirm. One row open at a time;
  tapping anywhere closes it instead of opening the editor.
- **Gesture-attachment finding (hierarchy-dump-verified):** inside the ScrollView+Button
  stack, `.gesture` AND `.simultaneousGesture` both silently lose the recognizer race —
  the drag never fires. `.highPriorityGesture` + 18pt minimum distance + a first-movement
  horizontal latch is the working recipe (taps still reach the Button, vertical scrolling
  stays native — pinned by the edit/menu/swipe tests together).
→ MealFlowUITests 15/15 (swipe test drives a deterministic coordinate press-drag; XCUI
flicks can outrun the recognizer). UNRELEASED: ships with the P5 polish pass as build 16.

### Build 15 — hybrid gesture split (2026-07-05, from on-device build-14 feedback)
The user hit build 14's pager conflict in the flesh (rows can't swipe; SwiftUI's pager
animation direction felt backwards and isn't controllable). Chose the hybrid deliberately
(rows-win was recommended; trade-offs discussed):
- **The TabView pager is GONE.** The summary zone (date header + gauge + active-energy
  line) is now a fixed, non-scrolling band that swipes between days via our own
  `DragGesture` (≥50pt, horizontal-dominant) — so the transition is ours: swiping right
  brings the previous day in **from the left** (calendar convention). ALL day changes
  (chevrons, title-tap, toast-tap, swipe) funnel through one `changeDay(by:)` →
  consistent `.asymmetric` slide everywhere. Swipe commits on release (no finger-tracking
  offset yet — noted follow-up if it feels abrupt on device).
- **Row swipe actions restored and WORKING** (no pager to steal them): leading = Log
  again, trailing = Delete → the no-undo confirmation. Tap → edit sheet and long-press
  menu unchanged. Day content fetches inside `FoodDayContent` so the outgoing day keeps
  its numbers while sliding away.
- **A11y gotcha worth remembering:** a bare `.accessibilityIdentifier` on a SwiftUI
  stack half-registers and can swallow child buttons from the accessibility tree (it hid
  "Set a daily target" from XCUI — and would have from VoiceOver). The fix is
  `.accessibilityElement(children: .contain)` + identifier.
→ MealFlowUITests 16 (swipe-days retargeted at `meal.day.summary`; swipe-to-delete now
confirms the delete end-to-end). Split test loop used throughout (fix→verify ≈ 3 min).

### Build 14 — Food-screen UX repage (2026-07-05, from the user's sr-designer review)
The user flagged the day screen as clunky (chevron-only paging, long-press-only actions);
a full design review found more; everything identified shipped:
- **Days page by horizontal swipe** (`TabView(.page)` inside the pushed screen; the system
  back gesture keeps its ~20pt leading edge, so both gestures coexist). Only the visible
  page ±1 is realized (365-day span, placeholder elsewhere — no eager Health fetches).
  Chevrons stay as the discoverable/accessible path; tap-title-to-today stays.
- **Gesture-grammar decision (verified, not assumed):** List `swipeActions` are DEAD inside
  a `TabView` pager — the pager consumes horizontal drags on rows (a failing UI test proved
  it). Removed by design rather than shipping a sometimes-firing affordance. The grammar is
  now: horizontal = time, tap = edit sheet (full action set — Edit/**Log again today**
  (new)/Delete), long-press = context menu (**Edit added** — it was missing while tap did
  it), plus `PressableCardStyle` press feedback so rows read as tappable at all.
- **Relog never teleports.** Log-again used to yank `anchorDay` to today mid-browse; now it
  stays put, badges the new entry, and (from a past day) shows a tappable "Added to Today"
  toast (2.5s, tap = jump home).
- **Past-day backfill works as intended:** Scan/Type from a browsed day prefills the
  when-row with THAT day (`beginCapture(_:preferredDate:)` in core; a capture-carried date —
  receipt print, typed "yesterday" — still outranks it; widget/Siri/daily-line paths pass
  nil). Kills the silent log-to-today surprise and gives empty past days a real backfill path.
- **The add bar is pinned** (`safeAreaInset`): Scan primary + a keyboard icon for typed
  entry — the screen's primary action no longer scrolls away under a full day.
- Naming reviewed ("Food" vs Diary/Log/Nutrition): **"Food" kept deliberately** (Fitbit/
  Samsung convention; "Meals" was the runner-up; "Diary" rejected for MFP-guilt register).
- **UI-test loop split** documented in CLAUDE.md: `build-for-testing` once →
  `test-without-building` per re-run (validated); `build-uitest/` git-ignored.
→ 387 package tests (+1: preferred-date prefill); MealFlowUITests 15 (+3: swipe-between-days,
past-day backfill, context-menu-carries-all-actions). Gauge/over-target state reviewed, no
change needed (amber, no alarm — C6 holds).

### Build 13 — typed-meal parsing fixes (2026-07-04, from on-device use)
User's real entry "Rising shine from bob Evans with scrambled eggs, salsa, 3 sausage links"
exposed two failures; both fixed and pinned by tests:
- **Mid-sentence sellers parse now.** Both extraction layers hard-coded "seller clause at the
  END of the text": `typedEntryInstructions()` told the model so (it obediently dropped
  "Bob Evans"), and `TypedSellerParser` took last-marker-to-EOL as the clause (8 words +
  digit → rejected, so no hint either). The prompt now says "from X"/"at X" names the seller
  *wherever it appears* and keeps menu-item names ("Rise and Shine") as the lookup key
  instead of rewriting the dish into ingredients; the parser bounds its clause at the next
  connective ("with"/"and"/comma) and stitches the sentence remainder back into cleanText.
  Division of labor unchanged: the MODEL is the primary extractor, the parser is hint + floor.
- **Clarification answers reach the model as text.** Tapping a question chip ("How many
  eggs?" → 3) re-resolved correctly but serialized as `item0=item0-opt1` in the lookup and
  estimate prompts — semantically invisible, so the number never moved. `QuestionAnswer` now
  denormalizes `questionPrompt`/`optionLabel` (optional fields; old pending-queue rows still
  decode, and the queue drops questions at commit so the answer must be self-describing) and
  both prompts render `promptDescription` ("How many eggs? 3").
- **Question chips hide once the user states their own number** — a stated override outranks
  any re-lookup (`nextUnresolvedItem` skips the item), so the chips were inert theater.
→ 386 package tests (6 new: 4 mid-sentence seller, 2 answer-rendering).

### Build 12 — design-review sweep (2026-07-03/04, both apps; user-selected all four batches)
A senior-designer pass over every screen (novice + experienced personas), then fixes:
- **Watch**: crown no longer auto-focuses the effort rater (scrolling the summary silently
  SET A RATING — the progression signal; now tap-to-focus with the crown glyph affordance +
  VoiceOver adjustable); rest renders inside the pager so End stays one swipe away
  (was: wedged for the whole rest); the interval timer counts DOWN
  (`intervalRemaining`, tests pinned) — "how much longer" is the glance answer; crown rep
  cap raised to max(30, 2×prescription) so overshoots (progression evidence!) record.
- **Meal flow**: commit bar (total + Log) pinned via safeAreaInset — it scrolled away on
  big receipts; Log disabled while any checked item is still looking up (never commit an
  unseen number; bounded by the ladder's always-answers guarantee); stable CTA label;
  reserved quantity-stepper slot; rename pencil affordance on item names; shutter now
  freezes the frame + haptic + "Reading…" during OCR (zero-feedback tap read as a miss);
  typed pill moved clear of the shutter; camera-unavailable gained Open Settings.
- **Routines/coach**: routine RENAME (detail view — name is the coach-merge key);
  exercise library search; builder back-swipe guarded by a discard dialog (silently lost
  the whole card stack); unscheduled routines allowed (empty repeat days verified safe);
  ImportRoutinesSheet brought to parity with the chat proposal card (NEW/UPDATES badges,
  days, "replaces N cards — progression carries over" diff, pinned Apply); coach
  unavailable state gained "Build it yourself" → manual builder; "Draft the plan now" is
  a real chip; run notation humanized ("5 warm · 20 run · 5 cool").
- **Hub/day (earlier in the sweep)**: gauge caption shows kcal LEFT (was a duplicate of
  the target); meal-section subtotals; delete = confirm-first everywhere; keyboard Done;
  week strip shows DONE checks read back from Health (`WorkoutWeekHistory`,
  workoutType read rides the meal-auth prompt; facts not streaks); bottom "New routine"
  CTA removed once routines exist; day-title tap jumps back to Today;
  `x-apple-health://browse/nutrition` deep-link attempt.
- **Contrast pass**: provenance/"Looking up…"/prefill/honesty strings promoted from the
  lowest tier (caption2+tertiary) to legible secondary, per the Theme's own floor.
- Checkbox/effort VoiceOver labels + adjustable actions.
- **Cross-suite MealFlow flake ROOT-CAUSED** (supersedes the earlier "launch-storm timing"
  guess, and my first race hypothesis): the Xcode TEMPLATE UI tests were the poison —
  `Adaptive_Fitness_CoachUITestsLaunchTests` (`runsForEachTargetApplicationUIConfiguration`)
  leaves the Xcode-27-beta simulator's UI configuration wedged (`simctl ui appearance` →
  "unknown"), after which **fullScreenCover presentation silently fails app-wide** while
  sheets/navigation keep working — so every MealFlow test died at the capture cover
  whenever the full bundle ran (template suites run first alphabetically), yet every
  hand-picked suite combination passed. Both template files deleted (a launch screenshot
  and an unread launch metric; the real coverage is the three flow suites). MealFlow
  helpers also hardened while diagnosing (settle on sheet nonexistence, waited taps, one
  scan retry + explicit cover assertion) — kept, they make the suite honest about
  presentation failures.
Watch: 55 unit tests green (2 new); phone suites green serially; package 380.

### P4 original spec pointer (history)
Full product spec: **`docs/calorie-tracking-spec.md`** (read it first — it carries the P4
non-negotiables C1–C7, the staged LLM pipeline, open questions CQ1–CQ5, and §9 "Direction for
the planning session"). The one-paragraph version: **identification + retrieval, not photo
guessing** — scan receipt/barcode/label → identify seller → identify items → native
confirmation screen (checkable items; structured tap-to-answer questionnaire only when it
materially changes the number — never chat) → per-item web lookup preferring the
manufacturer's/restaurant's own data → write to Apple Health (`dietaryEnergyConsumed`, the
water-logging pattern; no private food store). Photo-of-plate estimation is an honest,
range-labeled fallback. Golden path ("salad benchmark"): widget → camera → snap → confirm →
saved, under ten seconds, zero typing. Reuses the P3 provider seam (`CoachMessage.Content.image`
was reserved for this). First spike: CQ1 — how the web lookup runs (app-side fetch + LLM
extraction vs a web-search-capable backend). Supersedes the original PRD's nutrition non-goal
(annotated there).

### Build 9 — Integration build ✅ MERGED to `main`, shipped as TestFlight build 10
Watch polish + Effort/RPE + roadmap integrations. (Shipped as build 10: build 9 bounced on an
ITMS-90626 Siri-description reject — App Intent descriptions can't contain "apple" — fixed by
rephrasing two start-workout intent descriptions.) Committed + verified:
- **Watch safe-area cutoff fix** ✅ — paged `.tabViewStyle(.page/.verticalPage)` children bled
  past the bottom safe-area inset; `ZStack{field.ignoresSafeArea();VStack+Spacer}` edge-slammed
  the bottom control into it (Simulator underrenders the inset → passed sim, clipped on
  hardware). Fix: `.pagedWorkoutBackground` = `containerBackground(_,for:.tabView)` on
  WorkoutActiveView/StrengthGlanceView/ExerciseDetailView/RoutineLaunchCard. **Screenshot-
  verified on Series 11 46mm + Ultra 3 49mm**; hardware confirmation is the user's.
- **Effort/RPE** ✅ — crown 1–10 skippable rating (`EffortRatingControl`) on both complete
  screens → writes `HKWorkoutEffortScore` (`relateWorkoutEffortSample`; HKWorkout retained past
  `end()`) AND feeds progression: `perceivedEffort` on the outcomes, `highEffortThreshold`
  holds an otherwise-clean advance / suppresses the run snap (never eases, never more
  aggressive — the subjective signal run v2's fatigue-blindness needed). Progression emits
  once on Done (a high rating can't retract an end()-time advance, so emission moved to Done).
  The "Next run"/"NEXT TIME" note previews the rating's effect live. 9 policy tests + watch
  integration test.
- **App Group foundation** ✅ — `group.com.memerson.Adaptive-Fitness-Coach` on phone+watch+
  widget; `RoutineStore.defaultFileURL()` → group container with idempotent one-time migration;
  widget target now links AdaptiveCore.
- **Siri App Entities (partial P5)** ✅ — `RoutineEntity`/`RoutineEntityQuery`; NextWorkoutIntent
  returns the entity; phone `StartWorkoutIntent` (→ points to watch); watch `StartRoutineIntent`
  + `WorkoutLaunchRequest` routes `SessionContainerView.chosen` straight into a routine's
  adaptive flow. Full CoreSpotlight index deferred.
- **Next-workout widgets + watch complications** ✅ — phone `NextWorkoutWidget` (systemSmall +
  Lock-Screen accessory) reads the App Group store's `nextOccurrence()` (nonisolated
  `RoutineStore.routinesFromDisk()` + static `nextOccurrence(in:)`); NEW watchOS widget-
  extension target `AdaptiveFitnessWatchWidgets` (Smart Stack + complication families) →
  `afcoach://start/<id>` → watch `onOpenURL` → `WorkoutLaunchRequest` → straight into the
  routine's adaptive flow. WorkoutKit scheduled compositions deliberately skipped (would hand
  tracking to Apple's app). Widget/complication *render* needs on-device confirmation; timeline
  + routing logic is unit-tested/exercised.
- **Deferred: Live Activities** (meal-lookup progress + pre-workout "Up next") — the one slice
  not built: `ActivityAttributes` must be shared app↔widget, which fights the file-system-
  synchronized groups (retroactive-conformance plumbing), and the value is marginal (the in-app
  "Looking up… → Saved" line already covers meal progress). Recommended as a focused follow-up.
- **Verified**: 350 package tests, phone unit, all phone UI suites (serial), 59 watch tests;
  safe-area fix screenshot-verified on Series 11 46mm + Ultra 3 49mm. On-device pass (effort
  write to Health, complication/widget render, Siri start, deep-link) is the user's.
- Decision recorded: hold TestFlight until the user validates the device-only integrations.

### Platform integration backlog (Apple-API leverage — researched at WWDC26/iOS 27, 2026-07-02)
Candidates for riding the OS instead of building UI. Roughly ordered by value; the first two are effectively part of P4, the rest are their own mini-milestones:
- **App Intents (iOS 27) as the P4 capture spine** — a `CaptureMealIntent` gives widget / Lock-Screen / Action-Button / Siri entry for free; **`LongRunningIntent`** runs the post-confirm lookup past the 30s intent limit and **auto-presents progress as a Live Activity**. Part of P4 proper (see `calorie-tracking-spec.md` §7).
- **Live Activities (iOS 27)** — now propagate automatically to the **watch Smart Stack**, StandBy, macOS menu bar, CarPlay. P4 lookup progress first; later a pre-workout "Up next: Morning Run · starts 7:00" activity on scheduled days (quiet, dismissible — N-goals still bar in-workout chat).
- **Siri entity/intent schemas (iOS 27)** — contribute routines and logged meals to the **Spotlight semantic index** so the new Siri can answer "what's my workout today" / "log this salad" with attribution into our app, no phrase registration. Natural P5 candidate; pairs with the coach.
- **WorkoutKit scheduled compositions** — sync our scheduled routines into Apple's Workout app / watch Smart Stack as *launch surfaces* (deep-linking into our session, keeping our adaptive engine in-session — N2/N3 untouched). Would replace nothing; adds discoverability where users already look.
- **HealthKit workout-zone APIs (WWDC26)** — we already ride HR zones; the same surface now does **cycling power zones** → the cheapest path to a future cycling mode (the interval engine is already zone-generic: it consumes an `Int?` position).
- **watchOS 27 FoundationModels (PCC on watch)** — enables future on-wrist *setup-phase* intelligence (e.g. post-workout summary phrasing). In-workout AI persona remains a PRD non-goal; nothing here changes that.
- **Watch: monitor Workout Buddy** — Apple's own coaching layer gained pace/duration insights; no third-party API yet. If one appears, evaluate whether our haptic cues can register with it rather than compete.

---

## Roadmap — P5 → P6 → confirm-on-device (agreed with the user 2026-07-05)

### P5 — polish deep dive ✅ DONE (shipped as build 16 — see the P5 section above)
The bar was "well built, polished, professional" — refinement of what exists, both targets:
- **Motion**: one animation vocabulary (the Food screen now mixes springs and eases from
  three gesture rewrites); transition/duration/curve consistency app-wide.
- **Tokens**: spacing/typography audit against `Theme` on both targets — hunt hardcoded
  values and near-duplicate text styles.
- **Haptics**: the phone's new swipe-commit impact should join a deliberate vocabulary
  (the watch's is semantic already), not accumulate one-offs.
- **States**: every loading/empty/error state gets happy-path care.
- **Accessibility**: VoiceOver labels/actions, Dynamic Type at both extremes, contrast.
  (The `.accessibilityElement(children: .contain)` bug caught in build 15 suggests
  siblings exist — audit bare identifiers on containers.)
- **Watch glanceability** re-check against N5.
- **Code polish**: `FoodDayView` deserves a structural read after three gesture rewrites;
  dead code, naming, comment accuracy; no behavior changes without a test.
- Two micro-fixes that need the user + device (see confirm-on-device): the Health
  deep-link URL probes land here once confirmed.
- Ships as **TestFlight build 16** (includes the unreleased post-15 gesture settlement).

### P6 — feature iteration (reshaped 2026-07-05 after build-16 real-model verdict)
**User verdict from on-device use: the on-device Apple model is "just usable enough" for
meal-NLP parsing and falls down hard on routine building/customization — while the manual
prompt-export → Claude-app → JSON-import loop works well. P6 therefore builds ON the
export loop; the PCC-dependent items are PUSHED (see below).**
- **Progression visibility: journal + structural confirms** (design agreed 2026-07-05).
  (1) A phone-side progression journal — every seed change, newest first, WITH its reason
  ("Fri · Bicep Curl 12→13 reps — clean session"; "Tue · run 2:00→2:30 — fast recovery,
  effort 5"). `ProgressionUpdate` already carries the change; persist the *why* alongside
  and render. (2) A lightweight confirm gate ONLY for structural moves — load step-ups
  (band topped) and run-shape graduations (walk shrink / continuous) — as a phone card or
  pre-workout watch prompt; declining = hold (already a first-class policy outcome).
  Micro-steps (+1 rep, +15s) stay automatic-but-logged: N3 intact, no nagging (Q5).
- **"Export to Claude" context packs** (the big one). Engine-agnostic packs = prompt +
  scoped context + response-format instructions; clipboard→Claude is today's transport, a
  future Claude-API `CoachEngine` consumes the same packs unchanged. Use cases (the
  personal-trainer catalog): program design/revision **with fitness snapshot** ("for
  someone like me" — VO2max, resting HR, 90-day workout frequency, progression state);
  **the check-in** ("how am I doing / is this enough to lose weight" — adherence,
  progression trajectory from the journal, effort ratings, weight trend, intake vs target
  vs active energy); **meal planning from real habits** (meal records incl. sellers,
  target, macros); **plateau troubleshooting** (one exercise's history + rest-recovery +
  effort); **constraint rework** ("knee hurts / hotel gym" — the existing validated
  import path returns the reworked week, progression grafted); **return-from-break**
  (workout-gap detection can proactively suggest the export). Skipped honestly: form
  checks (no video), real-time coaching (N-goals).
  - **Scope picker**: per-export composable checkboxes (all/specific routines · fitness
    snapshot · workout history 30/90d · nutrition history), use-case presets, and an
    always-visible includes-line ("3 routines · 90-day snapshot · no meals").
  - **Disclosure**: one-time honest sheet on the first health-inclusive export ("copies
    your health data as text; whatever app you paste it into governs it from there —
    share with apps you trust"), Oura/Whoop-register, never scary; the includes-line
    persists on every export. The user performing the copy keeps this inside Apple's
    Health data rules (nothing leaves via API).
  - Build: `HealthSnapshotBuilder` (new HK reads: VO2max, RHR, respiration, weight —
    deferred-contextual auth like meals; aggregates only, never raw sample streams),
    pack composer + per-use-case templates, scope UI. Reuses `CoachContextBuilder`'s
    routine-JSON + progression prose and the untouched validator→import→graft path.
- **Watch quick-log + complication.** TextField (dictation/scribble free on watchOS) →
  `sendMessage` to the phone → the SAME identify/resolve pipeline → compact draft back →
  glanceable confirm/cancel on watch → phone commits through the standard funnel. The
  model never runs on watch; the phone is the brain (existing split). The on-device
  model stays HERE — meal NLP is the one job it's usable for. **Offline (phone
  unreachable): queue raw text via `transferUserInfo`, honest "will look it up when
  your iPhone is nearby", items land in the phone's pending-review flow — NOT
  auto-committed numbers nobody saw.** The pending flow needs real design (what if the
  user never opens the phone? reminders?) — the user flagged this exact risk.
- **Entry refresh / alternatives.** When the lookup matched the wrong item/size: from an
  entry, "pick the next best" candidate or try a different source. Seed: the edit
  sheet's "Look up again" already re-runs the ladder; this extends it to surface
  alternates instead of only the top hit.

**Pushed (PCC-dependent — awaiting the grant, and re-evaluate even then):**
- **Agentic rung 3** (FoundationModels tool loop for meal lookup) — the `AgenticLookup`
  seam + `LookupLabView` harness exist, `agent: nil` at both construction sites; needs
  PCC's 32K window (the 4K on-device window is the proven blocker, spike 2026-07-03).
- **FoundationModels coach for routine building** — stays wired behind the `CoachEngine`
  seam (`-simulateCoach` still drives the tests), but the Claude export loop is the
  invested path now; PCC might rescue its quality — judge when the grant lands.

### Confirm on device (user-assisted; blocked on being at the hardware)
- **Health deep links**: probe list for the Nutrition room (`browse/NUTRITION`,
  `DataType/HKQuantityTypeIdentifierDietaryEnergyConsumed`, `HealthTopic/…` variants)
  and Active Energy (activity/`HKQuantityTypeIdentifierActiveEnergyBurned`) — tap
  through once, hardcode the winners (graceful fallback already in place), and make the
  active-kcal line tappable.
- **LookupLab spike** (`-lookupLab`): measure rung coverage/latency on the real network
  → the rung-3 go/no-go.
- **PCC flow**: coach real-model validation (persona, `propose_plan`, latency) and the
  Small Business grant → server-model switch status.
- **Strength thresholds**: observational, by design — Friday's session looked right;
  keep using it and adjust from accumulated real workouts. No action item.
- The standing builds-13→16 on-device validation list (header).

## Open items / TODOs (carried forward)

- **Device-only verification:** real HR→zone→adapt loop, haptics feel, Action Button auto-start, run **and now the strength `HKWorkoutSession`** appearing in Apple Health (Traditional Strength Training), and the **Calendar event flow** (`CalendarService` needs full calendar access — the sim can't grant it reliably). The sim can't cover these.
- **Strength form demos** are SF Symbol placeholders (`FormDemo.symbol`). Replace with real static diagrams / tap-to-play animations later — purely a data + render swap, no model change (`FormDemo` already has `.diagram`/`.animation` cases).
- **TestFlight:** build **1.0 (6)** (zero-config adaptation + instant end) is **live for internal testing** (export compliance cleared; `internalBuildState: IN_BETA_TESTING`). The whole headless pipeline — archive → API-key export/upload → compliance — is documented in **`docs/TESTFLIGHT.md`**. Credentials live in the **git-ignored `.env`** (issuer id, key id, the *path* to the `.p8`, app/team ids); the key material is never committed or read. **Release only significant milestones** (a redesign, the end of a phase), not every commit. New builds now declare `ITSAppUsesNonExemptEncryption = NO`, so they skip the "Missing Compliance" stall.
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
3. `cd AdaptiveCore && swift test` should be ~350 green instantly. Full suites: watch scheme test (unit + UI, incl. the self-driving `-simulateStrength` E2E; ~59 watch tests) and phone `RoutineFlowUITests` + `CoachFlowUITests` (needs `-simulateCoach`) + `MealFlowUITests` (needs `-simulateMealScan`; 10 tests) — all phone UI suites **serially** (`-parallel-testing-enabled NO`) — plus the `CoachSchemaDriftTests` + `MealSchemaDriftTests` + `SwiftSoupBlockParserTests` unit targets. Safe-area layout is screenshot-verified on watch sims by UDID (Series 11 46mm `545DCE24…`, Ultra 3 49mm `824FF2AB…`).
4. **State: TestFlight build 16 (P5 polish + gesture settlement) released; the 5 lb weight-grid fix is on the tree unreleased (verified green, awaiting the user's ship-or-hold).** **NEXT: P6 — read the RESHAPED Roadmap section above first** (2026-07-05: the on-device model verdict demoted the FoundationModels coach; P6 = progression journal + structural confirms, "Export to Claude" context packs, watch quick-log, entry refresh/alternates; PCC items pushed). Also pending on-device validation by the user: watch cutoff on real hardware; effort score in Apple Fitness/Training Load; widget + watch-complication render; Siri "start workout"/"log a meal"; P2 strength thresholds on a real workout. **Queued/committed for the next upload:** phone-widget Mac opt-out (ITMS-90863 advisory). **Cleanest next feature:** Live Activities (deferred — see Build 9 section for the cross-target `ActivityAttributes` rationale). **On grant (if it lands):** Small Business Program → PCC access = re-add the `com.apple.developer.private-cloud-compute` entitlement; then re-judge the pushed items (agentic rung 3 flag-flip, coach quality) — do NOT auto-reinvest, the Claude export loop is the chosen path (see `[[p4-calorie-tracking]]` + `[[p3-ai-coach-design]]` memories). Deferred backlog (IMU heuristics, HR-zone circuit mode, snapshot tests, sequence finalize handoff, Claude-API/user-key coach engines + Settings backend picker, conversation persistence, full CoreSpotlight index) lives in the milestone/backlog sections above. `docs/DESIGN-PRINCIPLES.md` is binding on any new screen.
5. Releasing to TestFlight (significant milestones only): see **`docs/TESTFLIGHT.md`**.
