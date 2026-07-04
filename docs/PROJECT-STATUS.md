# Project Status & Handoff

The single entry point for picking up this project. Read this, then `docs/adaptive-fitness-coach-spec.md` (PRD) and the design handoffs in `docs/design/`.

_Last updated 2026-07-03 (evening): **P0–P4 + the build-9 integration pass all on `main`**. **TestFlight build 10 is live** (`IN_BETA_TESTING`) — carries P2 + P3 + P4 + build-9 (watch safe-area fix, Effort/RPE→Health+progression, App Group, next-workout widgets/complication, Siri routine entities). Working tree clean. **Pending on-device validation (all ride build 10, the user's job):** watch cutoff on real hardware, effort score landing in Apple Fitness + Training Load, widget/complication render, Siri "start workout", P2 strength thresholds, P3 coach real-model. **Queued (committed, next upload):** phone-widget Mac opt-out (ITMS-90863 advisory). **Deferred:** Live Activities (cross-target ActivityAttributes vs. marginal value — see build-9 section). **On grant:** Small Business Program → PCC access = one-line switch to Apple's 32K server model for meal lookups + coach._

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

### Build 10 on-device feedback fixes (2026-07-03, uncommitted → next build)
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

### Build 11 — senior-engineer review sweep (2026-07-03, whole project)
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
4. **State: TestFlight build 10 is live** (P2+P3+P4 + build-9 integration). **Next is on-device validation by the user** (nothing more to build for it): watch cutoff on real hardware; effort score in Apple Fitness/Training Load; widget + watch-complication render; Siri "start workout"/"log a meal"; P2 strength thresholds on a real workout; P3 coach real-model (all three intents — persona, `propose_plan` reliability, PCC latency; the graft invariant is pinned by `RunProgressionTests`). **Queued/committed for the next upload:** phone-widget Mac opt-out (ITMS-90863 advisory). **Cleanest next feature:** Live Activities (deferred — see Build 9 section for the cross-target `ActivityAttributes` rationale). **On grant:** Small Business Program → PCC access = re-add the `com.apple.developer.private-cloud-compute` entitlement + flip the meal resolver's `agent:` non-nil → Apple's 32K server model (see `[[p4-calorie-tracking]]` memory). Deferred backlog (IMU heuristics, HR-zone circuit mode, snapshot tests, sequence finalize handoff, Claude-API/user-key coach engines + Settings backend picker, conversation persistence, full CoreSpotlight index) lives in the milestone/backlog sections above. `docs/DESIGN-PRINCIPLES.md` is binding on any new screen.
5. Releasing to TestFlight (significant milestones only): see **`docs/TESTFLIGHT.md`**.
