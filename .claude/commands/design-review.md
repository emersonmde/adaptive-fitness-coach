---
description: Comprehensive sr-designer UI/UX review of the whole app (watch + phone) — per-screen fan-out + per-flow holistic + cross-cutting & cross-device lenses + best-in-class research + redesign ideation → verified report + roadmap draft
---

# Whole-app (watch + iPhone) — comprehensive UI/UX design review & roadmap ideation

Act as a **senior product designer specializing in wearables and companion apps** conducting a
full design review of the app across both devices, at the depth a paid human design audit
would reach. The deliverable is a
report that seeds the project's **next roadmap** (the current one is complete): ideas big and
small, from one-line polish to major redesigns, for the user to triage later. Breadth of
credible ideas beats a short pre-filtered list — the user decides what makes the roadmap, not
the review.

**The review runs on YOUR design expertise and research, not the project's self-image.** The
project's docs describe current intent, not immutable law: if evidence or best practice says a
principle, PRD requirement, or "non-negotiable" is holding the UX back, say so and propose the
change — clearly labeled as a principle/requirement change with the reasoning and what it
unlocks. Nothing is sacred except the user's actual outcomes on the wrist.

Use the **Workflow tool** to orchestrate: the user has opted into multi-agent fan-out for this
command. Use the `ui-design-reviewer` agent type for review-stage agents. Token cost is
accepted; optimize for coverage and idea quality.

## Inputs every agent grounds in

- **The storyboards** (each has a `README.md` index — screen → flow → notes, incl. known sim
  artifacts; `raw/` holds bursts and transitional frames):
  - Watch: `design-review/watch-storyboard-2026-07-13/` — 38 screenshots, 5 flows.
  - Phone: `design-review/phone-storyboard-2026-07-14/` — 38 screenshots, 6 flows (home hub,
    routines, progression, coach/Claude round-trip, food, permission moments).
- **Current design intent** (context to understand, license to challenge):
  `docs/adaptive-fitness-coach-spec.md` §3 (N1–N7), `docs/DESIGN-PRINCIPLES.md` (the "glance
  contract"; the run screen is the user-validated high-water mark — challenging it requires
  real evidence, not taste), CLAUDE.md's "Two-tier color system" section (the dark/neon look
  deliberately diverges from the light `docs/design/*.html` handoffs).
- **Design-craft calibration**: each review agent loads the `frontend-design` skill (Skill
  tool); if unavailable in the agent, Read its SKILL.md under
  `~/.claude/plugins/cache/claude-code-plugins/frontend-design/`.
- **The live app when a still isn't enough**: drive the watchOS 27 or iOS 27 sim with
  `simctl launch` (per-flow `-simulate*`/`-seed*` args are listed in each storyboard README
  and CLAUDE.md) + `axe tap/swipe/type --udid` + `simctl io screenshot` to reproduce states,
  test hunches, or capture missing variants.
- **Token sources of truth**: `Adaptive Fitness Coach Watch App/Views/Theme.swift` and
  `Adaptive Fitness Coach/Views/Components/Theme.swift` (colors, motion, haptics, gestures).
  Verify suspected inconsistencies against code before reporting.

## Orchestration shape

**Phase 0 — scope (inline).** Read both storyboard READMEs; enumerate ~76 screens across 11
flows on two devices, and each README's known-gaps list (crown-only states on watch;
widgets/Siri/real-camera/share sheets on phone — not missing coverage).

**Phase 1 — research (fan out, ~4 agents).** Before judging anything, build the expertise
base. Agents research via WebSearch/WebFetch and distill into pattern briefs with sources:
1. **watchOS + iOS HIG & platform state of the art** — current design guidance for both,
   workout-app and health-app conventions, what Apple's own Workout/Fitness apps do and why.
2. **Best-in-class competitors** — Strava, WorkOutDoors, Gentler Streak, Nike Run Club,
   Peloton, Athlytic, and phone-side MacroFactor/MyFitnessPal/Lose It: what their UX gets
   right/wrong — glanceability, adaptivity communication, post-workout moments, and
   friction-free food logging.
3. **Wearable interaction research** — glanceability findings, mid-exertion legibility,
   haptic vocabulary design, one-handed/no-look interaction.
