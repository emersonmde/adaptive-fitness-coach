# The Nutrition System — how meals are logged and the energy budget adapts

The design reference for the food side of the app: how a meal becomes a logged number, how the
daily calorie **budget** is set and adapts through the day, and the science and algorithms behind
the target math. Read this before changing anything under `AdaptiveCore/Sources/AdaptiveCore/Nutrition/`,
the phone's `Services/Nutrition/`, or the Food screens.

Companion to **`docs/calorie-tracking-spec.md`** (the P4 product spec — C1–C7, the capture pipeline,
the retrieval-before-estimation thesis). That doc is *what and why at the product level*; this doc is
*how the mechanisms work and the invariants a change must preserve* — the nutrition analogue of
`ADAPTIVE-SYSTEM.md`.

**Drift policy (same as ADAPTIVE-SYSTEM.md).** This doc anchors on type names, constant identifiers,
invariants, and contracts — never line numbers or code quotes. The durable truth is the *relationships*
(e.g. "active energy is realized, never forecast"; "weight calibrates total TDEE, not basal vs active").
Numeric defaults live in the snapshot table (§7), marked as such — tuning a constant updates its cell and
nothing else. Everything named is greppable; if a grep for an identifier fails, the doc has drifted and
the code wins.

---

## 1. Shape of the system

Same discipline as the workout engine: **all intelligence is pure Foundation-only value types in the
`AdaptiveCore` package** (no HealthKit, no SwiftUI, no `Date.now`), imported identically by the app and
exhaustively unit-tested with `swift test`. The phone is a thin shell that owns HealthKit, persistence,
and the clock.

**Apple Health is the system of record (C5).** The app writes `dietaryEnergyConsumed` (+ macros) the way
Health logs water, and reads intake, active energy, weight, and body profile back out. There is no private
nutrition or metrics store; deleting the app loses no data. Everything downstream — the budget, the
calibration — is computed from what Health already holds.

---

## 2. Capture → log → Health (the logging pipeline)

The staged, retrieval-first pipeline is specified in `calorie-tracking-spec.md` §5 and lives in
`AdaptiveCore/Nutrition/` (`MealPipeline`, `MealResolver`, `MealLogController`, `NutritionModels`) with a
`ScriptedMealPipeline` fake behind `-simulateMealScan`. In brief: **capture** (receipt / barcode / label /
plate) → **identify** seller + items → **confirm** (native checkboxed screen, tap not type) → **research**
(per-item lookup, provenance-graded) → **write** to Health via `NutritionRecorder`. Provenance (verified /
database / estimate) is never flattened; an estimate shows as a range, never a false-precise number (C3/N6).

`NutritionRecorder` (protocol in the package; `HealthKitNutritionRecorder` on phone, `InMemoryNutritionRecorder`
for sim/tests) is the write/read seam. `intake(on:)` sums a day's dietary energy (all sources); our entries
carry full metadata in an `HKCorrelation`, energy from other apps counts toward the total but stays unlabeled.

**Three distinct UI states, everywhere (binding standard).** Real data / genuinely-empty / failed-to-load are
never conflated. A failed HealthKit read renders "Couldn't read this day — Try again", never the empty-day
text, and a failed fetch never seeds the day cache (a fabricated-empty snapshot once made the whole history
look deleted). *A failed read must never render as absence.*

---

## 3. The energy budget (build 22)

The daily target is not a fixed number — it is a **live budget** that rises through the day as the watch banks
active energy, built entirely from Health data. The primitive the user chooses is a **deficit** (kcal/day
below maintenance).

**The model** (`DynamicDayBudget`, pure):

```
budget(t) = max(floor,  basalTrust·BMR  −  deficit  +  activeTrust·activeEarnedSoFar(t))
```

- **BMR** — Mifflin–St Jeor from the Health body profile (`CalorieTargetCalculator.bmr`), banked up front.
- **activeEarnedSoFar(t)** — Apple `activeEnergyBurned` cumulative from local midnight to now. **Realized as
  earned, never forecast** — this is the load-bearing design choice. Because active energy is only ever
  counted once the watch has recorded it, all three hard cases fall out for free: an idle morning shows a sane
  floor (not an impossible low number), a morning workout banks calories that stay banked (no assumption they
  continue), an evening workout grows the budget in the evening (never underestimated during the day). At day's
  end `activeEarnedSoFar` is the full day's active, so the final budget equals **TDEE − deficit** exactly;
  intraday it is a conservative running "safe to eat" number.
