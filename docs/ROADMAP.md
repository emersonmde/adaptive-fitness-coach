# Roadmap — design-review remediation (2026-07)

The active roadmap, succeeding the completed P0–P6.1 phases. It converts the July 2026
design review (**`docs/design/DESIGN-REVIEW-2026-07.md`** — 511 verified findings across
watch + phone) into **six work milestones**, grouped by shared verification workflow —
each milestone's changes are exercised and screenshot-verified through one test surface,
so a milestone closes in one verification pass (a large one may span 2–3 sittings, but it
ships and verifies as a unit). M0 is an on-body pass that runs in parallel; M7+ is a menu
of big swings picked one at a time.

**How to use this file in a fresh session**
1. Pick the next unchecked milestone (sequenced; M0 is parallel-safe).
2. Read its linked sections of `DESIGN-REVIEW-2026-07.md` — finding IDs (B/W/P/S/T/§5/§6/§7)
   refer to that report, which carries the full evidence, file:line refs, and recommendations.
3. Resolve the milestone's **Decisions needed** with the user *before* coding — most are
   principle/spec amendments only the user can make.
4. Ship = tests green **and screenshots of every changed state reviewed** (standing process
   rule from build 21: UI-test-green is not visually-verified) **and** no regression of the
   report's §3 protect list (the run glance contract, reserved slots, the propose→reason→
   confirm funnel, honest-async summaries, estimate honesty, one-tap start are all binding).
5. Mark the milestone done here (checkbox + one-line outcome), update PROJECT-STATUS if the
   "NEXT" pointer moves.

**Global rules**
- T11 (stale doc comments) is not scheduled work: fix any listed stale comment whenever a
  milestone touches its file (WorkoutActiveView.swift:5, AdaptationBannerView.swift:8,
  WorkoutSequenceView.swift:7, ImportRoutinesSheet includes-line comment).
- Anything tagged `hardware-verify` ships its code-side fix only when the fix is sound
  regardless of the sim question (the report marks these); otherwise it waits on M0.
- Findings verdict `requires-principle-change` never ship silently — each is a named
  decision in the register at the bottom.

---

## Sequencing at a glance

```
M0 on-body verify ───────────── parallel; gates parts of M4 (AOD scope, End-guard design)
M1 trust & honesty      ← first: 2 of 4 blockers; all state/receipt fixes, no architecture
M2 app-wide sweep       ← mechanical: targets + type + copy + color, one screenshot pass
M3 adaptation legibility + mixed sessions  ← flagship + 4th blocker (shared components)
M4 watch session: resilience + self-sufficiency  ← engine work; wants M0's data
M5 food loop            ← phone food + watch quick-log + permissions
M6 phone surfaces: coach round-trip + IA/layout
M7+ big swings — menu, pick deliberately after M1–M6
```

M1 and M2 are independent of each other; everything else benefits from landing after M2
(the sweep touches the same files — merging later avoids conflicts).

---

## M0 — On-body verification & storyboard recapture *(parallel; mostly the user's wrist)*

*Sources: report §7 (full 36-item list), T12.*

