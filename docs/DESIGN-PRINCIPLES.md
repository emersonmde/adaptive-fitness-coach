# Design Principles — distilled from the run screen

The run glance screen is the product's design high-water mark (user-validated on real runs).
These are the principles that make it work, written down so every future screen — P2's
redesigned strength screens first — is held to the same bar. Check new UI against this list
the way code is checked against the PRD's non-negotiables.

## The glance contract

1. **One dominant element per screen.** The run screen is the phase verb + interval timer;
   everything else recedes. If two things compete for the first 200ms of a glance, cut one.
   (Strength's analogue: the rep count / hold ring.)

2. **Color is the instruction, never a grade.** Green = run, cool blue = recover. The tinted
   near-black *field* telegraphs the state before any text is read. Hue meanings are learned
   once and never re-mapped — "green when you're doing well" was considered and rejected
   because it would make green ambiguous between *what to do* and *how you're doing*.

3. **One variable, one channel.** Hue = instruction. **Motion = attention/compliance** (the
   zone bar pulses when hot; the WALK verb throbs when cadence says you're still running).
   Weight/size = hierarchy. Never encode two meanings on one channel.

4. **Glance-safe color pairs only.** Green↔amber failed on a real run (sunlight washout,
   motion blur, red-green CVD ≈ 8% of men). Phase pairs must be far apart on the hue wheel
   without using red (red = danger only). Warm = effort, cool = recover.

5. **Glyph-anchor every number.** ♥ before HR, ⏱ before elapsed. The glyph identifies the
   number *before* it's read — and disambiguates against the unremovable system clock.
   Corollary: keep our time readouts in the corner *farthest* from the system clock.

6. **Two primary metrics, no vanity third.** In-workout top row = glyph-anchored session
   clock (left) · glyph-anchored HR (right). Promoting everything removes hierarchy; a glance
   should land on a metric, not scan a lineup. (The old center "n of N" interval counter was
   removed 2026-07-16: a run session is a time box, not a fixed interval count, so the count
   changes as the engine reshapes cycles — a moving denominator is a lie, not an ambient cue.)

7. **Reserve layout slots; never jump.** The adaptation cue / Start Run pill share one
   fixed-height slot (`Color.clear.frame(height:)`). Content appears and disappears without
   reflow — layout jumps read as glitches at a glance.

## The interaction contract

8. **Haptic-first; the screen confirms, it doesn't instruct** (N5). Cues are felt: triple
   bursts spaced ~350ms so at least one pulse lands between footfalls at running cadence.
   Distinct types per direction (sharp `.notification` = go, `.directionDown` = ease).

9. **Closed-loop cues with grace, cap, and acceptance.** A cue the body didn't follow gets
   re-signaled (cadence-verified) — but only after a grace period (deceleration isn't
   defiance), at most 3 times (alarms that cry wolf get ignored), and then the system
   *accepts* the user's choice: screen calms, and the choice is never punished by
   progression (`walksDefied`). The loop informs; it never fights the human.

10. **Effort rises only on evidence; it falls on suspicion.** Every threshold asymmetry
    (back-off windows vs extension gates, calibration tiers, progression rules) errs toward
    easier. The cheap error is always the recoverable one.

11. **Never make the user wait for bookkeeping.** End-of-workout is instant from local
    state; the OS finalize fills in totals in the background behind an honest status line
    ("Saving to Health… → Saved"). Optimistic UI, truthful labels (N2/N6): never claim
    "Saved" before the OS confirms.

12. **Adaptation must be quietly perceivable.** One calm line ("Next run: 2 min run · 90s
    walk") when something changed; silence when nothing did. Invisible adaptation reads as
    a broken product; chatty adaptation reads as nagging (Q5).

13. **Failure screens always have an exit.** Skip / End actions on every failure state —
    being wedged mid-workout is worse than the failure itself.

**Worked example (P2 rest ring):** one ring, one variable. With HR on an adaptive rest, a
strength-blue ring **fills** with recovery progress (blue = the recovery instruction) and the
falling heart rate is the hero. Without HR (or on a fixed rest card), the classic heat-amber
ring **drains** with time as the hero. A blue-over-amber dual arc was considered and rejected:
two arcs on one ring is two variables in one channel.

*(The original P2 strength-redesign checklist that closed this doc shipped in full and
was removed; the rest-ring worked example above remains as its record.)*