- **deficit** — the user's chosen kcal/day (0 = maintain, negative = surplus).
- **floor** — `CalorieTargetCalculator.floorKcal` (1200). Never suggest an unsafe intake. An aggressive deficit
  that would push the resting budget below the floor sits at the floor and rises as activity banks — the deficit
  is "earned through the day". Surfaced as a gentle "at your safe minimum — move more to unlock your full
  deficit" hint (`isAtFloor`).

**Why measured active replaces the old activity multiplier.** The build-8 target used `BMR × ActivityLevel`
(1.2–1.725) ± a ±500 goal. The watch measures NEAT + exercise directly and per-day, so the multiplier is gone
from the budget path — measured active is strictly more personalized. (TEF, ~10% of intake, is captured by
neither term — a safe under-count of expenditure; not modeled.)

**Modes.** `CalorieTargetStore` holds either a **deficit** (Health has body data → `DynamicDayBudget`) or a
**fixed** manual number (Health lacks the body data → the old static `DayBudget`, unchanged). No migration of a
pre-build-22 fixed number: the target is a *preference*, not data (all meals/weight/energy are in Health), so a
returning user simply re-picks a deficit — which then reflects all their existing Health history — rather than
being stranded on the old fixed-number mode.

---

## 4. Scientific parameters (defaults + rationale)

Constants carry sourced doc comments in `EnergyBudget.swift`; see §7 for the snapshot.

- **`activeTrust = 0.80`** — a −20% haircut on watch active energy. Apple Watch systematically *overestimates*
  active energy (validation meta-analyses: signed mean error ≈ −7%…+53%, MAPE ≈ 28%, predominantly positive).
  ×0.80 lands near the true mean, biased slightly conservative. The asymmetry justifies erring low:
  over-discounting only enlarges an already-safe deficit; trusting the watch banks phantom calories → "doing
  everything right, no results", the one failure mode this feature exists to prevent.
