# Design Review — July 2026

**Scope:** full-app review, watch + phone (watchOS 27 / iOS 27), ~76 screens across 11 flows. 136 agents: 4 research briefs, 42 per-screen reviews, 11 flow walkthroughs, 8 cross-cutting lens audits, 4 redesign-ideation agents, adversarial verification of every finding. **511 findings survived verification.** Screen refs use storyboard filenames (e.g. watch `14-run-adaptation-easing.png` → "watch 14"). Effort tags: S/M/L. Verdicts: `confirmed` unless tagged `hardware-verify` or `requires-principle-change`.

---

## 1. Executive summary

This is a design-mature product with an unusual profile: the **hardest problems are already solved** and the **cheapest ones are the biggest remaining liabilities**. The in-effort watch screens are genuinely best-in-class — the glance contract (one dominant element, color-as-instruction, reserved slots, haptic-first) is executed with a discipline that exceeds Apple's own Workout app, and the propose→reason→confirm grammar (STEP UP cards, ImportRoutinesSheet, the live-recalculating effort note) independently matches the TrainerRoad/Garmin gold standard the research briefs identify as where the whole market is racing. The color-token system is the most disciplined audited in this review: zero system-color literals, documented exceptions, one off-token hex in the entire app.

The debt is concentrated in three places, and none of them require new invention:

**1. The differentiator is invisible after the fact.** In-session adaptation — the product's thesis — collapses to a bare `Adaptations 3` count on the summary; the `AdaptationEvent` sentences the engine already composes render nowhere but VoiceOver; strength seeds move on the phone with zero provenance; mixed sessions adapt in total silence. This is the canonical opacity-not-error trust-erosion event the adaptive-coaching research brief names, sitting directly on the product's core promise (N3, principle 12). The fix is mostly plumbing a model the engine already computes to surfaces that already exist. **Highest-leverage change in the review.**

**2. The app violates its own honesty standard at exactly three fabrication points.** A run that dies 20 minutes in gets "Couldn't start — Nothing was saved" (both claims false); a failed Health read renders a confident "0 of 2,200 · 2,200 left" calorie gauge; the mixed-session summary asserts "recorded in Health" with zero save-state tracking. Each is a direct N6 violation of the user's own binding standard ("failure must not render as absence"), each is S–M effort, and each sits at a moment where trust is unrecoverable if lost (the NRC end-of-run-crash lesson from the competitor teardown).

**3. The physical input layer lags the design's own reasoning.** End Workout is a single unguarded destructive tap directly below Water Lock — the control that exists *because* sweat fires false touches; there is no Pause anywhere; there is zero Always-On handling (the most common wrist state is undesigned); Reduce Motion deletes the compliance channel with no static substitute; and a scatter of sub-44pt targets sits precisely in the wet-finger contexts the codebase elsewhere explicitly designs for. One guarded-gesture pattern, one AOD pass, and one 44pt sweep close it.

Everything else — copy drift, token paperwork, Dynamic Type resilience, receipt gaps — is real but ordinary maintenance on an unusually sound foundation. The redesign concepts (§6) show where the product can go once the floor is fixed: the summary-as-verdict and OS-surface concepts are both high-feasibility and aim squarely at the differentiator.

---

## 2. Scorecard

Grounded in the lens summaries and finding digests; not grade-inflated.

| Dimension | Score | Justification |
|---|---|---|
| **Glanceability** | **4/5** | The in-effort screens meet the research's sub-second peek budget almost perfectly (one dominant element, linear encodings, zero mid-effort targets) — but zero `isLuminanceReduced` handling means the single most common wrist state (Always-On dim) is entirely undesigned. |
| **Hierarchy** | **4/5** | One-dominant-element holds across watch and phone (Up Next hero, dominant-current-line chat); deductions for the buried adaptive payoffs — the effort dial below eight stat rows, the journal behind an unlabeled glyph, the mixed summary that is only a checkmark. |
| **Color system** | **4.5/5** | The most disciplined two-tier token system audited: every semantic tokenized, exceptions documented in-source. Half a point off for two leaks that break the system's own written rules in its highest-stakes zone (Water Lock in walk-instruction blue mid-session; run-green quietly doing the rejected "success/grade" job on watch summaries). |
| **Typography** | **3/5** | The one untokenized design channel: zero Font tokens on watch, one on phone; 11 improvised display sizes; fixed-pt heroes (metricNumber 34pt, rep hero 50pt, verb 38pt) ignore Dynamic Type while neighbors scale, inverting hierarchy at AX sizes; the effort stepper mathematically overflows the 42mm canvas. |
| **Copy** | **3.5/5** | Unusually deliberate voice (verbatim promise echoes, one failure grammar) — but the calorie number answers to four names, "Hold" collides with the app's own exercise noun, raw "effort 6" leaks past the taught vocabulary, coach verbs drift mid-flow (Review & apply → Import → Applied), and Title/sentence case mix system-wide. All S-effort string sweeps. |
| **Accessibility** | **3.5/5** | Real craft where it counts (VoiceOver labels on custom controls, adjustable actions, CVD/grayscale-safe state pairs, AA-audited text tokens) — undercut by systemic gaps: no AOD pass, Reduce Motion deletes an information channel with no substitute, a scatter of sub-44pt targets, and fixed frames that break at AX type sizes. |
| **Flow coherence** | **3.5/5** | Standalone flows are strong and the confirmation grammar is learnable — but the mixed-session flow structurally collapses (skipped summaries, silent adaptation, no effort rating), post-confirm/post-Done moments reset instead of closing loops, and the two AI paths divide by mechanism instead of job. |
| **State honesty** | **3.5/5** | The paradox dimension: the architecture is best-in-class (three-state saves, honest async fill-ins, failure-not-absence in food day) *and* the review's worst findings are honesty failures — the mid-session-death copy, the fabricated calorie gauge, the unverified mixed save claim, the includes-line that can lie. The pattern exists everywhere; it was skipped at three load-bearing points. |
| **Adaptivity legibility** | **4/5** | Signal-in-motion / explain-at-rest matches the research's converged grammar point-for-point, and the effort-rating double-count guard is beyond any shipping competitor. Loses the point on one systemic gap: in-session adaptations are attributable for a 4–10s chip window, then vanish into a bare count with no Layer 2 anywhere. |

---

## 3. What's working (protect list)

Synthesized from the per-unit protects; these are the things fixes must not regress.

1. **The run glance contract, everywhere it was transplanted.** One dominant verb+countdown in the state color, glyph-anchored corner metrics placed away from the system clock, countdown-not-countup, zero mid-effort touch targets, linear zone ladder. Intact on warmup, intervals, cooldown, strength glance, and the mixed-session run block. Do not add elements to these screens.
2. **The reserved-slot discipline (principle 7).** Adaptation cue / Start Run pill share one fixed slot; the food line's trailing status slot; the run summary's height-reserved comparison slot; the gauge's 236pt slot. Layout never jumps. Every new state should inherit this pattern, and several findings are just places that didn't.
3. **The adaptation cue's structural mechanics** (watch 14): phase-bounded asymmetric lifetimes (10s easing linger vs 4s push flash), triple-redundant direction encoding (chevron + word + hue), correct Reduce Motion / VoiceOver degradation. Ahead of Apple's Workout Buddy.
4. **The propose→reason→confirm funnel, at every altitude.** STEP UP card (diff + named-inputs reason + calm Confirm/Hold, no expiry, no nagging), ImportRoutinesSheet (full-content preview, honest replaces-cost line, progression-carries-over reassurance), watch structural handoff ("confirm on iPhone"). Matches and slightly exceeds the TrainerRoad gold standard from the coaching brief.
5. **The live-recalculating effort control** (watch 20–21, strength NEXT TIME): rating in, consequence out, previewed before leaving the wrist; untouched suggestions never double-count into progression. The flow's single strongest trust mechanism.
6. **Honest-async summary architecture:** instant engine-owned hero, OS totals filling behind a truthful "Saving to Health… → Saved" line that never claims early (principles 11/N2/N6). The end-of-workout reliability posture the NRC crash reports prove is unforgivable to lose.
7. **The quick-log promise thread:** "Save for iPhone" → "Saved for iPhone" → "From your watch — needs review" → a notification naming both devices. Verb honesty documented as deliberate in-source. Cut its ceremony, never its contract.
8. **Failure-not-absence machinery in food:** failed Health reads render "Couldn't read this day — Try again," never an empty day; failed prefetches cache nothing. The user's binding standard, actually encoded.
9. **The estimate-honesty stack:** visible ranges ("350–600 kcal · estimate"), provenance labels, `.userStated` vs estimate distinction, kcalEdited guard, Log disabled while lookups are unresolved ("never commit a number the screen hasn't shown"), portion question pre-answered by default.
10. **The color-token system as a whole:** zero system-color literals in view code, twin-token discipline (recover/info), hot-as-destructive scoped in its doc, exceptions written down with conditions. The violations found are the complete set — the system is load-bearing.
11. **The progression journal's row grammar:** before→after diff + named-evidence reason + locale-aware units + honest empty state. State-of-the-art explained adaptation; every fix should route *into* it, not around it.
12. **One-tap start on a large target** (watch picker, post-Done pill, phone Up Next hero restraint) — the exact property Apple broke in watchOS 26 and had to restore in 26.4 (platform brief §3). Sacred.
13. **Deferred-contextual permissions:** no launch wall anywhere; every Health/notification ask fires adjacent to intent; denial degrades without nagging. Above category baseline — the findings are about dressing this skeleton, not rebuilding it.
14. **The crown-adjusted rep hero + one-tap Done set:** prescription pre-fills, crown corrects only when reality differed, the tap advances *and* captures progression evidence — N1 achieved without losing the data.
15. **Coach chat's dominant-current-line pattern** and honest failure entries with Retry + manual-builder exit (principle 13 in chat form).

---

## 4. Verified findings by severity

### 4.1 Blockers

**B1 — Mid-session workout death renders as pre-start failure and lies twice.** *(watch 09-start-couldnt-start · blocker/M · confirmed)*
The single `.failed` state serves both pre-start failure and mid-session death: `handleFailure()` (WorkoutSessionManager.swift:190-197) routes a run dying 20 minutes in to "Couldn't start… Nothing was saved" — both claims false, since `handleFailure` calls `backend.end()`, which `finishWorkout()`s and may save partial data to Health (HealthKitWorkoutBackend.swift:71-96). Direct N6 violation; the enum's own doc comment is wrong for the post-start path.
→ Split the state: `.failedToStart` keeps current copy; `.failedMidSession` gets "Workout ended unexpectedly. What was recorded is in Health" + elapsed time + a path to the summary.

**B2 — Calorie gauge fabricates a full budget on Health read failure.** *(phone 27-food-day-with-target · blocker/S · confirmed)*
When the Health read fails, the failure notice appears only in the entry list while the gauge above renders a confident "0 of 2,200 / 2,200 left" from a seeded-empty `DailyIntake()` (FoodDayView.swift:438; `loadFailed` gates only the entry scroll, the gauge never consults it). A user who ate 1,400 kcal is told they have their full budget. Direct N6 violation of the standard the team already applied to the adjacent element.
→ Failure-aware gauge: em-dash the consumed number when `loadFailed` with no cache, suppress "N left," retry adjacent to the gauge; cached snapshot with a "last known" marker when available.