- Walk §7 top to bottom on Series 11 (+ a 40–42mm check for size-floor items); record a
  verdict per line (real / sim artifact / can't-repro).
- Key gates produced: **End-Workout false-touch frequency** in sweat/rain (decides the B3
  guard design in M4), **actual AOD dimmed rendering** (scopes W11), whether the tinted
  state fields (#06180C/#061520) render at all on OLED, cue-vocabulary legibility
  (EASING/RECOVER/STRONG/GO → possibly collapse to two).
- Recapture the broken storyboard material (T12): phone 01/02 black frames (capture
  settle-wait bug), food-day first-use and loadFailed states.

**Done when** §7 has a verdict per line and affected milestones are re-scoped. No app code.

---

## M1 — Trust & honesty  ⟵ **start here (blockers B1 + B2)**

*Sources: H1.1 + H1.6 = B1, B2, P13, P27, T2, W1, W3–W5, W17–W20, P14, P23, W22, P3, P4, T5.*
*One verification surface: every failure/summary/settled state on both devices, forced via
`-simulate*` args and screenshot-reviewed.*

The app violates its own binding standard ("failure must not render as absence") at three
fabrication points, the end-early path fabricates celebration and poisons the comparison
baseline, and finished loops read as resets for want of cheap receipt states.

**Scope — honesty**
- **B1**: split `.failed` into `.failedToStart` / `.failedMidSession` (WorkoutSessionManager);
  mid-session death names what happened, shows elapsed time, points at what Health recorded.
- **B2**: failure-aware calorie gauge — em-dash consumed, suppress "N left" when `loadFailed`
  with no cache; retry adjacent to the gauge (FoodDayView).
- **W1/W3/W4/W5 + T2**: shared `WorkoutFailedView(cause:actions:)` — six start-failure
  findings in one vehicle. Retry primary and above the fold; permissions copy only for
  `.errorAuthorizationDenied`; "waiting" vs "confirmed empty" split on first launch; no
  bare eternal spinners.
- **W17/W18**: ended-early summary drops celebration grammar; hero shows elapsed, not "0:00".
- **W19**: gate the comparison pipeline on `endedEarly` (digest metadata) — aborts must not
  inflate "vs last run" or drag the 28-day baseline.
- **W20**: "Discard workout" on ended-early summaries under a threshold
  (`HKWorkoutBuilder.discardWorkout()`; default keep).
- **P13**: "Some didn't save" becomes a visual warning with tap-to-retry.
- **P27**: export includes-line reconciles against what actually composed.

**Scope — receipts & loop closers**
- **P14**: Confirm/Hold collapses in place to a one-line settled state linking the journal.
- **P23**: applied-card verdicts snapshot at apply time.
- **W22**: post-Done shows "Done today ✓ · Next: Thu" for a few hours; Start demotes to
  "Start again".
- **P3/P4**: today's missed workout stays up-next until day end; nil-aware RelativeWhen —
  no fabricated "Mon · 12:00 AM" (also fixes the widget path).
- **T5** reserved-slot violations: cue-pill height vs its reservation; effort-caption
  line-count jump under the user's finger; "Next run:" slot always reserved; coach input
  bar fixed height; Review-&-apply swap height.

**Decisions needed**: discard-threshold value (suggest < first run interval).
**Verify**: package tests (state split, endedEarly gate, nextOccurrence day-end); screenshot
every failure + settled state.

---

## M2 — App-wide mechanical sweep: targets, type, copy, color

*Sources: H1.2 + H1.3 + H1.4 + H1.5 = W10, W21, W24, W25, P5, P12, P19, P20, P22, P35,
P38, T8, P29, B3-minimum · S1, P36, T6, P1, P8 · S4, S5, T7, P6, P10, P15, P2 · T3, P41,
S6, W16, §5-P2, §5-P5.*
*One verification surface: no logic changes — a single grep-driven sweep + screenshot/AX
pass over every screen at default and AX sizes verifies all four strands at once. Large
(2–3 sittings) but each strand is S-effort items; ship and verify as one unit.*

**Strand 1 — touch-target & input floor**
- 44pt sweep via `contentShape` insets (the repo's QuantityStepper `-6` pattern): watch —
  skip pill W10, effort-stepper overflow W21 (label minWidth ~64–70, never shrink targets),
  weight chip W24, strength ± W25 (+ circle-fill contrast); phone — Confirm/Hold P5, camera
  pill P12, DayPicker + Edit Cards/Ask-coach P19, builder steppers P20 (+ hold-to-repeat),
  coach chips + send P22, WHEN/meal chips P35 (+ row spacing ≥ inset), "Type it instead" P38.
- **B3 minimum**: widen the End/Water-Lock gap, both pills ≥44pt (full guarded end → M4).
- **T8**: quick-log Save + phone Apply fire `success`; ± weight clicks (distinct tick at the
  seed); crown binding for weight; **2.5 kg grid for metric locales**; persist quick-log
  drafts on Close; effort-scale extent dots; one-shot crown hint; bolder direction arrow;
  minimum rest-ring arc; stepper direct entry; name-field autofocus; dirty-state discard
  confirms; copy-prompt toast not alert; collapse the sparkles menu's transport verbs;
  `commitTick` on live-committing schedule edits; optimistic portion re-scale.
- **P29**: PrimaryButton reads `\.isEnabled` — disabled CTAs stop glowing.

**Strand 2 — typography tokens & Dynamic Type**
- Display type scale (hero/metric/verb + weights) in **both** Theme enums; migrate the 11
  improvised `.system(size:)` call sites (S1).
- `@ScaledMetric(relativeTo:)` every hero number + the 168pt gauge frame (P36); no fixed
  frame clips scaled text; effort stepper fits 42mm at all sizes.
- T6 resilience: ScrollView/lineLimit/scaleFactor guards across the listed watch + phone
  views (share WhenRow's ViewThatFits helper). **P1**: phone empty state in a ScrollView.
  **P8**: proposal headlines never truncate the terms of the change.

**Strand 3 — copy rulebook + sweep**
- One noun: "budget" (S4). Effort in the coarse taught vocabulary everywhere (P15/S5).
  "Hold" → outcome labels (P6). Sentence case; "Done" never doubles as headline and button;
  one commit verb per flow; `shortTime()` one style; T7's full list (picker duration parity,
  "UP NEXT · TUE 6:30", "1 of 1" suppression, cooldown "Finishing…", "Added 2 routines…",
  "Keep for later", conditional footers, coach sheet Done-slot). First-run watch-orientation
  lines (P2, P10). Land a 10-line copy section in `DESIGN-PRINCIPLES.md`.

**Strand 4 — color/token paperwork**
- Mint `zoneLow`; neutral utility tint for Water Lock + quick-log chrome (W16); destructive
  never accent-tinted — fix P41 **and add the UI test** auditing `role: .destructive` under
  the global tint; neutral cancellation actions app-wide; final-5s countdown tints with the
  NEXT phase color; week-strip today-by-form; builder add-menu semantic icons; UpNextCard
  hexes promoted to tokens; S6 zone rungs → ~0.35–0.4 opacity.
- **Decisions needed** (write outcomes into the token files): §5-P2 run-green at-rest
  exception vs drop; §5-P5 heart-glyph exception (recommend keep + codify); amber
  "gradient jobs only" doc-text amendment.

**Verify**: one screenshot/AX pass over all screens at default + AX3 (axe AX dumps for
watch target sizes); grep sweeps; the new destructive-tint UI test; existing suites serial.

---

## M3 — Adaptation legibility + mixed-session completion  ⟵ **flagship + blocker B4**

*Sources: H2.1 + H2.3 = W13, W30–W34, P16, P17, T1, W23, W26, P7, §5-P3 · B4, W35–W39.*
*One verification surface: the three `-simulate*` session scripts end-to-end + codec tests;
mixed reuses the adaptation-note and summary components this milestone builds — grouping
them means the components are designed once for both.*

The differentiator is invisible at rest, and the flow combining the product's two halves
discards both payoff moments.

**Scope — the model change first**
- Versioned codec: `SessionSummary`/RunDigest persist the `AdaptationEvent` list (W13 — the
  engine already composes every sentence; today's only surface is VoiceOver). Summary
  renders one calm line per event instead of `Adaptations: 3`.

**Scope — watch strength legibility**
- NEXT TIME rows: direction ↗/→/↘ from the delta (W30 — ease currently renders as advance),
  from→to values (W31), truncation priority inverted (W32). Explicit ratings always
  acknowledged even on no-op (W33 — needs **§5-P3**). This-vs-last per exercise reusing the
  run side's honest-empty pattern (W34). Post-hoc rep correction on the rest card + one-time
  crown coach mark (W23). Override delta chip "+10 lb · saved for next time" + reset (W26).

**Scope — phone provenance**
- Routine detail shows live seeds with provenance for BOTH run and strength, linking the
  journal; silence when unchanged (P16, P17). Journal rows navigate to routine/session and
  state when a change takes effect (T1). Proposal in-card editability: tappable value →
  plate-increment stepper, journaled as user-adjusted (P7).
- **T1 minors**: picker adaptive-context line; warmup "Detected" attribution; cue-pill tap
  shows `event.message`; glossed "Recovery drop"; suggestion names its HR input; post-Done
  echoes the next-run promise; strength rests line; budget calibration change-marker;
  typed-clamp disclosure; auto/micro journal distinction.

**Scope — mixed sessions**
- **B4**: replace `SequenceDoneView` with a unified sequence summary stitching the standalone
  components — per-block ledger row (glyph · duration · headline stat · save state), the
  same adaptation notes, one effort rating for both blocks (W38).
- **W35**: HR pins top-right on every in-session screen (one HStack reorder; reported 4×).
- **W36**: handoff becomes an acknowledged beat — 1–2s transition card + `.success` haptic;
  home for per-block save status. **W37**: adaptation notes render in mixed.
- **W39**: per-block finalize tracking behind the save claims; honest per-part status +
  retry; fix the stale comment.

**Decisions needed**: §5-P3 (acknowledge explicit input on no-op — recommend yes).
**Verify**: codec round-trip tests (versioned!); direction-glyph unit tests; all three
`-simulate*` scripts screenshot-reviewed. Read `docs/ADAPTIVE-SYSTEM.md` before the codec.
**Feeds**: M7 Verdict summary and Ask-why build directly on this.

---

## M4 — Watch session: in-session resilience + self-sufficiency

*Sources: H2.2 + H2.6 = W11, W12, W14, W15, B3-full, W27–W29, T4 · §5-P1, W2, P9, C12-lite.*
*One verification surface: the watch session loop (`-simulateWorkout`/`-simulateStrength` +
axe) plus fresh-install launch; engine changes tested in the package. Wants M0's AOD and
false-touch data.*

**Scope — resilience**
- **W11 AOD**: `isLuminanceReduced` branch on the shared in-workout components — instruction
  + countdown bright, pulses suppressed, HR redacted (scope against M0's observed rendering).
- **W12 Reduce Motion**: static high-salience substitutes for all three compliance pulses.
- **W14 Pause/Resume**: first control on both pages; freezes `IntervalStateMachine` ticks
  (stop feeding deltas — the clock-free architecture makes this cheap); HKWorkoutSession
  pauses natively. Read ADAPTIVE-SYSTEM.md first; test-pin evidence freeze.
- **W15**: Water Lock flips the pager to `.metrics` before locking (one line).
- **B3 full**: guarded end per M0's data — hold-to-end (~0.8–1s fill, haptic) on BOTH run
  and strength, or instant end + resume-window pill. Never a modal confirm.
- **W27/W28/W29**: recovery ring vs countdown get different *forms* (ring = recovery only,
  linear bar = fixed time); HR-extension explains itself; rest card previews what's next.
- **T4 motion discipline**: heart glyph stops pulsing perpetually (static, or pulse = stale
  reading); pulse-precedence policy; suppress hot pulse while a cue shows; cooldown
  grace-gates the hot pulse and retargets the ladder.

**Scope — self-sufficiency**
- **§5-P1 / W2**: "Just run" primary on the empty state launching the default adaptive
  RunCard (the zero-routine path exists and is tested; only LaunchView withholds Start).
  **Requires the user amending N4's letter.**
- **P9**: structural proposals confirmable on the wrist post-workout (Confirm/Keep); phone
  card becomes fallback. Idempotent store writes.
- **C12-lite** (optional): pre-start stance line, silence on normal days (no ease-down tap —
  that's §5-P6, M7+ territory). Start-failure preflight at picker load.

**Decisions needed**: B3 guard style (M0 data); §5-P1 (N4 wording) — self-sufficiency
scope is blocked without it (resilience scope isn't).
**Verify**: engine pause tests in the package; session-loop + fresh-install screenshot pass;
hold-to-end feel is on-body.

---

## M5 — Food loop: friction, honesty, permissions

*Sources: H2.4 = P30–P34, P37, P39, P40, W6–W9, P11, P42, P43, P44–P46, §5-P4 partial.*
*One verification surface: the MealFlow UI suite (serial) + `-simulateQuickLog`/
`-simulateMealScan` + an action-count walkthrough (≤3 typed, ≤2 repeat).*

**Scope — friction**
- **P40**: typed meal commits from ONE surface in ≤3 actions (chips + Log on the typed
  sheet, estimate inline; parsed number visible pre-commit per spec §4.3; full sheet only
  for low-confidence parses/scans).
- **W8 recents**: 1–3 one-tap recent-meal rows on the watch via applicationContext;
  dictation becomes fallback. **W9**: auto-dismiss "Saved for iPhone" ~1.5s; actionable 4h
  notification. **W7**: echo the parked text, tappable to re-dictate. **W6**: wrap guard +
  shorter saved copy.
- **P11**: ≥2 parked logs collapse to one summary card → sequential review.
- **P39**: photo-library import (PhotosPicker → same still→OCR→classify path).

**Scope — honesty + permissions**
- **P32/P33/P34**: the estimate band survives aggregation — labeled midpoint at item level,
  "≈"/estimate-dot at day totals, stored range in the edit sheet.
- **P37**: "(tap to name it)" never reaches Health. **P30/P31**: fallback target mode gets
  the Health deep-link + preset scaffolding.
- **P43**: watch identity on the baton (applewatch glyph + "From your watch · <time>").
  **P42**: Delete leaves the nav-confirm slot → full-width hot footer row.
- **P44/P45/P46 + §5-P4 partial**: one Health ceremony at target setup; purpose-list consent
  copy in encounter order; notification ask becomes a user-initiated soft-prime on the
  review card; defer the target sheet's auto-auth until engagement (no spec change).

**Decisions needed**: none hard — §5-P8 (auto-commit inversion) is deliberately M7+ menu.
**Verify**: MealFlow serial + walkthrough + screenshots.

---

## M6 — Phone surfaces: coach round-trip + IA/layout/affordances

*Sources: H2.5 = P21, P24–P26, S3, C16-core, P28 · S2/§5-P9, T9, T10, P18.*
*One verification surface: the phone UI suites (serial) + a full phone screenshot pass —
both halves are phone-only view work with no engine surface.*

**Scope — coach round-trip integrity**
- **P21**: dedicated `requestDraft()` forcing the propose_plan tool path with committed UI
  state; one named-gap prompt if info is missing. Fix the sim script; production-model
  compliance is an M0/§7 check.
- **P24**: per-routine include checkboxes + tappable day chips + "Edit before applying"
  (operates on the validated payload — the pinned-validation invariant holds).
- **P25**: UPDATES rows render a collapsed before/after diff. **P26**: `buildNewPlan`
  grounds in routinesJSON + progressionSummary when the store is non-empty.
- **S3**: three-state watch-sync receipt at coach-Apply and routine detail.
- **C16-core**: exchange snapshots — in-flight node on "Send for review"; return diffs
  against the snapshot before the import gate (degraded form: badge the Import button).
- **P28**: includes-line moves into the pinned export bar.

**Scope — IA / layout / affordance**
- **S2 + §5-P9 decision**: 2–3-tab structure (Week/Food) **or** write single-stack
  minimalism into DESIGN-PRINCIPLES. The absence of the decision is the defect.
- **T9**: bottom-anchor the coach conversation; content-sized detents for one-number
  sheets; export sheet compacts so scope + includes-line co-render; collapse identical rest
  rows; builder card shows derived total + current seed; rounds before the list; one
  edit-row grammar; empty-state composition; library promotes the prescription line +
  contextual Add on the info sheet.
- **T10**: kill looks-tappable-isn't (glass time chip, "Next · Fri", "× 3 rounds"); give
  the tappable-with-no-affordance surfaces visible affordances (Up Next card, food entry
  rows, "2,200 left" target edit, dismiss-without-saving, library selection state, journal
  split from the sparkles capsule and labeled).
- **P18**: scroll-edge material behind the nav bar on routine detail.

**Decisions needed**: §5-P9 (tabs vs documented single-stack) — decide first; it shapes T9.
**Verify**: RoutineFlow/CoachFlow/MealFlow serial + phone screenshot pass.

---

## M7+ — Big swings (menu; pick one at a time after M1–M6)

Each needs a prototype + on-body validation before committing; feasibility/risk in report
§6. Recommended order:

- [ ] **Verdict summary / Debrief** (H3.1 = C6+C9+C15, HIGH feasibility, after M3). The
      summary's dominant element = what the engine decided and why, live-recalc with the
      effort dial; designed "Same plan — it worked" steady state; totals demoted; phone
      debrief decomposes named inputs. Gates: §5-P2 hue scoping (M2) + a deliberate on-body
      challenge to the P6.1 time-running-hero decision.
- [ ] **Adaptation in the OS's morning voice + zero-launch start** (H3.2 = C3+C1). Morning
      widget with the Layer-1 decision + reason; STEP UP confirms from a notification
      (needs **§5-P7**); Smart Stack scheduled-start card with honest staleness. Ship C3(b)
      first — lowest risk, highest leverage.
- [ ] **Decision inbox / thread home** (H3.3 = C10+C13+C14, MODERATE). One card anatomy for
      every pending thing; ledger lines for every number that moves; explicit baton
      lifecycle. Ship the degraded thread first; every segment needs distinct failed states.
- [ ] **Watch food loop inversion** (H3.4 = C8 reshaped; needs **§5-P8** spec change +
      explicit opt-in "Trust my watch logs"). Medium+ confidence parses auto-commit
      phone-side as editable provenance-labeled entries; wrist says "Logged" without
      promising a number.
- [ ] **Motion-sensed strength** (H3.5 = C7, R&D behind the archetype gate). MVP: motion
      ARMS a confirm; undo carries rep correction; go/no-go on on-body false-positive
      rates. No sim path.
- [ ] **Ask-the-coach-why** (H3.6 = C11, HIGH feasibility, gated on M3's provenance
      structs). A uniform quiet "why?" on every adaptive number; static chips are the
      floor; prose structurally grounded in the decision's actual inputs. Dominant risk is
      N6 — mitigation is structural.

**Banked what-ifs from §6.5** (attach to the nearest milestone when it opens): warmup
"ready ramp" (M4/Verdict), state-horizon edge border (M4 AOD), cooldown-as-landing (M4),
before→after interval strip (Verdict), session spine (M3-mixed follow-on), builder timeline
(M6), coach brief card (M6), week-strip proposal preview (M6), ghost-gauge onboarding /
uncertainty-native gauge / permissions ledger / kill-the-manual-kcal-fallback (M5
follow-ons), delete the new-routine sheet (M6 candidate).

---

## Decision register (user calls; resolve at the owning milestone)

| Decision | Report ref | Owning milestone | Recommendation in report |
|---|---|---|---|
| End-Workout guard style (hold vs resume-window) | B3, §7 | M4 (M2 ships the minimum) | Hold-to-end; measure false touches first (M0) |
| Run-green at-rest exception vs drop | §5-P2 | M2 | Resolve either way, in writing |
| Red heart glyph exception | §5-P5 | M2 | Keep + codify |
| Amber "gradient jobs only" doc text | T3 | M2 | Amend the contract text |
| Acknowledge explicit input on no-op (P12 amendment) | §5-P3 | M3 | Amend — keeps the rating channel alive |
| Ended-early discard threshold | W20 | M1 | < first run interval — **shipped as recommended (M1, 2026-07-15)** |
| Watch-seeded first-run routine (N4 letter) | §5-P1 | M4 | Amend — kills the dead end |
| First-use food interception (C6 amendment) | §5-P4 | M5 | Partial fix needs no change |
| Tabs vs documented single-stack | §5-P9 | M6 | Decide; absence is the defect |
| Crown-nudge / "Feeling rough?" (N1/N3 wording) | §5-P6 | M7+ (C12/C4) | Signal-not-tune amendment |
| Structural confirms outside the app | §5-P7 | M7+ (morning voice) | Amend with guards |
| Watch quick-log auto-commit (reverses 2026-07-06) | §5-P8 | M7+ (inversion) | Opt-in inversion; label as spec change |

## Milestone status

- [ ] M0 — On-body verification & recapture *(parallel)*
- [x] M1 — Trust & honesty (blockers B1, B2) — *2026-07-15: state split + shared
      `WorkoutFailedView`, failure-aware gauge, ended-early summary (neutral header, elapsed
      hero, W19 digest gate, discard-under-first-interval), done-today receipt, settled
      proposal receipts, verdict snapshot, includes-line reconcile, day-end up-next +
      nil-aware when, T5 slots. Discard threshold decided as recommended (< first run
      interval). New sim hooks: `-simulateStartFailure[Permissions]` / `-simulateMidFailure`.
      Not sim-forceable (deferred to M0 on-body/manual): B2 loadFailed visual, P13 warning
      visual, W22 done-today visual — all unit/UI-test covered.*
- [ ] M2 — App-wide sweep: targets · type · copy · color (B3 minimum)
- [ ] M3 — Adaptation legibility + mixed sessions (blocker B4, flagship)
- [ ] M4 — Watch session: resilience + self-sufficiency (B3 full)
- [ ] M5 — Food loop: friction · honesty · permissions
- [ ] M6 — Phone surfaces: coach round-trip + IA/layout
- [ ] M7+ — Big swings (menu above)