- **`basalTrust = 1.0`** — no haircut. Mifflin–St Jeor is *unbiased* at the population level (95% CI ≈ −26…+8
  kcal/day); its error is symmetric individual variance (~±10%), not bias. Basal needs an uncertainty *band*
  (the calibration's prior SD), not a point shift.
- **`tissueKcalPerKg = 7700`** — energy density of body-mass change, for reverse-calculating TDEE from a weight
  trend. Standard mixed-tissue rule; approximate (water/glycogen wash out only over ≥2–4 weeks — hence a trend
  fit, not endpoint-minus-endpoint).

---

## 5. Weight-trend calibration (Bayesian shrinkage)

`EnergyBalanceCalibrator` learns a per-user correction so the budget converges on the user's *real* metabolism
rather than the textbook estimate. It is pure and takes trailing daily series (weight, intake, active) from an
`EnergyHistorySource`.

**The estimate.** From the trailing window (up to 28 days):

```
TDEE_obs = mean_daily_intake − slope·7700          // slope = kg/day from a least-squares weight trend fit
```

blended with the population prior by **precision weighting** (`w = 1/variance`):

```
TDEE_post = (w_obs·TDEE_obs + w_prior·TDEE_prior) / (w_obs + w_prior)
```

As the window lengthens and weigh-ins accumulate, the observation's standard error shrinks (slope SE ∝ σ/n^1.5),
so the posterior **migrates continuously** from the safe default toward the personal value — no hard threshold,
no fixed wait. "Mostly personal" arrives around 3–4 weeks of regular weigh-ins; sparse or estimated weight simply
keeps it near the prior. *This is the answer to "when does the custom factor beat the general 28%/10%": the
moment the observation's SE drops below the prior's SD, precision weighting tips toward personal — automatically,
at whatever cadence the user weighs in.*

**Identifiability (binding).** A weight trend constrains only the **sum** (total TDEE), never basal vs active
separately. The whole learned residual is therefore folded into **`basalTrust`** (personal metabolism is the
dominant unknown weight reveals); **`activeTrust` stays at its sensor-derived prior** (watch bias is a device
property, not personal metabolism, and can't be separated from weight data).

**Guardrails.** `basalTrust` is clamped to `basalTrustBounds` (0.7–1.3); implausible weight samples and
low-intake-coverage days are down-weighted; shrinkage keeps thin data near the prior automatically. A
user-facing "tuned to your data" note (`Calibration.isConfident` / `deviationPercent`) appears only with enough
clean evidence (≥14-day span, ≥8 weigh-ins, coverage ≥ 0.5, and the observation SE below the prior SD).

**Known limitations (stated, not hidden).**
- The estimate inherits the user's **intake-logging accuracy** — chronic under-logging biases `TDEE_obs` low,
  pulling `basalTrust` down (targets slightly *lower* — the safe direction). The clamp and prior bound the damage.
- **BMR uses the latest `bodyMass` sample even if stale** — basal is slightly off until a scale reports, then
  self-heals once regular weigh-ins engage the calibration.

---

## 6. Data flow, persistence, refresh

- **`EnergyHistorySource`** (protocol; `HealthKitEnergyHistorySource` on phone, `InMemoryEnergyHistorySource`
  for sim/tests) supplies the trailing series. The HealthKit impl uses `HKStatisticsCollectionQuery` (daily
  buckets for dietary + active energy) and an `HKSampleQuery` for `bodyMass`; all three reads are already
  authorized elsewhere.
- **`CalorieTargetStore`** (`@MainActor @Observable`, UserDefaults-backed, ephemeral under `-uiTesting`) persists
  the deficit / fixed target, the cached BMR, and the `Calibration` snapshot. It builds the budget
  (`dynamicBudget(consumedKcal:activeEarnedKcal:)` → `DynamicDayBudget`, or `budget(consumedKcal:)` → `DayBudget`
  in fixed mode) and exposes a back-compat `target: Int?` (the resting baseline) for the hub line and export pack.
- **Refresh is on-demand, once a day.** `refreshCalibration()` is called from `FoodDayView.task`; it throttles to
  one recompute per calendar day (weight moves over weeks). The intraday budget recomputes on the existing
  `refreshTick` / active-energy fetch. No background-refresh infrastructure.
- **UI surfacing** (`FoodDayView` + `CalorieGaugeView`): the live ring, a "+N earned today" line, the at-floor
  hint, and the plain-language calibration note — within N1/N5/C6 (quiet, glanceable, no alarms/streaks).
  `TargetSetupSheet` collects the deficit (presets + custom) with a live resting-target preview.

---

## 7. Numeric snapshot (tune here, then update the cell)

| Constant | Value | Meaning |
|----------|-------|---------|
| `EnergyBudgetConstants.activeTrustDefault` | 0.80 | haircut on watch active energy (−20%) |
| `EnergyBudgetConstants.basalTrustDefault` | 1.0 | no haircut on Mifflin BMR (unbiased) |
| `EnergyBudgetConstants.tissueKcalPerKg` | 7700 | energy density of weight change |
| `EnergyBudgetConstants.basalTrustBounds` | 0.70…1.30 | clamp on the learned basal correction |
| `EnergyBudgetConstants.priorTdeeCoefficientOfVariation` | 0.10 | prior SD as a fraction of TDEE |
| `CalorieTargetCalculator.floorKcal` | 1200 | never suggest below this intake |
| calibration window | 28 days | trailing series length |
| confidence gate | span ≥14 d, ≥8 weigh-ins, coverage ≥0.5 | before showing "tuned to your data" |

---

## 8. Testing philosophy

Weight moves too slowly to hand-validate a calibration, so the estimator is validated **against synthetic
ground truth** (`EnergyBudgetTests.swift`, Swift Testing). A seeded deterministic PRNG builds a virtual person
with a *known* true BMR and active pattern, then feeds noisy simulated inputs (watch active with +bias+noise,
daily weight with water noise + sodium spikes, intake with logging noise). The tests assert the recovered TDEE
converges to truth (unbiased across seeds, beats the prior by >2×), the posterior SE shrinks as evidence
accrues, personal beats default by ~3–4 weeks, the reported SD is calibrated against actual error, and the
guardrails keep thin/noisy/under-logged data near the safe prior. This is the standard way to test an estimator
whose real-world ground truth is unobservably slow, and it fits the package's deterministic pure-test model.

---

## Deferred (kept easy by the deficit-primitive)

- **"Lose X lb/week"** as a *view* over the deficit, via a **dynamic** energy-balance model (Kevin Hall / NIH
  Body Weight Planner). **Never the 3500-kcal rule** — it ignores metabolic adaptation and was retired by the
  American Society for Nutrition in 2012.
- **Per-user `activeTrust`** — needs a signal separating basal vs active (e.g. rest-day vs workout-day weight
  response), which a flat weight trend cannot provide.
- TEF modeling; an optional personal-average "expected active" morning baseline (rejected to keep the
  realize-as-earned model honest).