**B3 — End Workout is a single unguarded destructive tap.** *(watch 16-run-controls, 29-strength-controls · blocker/S · confirmed, reported 3×)*
`Button(role:.destructive)` → `endManually()` directly (WorkoutControlsView.swift:52-60; same in StrengthControlsView), sitting ~10–13pt below Water Lock — the control that exists *because* sweat/rain fire false touches (the page's own doc comment). No confirm, no hold, no undo; an accidental end mid-strength discards remaining progression evidence and an early end strands the adaptive session with no resume. The wearable brief is explicit: destructive actions under motion need a guarded gesture, not a tap. Moderating facts: the controls page is one deliberate swipe from the glance, and Apple's own Workout app ends on plain tap — this is a design decision, not just a defect; the *frequency* of false End touches in rain is hardware-verify.
→ Hold-to-end (~0.8–1s progress fill, haptic on commit) on both run and strength so the habit transfers — or instant end + a 5–15s "Resume" pill in the summary's reserved slot. A modal confirm is the worst option (N5/principle 11). At minimum widen the gap and bring both pills to ≥44pt.

**B4 — Mixed sessions end on a bare Done card.** *(watch 38-mixed-summary · blocker/L · confirmed)*
Per-block summaries are skipped entirely (`Color.clear.onAppear` advances at WorkoutSequenceView.swift:99, :181); `SequenceDoneView` is checkmark + "Done" + one caption. No run totals or comparison, no "Next run" line, no strength NEXT TIME notes, no effort rating — while progression *is* recorded, invisibly. Violates principle 12 ("invisible adaptation reads as broken") at the flow's payoff moment; `manager.summary` already exists at `.complete`.
→ Replace `SequenceDoneView` with a unified sequence summary stitching the existing standalone summary components: per-block ledger row (glyph · duration · headline stat · save state), the same one-line adaptation notes, one effort rating applied to both blocks.

### 4.2 Majors — Watch

**First launch / start failure**

- **W1** (02) — "No context ever arrived" and "context received, library empty" collapse into one "Create a routine on your iPhone" state after timeout (SessionContainerView.swift:127-130); sync failure renders as confirmed-empty against the code's own N6 comment. → Split the states; show "Waiting for iPhone…" and say the watch is still listening (it is). [S · confirmed]
- **W2** (02) — Empty state is a hard dead end on a watch-first app: Start hidden when routine==nil while the zero-routine run path exists and is tested (RunSessionContainerView fallback :395, HealthFitnessCalibrator seeding). → "Just run" primary launching the default adaptive RunCard; "Create on iPhone" secondary. See also §5-P1. [M · confirmed]
- **W3** (01) — Bare spinner + one caption for up to a hard-coded 10s; wrist peeks are ≤5s (CHI 2017, wearable brief §1) so the first impression is "it hung." → Show the guidance scaffold immediately with "Syncing from iPhone…" as a status line; keep the timeout. [S · confirmed]
- **W4** (09) — Copy says "try again" but the only affordance is Back (retry = 4 steps); transient HK races make retry the likeliest correct action, and the exit renders below the fold. → Primary full-width "Try Again" (`reset()`→`start()` exists), secondary Back, above the fold. [S · confirmed]
- **W5** (09) — The error is discarded (bare `catch`, WorkoutSessionManager.swift:164-172) yet copy always blames Health permissions — any other cause sends the user on a wrong permission hunt. → Branch on HKError; permissions copy only for `.errorAuthorizationDenied`; log the error. [M · confirmed]

**Quick-log**

- **W6** (08) — The saved-state instruction truncates at default type size ("Review it on your iPhone to…" — the actionable clause is cut); no ScrollView/fixedSize (QuickLogView.swift:70-94). → Wrap guard + shorter copy ("Finish it on your iPhone — nothing is logged yet."). [S · confirmed; repro on 40/41mm **hardware-verify**]
- **W7** (08) — The confirmation never echoes what was captured; dictation mis-transcription is the dominant on-wrist failure and surfaces only hours later at phone review. → Quote the parked text under "Saved for iPhone," tappable to re-dictate. [S · confirmed]
- **W8** (05/07) — Every log is full free-text (5–6 wrist actions + mandatory phone review) with no recents/repeat-last despite heavily repeating diets; MacroFactor's quick-add benchmark is 3 actions (competitor brief §4). → 1–3 one-tap recent-meal rows synced from phone history over the existing applicationContext channel; dictation becomes the fallback. (Review-skip for exact repeats is a separate design decision — §5-P8.) [L · confirmed]
- **W9** (05–08) — The full round trip is ~7–8 actions across two sittings, two of them pure ceremony. → Auto-dismiss "Saved for iPhone" after ~1.5s (Apple Pay pattern); make the 4h review notification actionable (Log-as-estimated / Open). [M · confirmed]

**In-run**

- **W10** (10) — "Start Run" skip pill's tap target is ~20pt tall — the only tappable control on the screen, used while walking. → `.frame(minHeight: 44).contentShape(Rectangle())` over the full reserved slot; visual pill stays small. [S · confirmed]
- **W11** (all in-run: 10–15, 24) — **Zero `isLuminanceReduced` handling in the watch target** (grep-confirmed, reported 3×). Wrist-down is the dominant posture; screens run 2–3 repeatForever pulses + a 1s countdown into the dim state; HR is Apple's named redaction candidate (platform brief §2). → AOD branch on the shared components: verb + countdown (run) / rep hero (strength) stay bright, suppress pulses, dim/redact HR. Observe the actual system-dimmed rendering first. [M · confirmed; rendering **hardware-verify**]
- **W12** (11–14) — Reduce Motion suppresses all three compliance pulses (hot-zone, gait-mismatch, pre-switch) with **no static substitute** — RM deletes a designed information channel; RM + haptics-off = no cue at all. → Static high-salience swap under RM (filled chip/outline on the mismatched verb, solid halo on the hot segment). [S · confirmed]
- **W13** (14 + 19) — **Adaptations promised but never delivered at rest** (reported 2×): AdaptationBannerView.swift:9-10 defers the readable detail to the summary, but `event.message`'s only surface anywhere is a VoiceOver label; the summary shows `stat("Adaptations","2")`. Structurally worse than reported: `SessionSummary` carries only `adaptationsApplied: Int` — the event list is never persisted, and RunDigest carries no adaptation fields, so the phone can't recover it either. The lens audit's single highest-leverage item. → Persist the events (small versioned-codec change), render one calm line per event ("Run 2 ended 30s early — HR held above zone 2"); the strings already exist in AdaptiveCore. [S(UI)+M(model) · confirmed]

**Controls**

- **W14** (16 + 29) — **No Pause/Resume anywhere** (grep-confirmed, reported 2×). A runner at a crossing has no way to freeze the interval clock; the engine keeps accruing zone/adaptation evidence through the stop — exactly the misleading signal N6 warns about. HKWorkoutSession pauses natively; the clock-free tick architecture makes engine pause cheap (stop feeding deltas). → Pause/Resume as the first control; must freeze IntervalStateMachine ticks too. [L · confirmed]
- **W15** (16) — Water Lock strands the user on the controls page: `enableWaterLock()` disables touch without resetting the pager, so the wet run proceeds with the glance screen unreachable. → Flip the pager to `.metrics` before locking (one-line change). [S · confirmed]
- **W16** (16 + 29) — Water Lock tinted `WatchTheme.recover` (walk-instruction blue) on a mid-session page, violating the token's own written scope. → Neutral utility tint; document the decision in Theme.swift. [S · confirmed]

**End-early summary (17)**

- **W17** — An aborted run gets full celebration grammar (bouncing checkmark, "Done," "Saved to Health") over "0:00 running"; `endedEarly` is consumed by the engine but never referenced by the view. → Branch the header: neutral copy, no bounce, surface what the engine does with an early end. [S · confirmed]
- **W18** — Hero shows "0:00 running" at 34pt — the dominant element is a zero that reads as data loss. → When 0, hero total elapsed with "ended before the first run interval." [S · confirmed]
- **W19** — The comparison pipeline has no endedEarly gate: the abort's RunDigest is written unconditionally, so the next real run shows an inflated "+15:00 vs last run" and the abort drags the 28-day baseline. RunProgression already gates on endedEarly — comparison is uniquely ungated. → Carry endedEarly in digest metadata; exclude from vsLast/baseline; suppress comparison lines on the abort summary. [M · confirmed]
- **W20** — No discard affordance: a 20-second mis-tap workout commits to Apple Health forever (pollutes Training Load); cleanup is phone-side only. `HKWorkoutBuilder.discardWorkout()` is first-class API — N2-adjacent addition, not a violation. → Secondary "Discard workout" on ended-early summaries under a threshold; default keep. [M · confirmed]

**Run summary / post-Done**

- **W21** (20 + 31/32) — **Effort stepper overflows the 42mm canvas** (reported 2×): 44+10+88(minWidth)+10+44 = 196pt vs 187pt total — mathematical overflow; both ± circles render edge-cut, shaving targets below 44pt exactly where wet post-run fingers tap. → Label minWidth ~64–70 + minimumScaleFactor; shrink the label, never the targets. [S · confirmed]
- **W22** (23) — Post-Done landing re-offers the just-finished workout as "UP NEXT · Start" with zero completion acknowledgment; no completed-today state exists anywhere. The loop the summary just closed visibly resets. → "Done today ✓ · Next: Thu" card state for a few hours, Start demoted to "Start again." [M · confirmed]

**Strength**

- **W23** (24, 35/37) — The rep hero is both prescription and logged outcome; the only correction affordance is an ~11pt 0.7-opacity crown glyph with no coach mark anywhere (grep-confirmed). An undiscovered crown silently records every prescription as achieved — the confident-but-wrong failure N6 forbids, degrading the N3 signal invisibly. → Keep mid-set friction at zero; add a post-hoc correction line on the rest card ("Logged 10 reps," tap to adjust — rest is the reading-tolerant moment, MobileHCI 2018) + a one-time crown coach mark/shimmer. [M · confirmed]
- **W24** (24 + 35/37) — The weight chip is a real button ~30–36pt tall directly above the full-width "Done set" CTA; a low mis-tap logs the set and starts a rest, no undo. → ≥44pt contentShape or make the whole hero zone the tap-through. [S · confirmed]
- **W25** (27/28) — ± adjusters render ~36pt effective circles (AX-dump measured 36.5pt wide), below the floor for sweaty mid-session fingers; fill-vs-field contrast computes ~1.25:1 so the circle boundary vanishes. → ≥44pt (48 safe) + brighter fill or 1pt stroke; consider crown-for-weight with plate-grid detents (the wet-hands path — wearable brief §4). [S · confirmed]
- **W26** (28) — Two + taps silently create a persistent plan-level change: overrides become N7 seeds with no delta shown, no reset-to-seed, no scope disclosure; a bailed session still persists the change. The policy also flags the dimension manually-progressed and freezes it. → Reserved-slot delta chip ("+10 lb · saved for next time," tap to reset); echo in NEXT TIME notes. Visibility fix, not behavior change. [M · confirmed]
- **W27** (25/26) — **The recovery ring is systematically mistakable for a draining countdown**: HR mode FILLS with readiness, the amber fallback DRAINS with time — opposite semantics on one identical circular form. In-repo proof: the storyboard's own captions misread frame 26. → Different forms: ring exclusively for recovery (labeled), a linear draining bar for fixed-time fallback. [M · confirmed]
- **W28** (25/26) — HR-mode rest extension jumps the countdown ~+60s and the ring visibly retreats as HR rises, with only "REST" as label — the canonical opaque-adaptation trust-erosion moment (coaching brief §1). → Reason chip ("HR still high — extending") + animate the timer change. [S · confirmed]
- **W29** (25/26 + 36) — The rest card shows nothing about what's next; in the mixed flow the user must swap dumbbells (20 → 12.5 lb) *during* the 30s rest but the weight is revealed only after. → Reserved-slot one-liner: "Next: Dumbbell Curl · 12.5 lb" (handle same-exercise rests: "set 2 of 3 · 30 lb"). [S–M · confirmed]
- **W30** (31/32) — Every NEXT TIME row hardcodes an ↗ glyph (StrengthCompleteView.swift:65-66) though Decision is tri-state and progressionNote fires on back-offs — **ease renders as advance**, the wrong direction cue at the exact back-off moment (principle 12: worse than none). → Derive the glyph from the delta: ↗ advance / → hold / ↘ ease (ease in recover-blue, never red). Direction data exists at the call site. [S · confirmed]
- **W31** (31) — Rows show destination only ("→ 11 reps"), no from-value, no reason, though ProgressionUpdate carries both and the phone renders "12 → 13 reps — clean session." → "10 → 11 reps" on the watch (formatting only); reason on tap or phone. [M · confirmed]
- **W32** (31) — The first NEXT TIME line clips its payload ("11 rep|s"): scaleFactor bottoms below the legibility floor and lineLimit(1) truncates the new-target token; the "confirm on iPhone" variant cannot fit one line at all. → Invert truncation priority (ellipsize the name, never the "→ 11 reps" token); allow 2 lines for the confirm variant. [S · confirmed]
- **W33** (32 vs 20/21) — Strength effort rating usually produces no visible response (the policy only converts advance→hold at high effort); a high rating makes the advance note silently *vanish* while the run flow trained the opposite. Users conclude the rating is decorative. → Quiet acknowledgment lines ("Felt easy — plan already stepping up" / "Felt all-out — holding Bench at 30 lb"); decision + reason already exist in Evaluation. See §5-P3 for the principle-12 amendment this needs. [M · confirmed]
- **W34** (30) — Strength summary has no this-vs-last comparison while the run summary has a reserved async slot — for the product whose strength promise is visible progression (N3), gains are invisible at the payoff moment (the Peloton missing-history cautionary tale, competitor brief §3). → Per-exercise line ("Goblet Squat: 30 lb — up 10 lb over 3 sessions") reusing the run side's honest-empty pattern; needs history read-back from HKWorkout metadata or the journal. [M · confirmed]

**Mixed sessions (33–38)**

- **W35** (35/37 + 24) — Live HR flips corners at the run→strength handoff (run pins top-RIGHT per principle 6, strength top-LEFT) — the trained sub-300ms glance finds the system clock instead, mid-workout. → Pin HR top-right everywhere; one HStack reorder. [S · confirmed, reported 4×]
- **W36** (34→35) — The automatic run→strength handoff has zero acknowledgment: the promised transition card (the file's own doc comment) doesn't exist — inter-block path is `Color.clear.onAppear` → spinner; the only cue is a near-black field-tint change that fails the grayscale test, and no handoff haptic exists. → 1–2s transition card ("Run done ✓ — Next: Goblet Squat") + `.success` haptic; the natural home for per-block save status. [M · confirmed]
- **W37** (38) — Adaptation is fully silent in mixed: `recordOutcome()` persists seed changes but no "Next run:" / NEXT TIME note renders — a violation of principle 12 as written. → Surface the same one-line notes the standalone summaries compose. [M · confirmed]
- **W38** (38 + flow) — Effort rating never offered for mixed sessions (both blocks' `.complete` branches skip the hosting screens), so RPE never reaches Health or progression for either block — the same workout content adapts on a systematically different signal by entry point. Plumbing exists (`writeEffort` via retained finishedBackend). → One rating on the sequence summary, applied to both blocks. [M · confirmed]
- **W39** (38) — "Each part was recorded as its own workout in Health" is a blanket save claim with zero per-block save-state tracking; the justifying comment is false on this path (those summaries are skipped), and `healthSaveState = .unconfirmed` on finalize failure is never consulted. Direct N6 + failure-renders-as-nothing behind an affirmative claim. → Track per-block finalize results; honest per-part status + retry; fix the stale comment. Until then soften the copy. [M · confirmed]

### 4.3 Majors — Phone

**Home hub & progression proposals**

- **P1** (01) — The empty state is a fixed VStack outside any ScrollView; at AX sizes it clips with no way to reach the primary CTA — the first-run user is stranded. → Wrap in ScrollView. [S · confirmed]
- **P2** (01) — First-run copy never mentions the watch — zero cue that workouts happen on the wrist (N4 comprehension gap). → One orienting line/glyph: "Routines sync to your Apple Watch — that's where you'll run them." [S · confirmed]
- **P3** (02) — The Up Next hero silently skips today's missed workout: `nextOccurrence` uses strictly-future dates and time-less routines default to midnight, so a passed time vanishes from the hub (capture: Tue 8:38 AM, Tue routine already showing "Tomorrow"). → Today-scheduled/not-done/time-passed stays up next until end of day; all-day occurrence for time-less routines; optionally the Runna "readapt or keep" prompt at day end (coaching brief §3). [M · confirmed]
- **P4** (03/16) — The hero renders fabricated "Mon · 12:00 AM" for time-less routines (midnight fallback + unconditional time append). N6-adjacent fabricated schedule signal. → Nil-aware RelativeWhen ("Mon" / "Mon · anytime"); also fixes the widget path. [S · confirmed]
- **P5** (03) — Confirm/Hold capsules ~30pt tall on the home's single consequential decision. → minHeight 44 + contentShape. [S · confirmed]
- **P6** (03) — "Hold" states no outcome (it keeps the earned seed, never nags — semantics living only in a code comment) and collides with the app's own "hold" exercise noun; it also journals a decline the user didn't knowingly make. → Outcome labels: "Step up" / "Keep 20 lb" + first-use footnote that the watch re-proposes when earned. [S · confirmed]
- **P7** (03) — Binary accept/reject with no in-card edit: a user wanting 22.5 lb must Hold; the manual escape (routine detail → builder) is invisible at the decision point. N1 blesses "app-proposed, user-adjustable"; editability-before-accept beats binary (coaching brief §5). → Tappable proposed value opening a plate-increment stepper; journal as user-adjusted. [M · confirmed]
- **P8** (03) — `.lineLimit(2)` mechanically truncates the compound headline's tail — the reps-reset term — at AX sizes. Never truncate the terms of a change being approved. → Structured lines (weight headline; "Reps reset to 8" secondary). [S · confirmed]
- **P9** (03) — Watch-earned structural proposals are confirmable ONLY on the phone (grep: zero watch references to the proposal store). An N4 watch-first user's progression silently plateaus with nothing on the wrist saying why. → Offer Confirm/Keep on the watch post-workout summary; phone card as fallback. N4-alignment, not a principle change. [L · confirmed]
- **P10** (03/04/05) — Nothing on the hub says sessions start on the watch, and the read-only hero is the most CTA-styled element (Apple's own watchOS 26 "looks startable but isn't" defect class). → Quiet "Starts from your watch" line/glyph until the first completed workout. [S · confirmed]
- **P11** (04) — Parked quick-logs pool for days by design and each renders as its own full-height card above the week strip — 3–4 items displace the home's core structure below the fold. → Collapse ≥2 into one summary card ("3 watch logs to review" + newest quote) opening a sequential review flow. [M · confirmed]
- **P12** (05) — The camera capture button — the app's most frequent intended action — has a ~24×28pt hit area. → 44×44 + contentShape, or make the trailing half of the pill the target. [S · confirmed]
- **P13** (05) — The partial data-loss state "Some didn't save" renders in the same caption/secondary styling as benign "Saved," no retry, no attention channel — violates the post-incident standard. → Warning tint/icon + tappable status to the failed entries with retry; keep the reserved-slot geometry. [M · confirmed]
- **P14** (03→16) — Confirming the STEP UP proposal produces pure absence: the card vanishes, the hub reflows, no settled acknowledgment, no route to the record (journal behind an unlabeled glyph). Violates principle 12. → Collapse in place to a one-line settled state ("Stepped up — Goblet Squat 20 → 25 lb · View journal"), receding next visit; same for Hold. [M · confirmed]
- **P15** (03/17) — One datum, three vocabularies: card "effort 6," journal "felt moderate," reason string "felt all-out (effort N)." The card and reason never migrated to the P6.1 coarse vocabulary the watch teaches. → `EffortLevel` label everywhere; demote raw numerics. [S · confirmed]

**Routine detail & builder**

- **P16** (07/08) — Cross-session run adaptation is fully invisible on the phone: adaptation rewrites run/walk seeds that NO phone view reads (grep-verified); "20 run" is the never-touched block duration. The product's core promise (N3) has zero phone provenance — the Garmin explained-adaptation pattern (coaching brief §2) is absent exactly where the user inspects the plan. → "Adapts now: 2 min run · 90s walk — grew after Tuesday's run" provenance line on the WORKOUT card, linking to the journal; silence when unchanged. [M · confirmed]
- **P17** (09/10) — Strength gets no INSIGHTS/progression surface at all (the reserved slot is gated on `routine.hasRun`); live watch-moved seeds render identically to hand-authored constants, and the journal is unreachable from this screen. The file's own comment — "an invisible feature reads as a missing one" — applied asymmetrically. → The same reserved slot for strength: latest seed change + reason + journal link; per-exercise change chip ("+5 lb Tue") deep-linking to the journal filtered to the routine. [M · confirmed]
- **P18** (10) — Content scrolls behind the status bar/header with no material or fade; card fragments bleed around the back button. → Scroll-edge effect / toolbar background material. [S · confirmed]
- **P19** (09/10 + 07/08) — Touch targets: DayPicker pills 38pt; "Edit Cards"/"Ask the coach" are bare ~20pt text labels 20pt apart — the screen's two most consequential entry points. → minHeight 44 across; padding/capsule on both actions. [S · confirmed]
- **P20** (11) — Builder stepper ± 30×30, weight buttons 32×32, 8pt cluster spacing — the most-tapped controls on the screen; the repo already solved this exact problem (QuantityStepper's `contentShape(Circle().inset(by: -6))`). → Apply the same pattern; add hold-to-repeat. [S · confirmed]

**Coach (P3)**

- **P21** (19/20) — "Draft the plan now" is advisory-only: it sends a plain user message; no layer forces the propose_plan tool, so nothing guarantees the draft turn yields a proposal (the storyboard shows the identical bubble twice). A skip control that must be pressed twice reads as the app ignoring the user. (The captured double-send is a ScriptedCoachSession artifact, but the structural gap is code-fact against the production engine.) → Dedicated `requestDraft()` forcing the tool path with committed UI state ("Drafting your plan…"); if info is genuinely missing, one named-gap prompt, not an open question. Fix the sim script; real-engine reliability check stays open (**hardware-verify** the on-device model's tool compliance). [M · confirmed]
- **P22** (18/20) — Primary interaction under 44pt: quick-reply chips ~31pt (and the smallest type on screen despite being the main path); send button a bare 30pt glyph. → ≥44pt chips + 44×44 send; chip type to .subheadline. [S · confirmed]
- **P23** (22) — The applied card contradicts itself: badges recompute against the live store and flip NEW→UPDATES the moment import lands, beside the frozen "Applied — updated 0, added 2." A self-contradicting AI audit record. → Snapshot per-routine status at proposal/apply; render the stored verdict. [S · confirmed]
- **P24** (21) — The import gate is strictly apply-all-or-cancel: no per-routine include, no day edit, no seed edit; rejecting one detail forces a chat re-ask (the Runna/Notion editable-draft refinement, coaching brief §5). Toggles operate on the already-validated payload, preserving the pinned-validation invariant. → Per-routine include checkboxes ("Add 1 routine") + tappable repeat-day chips + "Edit before applying" into the builder. [M · confirmed]
- **P25** (21) — UPDATES cases show only the incoming state plus a count-level "Replaces the N cards you have now" — the user approves replacing content they cannot see (TrainerRoad's Plan Adaptation Overview is a diff, coaching brief §4). → Collapsed "Currently: …" before/after diff per row; requires threading the existing routine through (the store has both sides). [M · confirmed]
- **P26** (18) — `buildNewPlan` interrogates from absolute zero (equipment/history/goal) though `reviseAll` already receives routinesJSON + progressionSummary from the same builder — re-asking "what equipment?" after a month of logged dumbbell sessions kills repeat use. Deliberate per code comment, but an ordinary design decision (§5-P10). → Ground buildNewPlan with the same context when the store is non-empty; intake confirms instead of asks. [M · confirmed]

**Export pack**

- **P27** (24) — The includes-line can lie: it derives "fitness snapshot" purely from scope flags while the pack body silently omits the section on a failed/empty Health read; same gap for "30-day progression." (On-screen only — the pasted text doesn't embed the line.) → Reconcile against what actually composed; surface "exported without snapshot — try again." [S · confirmed]
- **P28** (23) — The includes-line — the screen's honesty mechanism — sits below the fold while the code claims it is "always visible." → Move it into the pinned export bar above Copy. [S · confirmed]

**Food logging**

- **P29** (26 + 28 + 30) — **PrimaryButton has no disabled styling**: hard-coded accent + glow, never reads `\.isEnabled`, so disabled CTAs render pixel-identical to enabled — a glowing button that no-ops, at three call sites. → One component fix: read `@Environment(\.isEnabled)`, dim text/stroke, kill glow. [S · confirmed, reported 2×]
- **P30** (26) — The fallback target mode is a dead end: copy says Health lacks body data but offers no path to fix it; degraded mode becomes permanent by omission, against N7's spirit. → "Add height and weight in Health…" + the `x-apple-health://` link already used elsewhere; re-check on return. [S · confirmed]
- **P31** (26) — The manual path has zero scaffolding (bare "Daily calories" field) while the deficit path gets 5 presets + explainer + preview; the fallback user is the spec-§2 beginner least able to invent a number. → 3–4 preset capsules reusing the in-file segment component. [S · confirmed]
- **P32** (30) — The item shows an honest "100–800 kcal · estimate" but the pinned bar collapses the 8× range to "Total ≈ 450" — fabricated precision laundered through an honest input, and 450 is what the day gauge spends. → Show the midpoint on the item line too, or label "(midpoint)"; longer-term carry the band into the gauge. [M · confirmed]
- **P33** (31) — Day-level totals collapse ranges to bare midpoints with no marker directly above a row reading "100–800 kcal" — visible non-reconciliation on one screen; the app's own "≈"/estimate-dot grammar exists elsewhere. → Prefix ≈/estimate dot when any counted entry has range provenance. [S · confirmed]
- **P34** (32) — The edit field pre-fills the midpoint and provenance shows a bare "estimate" — the stored 100–800 range appears nowhere; the user edits a number that is not the stored fact (the kcalEdited guard correctly preserves the range; the display doesn't earn it). → Append the range to detailLabel, matching the confirmation sheet. [S · confirmed]
- **P35** (30/32/34) — WHEN/meal-slot/portion chips across the shared sheets are ~24–28pt tall, rows 8pt apart, so a thumb aiming Lunch lands on Yesterday; the codebase's own fix pattern exists (QuantityStepper inset −6 with an explanatory comment). → `contentShape(Capsule().inset(by: -8…-10))` in the shared chip builders + row spacing ≥ the expansion. [S · confirmed, reported ~3×]
- **P36** (31/32) — `Theme.metricNumber` is fixed 34pt with no relativeTo and the gauge is a fixed 168×168 frame — the food hero ignores Dynamic Type while surrounding text scales; hierarchy inverts at AX sizes. → @ScaledMetric the token (every consumer benefits) and scale the gauge frame. [M · confirmed]
- **P37** (34) — The plate item name is literally "Plate of food (tap to name it)" and commit writes it verbatim to Health (N2-permanent); rename pre-fills the instruction string. → Store "Plate of food"; carry the hint in presentation only; strip the parenthetical at commit. [S · confirmed]
- **P38** (33) — "Type it instead" — the escape hatch for the app's most frequent action — is ~30pt tall, 100pt above the bottom edge behind the shutter. → ≥44pt; consider promoting placement. [S · confirmed]
- **P39** (33) — No photo-library import anywhere (grep: zero PhotosPicker hits) despite the flow explicitly designing for deferred logging (receipt backdating, Yesterday chips) — a photo snapped at lunch can't be logged at dinner. → Library entry on the capture screen feeding the same still→OCR→classify path. [M · confirmed]
- **P40** (28→30) — One typed log = two stacked modal sheets with two differently-named commits ("Add" then "Log 1 item"), ~5 actions per meal vs MacroFactor's 3 (competitor brief §4). → Merge to one surface (chips + Log on the typed sheet, estimate inline); constraint: the parsed number must stay visible pre-commit (spec §4.3). Reserve the full sheet for low-confidence parses/scans. [M · confirmed]

**Watch quick-log review (35)**

- **P41** — Destructive Delete renders in brand emerald: `role: .destructive` silently overridden by the app-wide `.tint(Theme.accent)`; three sibling surfaces already fixed exactly this with Theme.hot. Inverts "red = danger only." → `.tint(Theme.hot)` + audit every role-destructive button under the global tint (add a UI test). [S · confirmed]
- **P42** — Delete occupies the top-right nav slot — iOS's habitual confirm position — and with the green tint is the most confirm-looking element on screen (the code comment flags the risk itself). → Full-width Theme.hot footer row matching the entry-edit sheet; nav keeps Cancel only. [M · confirmed]
- **P43** — Zero watch identity on the cross-device baton: the header maps `.typed` → keyboard glyph/"typed," indistinguishable from phone entry; watch origin surfaces only in the delete dialog. → applewatch glyph + "From your watch · <capture time>" header for QuickLogRequest drafts. [M · confirmed]

**Permissions**

- **P44** (36) — Consent copy mismatch: the Health usage string talks about meals and export aggregates, but the first visible request is Body Measurements fired from "Set a daily target" — the actual purpose is never named at the consent moment (plus a spaced-hyphen typo). → Rewrite as a purpose list in encounter order: body measurements → calorie budget; dietary energy → intake; VO2max/RHR → export only. [S · confirmed]
- **P45** (38) — The one-shot notification permission fires from a background event (first watch quick-log arrival) with zero priming, physically covering the needs-review card that would explain it; denial permanently kills the app's only notification. → Soft-prime on the needs-review card ("Remind me if this sits unreviewed?"); fire the system prompt on that tap. [M · confirmed]
- **P46** (36/37) — The first food session fires two separate full-screen Health ceremonies minutes apart (body-profile read at target setup, nutrition write+read at first Log — the second interrupting the first meal commit), each a 3-step ceremony with iOS 27's history-choice step. → Consolidate the food-flow types into the target-setup ask; keep the export snapshot read set separate. [M · confirmed]

### 4.4 Majors — System-wide (lens audits)

- **S1** — **Typography is the one untokenized channel**: watch Theme has zero Font tokens, phone exactly one; 11 hard-coded display sizes across the summary/active/effort views; drift already observable (34pt metric role semibold on phone, bold on watch). → A small display scale (hero/metric/verb) in both Theme enums, migrate the 11 call sites — the project's own Motion-token precedent. [M · confirmed]
- **S2** — **No top-level tab structure**: Food — a several-times-daily surface — is a pushed screen inside the single "Your Week" stack; every meal log = root → Food → push → modal. → 2–3 tab structure (Week/Food) or a root-level Food hero; if single-stack is deliberate minimalism, document it as a principle — no doc currently declares it (§5-P9). [M · confirmed]
- **S3** — **The phone→watch routine push has no receipt anywhere**: pushes are silent, the isPaired/installed guard drops silently, and a failed handoff renders as absence on the wrist — the device N4 makes canonical. Nuance: applicationContext is OS-queued, so away ≠ dropped; three states is the honest granularity. → Receipt chip at coach-Apply and routine detail: "On your watch ✓" / "Will sync when nearby" / "Watch app not installed." [M · confirmed]
- **S4** — The calorie number has **four names** ("Daily goal" / "deficit budget" / "Set target" / "Use this goal" — three on one sheet), undermining the transparent-TDEE story the build-22 budget depends on (MacroFactor's moat is transparency, competitor brief §4). → "Budget" everywhere; "floor" reserved for the safe-minimum state, defined inline once. [S · confirmed]
- **S5** — Consent-card wording cluster: "Hold" (collides with plank/builder vocabulary), "effort 6" (raw score the user never sees elsewhere; `EffortLevel(score:)` is one call away), "rep band" (coach jargon). → "Not yet"/"Keep 20 lb"; "felt moderate"; "Hit the top of the rep range." [S · confirmed]
- **S6** — Watch inactive zone-ladder rungs at 0.22 opacity ≈ 1.3–1.5:1 on black (WCAG 1.4.11 wants 3:1); the ordinal "how far above target" reading collapses in glare. → Raise to ~0.35–0.4 or hairline per rung; keep active/target dominance. [S · confirmed]

### 4.5 Minor + polish — clustered by theme

*(Full per-item detail lives in the four digests; this section preserves every theme with its representative items and the shared fix vehicle.)*

**T1 · Adaptive transparency minors** — picker shows no adaptive context at launch (principle 12 literally specifies the line: "Today: 2 min run · 90s walk — eased after Tuesday"); warmup's cadence-detection mechanic is invisible ("Run to begin · tap to skip" + "Detected" attribution); cue pill looks tappable but is inert (make the tap show `event.message` — also patches the Layer-1 gap; Apple patched this defect class in 26.4); "Recovery drop — 26 bpm" unglossed; summary suggestion doesn't name its HR input; post-Done landing never echoes the "next run 45s→30s" promise; rest clock triple-ambiguity in HR mode; no rests line in the strength summary though `restRecovered` gates progression; hub carries zero engine state; journal rows are dead ends (no tap-through to routine/session, no "takes effect Mon"); import UPDATES badge gives no magnitude; budget calibration moves weekly with no change-moment marker (MacroFactor surfaces it as an event); typed-value clamps (800–6,000) silent; auto/micro journal entries indistinguishable from pending. *Vehicle: the adaptation-legibility milestone (§8-H2).*

**T2 · Honest-failure minors** — failed Health-history read renders identically to no-history on the run summary; effort-write silently dropped on 5s timeout; "Check Health for this workout" is terminal with no re-check; bare unlabeled spinners (strength no-data, target-setup sheet — no timeout, spins forever); "Check Health permissions" names no destination (fix lives in iPhone Health → Sharing); three hand-rolled watch failure views with divergent copy → extract shared `WorkoutFailedView(cause:actions:)` — the single fix vehicle for six start-failure findings.

**T3 · Color/token hygiene** — zone-ladder slot 0 wears strength royal blue (mint a `zoneLow` token; reported 3×); walk screen's most saturated green is the zone bar's aerobic segment; final-5s countdown tints with the CURRENT phase color (tint with the NEXT phase's — it previews the instruction, matching the haptic); heart glyph permanently hot-red (platform convention — keep, but document; §5-P5); run-green as undocumented success/grade on watch summaries and Done buttons (§5-P2); Theme.info shares the watch recover hex (documented tension — consider teal drift); phone Cancel/dismiss renders brand emerald app-wide via global tint (one systemic fix: neutral cancellation actions; accent reserved for the affirmative); week strip stacks three green meanings in one 40pt component (differentiate today by form, not hue); builder add-menu teaches the wrong color vocabulary (all-accent icons vs semantic card colors); amber's binary over-budget verdict contradicts the "gradient jobs only" contract text (amend the doc); UpNextCard's two off-token hexes include Electric-Lime residue (promote to tokens, re-derive from emerald). **Protect finding:** these are the *complete* set of leaks — the token system is load-bearing; both leaks sit on in-session/summary surfaces, the highest-risk zone.

**T4 · Motion-channel discipline** — the heart glyph pulses perpetually whenever bpm > 0 (reported 3×) — decoration spending the reserved attention channel; make it static (or pulse only when the reading is stale — the better N6 fit; one shared-component fix); up to four concurrent pulses at the adaptation moment with no precedence policy → define pulse precedence; suppress the hot pulse while a cue is visible (pulsing cause and response at once is double-signaling); cooldown's phase-blind hot pulse fires during every realistic cooldown ("deceleration isn't defiance") → grace-gate while HR falls, and retarget the ladder (targetZone is never updated for cooldown).

**T5 · Reserved-slot / layout-jump violations** — the cue pill measures ~22–23pt against its fixed 20pt reservation (the slot that doc-comments the principle violates it at default type size); the summary's "Suggested…" caption swaps line counts on first ± tap, jumping Done under the user's finger; "Next run:" note conditionally rendered (reserve the slot — the pattern exists 3 lines up); coach input bar reflows every turn (fixed-height slot); Review-&-apply swaps to caption height on apply.

**T6 · Dynamic Type / text resilience** *(schedule as one app-wide pass; sim-testable)* — fixed `.system(size:)` heroes that invert hierarchy at AX sizes: run verb 38pt, summary hero 34pt, effort word 22pt + 88pt frame, rest numerals + fixed 104pt ring, rep hero 50pt, cue slot 20pt → `@ScaledMetric(relativeTo:)` across the board. Missing ScrollView/lineLimit/scaleFactor: watch empty state, both quick-log phases, picker summary, controls Labels (both sides), exercise names (lineLimit(1) × 0.6 scale → ~12pt floor on 20-char library names), the 17 comparison line's ragged wrap; phone WeekStrip fixed circles, day-pill 7-across grid, seven-chip rows that can't wrap (share WhenRow's existing ViewThatFits helper), send glyph, coach name+badge rows, MealConfirmation's fixed 18pt total slot.

**T7 · Copy, labels, consistency** — "Done" doing double duty as state headline and commit button (reported 3×; rename the button "Finish"); "Couldn't start" restated verbatim as body line 1; picker summary inconsistency (strength omits duration though `estimatedMinutes` exists — duration is the go/no-go input); "UP NEXT" carries no schedule anchor ("UP NEXT · TUE 6:30"; the data is synced); bare "1 of 3" ambiguous on nested-count screens; "1 of 1" carries zero information (suppress or repurpose as "then: strength" in mixed); controls headers inconsistent between run and strength; `shortTime()` emits three unit styles that meet in one phrase → normalize (m:ss matches the timer just watched); cooldown's final-5s reuses interval-switch grammar, promising a phase that never comes (quiet "Finishing…" — visual channel only, the haptic is already distinct); goal/target noun drift; "deficit budget" jargon at first contact; "needs review" passive; casing register mixed system-wide (adopt sentence case; four Title Case holdouts; one-line rule in DESIGN-PRINCIPLES); "Applied — updated 0, added 2" debug diction → "Added 2 routines to your week" + a "See your week" exit; watch/phone commit-verb drift (Review & apply → "Import 2 Routines" → Applied — parameterize the sheet title); quick-log Cancel semantics ("keep waiting") stated only inside the delete dialog → "Keep for later"; unconditional footer sentences (run-alert copy on strength routines; weights copy on run-only builders); coach "Done" in the cancellationAction slot breaks the app's own sheet grammar.

**T8 · Input affordances / haptics** — quick-log Save fires no haptic at the commit moment (`.success` is used elsewhere); ± weight taps give no haptic (`.click` per step, distinct tick crossing the seed); weight has no crown binding though reps do (crown is the wet path); step grid hardcoded 5 lb while display is locale-aware (metric users see 9→11→14 kg — arithmetic looks broken; 2.5 kg grid); quick-log Close silently discards dictated text (persist the draft); the watch empty state has zero tappable elements including quick-log (the code says a meal log needs no routines); effort scale's extent invisible (four-dot indicator — doubles as the grayscale-safe channel); permanent "Turn the crown for more" hint (one-shot, persisted flag); the direction arrow teaching the haptic grammar is the thinnest mark on screen (`.title3.weight(.black)`); the HR-mode rest ring can start near zero and never visibly move on a 30s rest (seed a minimum arc; fall back to time mode when the model can't move in the window); phone Apply — the highest-stakes commit — fires no haptic (`Theme.Haptics.success`); builder steppers lack hold-to-repeat and direct entry (0→15 warm-up = 15 taps); name fields not auto-focused; dirty-state discards without confirm (new-routine sheet, coach intake "Done"); copy-prompt success as a blocking three-sentence alert (toast + haptic; move instructions into the export flow); the sparkles menu's 6 items are 4 transport verbs (collapse to one "Send to Claude…" + Import); day/time schedule edits commit instantly with zero signal while cards need modal Save (signal live-commits with `commitTick`); typed-parse portion chips flip to "Looking up…" for a local deterministic re-scale (resolve optimistically).

**T9 · Layout & dead space** — coach first-open puts the question at top and chips ~1,200pt away (bottom-anchor the conversation); third chip clipped to a lone letter; full-height sheets for one-number jobs (~70% dead: target setup, single-item confirmation, single-item review — content-sized detents / bottom-align into the thumb zone); export sheet's six full-height use-case cards push scope + includes-line below the fold (compact chip grid so use case + scope + includes co-render); four identical "Rest — 30s" rows ≈40% of a card for one bit (collapse to a meta line; label the trailing rest's between-rounds meaning); builder card never shows the derived total or current seed while two-thirds of it is empty; "× 3 rounds" arrives after the list; two edit-row grammars in one stack; empty-state composition floats (~240pt void); exercise library's decision-relevant prescription line is the smallest element under a 40pt decorative icon column (promote it; the info sheet buries it below the fold and is read-only from the library at max add-intent — add a contextual Add button).

**T10 · Affordance grammar** — looks-tappable-isn't: UpNextCard's glass time chip, routine detail's "Next · Fri" chip, "Repeat × 3 rounds" accent-semibold static text (reported 2×). Tappable-with-no-affordance: the whole Up Next card, food entry rows (the only route to Delete), "2,200 left" as the only target-edit affordance, post-first-use food row target covering only glyph+text, dismiss-without-saving hidden behind long-press only, library rows where selection state lives in a 22pt icon alone, journal reachable only via an unlabeled chart glyph fused with the sparkles menu in one capsule (split and label — also the P3 coach entry point's discoverability), NAME field reading as a static card.

**T11 · Stale docs (regression vectors)** — amber-recover doc rot in WorkoutActiveView.swift:5 and AdaptationBannerView.swift:8 (both still describe the failed amber mapping the `heat` rename guards against; reported 4×); WorkoutSequenceView.swift:7's false claim that the launch screen masks the handoff; ImportRoutinesSheet's "always visible" includes-line comment. One-line fixes; batch with any touch of these files.

**T12 · Review-material / process defects** — phone stills 01/02 are byte-identical black frames (capture-pipeline settle defect); the food-day first-use and loadFailed states were never captured. Recapture before the next review cycle treats those beats as covered.

**Anti-regression notes:** watch 15 (cooldown) and 25 (rest) pass the core glance audits — budget any fixes into the summary or single-word swaps, not on-screen density. The permission *timing* architecture and quick-log sheet grammar are verified-conformant; don't re-open them while fixing their dressing.

**Cross-cutting fix vehicles worth scheduling as units:** (1) shared `WorkoutFailedView` — six start-failure findings; (2) app-wide @ScaledMetric/Dynamic Type pass — ~15 findings; (3) shared HeartRateView changes (static glyph, AOD branch) — run + strength at once; (4) mixed-session summary rework — B4 + four majors on one screen; (5) `zoneLow` token mint + Theme exception docs — the color-hygiene cluster; (6) disabled-state PrimaryButton — every phone CTA call site.

---

## 5. Principle / requirement challenges

Findings and concepts that cannot ship without amending an N-rule, a DESIGN-PRINCIPLES tenet, or a documented spec decision. Each: evidence → tradeoff → what it unlocks.

**P-1 · Seed a built-in first-run routine on the watch (challenges N4's letter).** *(watch 01/02 · minor/L)*
Evidence: the fresh watch launch is a dead end, yet the zero-routine run path exists and is tested (default RunCard fallback, silent HealthFitnessCalibrator seeding) — only LaunchView withholds Start. Spec line 40 explicitly assigns routine setup to the phone, so a watch-seeded "First run" reinterprets that sentence. Tradeoff: N4's clean "phone authors, watch executes" division vs eliminating the fresh-install dead end; N7 plus spec Q1 (C25K default, de-risked by self-correction) already sanction a conservative default. Unlocks: first wrist contact becomes the product's thesis — start now, it adapts — instead of a referral; genuinely phone-optional from minute zero. UI-level change, near-zero engine surface.

**P-2 · Run-green tinting improvement deltas — doc and code contradict (DESIGN-PRINCIPLES #2).** *(watch 18 · minor/S)*
Evidence: "green when you're doing well" is exactly what principle 2 records rejecting, yet WorkoutCompleteView.swift:179 tints improved deltas run-green (with a code comment defending it), and run-green also grades "Saved to Health" and affirmative CTAs — a de-facto unlabeled exception, and a nominal brand-accent leak since the hexes are identical. Tradeoff: either drop the tint (the +/− sign prefix already carries direction — no accessibility failure) or amend principle 2 with a scoped at-rest exception ("post-session, run-green may carry the run quantity / a documented watch affirmative-accent token"). The current doc/code contradiction is the actual defect; resolve one way, in writing.

**P-3 · Acknowledge explicit user input even when the system correctly does nothing (principle 12's silence clause).** *(watch 32 · major/S)*
Evidence: rating a strength session "Easy" produces zero visible response (the policy only ever converts advance→hold), while Hard/All-out visibly remove advances — the screen's only input reads as decorative, suppressing future ratings. The fix ("Easy noted — plan already advancing") contradicts principle 12's "silence when nothing did [change]" as written. Amendment: distinguish *system* silence (nothing changed — stay quiet) from *explicit-user-input* silence (user acted, no visible consequence — acknowledge once). Cost: one caption line, only after a deliberate tap. Unlocks: the rating channel stays alive, which the progression policy depends on.

**P-4 · First-use food interception (calorie-spec C6 amendment).** *(phone 25 · major/M)*
Evidence: first tap on Food auto-presents the target sheet, whose `.task` immediately fires Health authorization → modal → spinner → OS sheet before the user ever sees the day screen. The one-time offer is a documented user decision (calorie-tracking-spec.md:88-94: "offered once and skippable"), so dropping it amends that bound. Tradeoff: first-use friction vs the user's "the whole reason to count calories is to meet a target." Partial fix needing NO principle change: keep the one-time offer but defer `requestAuthorization` until the user engages (HIG: user-initiated prompts), or make the offer non-modal inline emphasis. The ghost-gauge onboarding whatif (§6.5) is the full-change version.

**P-5 · The red heart glyph (principle 4 scope amendment — recommend keeping the code).** *(polish/S)*
Evidence: the heart is permanently `WatchTheme.hot` against "red = danger only." The recommendation is to keep it — Apple Health's platform convention buys instant metric recognition — and codify the exception: "hot doubles as the ♥ anchor, glyph-size only, never text/fill." Confusion risk low (caption-size glyph; attention rides the separate motion channel). Paperwork, not code.

**P-6 · Crown-nudge / pre-run "Feeling rough?" — a sanctioned user signal into the loop (N1/N3 wording).** *(concepts: Hardware-first mid-run; The Check-in)*
Evidence: the system can ease the user down mid-run, but the user has no sanctioned channel to ease the system down — their only moves are defy (noise) or skip (silence), both worse signals than an honest "not today" (De Gruyter 2025: sensors can't see non-training stress). Amendment: N3's "the user does not tune this" → "…but may signal it"; N1's permitted inputs gain "one-tap pre-session readiness override." The override is treated as evidence (the `walksDefied` never-punished precedent), never a parameter edit; ease-downs are journaled and soft-capped. Unlocks the coaching brief's "global trust dial" (Garmin's recommendation-not-instruction stance), currently absent.

**P-7 · Structural confirms outside the app (P6 gate location).** *(concept: Adaptation in the OS's morning voice)*
Evidence: the STEP UP card is already a two-button decision with its reason inline — it meets the research bar for confirm-without-app. Amendment: "structural changes are confirmed in the app" → "…wherever the diff is fully visible"; ImportRoutinesSheet stays mandatory for anything that can't render as a one-line diff. Unlocks: confirm rate (a notification with a Confirm button competes with nothing); Layer-1 reasons reaching users who never open the phone app. Guards: Hold as the default-safe action, journal badge, undo path, idempotent store writes.

**P-8 · Watch quick-log auto-commit (reverses the documented always-pending decision).** *(concept: Log-is-logged; quick-log recents sub-recommendation)*
Evidence: PendingMealQueue states "Queued text is never auto-committed into Health" — a deliberate 2026-07-06 decision (locked phones can't run the lookup ladder in WCSession's deadline; user-as-actor copy was a deliberate rework). The feasible inversion keeps the transferUserInfo park but auto-commits medium+ confidence results phone-side as normal editable entries, demoting needs-review to near-zero-confidence; the wrist honestly says "Logged" without a number. Tradeoff: dictation errors land in Health (editable, provenance-labeled) vs the 7-action two-sitting flow plausibly killing logging compliance — "failure must not render as absence" cuts in favor of the inversion, and HITL research says don't checkpoint reversible micro-decisions. Must be labeled a P6 spec change and probably gated behind an explicit opt-in ("Trust my watch logs").

**P-9 · Single-stack phone IA is an undocumented principle.** *(lens · major/M)*
Evidence: no top-level TabView exists; Food is buried one push deep. Either adopt a 2–3-tab structure or write the single-stack minimalism down as a principle so future surfaces stop accreting into one stack by default. The absence of the decision is the defect.

**P-10 · Deliberate-but-challengeable design decisions (no principle change required; recorded for honesty):** coach `buildNewPlan`'s empty context ("a fresh plan starts from intake" — code comment, not an N-rule; challenge is legitimate, P26); the scan-first hero on the food day (a bet, not a principle — the typed path is the retained majority per the Lose It teardown); the mandatory confirmation sheet for user-stated calorie counts (spec §4.3 relaxation is N6-safe: logging a user-stated number fabricates nothing); raw-totals-never-on-wrist (the Verdict-summary concept implies a new N2 corollary — state it if adopted).

---

## 6. Redesign concepts

All sixteen concepts from the ideation agents, grouped by lens, with feasibility/risk verbatim-condensed. Plus the whatifs that rise to concept level.

### 6.1 Platform-native maximalist

**C1 · Zero-Launch: the Smart Stack IS the watch home screen.** Feed the routine schedule into a Smart Stack widget with time-based RelevantContext; the whole card face is the start target; Action Button (Ultra) starts the next scheduled session; the in-app picker demotes to off-schedule fallback. *Feasibility HIGH — ~70% of plumbing ships today (NextWorkoutComplication + `afcoach://start/<id>` deep link + nextOccurrence provider); new work is relevance declaration, countdown-auto-start, and upgrading StartRunIntent. Risk: widget staleness is a trust surface (reload on context receipt or show honest age, N6); relevance is OS-arbitrated — the picker stays first-class; auto-start creates a REAL HKWorkout (N2) — big cancel target + start haptic; Smart Stack behavior is hardware-verify.*

**C2 · The energy budget lives in the Dynamic Island / watch Smart Stack.** Meal logs start/update an Energy Budget Live Activity (compact island = kcal left; lock screen = the linear budget bar with the earned-active segment); the watch gets the glance for free via supplementalActivityFamilies; the pending-review chip rides along. *Feasibility MEDIUM — greenfield ActivityKit; data side clean (EnergyBudget is pure package logic; MealLogController is the choke point). Risk: PLATFORM — the 8h Live Activity lifetime fights an all-day budget; background WC wakes can update but not start an activity; extensions can't read HealthKit (snapshot pushes → a staleness window vs N6). Recommended descope: meal-windowed activities + an ordinary lock-screen/StandBy widget + a watch budget widget via App-Group snapshot. Lock-screen calories need an opt-in.*

**C3 · Adaptation speaks in the OS's morning voice.** (a) "Tomorrow" widget: the Layer-1 decision + reason chip ("Next run: 3:00/60s — walks ended on HR recovery"), silence when unchanged; (b) STEP UP proposals become actionable notifications / interactive widgets with Confirm/Hold App Intents; the import sheet stays mandatory for multi-routine proposals. *Feasibility HIGH — PendingProposalCard is already a two-function decision; wrapping ProgressionIntake.confirm/decline in App Intents is near-free; transferUserInfo already background-wakes the phone. Risk: App-Group-safe store writes + idempotent double-fire handling; no relevance API on iPhone home/lock; requires the principle amendment in §5-P7. The lowest-risk, highest-leverage concept of the four.*

**C4 · Hardware-first mid-run: crown and physical inputs over the controls page.** Hold-to-end with a filling ring; crown rotation on the glance nudges the current walk once (bounded, evidence-fed like walksDefied); pause on physical input. *Feasibility MEDIUM — hold-to-end is a day of SwiftUI; crown-extend is small pure-Swift engine work (the crown is free on the metrics page); BUT crown-press chords have no third-party API and Action-Button in-session behavior is unverified — reshape around Double Tap (`handGestureShortcut`) + hold-to-end + crown-extend. Risk: N3 tension is a deliberate spec amendment (§5-P6); accidental-rotation guards + haptic timing are hardware-verify.*

### 6.2 Radical minimalist

**C5 · One-screen run: kill the controls page, end by guarded hold.** The glance screen IS the workout; press-and-hold anywhere (~1.5s, escalating haptics, edge sweep) ends; the pager disappears. *Feasibility MEDIUM-HIGH for the core; LOW for two sub-claims — pause "already exists" is false for this codebase (zero pause plumbing), and wet-detection Water Lock has no API. Risk: self-contradictory with the app's own reasoning — hold-anywhere is maximally exposed to sustained wet touch; the expensive error (accidental end, in Health forever) must stay the recoverable one → ship only with a post-end undo/resume window, and treat the wet false-trigger rate as the go/no-go hardware metric. Also retires the HIG controls-page habit transfer — an explicit platform deviation.*

**C6 · Verdict summary: one wrist screen headlined by what the engine decided.** "Next run: 45s run · 1 min walk" + a 2–4-word reason chip as the headline; effort dial + honest save line below; stats/comparisons move to a phone post-run card and the journal. *Feasibility HIGH — the verdict line is already computed live at summary time (notePreview → RunProgressionPolicy.evaluate); reasons exist as ProgressionReason; RunDigest already carries most phone-side stats. Gaps: a structured short-form reason enum; per-adaptation receipts need to ride the digest. Risk: the steady-state "no change" session needs a designed headline ("Same plan — it worked") — on a verdict screen silence reads broken; N4 softens (totals eventually need the phone) — a deliberate tradeoff to state; the crown-dial reversal of the P6.1 no-crown decision is coherent on a one-screen summary but should be stated as intentional.*

**C7 · Kill "Done set": motion-detected set completion with tap fallback.** Wrist IMU detects rep cessation per archetype; `.success` haptic starts rest; an "undo — still lifting" chip covers false positives; unreliable archetypes keep today's pill. *Feasibility MEDIUM — the archetype hook exists (Exercise.archetype, the P2 forward hook) and a detector slots into AdaptiveCore beside RunningCadenceDetector, but the heuristic is unbuilt R&D, motion streaming is net-new plumbing, and most current library entries are `.stationary` — day-one payoff limited to press/row/curl. Risk: THE UNDERAPPRECIATED RISK IS DATA — Done-set is the reps-capture moment; auto-completion silently credits the prescription, inflating progression on fabricated evidence (N6 one layer down). The undo chip must carry rep correction. No simulator path for IMU at all. The N6-correct MVP: motion ARMS a confirm haptic-tap; graduate per-archetype after on-body false-positive rates are known.*

**C8 · Log-is-logged: watch food capture writes immediately; review becomes refinement.** *(See §5-P8 for the principle reversal.) Feasibility LOW-MEDIUM as specced (no on-watch estimator; the synchronous round trip was built and removed), MEDIUM-HIGH reshaped: keep the park, auto-commit medium+ confidence phone-side with the honest band, review only for garbage; the wrist says "Logged," the number arrives where the phone is next seen. Risk: reverses a documented decision — label it; dictation errors land in Health (editable + provenance-labeled must be genuinely discoverable); background FoundationModels inference on a locked phone is unproven — design must tolerate "resolves at next unlock."*

### 6.3 Coaching-first

**C9 · The Debrief: summaries as the coach's narrative, decision first, totals second.** Watch headline = verdict + reason chip in the decision-direction color; phone debrief adds Garmin-style Layer-2 decomposition (named inputs with direction arrows) + thumbs-up/down feeding effort calibration (Strava's post-launch fix, built in — competitor brief §2). *Feasibility HIGH — seeds evaluate synchronously at session end; ProgressionReason carries rendered reasons; RunDigest ships the named inputs in HKWorkout metadata. New: persisting the AdaptationEvent list (small versioned-codec change — same fix as W13) and the thumbs→calibration path. Risk: verdict-in-hue re-maps instruction colors into evaluative territory — needs the §5-P2 scoping of principle 2, or use weight/position; the verdict must cite only engine-local facts pre-finalize (N6); two feedback channels (thumbs + effort) need a precedence rule against double-counting.*

**C10 · One Ledger: the home hub becomes the coach relationship's timeline.** Pinned Up Next hero above one chronological stream — observations (quiet rows), decisions (cards), proposals (cards with buttons); budget recalibrations and realized-active-energy events finally get visible cause-and-effect. *Feasibility MODERATE — ProgressionJournal is already a ledger in miniature and the confirm verbs reuse verbatim, but a budget-event journal must be built and the merge layer spans four stores with three persistence models. Risk: partial-failure states multiply (every segment needs a distinct failed state — the user's own standard); Health-read latency must never delay the local-only hero (load-bearing constraint); the no-expiry proposal stance must not become a nag-by-layout; a real identity shift for the phone (what's-next → what-happened) — ship behind the unchanged hero.*

**C11 · Ask-the-coach-why: decision provenance as a system-wide affordance.** Every adaptive number gets a uniform quiet "why?" that opens CoachChatView pre-seeded with a structured DecisionContext; explanation writes nothing (outside the validator funnel by construction); a hardened what-if emits a normal proposal through the existing gate. *Feasibility HIGH and unusually seam-aligned — CoachIntent is an open enum built for `.explain`; CoachContext is read-only by construction; ContextPack is the serialization precedent; EnergyBudget already exposes ideal explanation inputs. Real work: per-decision-family provenance structs (journal entries carry rendered strings, not inputs). Risk: THE DOMINANT RISK IS N6 — a generative model explaining a deterministic decision can assert causal claims the engine never made; mitigation must be structural (context includes the exact reason case + numerics; prompt forbids citing outside them; fallback chips assert-tested). Static chips render instantly, prose streams in; Apple-Intelligence-gated — the chips must be good enough to be the feature (build C9's Layer 2 first).*

**C12 · The Check-in: a pre-start coach presence on the watch.** One reserved-slot stance line ("Seeding easier — Tuesday's walks ran long"; silence on normal days) + a quiet "Feeling rough?" one-tap ease-down, never punished by progression. *(Principle amendment in §5-P6.) Feasibility MODERATE-HIGH — the watch owns everything needed; ease-down is a transient multiplier at plan-expansion time (immune to context races); walksDefied is the mechanical precedent; the stance line needs a small watch-local last-outcome record. Risk: UX over technical — the stance line needs a crisp data trigger for silence or it becomes chatty (principle 12's other failure mode); ease-downs must be journaled and soft-capped (three consecutive is signal); a mis-tap needs an undo/visible eased state before Start.*

### 6.4 Continuity-first

**C13 · The Thread: home hub as a live day timeline.** Chronology above/below a pinned "now": what happened (with reason chips), what's coming, and every in-flight handoff as an explicit node (parked → arrived → resolved; sent to Claude → awaiting → imported). *Feasibility HIGH for the data (all stores are dated and already injected into WeekView; pure view-model merge), MEDIUM for the build; full handoff fidelity inherits C14's cost. Risk: heterogeneous failure modes (every segment needs failed/loading states); the no-expiry proposal stance vs a feed that re-floats old cards (needs a decaying held state); demoting Routines changes root IA; feed-ness must be capped (~7 days) and the reason chips stay facts-not-grades. Ship the degraded thread first — the journal is genuinely buried today.*

**C14 · Batons: one first-class pending-handoff object.** Unify the four handoffs (quick-log, structural proposals, coach proposals, Claude round-trip) behind one lifecycle grammar (created → in-flight → diff-preview → accept/edit/hold → applied) with a phone tray and honest watch delivery states. *Feasibility MEDIUM — implement as phone-side AGGREGATION (protocol/adapter per pending type), not a unified wire model (rewiring transports breaks per-channel codec versioning); WCSessionDelegate callbacks give honest queued/delivered for free; resolved-acks need a latest-state-wins field, not a conversation. Risk: consequence tiers required (a taco ≠ a 25 lb step-up) or the grammar flattens stakes; quick-log can never show a diff on the watch by design (the phone does the lookup at review time); batched-review counts collide with the no-nag stance — gate to time-sensitive batons. The watch post-save dead-end fix is independently cheap and should not wait.*

**C15 · The summary IS the baton.** Reorder the watch summary: decision headline + reason → handoff state ("seeds send when you finish") → effort adjust (kept — the best interaction on the watch) → OS totals below; phone-side, plan shifts arrive as the Runna "readapt or keep" calm choice. *Feasibility HIGH — the cheapest concept of the four; everything is computed locally at summary time; the structural-vs-micro flag exists; 3–5 days of view work. Risk: design, not engineering — challenges the deliberate P6.1 time-running-hero decision (frame as a principle-consistent correction, validate on-body); four things above the fold must collapse into one dominant element; the live-recalc coupling between the dial and an off-screen headline needs reserved height + local signaling; "sent to iPhone" is a lie at render time (bind to the WC callback); the no-change session must collapse to quiet.*

**C16 · Claude round-trip as a tracked exchange.** "Send for review" snapshots the pack and creates an in-flight node; on return, the diff renders against the snapshot ("Claude changed 2 of the 3 routines you sent Tuesday; your progression since is preserved") before the existing import gate. *Feasibility MEDIUM-HIGH for the core (ExchangeStore mirrors ProgressionProposalStore; the flat RoutineExchange schema is diff-friendly; the progression-graft claim is already true in code); LOW for the conveniences — pasteboard auto-detect nags (iOS 16+ paste prompts) and no documented Claude-app URL scheme exists → design the degraded form: the in-flight node badges the Import button. Risk: three-way staleness (snapshot vs current vs returned) must be flagged honestly; exchanges are user errands, so quiet expiry is appropriate here (unlike proposals).*

### 6.5 Whatifs that rise to concept level

- **The warmup "ready ramp"** (watch 10): the zone ladder grows to hero size; cadence + zone visibly climb to the target band; crossing it snaps into the run field with a "Detected" attribution — the adaptive engine demonstrating itself in the one in-session moment with a reading budget; the countdown demotes to "auto-starts in 0:22," resolving the honesty and discoverability findings in one move.
- **The "state horizon"** (watch 11–13): a full-bleed luminous border in the phase color draining around the screen edge, shifting to the NEXT phase's color in the final seconds — peripheral ambient color beats digits for state-keeping (MUM 2025), survives sunlight where 6%-luminance fields don't, and doubles as the AOD representation.
- **Cooldown as landing sequence** (watch 15): the hero flips to live HR recovery (the HRR primitive the engine already computes), the ladder animates the descent, and the workout closes itself on the HRR target — dead seconds become the adaptive loop's most visible payoff.
- **Before→after interval strip** (watch 20/21): two proportional green/blue segment bars (this run above, next run below) that morph live as the effort level steps — the rating's consequence readable in <300ms (Blascheck InfoVis 2018) using the vocabulary the run already taught.
- **The session spine** (mixed 33–38): a thin segmented strip where each block is a segment in its own semantic color — royal blue legitimately appearing BEFORE the handoff, teaching the transition instead of springing it; a shortened block visibly shrinks its segment.
- **The builder timeline** (phone 11): draggable stacked walk-blue|run-green|walk-blue bar with a live total and a faint preview of today's actual seeded intervals — parameter entry becomes seeing the workout you'll feel, in the learned color language; the same component later renders routine thumbnails.
- **The coach brief card** (phone 18): a pinned, editable slot card (Equipment · History · Goal · Time/week) the conversation fills; "Draft the plan now" becomes a hard state transition when minimum slots fill — fixes the placebo escape hatch and gives the HITL "inputs used" panel for free.
- **Week-strip proposal preview** (phone 20): render the proposed week inside the coach card in the home's own week-strip grammar, ghosted-current vs solid-proposed — the user approves the thing they live with.
- **Ghost-gauge onboarding** (phone 25): the reserved 236pt gauge slot renders a dimmed ring with inline deficit presets; pick "−500" and it animates alive in place; Health auth fires only at that tap. Log-first, goal-second, permission-last, zero modals (pairs with §5-P4).
- **Uncertainty-native gauge** (phone 27/31): the filled arc ends in a gradient tail spanning the day's estimate spread; "≈1,400–2,100 left" collapses to a point as entries verify; tapping opens the TDEE calibration's existing math — out-transparency-ing MacroFactor with machinery that already exists on the expenditure side.
- **The permissions ledger** (phone 36–38): one app-styled "What this app reads" card (three purpose rows) firing consolidated prompts, mirrored in Settings as a living ledger of what was read, when, and under which grant window — the anti-Whoop/Oura move the De Gruyter opacity research says nobody makes; the rows later become the budget-provenance surface.
- **Kill the manual-kcal fallback** (phone 26): ask for height and weight (the numbers a beginner actually knows), write them to Health, grant the full dynamic budget — a typed weight is a better N7 seed than a typed calorie target, and the second budget mode (with its missing breakdown and dead-end copy) disappears.
- **Delete the new-routine sheet** (phone 15): "+" drops straight into the builder; the routine names itself from what was built and suggests days from observed workout times, confirmed inline on Save — build-then-confirm, matching the app's own propose-confirm grammar.

---

## 7. Hardware-verify list

Everything the simulator cannot settle. Verify on Series 11 / Ultra 3 (and 40–42mm for size floors) before scheduling dependent fixes.

**Safe-area / sim under-render (the documented artifact class)**
- watch 09 — exit Back button below the fold (~10pt sliver); does ContentUnavailableView scroll at large type?
- watch 19 — stats block: edge clipping is the artifact, but two values overlap vertically ("7:56"/"0:26") which safe-area can't explain — apply `.contentTransition(.numericText())` regardless.
- watch 01 — "Syncing" caption detached ~80pt from its spinner despite spacing:8.
- watch 20/22 — next-run note and split line edge-clipped; width math says they fit; the 6pt padding is genuinely under platform margins (`.scenePadding` fix is sound either way).
- watch 18/20/21 — summary lines edge-to-edge; clock collides with the + effort corner — the adaptation line is principle 12's one calm line; if real, scenePadding + 2-line wrap.
- watch 24 — "Done set" bottom clipping on 42mm (fix verified on 46/49mm only).
- watch 30 — 6pt horizontal padding / flush-left stat labels.
- watch 31/32 — NEXT TIME right-edge clipping ("11 rep|s") despite in-code guards.
- watch 35/37 — pager dot atop "Done set" (matches the already-hardware-fixed idiom).
- watch 38 — checkmark sharing the system clock's band (top-anchored-ScrollView half is code-real).
- watch 27 — form-demo below-fold peek vs page dots (bottom-inset zone).
- watch 08 — "Review it on your iPhone to…" truncation: ship the wrap fix unconditionally; confirm repro on 40/41mm.
- phone 08 — ghosted content smearing right of the back button under the nav bar (sim renders materials unfaithfully).

**Always-On / dimming**
- watch 10–15, 24 — observe the actual system-default dimmed rendering (frozen mid-pulse? unredacted HR?) before scoping the isLuminanceReduced branch (the code gap itself is confirmed).
- watch 15 — recoverField's ~6–8% lift over black in AOD (self-labeled "no change required"; attach to the AOD work).

**Sunlight / contrast / legibility (on-body only)**
- watch 11–13 — the tinted state fields (#06180C / #061520) render as pure black in every frame (pixel-verified) — sim under-render or a silent loss of the principle-2 glance channel; if it renders, grayscale-test whether ~6% luminance survives AMOLED sunlight at all.
- watch 24 — strengthField #070E1C "reads as plain black"; if it fails on-wrist, brighten all three fields to equal perceptual lift.
- watch 10 + 33/34 — target-zone marker (1.5pt stroke on 0.22-opacity capsule): does it die in daylight?
- watch 14 — cue typography (~11pt sky-blue on dark glass) at the outdoor floor; `.bold` bump is near-free.
- watch 26 + 36 — rest-ring empty track at 0.18 opacity near-invisible at low readiness; end-cap dot is cheap regardless.

**Haptics / feel (felt-only)**
- watch 17 — `playComplete()` unconditional for abort vs completion; is a neutral `.stop` discriminable within the 3–5-tacton budget (wearable brief §3)?
- End Workout — measure actual false-touch frequency in rain/sweat before adding friction (the one hardware input for B3's design question).
- C4/C5 — hold-to-end timing, accidental-crown rates, Double Tap reliability.

**Dynamic Type / AX runtime**
- watch 16 — controls Labels at AX sizes: `simctl ui content_size` fails on the watchOS 27 runtime — needs device or future toolchain.
- watch 16 — can the crown still page the TabView under Water Lock? (Fix ships either way.)
- watch 03/04 — quick-log toolbar button ~29pt visual; confirm the corner-button extended hit region ≥44pt via AX tree.
- symbolEffect(.pulse) Reduce-Motion respect (lens claim; check on hardware).

**Model / latency behavior (production engines unobservable in sim)**
- phone 29/30 — does the on-device model reliably split "salad and a coke" into two items (the single-item capture is a ScriptedMealPipeline artifact; the prompt instructs splitting)? If it under-splits, add deterministic conjunction splitting.
- phone 28→30 — real typed-parse/photo-identify latency; if >~3s, add an "Enter it yourself" escape on the identifying view.
- phone 19/20 — the production FoundationModels engine's compliance with a forced draft turn (P21's reliability check).
- watch 14 — cue vocabulary: four tokens (EASING/RECOVER/STRONG/GO) for two haptic directions — legible signal or noise at a mid-run peek? Fix the stale "amber = easing" comment unconditionally; if on-body says collapse: EASING/PUSHING.
- C1 — Smart Stack relevance behavior (not sim-testable).

---

## 8. Roadmap draft (proposed successor to the completed P0–P6.1 roadmap — does not modify PROJECT-STATUS.md)

A triage menu, not a pre-filtered list. Every item: impact rationale → acceptance criteria as design outcomes. S/M/L are the digest effort tags.

### Horizon 1 — Polish now (S/M fixes, days each, no architecture)

**H1.1 State-honesty sweep** *(B1, B2, W39, P27, P13, T2)*
Impact: the three fabrication points sit on the app's own binding standard; each is unrecoverable-trust territory (the NRC lesson).
- A run that dies mid-session lands on a screen that names what happened, shows elapsed time, and points at what Health actually recorded — never "Nothing was saved" when something was.
- A failed Health read can never produce a confident calorie number anywhere: gauge, day totals, and hub line all render a distinct failed state with retry.
- The mixed summary claims only what per-block save-state tracking has confirmed.
- The export includes-line always matches what actually composed.
- "Some didn't save" is visually a warning with a one-tap path to retry.
- Shared `WorkoutFailedView(cause:actions:)` replaces the three divergent failure views; permissions copy appears only for permission errors; Try Again exists wherever copy promises it.

**H1.2 Touch-target & input floor** *(B3-minimum, W10, W21, W24, W25, P5, P12, P19, P20, P22, P35, P38, T8)*
Impact: the sub-44pt scatter sits exactly in the wet-finger/mid-effort contexts the app designs for elsewhere; one sweep, one standard.
- No tappable control anywhere renders an effective target under 44pt (visuals may stay small; contentShape carries the floor).
- End Workout requires a hold or grants a resume window; the End/Water Lock gap widens regardless.
- Commit moments fire haptics from the existing Theme vocabulary (quick-log Save, phone Apply, ± steps).
- The weight grid is locale-aware (2.5 kg steps for metric users).

**H1.3 Dynamic Type & typography tokens** *(S1, P36, T6)*
Impact: ~15 findings share one root cause — the untokenized type channel; AX sizes currently invert hierarchy on every hero.
- Both Theme enums carry a display type scale (hero/metric/verb) with documented weights; the 11 improvised call sites migrate.
- Every hero number scales with Dynamic Type via @ScaledMetric; no fixed frame clips scaled text; the effort stepper fits a 42mm canvas at all sizes.

**H1.4 Copy rulebook + string sweep** *(S4, S5, T7)*
Impact: all S-effort; the drift concentrates where features grew fast, and a 10-line rulebook prevents regression.
- One noun for the calorie number ("budget") everywhere; "Hold" → outcome labels; effort renders in the taught coarse vocabulary on every surface; sentence case adopted with the four holdouts swept; one commit verb per flow ("Apply/Applied"); "Done" never doubles as headline and button; `shortTime` emits one style; a copy section lands in DESIGN-PRINCIPLES.md.

**H1.5 Color/token paperwork** *(T3, P41, §5-P2, §5-P5)*
Impact: closes the complete set of leaks in an otherwise load-bearing system, in writing, so it stays closed.
- `zoneLow` token minted; Water Lock and quick-log chrome get a sanctioned non-workout utility tint; destructive actions are never accent-tinted (UI test enforces it); cancellation actions go neutral app-wide; the heart-glyph and post-session-green decisions are resolved one way and documented in the token files; the stale amber comments die.

**H1.6 Small receipts & loop closers** *(P14, P23, W22, P4, P3, T5)*
Impact: cheap acknowledgment states that stop finished loops from reading as resets.
- Confirming/Holding a proposal leaves a one-line settled trace linking to the journal; the coach applied-card never contradicts its own receipt; post-Done the watch shows "Done today ✓" instead of re-offering the finished workout; no fabricated "12:00 AM" ever renders; today's missed workout stays visible until day end; no layout jumps under an actively tapping finger.

### Horizon 2 — Next milestone (flow-level reworks)

**H2.1 Adaptation legibility milestone** *(W13, W30–W34, P16, P17, P15, T1 — the review's highest-leverage theme)*
Impact: the product's differentiator is currently invisible at rest — the exact opacity the trust research names as the canonical erosion event; the engine already composes everything needed.
- `SessionSummary`/RunDigest persist the adaptation event list (versioned codec); the summary renders one calm line per event ("Run 2 ended 30s early — HR held above zone 2") instead of a count.
- NEXT TIME rows carry direction (↗/→/↘), from→to values, and never lie about ease.
- The phone routine detail shows live seeds with provenance for BOTH run and strength ("Adapts now: 2 min run · 90s walk — grew after Tuesday"), linking into the journal; silence when unchanged.
- The strength summary gains this-vs-last; the rest ring's extension explains itself; explicit ratings are always acknowledged (per §5-P3).
- Journal rows navigate to their routine/session and state when the change takes effect.

**H2.2 In-session resilience** *(W11, W12, W14, W15, B3-full, W27–W29)*
Impact: the dominant wrist state (AOD), the dominant interruption (pause), and the dominant failure mode (wet touch) all get designed behavior.
- Every in-workout screen has a designed isLuminanceReduced rendering: instruction + countdown bright, pulses suppressed, HR redacted per the platform brief.
- Reduce Motion swaps every compliance pulse for a static high-salience treatment — the channel is never deleted.
- Pause/Resume exists on both control pages and freezes the interval engine's evidence accrual.
- Water Lock returns the pager to metrics; ending is guarded; recovery vs countdown use different forms; the rest card previews what's next.

**H2.3 Mixed-session completion** *(B4, W35–W39)*
Impact: the flow that combines the product's two halves currently discards both of their payoff moments.
- The handoff is an acknowledged beat (transition card + haptic); HR never changes corners; the sequence ends on a per-block ledger with honest per-part save state, the same adaptation notes as standalone flows, and one effort rating feeding both engines.

**H2.4 Food friction & honesty** *(P29–P40, W8, W9, P11, P43, §5-P4 partial)*
Impact: the highest-frequency action in the app is ~2 sheets and ~5 actions over MacroFactor's 3-action budget, and range-honesty breaks at the day level.
- A typed meal commits from one surface in ≤3 actions with the parsed number visible pre-commit; recents make a repeat meal ≤2 actions on the phone and the watch alike.
- Estimates keep their band identity through every aggregation ("≈" at day level; the edit sheet shows the stored range).
- Photo-library import exists; the plate-item hint never reaches Health; the watch baton wears watch identity end-to-end and Delete reads as destruction.
- Health asks consolidate to one ceremony at target setup; the notification ask is user-initiated from the review card; the first-use offer defers its OS prompt until engagement.

**H2.5 Coach round-trip integrity** *(P21, P24–P26, S3, C16-core)*
Impact: the confirm gate is gold-standard; everything around it leaks trust.
- "Draft the plan now" always yields a draft or one named-gap question; the import sheet offers per-routine include and a true before/after diff for updates; a returning user's coach opens grounded in their store; receipts are frozen at apply time; every apply/detail surface carries the three-state watch-sync receipt.

**H2.6 Watch self-sufficiency** *(§5-P1, W2, P9, C12-lite)*
Impact: N4 says watch-first, but first launch, structural confirms, and start failure all currently refer to the phone.
- A fresh watch can start an adaptive run in one tap; structural proposals are confirmable on the wrist post-workout; start failure is preflighted at picker load so the trailhead case nearly never occurs.

### Horizon 3 — Big swings (redesigns / principle changes; each needs a prototype + on-body validation)

**H3.1 The Verdict summary / Debrief** *(C6 + C9 + C15 — converging concepts; HIGH feasibility)*
Impact: makes the engine's decision the product's signature moment — the Gentler-Streak pattern the competitor brief holds up, on machinery that already computes everything at summary time.
- The summary's dominant element is what the engine decided and why, live-recalculating with the effort dial; a no-change session has a designed steady-state headline; totals remain honest and demoted; the phone debrief decomposes named inputs with direction. Requires the §5-P2 hue-scoping decision.

**H3.2 Adaptation in the OS's morning voice + zero-launch start** *(C3 + C1; HIGH feasibility)*
Impact: the explained-adaptation layer reaches users who never open the app; the start path drops to raise-wrist → one tap.
- A morning widget shows the Layer-1 decision + reason (silence when unchanged); STEP UP proposals confirm from a notification with journal badge + undo (per §5-P7); the Smart Stack card is the scheduled start surface with honest staleness. Ship C3(b) first — lowest risk, highest leverage.

**H3.3 The decision inbox / thread home** *(C10 + C13 + C14; MODERATE)*
Impact: one learnable confirm grammar for every pending thing; budget changes finally get cause-and-effect provenance; in-flight batons can never silently vanish.
- All pending items share one card anatomy (source glyph · diff · reason · Confirm/Edit/Keep); every number that moves writes a ledger line saying why; the pinned hero and one-tap start never regress; failed segments render as failures.

**H3.4 Watch food loop inversion** *(C8 reshaped + W8; requires §5-P8 spec change)*
Impact: the 7-action two-sitting flow plausibly caps logging compliance; the reshaped inversion keeps every honesty guarantee.
- Opt-in "trust my watch logs": medium+ confidence parses auto-commit phone-side as editable, provenance-labeled entries with honest bands; review survives for low confidence; the wrist says "Logged" and never promises a number it can't know; recents chips make repeats two actions.

**H3.5 Motion-sensed strength** *(C7; MEDIUM, R&D — behind the archetype gate)*
Impact: the last per-event manual input in the workout product disappears where the signal supports it.
- Per-archetype: motion ARMS a confirm (MVP) before any auto-complete graduates; the undo chip carries rep correction so progression evidence never inflates; unreliable archetypes render exactly today's flow. Go/no-go on on-body false-positive rates; no sim path exists.

**H3.6 Ask-the-coach-why** *(C11; HIGH feasibility, gated on H2.1's chips)*
Impact: the market's Layer-3 ceiling (Whoop Coach) on a validated read-only seam — the coach infrastructure earning its keep at every moment of doubt.
- Every adaptive number carries one uniform quiet "why?"; the static input chips render instantly and are the fallback *and* the floor; prose is structurally grounded in the decision's actual inputs; any hardened what-if routes through the existing proposal gate.

---

*Process notes for the next review cycle: fix the screenshot settle-wait (black frames on phone 01/02), capture the food-day first-use and loadFailed states, and burn down the §7 hardware-verify list on-body before re-scoring glanceability and state honesty.*