4. **Fitness-coaching & AI-coach UX** — how products communicate *adaptive* decisions without
   eroding trust (N3's automatic effort adaptation is the differentiator), and current
   patterns for AI-proposal → human-confirm flows like the coach's.
These briefs are distributed to every later agent.

**Phase 2 — per-screen review (fan out, pipeline).** One agent per screen (tightly-coupled
variants may share, e.g. the four run-summary scroll states). Each agent judges the still as
a screen — hierarchy in the first 200ms, layout/spacing, typography, color semantics and
CVD/sunlight robustness, copy, touch targets, Dynamic Type resilience, honest states (loading/
empty/failure) — informed by the research briefs and the glance contract. Each finding:
`{screen, observation, evidence/principle, severity(blocker/major/minor/polish),
recommendation, effort(S/M/L), confidence}`. Each agent must also report **one thing the
screen does well** (protect list) and **one ambitious "what if" idea** — a bigger swing than
the incremental fix, even if speculative.

**Phase 3 — per-flow holistic review (fan out, one agent per flow).** Walk the flow's screens
in order as a first-time user: narrative coherence, transition logic, copy consistency, where
the moment of truth lands, dead ends, what a sweaty mid-run glance vs a calm post-run read
each need. Then as a 30-day retained user: what gets tedious, what should have receded. Flag
cross-screen inconsistencies invisible at single-screen zoom.

**Phase 4 — cross-cutting lenses (fan out, one agent per lens).**
1. Accessibility & glanceability (contrast, CVD, motion-as-channel, target sizes).
2. Type & spacing system coherence (one scale or per-screen improvisation? audit vs Theme.swift).
3. Color-system integrity (two-tier rule; any hue doing two jobs?).
4. Copy & voice (one register; promise→result naming through flows).
5. Platform HIG conformance, both OSes (where divergence is deliberate vs accidental — use
   the research briefs).
6. Interaction cost (taps/scrolls per job-to-be-done; what should be zero-read per N5).
7. **Adaptivity legibility** — is the app's core promise (it adapts to you) *perceivable and
   trustworthy* on the wrist, on the phone, and afterward? The differentiator; judge it hardest.
8. **Cross-device continuity** — the handoffs ARE the product: quick-log parks on the wrist →
   resolves on the phone; progression earned on the watch → confirmed on the phone; routines
   authored on the phone → consumed on the watch; permission moments interrupting flows. Do
   the two devices feel like one product (vocabulary, color language, promise→result copy),
   and does each handoff tell the user where the baton is?
Motion/haptics can't be judged from stills: audit token usage in both targets' views and flag
code-level incoherence (missing Reduce Motion paths, unpulsed attention states), labeled as
needing on-device verify.

**Phase 5 — redesign ideation (fan out, ~4 visionary agents).** Freed from incrementalism,
each proposes bold alternatives grounded in the research: e.g. rethink the session pager, the
summary moment, the home hub, the food-logging loop, the adaptation-communication model, the
cross-device handoff story. Each concept: the idea, what it improves, what it costs, which
current principles/requirements it would change, and a rough mockup description. Divergent by
construction — assign each agent a different starting lens (platform-native maximalist /
radical-minimalist / coaching-first / continuity-first).

**Phase 6 — adversarial verify (fan out over deduped findings).** A skeptic tries to kill
each finding: sim artifact? already true in code? contradicts real evidence? not worth a
sprint? **Contradicting a current principle or N-rule does NOT kill a finding** — reclassify
it as `requires-principle-change` with the tradeoff stated. Keep verdicts attached. Ideation
concepts aren't killed, only annotated with feasibility/risk.

**Phase 7 — synthesis.** Produce `docs/design/DESIGN-REVIEW-2026-07.md`:
- Executive summary: the honest overall read and the three changes that matter most.
- Scorecard (/5 + one-line justification): glanceability, hierarchy, color system,
  typography, copy, accessibility, flow coherence, state honesty, adaptivity legibility.
- What's working (protect list).
- Verified findings by severity, with screen refs, recommendation, effort, verdict.
- Principle/requirement challenges — each with evidence, tradeoff, and what it unlocks.
- Redesign concepts (from Phase 5) with feasibility annotations.
- Hardware-verify list.
- **Roadmap draft**: everything clustered into themes across three horizons —
  *polish now* (S/M fixes), *next milestone* (flow-level reworks), *big swings* (redesigns /
  principle changes) — each item with impact rationale and acceptance criteria phrased as
  design outcomes. Mark it as the proposed successor to the completed roadmap in
  `docs/PROJECT-STATUS.md`; do not rewrite PROJECT-STATUS itself without the user.

## Cautions (tell every agent)

- **Sim artifacts, not bugs** (each README's notes section lists them): watch safe-area
  under-render (edge-clipped stat lines → "verify on hardware"), Water Lock shows no visible
  state, canned/scripted data everywhere (comparison lines, kcal numbers, coach prose from
  `ScriptedCoachEngine` — review the coach's structure, not its writing), 0:00 durations from
  compressed `-simulate*` scripts, ephemeral stores resetting between phone launches, and the
  red disconnected-phone status icon.
- Watch screenshots are @2x pixels of a 187×223pt (42mm) canvas; phone is @3x of 402×874pt
  (iPhone 17 Pro); convert before claiming sizes.
- The phone forces dark mode by design — do not report a missing light mode as a bug, though
  challenging that choice with evidence is fair game.
- Ambition is welcome; hand-waving is not. Every recommendation — incremental or radical —
  needs a reason a senior designer would defend, grounded in the research briefs, the
  screenshots, or the code.

Run the phases, then deliver the report path and a chat summary leading with the three
highest-leverage recommendations and the boldest idea worth prototyping.
