# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A watch-first adaptive running app (iOS + watchOS, SwiftUI). For current status, milestone scope (P0 done; P1 next), and open TODOs, read **`docs/PROJECT-STATUS.md`** first, then the PRD `docs/adaptive-fitness-coach-spec.md`.

## Build & test

**Critical toolchain gotcha:** the watch target's minimum is **watchOS 27**, which ships only in the **watchOS 27 SDK → Xcode 27 beta** at `/Applications/Xcode-beta.app`. The default `xcode-select` is Xcode 26.5. Any `xcodebuild` for a device target (watch, or the iOS scheme — it embeds the watch app) **must** prefix `DEVELOPER_DIR`:

```bash
# Pure logic — the fast loop. Default toolchain, no simulator. ~62 tests.
cd AdaptiveCore && swift test
cd AdaptiveCore && swift test --filter AdaptationPolicyTests          # one suite
cd AdaptiveCore && swift test --filter IntervalStateMachineTests/nonPositiveDeltaIsInert  # one test

# Watch / iOS — need the beta. Target a watchOS 27 sim BY UDID (its name collides with the 26.5 sim).
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project "Adaptive Fitness Coach.xcodeproj" -scheme "Adaptive Fitness Coach Watch App" \
  -destination 'id=<watchOS-27-UDID>' build      # or: test
#   find a UDID:  xcrun simctl list devices available | grep -A6 "watchOS 27"

# Run a single XCUITest / Swift Testing case in a device target:
#   ... test -only-testing:"Adaptive Fitness CoachUITests/RoutineFlowUITests/testCreateRoutineAppearsInWeek"
```

**Phone UI tests are flaky in PARALLEL** (xcodebuild clone contention) — always add `-parallel-testing-enabled NO`. They pass reliably serially.

**Simulator launch args** (the sim generates no HR/zone data and `simctl` can't grant HealthKit/notification auth, so use these to demo/test):
- Watch `-simulateWorkout` — scripted HR/zones via `SimulatedWorkoutBackend`, compressed plan, auto-starts, skips the HealthKit prompt. **The only way to see the adaptive loop in the simulator.**
- Phone `-uiTesting` — throwaway store, skips the notification prompt (used by the XCUITests).
- Phone `-seedDemo` — throwaway store seeded with demo routines (QA/screenshots).

Adding a new `.swift` file under a target's folder auto-compiles it — the project uses **file-system-synchronized groups** (objectVersion 77), so no `project.pbxproj` edits are needed to add sources. Adding a *non-source* file to a target (e.g. the watch `Info.plist`) requires a `membershipExceptions` entry in the pbxproj.

## Architecture (the parts that span multiple files)

**The brain is a pure Swift package; the apps are thin shells.** All adaptation logic, models, and persistence live in **`AdaptiveCore/`** (Foundation only — no HealthKit, no SwiftUI), imported identically by both apps and exhaustively unit-tested on macOS without a simulator. When changing behavior, change it here and test with `swift test` before touching the device apps.

**The interval engine is deterministic and clock-free.** `IntervalStateMachine.tick(deltaTime:currentZone:)` is a value type the caller drives once a second; it consumes the heart-rate zone as a plain **`Int?`** and emits transitions (→ haptics) and adaptations (→ UI). `AdaptationPolicy` decides shorten/extend/lengthen using a leaky-integrator hysteresis (so a brief zone blip doesn't reset a sustained window) and **asymmetric confirming windows** — backing off is quicker than pushing effort (the PRD's "bias toward backing off"). Because the engine takes a number, it has no idea whether the zone came from Apple or a script — which is what makes it testable and the OS dependency swappable.

**Zone-as-position contract (subtle).** The engine compares `currentZone` to `targetZone` as a **1-based position** (1 = lowest zone; aerobic target = 2). `HealthKitWorkoutBackend` normalizes Apple's raw `HKWorkoutZone.index` (whose base is unspecified) into that position within the user's zone configuration; `SimulatedWorkoutBackend` already emits 1-based positions. Never assume Apple's index base elsewhere.

**The `WorkoutBackend` seam (watch).** `WorkoutSessionManager` (`@Observable`, the device shell that owns the `HKWorkoutSession` lifecycle + the tick loop + the observable UI state) talks to a `WorkoutBackend` protocol, not HealthKit directly. `HealthKitWorkoutBackend` is production (real `HKLiveWorkoutBuilder`, native `didUpdateWorkoutZone`); `SimulatedWorkoutBackend` is scripted. This is the seam that makes the whole workout deterministically testable (`WorkoutFlowTests`) and demoable in the simulator. The manager exposes a small `tick(delta:)` / `receiveZone(_:)` test surface and an `autoTick: false` flag so tests drive it without a clock.

**Data flow & sync.** The phone owns routines (`RoutineStore`, shared from `AdaptiveCore`); changes push to the watch one-directionally via `WatchConnectivity` `updateApplicationContext` (latest-state-wins, survives the counterpart being absent — supports "watch-first, phone-optional"). `WCMessageCodec` (in the package) is the shared serializer both sides use. The watch reads its own local `RoutineStore` populated by the received context; it never needs the phone present at workout time.

**The OS is the system of record (N2).** The app never writes its own HR/calorie/route samples — `HKLiveWorkoutBuilder` persists the workout to Apple Health on the app's behalf; the summary screen reads totals back. There is no private metrics store.

**Two-tier color system.** The **brand accent** (phone-only: CTAs, selected states, today-ring, hero glow) is emerald `#34E27A` — deliberately the *same* green as the `run` semantic, chosen by the user over the earlier Electric Lime `#C6FF3D` so the phone reads as one coherent green. Green=run / amber=walk / blue=strength / red=hot are **workout-state semantics**, a separate language tied to the watch's haptics and learned mid-run — the watch never uses the brand accent. Scheduling a routine writes a recurring **Calendar event** (EventKit, `CalendarService`), not a local notification. Tokens live in a `Theme` enum per target (`Adaptive Fitness Coach/Views/Components/Theme.swift` and `Adaptive Fitness Coach Watch App/Views/Theme.swift`). The implemented look is dark/neon and intentionally diverges from the light-mode `docs/design/*.html` handoffs (use those for screen *flows*, not visual style).

## Non-negotiables (from the PRD §3 — binding on design and engineering)

N1 logging is invisible · N2 real Apple workouts, OS is system of record · N3 effort adapts automatically · N4 watch-first / phone-optional · N5 haptic-first, glanceable (never require reading the watch mid-effort) · N6 graceful degradation, never fabricate a signal · N7 defaults are self-correcting seeds. These constrain every screen and behavior — check changes against them.

## Conventions

- Commit/PR trailers and not committing/pushing without being asked are covered by the global config; the user delegates branch/merge management to Claude (work on a feature branch per milestone, merge to `main` when green).
- Swift Testing (`import Testing`, `@Test`, `#expect`) for unit/integration tests; XCTest only for the XCUITest UI tests. Don't mix.
