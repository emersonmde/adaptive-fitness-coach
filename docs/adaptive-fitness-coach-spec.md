# Adaptive Fitness Coach — Product Spec

**Version 1.0** · Status: Approved for design + technical design · Scope: iOS + watchOS

---

## 1. Summary

A watch-first fitness app that removes the two things that stall beginners: not knowing *what to do*, and not knowing *how hard to push*. The user states a goal; the app builds a routine, shows how to perform each movement, and keeps the user in the correct effort band automatically — adjusting run/walk intervals to heart rate in real time, and progressing strength load session over session — without the user ever manually logging a set or editing the plan.

*(Scope note: the shipped roadmap evolved past this document's phasing — the P3 built was AI routine building rather than §5's learned-adaptation P3 (deferred), and calorie tracking, originally a §8 non-goal, is now P4 with its own companion spec, `calorie-tracking-spec.md`. `PROJECT-STATUS.md` is the living source of truth for phase numbering; this document remains authoritative for the workout product's non-negotiables and core experience.)*

The product is a **UI and intelligence layer over Apple's Workout stack**. Every session is a real Apple workout via WorkoutKit/HealthKit; the app does not record its own metrics. Heart rate, calories, and route are captured natively by the OS and live in Apple Health.

---

## 2. Problem & user

**Primary user:** an adult building a fitness habit, low cardio base, training privately at home with adjustable dumbbells. Not a quantified-self enthusiast; will not maintain a manual log.

**What existing apps leave unsolved for this user:**
- Routine apps make *logging* the core interaction — recording reps, guessing weights, editing the plan after each session. Beginners abandon it.
- Couch-to-5K apps run *fixed* interval scripts with no awareness of whether the user is over- or under-working, and no real scheduling.
- Strength apps assume the user already knows what weight to start at and when to progress — the single hardest question for a beginner.

**Thesis:** make the logging invisible and the effort self-regulating. The user follows ambient guidance; the app infers everything else from sensors and session outcomes.

---

## 3. Non-negotiables

Invariant across every phase and every downstream design/engineering decision.

**N1 — Logging is invisible.** The user is never asked to record what they did. The app infers outcomes (reps completed, fatigue, effort) from sensors and session events. The only inputs ever requested are *forward-looking seeds*: an app-proposed, user-adjustable starting weight, and (P3 only) an optional one-tap effort rating. The user never edits the plan after a session to make progression work.

**N2 — Real Apple workouts, not a private tracker.** Every session starts and stops an actual Apple workout via WorkoutKit/HealthKit. The app never records its own HR/calorie/route data to push into Health. The OS is the system of record.

**N3 — Adaptation keeps the user in an optimal band, automatically.** Running: live HR governs interval length in real time. Strength: performance governs next-session load, targeting ~1–3 reps in reserve. The user does not tune this.

**N4 — Watch-first, phone-optional.** Every workout is fully runnable from the watch with the phone left behind. The phone is for routine setup and (P3) overnight model training only.

**N5 — Ambient guidance.** In-workout direction is haptic-first: the user follows the buzz, not a voice or a screen. Following a session must never require listening to audio coaching or reading the watch mid-effort.

**N6 — Graceful degradation, never a fabricated signal.** Every exercise has a defined fallback. Where the wrist has no reliable read, the app falls back to set-outcome and does not invent a fatigue signal. Confident-but-wrong guidance is the one unacceptable failure mode.

**N7 — Defaults are seeds, not commitments.** Starting parameters (interval ratios, weights) are best-effort defaults the system corrects from the user's response. A wrong default self-corrects; it never requires the user to fix it. This is what allows shipping before every default is research-optimal.

---

## 4. Core experience

1. **Set up (phone).** The user describes a goal in plain language; the app generates a structured routine (e.g., Mon/Thu adaptive runs, Tue/Fri strength circuits). The user may reorder or swap, but does not have to.
2. **Schedule.** The user sets days, times, and frequency. Sessions surface as notifications.
3. **Launch (watch).** A reminder fires; the user starts the session on the watch and leaves the phone behind.
4. **Follow.**
   - *Run:* the watch starts a real outdoor run/walk workout and drives intervals by HR. A distinct haptic marks each run↔walk switch. The user runs when buzzed to run, walks when buzzed to walk — no looking, no listening.
   - *Strength:* the watch presents the exercise sequence as cards — each with a brief form demo the first times, hideable once learned — and starts a real strength workout. The user follows the sequence; the app proposes the weight.
5. **Done.** The session is in Apple Health as a native workout. Nothing to log.
6. **Adapt.** The next run's intervals and the next strength session's loads reflect what just happened — automatically.

---

## 5. Scope & phasing

Each phase ships a complete, usable product. Phases are sequenced by **complexity and risk**, not feature glamour: the cheapest high-value capability ships first, and the highest-complexity capability (personalization) ships last.

### P0 — Adaptive run/walk, end to end *(no ML)*

The entire adaptive loop, proven on running alone with zero ML. De-risks the unfamiliar platform by validating the full workout-session lifecycle in something usable from week one.

**Ships**
- watchOS app; minimal phone companion.
- Real Apple outdoor run/walk workout via WorkoutKit/HealthKit, with live HR.
- One workout type: adaptive Run/Walk, Couch-to-5K style, progressing toward a continuous **5k**.
- HR-driven real-time interval adaptation. Zones computed by the app from raw HR + the user's max HR (the app does **not** depend on Apple exposing a live computed zone). HR holds target zone → continue/extend the run; HR runs hot over a sustained window → end the run early / lengthen the next walk; HR not recovering during the walk → lengthen the walk.
- Haptic-first transitions: distinct, run-feelable buzz patterns per switch; no audio or screen interaction required.
- Scheduling + reminders: user-set days/times/frequency; notification launches the session.

**Control-logic constraints (binding on engineering)**
- Operate on **smoothed/sustained** HR, never instantaneous spot readings: HR lags effort by 30–60s+ (more for a deconditioned user). A single high reading is not grounds to act.
- Bias toward backing off over extending: early-interval low HR may be lag, not sustainable aerobic state — treat "extend the run" as the higher-risk action and require a longer confirming window for it than for "back off."
- Adaptation operates within the session, interval to interval. True mid-interval throttling is a later refinement, not required here.

**Done when**
A user schedules a run, gets a reminder, launches on the watch with the phone left behind, completes a run/walk in which intervals visibly adjusted to HR, follows the entire session by haptics alone, and finds the workout in Apple Health as a native activity.

**Not in P0:** strength, any IMU/fatigue work, any ML, multi-exercise sequencing.

### P1 — Strength sequencing *(static, no adaptation)*

Bring the user's full routine in as guided sequences. No strength adaptation yet.

**Ships**
- Routine builder (phone): the user's strength days as ordered exercise sequences.
- Card sequence (watch) per strength session; per-exercise form demo, hideable once learned.
- Real Apple strength workout via API, started/stopped per session.
- App-proposed starting weights (conservative defaults within the user's dumbbell range), user-adjustable. *(A seed per N1 — not a log.)*

**Done when**
The user's full week (runs + strength) is schedulable; on a strength day the watch walks them through the exercise sequence with form demos and a proposed weight; each session is a real Apple workout in Health; the user logs nothing.

**Not in P1:** session-to-session progression, any IMU/ML, surveys.

### P2 — Deterministic strength adaptation *(no trained model)*

Add progression and in-set signal using **deterministic** logic only — no training step, cannot regress below set-outcome.

**Ships**
- Session-to-session progression from **set outcome** (all target reps clean / last reps grinding / stopped early → adjust next session's load and reps toward the ~1–3 RIR band). Self-labeling; no user input.
- Deterministic IMU heuristics where the wrist has a clean read, grouped by biomechanics (a handful of archetypes, not one model per exercise):
  - *Wrist tracks load* (press, overhead press, row, curl): relative velocity-loss — this rep's peak speed vs the set's best, flagged at a ~25–30% drop.
  - *Isometric* (plank): stability-envelope duration with tremor-onset / orientation-drift thresholds.
- Set-outcome remains primary; heuristics are confirmatory where supported; set-outcome-only fallback elsewhere (e.g., stationary-torso leg work — no fabricated signal, per N6).
- *(Optional, gated)* A pretrained or one-time-tuned off-the-shelf model may be **evaluated** here, but ships only if it beats the deterministic heuristic on held-out sessions. Default path is heuristic.

**Done when**
Across consecutive strength sessions, weights and reps adjust automatically in the correct direction from performance alone; plank targets adapt; the user never edits the plan or logs a set.

**Not in P2:** personalization, learned models in the default path, surveys.

### P3 — Learned, personalized adaptation

Replace heuristics with a model **personalized from day one** — the only configuration in which the model earns its complexity.

**Ships**
- Fatigue/effort model on a HAR-encoder backbone, trained on labels the app collects for free (set outcome; optional one-tap end-of-session "too easy / about right / too hard").
- On-device personalization: train overnight on iPhone, deploy the updated model to the watch for the next session.
- Position/orientation invariance via augmentation.

**Rationale (binding on scope):** cross-person fatigue models generalize poorly (~55% in published work) while personalized models reach ~98%. A generic model is therefore not an acceptable substitute for personalization — personalization is the feature, not polish.

**Done when**
A per-user model measurably outperforms the P2 heuristic for that user after a defined break-in period; the overnight train→deploy loop runs unattended; adaptation quality improves with continued use.

---

## 6. Open questions

| # | Question | Resolution |
|---|----------|------------|
| Q1 | Default run/walk ratio for a low-fitness / high-BMI beginner. | Literature review at P0. Candidates: NHS C25K wk1 (≈60s run / 90s walk); a more conservative walk-heavy ratio; Galloway run-walk. De-risked by N7 — HR self-corrects a wrong default. |
| Q2 | Target HR zone for a deconditioned user (%HRmax vs heart-rate-reserve/Karvonen; which "conversational" Zone-2 boundary). | Literature review at P0; validate against the user's measured max HR. |
| Q3 | What live HR data WorkoutKit/HealthKit exposes during a session (raw stream vs computed zone). | Engineering spike — first P0 task. P0 ships either way; fallback is app-computed zones from raw HR. |
| Q4 | Cold-start behavior before any personal data exists (P3). | Deterministic heuristics + conservative defaults; personalize as data accrues. |
| Q5 | How adaptations surface without nagging (haptic-only vs one-line card) and how much silent change the user trusts. | Design exploration, bounded by N5. The thesis depends on this dial. |

---

## 7. Dependencies & platform constraints

- **WorkoutKit / HealthKit** — workout session lifecycle + live HR. Q3 spike confirms the exact live-data surface.
- **watchOS background execution** — the card/guidance UI must stay live while the workout session runs underneath.
- **Action Button (Apple Watch Ultra)** — bind to launch the scheduled session (P0/P1).
- **WatchConnectivity** — phone↔watch routine sync and (P3) model deployment.
- **Core ML** — updatable/personalizable models for P3 on-device fine-tuning.

---

## 8. Non-goals

- Not a social or sharing app.
- Not for advanced lifters optimizing hypertrophy/periodization; target is approachable beginner training.
- ~~No nutrition or calorie tracking — weight loss is driven by diet, handled outside this app.~~
  **Superseded (P4).** This assumed calorie counting was a solved problem elsewhere; trying the
  existing apps proved otherwise. Calorie tracking is now in scope as its own product surface
  with its own spec and non-negotiables — see **`calorie-tracking-spec.md`**. What this
  non-goal *meant* still binds: no tedious manual nutrition logging, and nothing here dilutes
  the watch-first workout product.
- No manual workout logging, ever (N1).
- No non-wrist sensors or external hardware.
- No AI "coach" persona — voice or chat — during workouts (N5).

---

## 9. Science basis

- **Running effort / zones:** HR-zone aerobic-base ("Zone 2") training; established beginner run-walk protocols (NHS Couch-to-5K; Galloway). Specific defaults pending Q1/Q2.
- **Strength progression:** autoregulation / reps-in-reserve (Tuchscherer, Reactive Training Systems); ~1–3 RIR beginner target; Velocity-Based Training and velocity-loss thresholds (~25–30%) (González-Badillo, Pareja-Blanco).
- **IMU fatigue:** published work concentrated on running/gait (single wrist sensor a strong predictor — Op De Beéck et al.); jerk / spectral-entropy / stride-variability as fatigue markers; the large generic-vs-personalized accuracy gap motivating P3.
- **Encoder starting points:** HAR backbones and datasets (UCI-HAR, WISDM, PAMAP2, MotionSense); task-specific fatigue datasets (e.g., shoulder-rotation, *Nature Scientific Data*) — used for representation, not for transferable fatigue labels.
