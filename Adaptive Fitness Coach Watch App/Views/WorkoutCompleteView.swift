import SwiftUI
import AdaptiveCore

/// A5 — done. Shown the instant the session ends: everything the engine tracked itself
/// (time running, splits, intervals) is here immediately; distance and average HR fill in
/// when the OS finishes finalizing the workout in the background. The one status line tracks
/// that finalize honestly — "Saving…" → "Saved to Health".
///
/// P6.1 rework: the screen's hero is **time running** — the quantity the adaptive engine
/// actually moves, engine-owned so it never flashes a placeholder, and the number the
/// comparison lines speak to. Under it: the run/walk split sub-line, then a reserved slot
/// where "vs last run" / "vs 28-day baseline" fill in asynchronously from Health history
/// (silent when there is no history — never a spinner, never a fabricated zero). The effort
/// rating is coarse-level buttons (no crown — the crown's one job here is scrolling), and
/// `notePreview` still shows the rating's effect on next session live.
struct WorkoutCompleteView: View {
    let summary: SessionSummary
    var saveState: HealthSaveState = .saved
    /// Comparison lines, filled asynchronously by the container; nil while loading (the slot
    /// holds its height), empty when there's honestly nothing to compare against.
    var comparisons: [RunComparison.Line]?
    /// True when the session ended before meaningful work (under the first planned run
    /// interval) — offers the quiet "Discard workout" exit (W20). Keep is the default.
    var canDiscard = false
    /// The "Next run" note for a given effort — recomputed live as the level steps.
    var notePreview: (Int?) -> String?
    /// Deletes the just-saved workout and exits (W20). Only wired when `canDiscard`.
    var onDiscard: (() -> Void)? = nil
    /// Done with the rating and whether the user actually adjusted/confirmed it by touch.
    /// An untouched suggestion still records to Health (user decision) but must NOT gate
    /// progression: the suggestion is derived from the same objective signals the policy
    /// already consumes, so feeding it back would double-count them — an auto-suggested
    /// "Hard" would suppress the very probe a back-off session was designed to earn.
    let onDone: (Int?, _ userAdjusted: Bool) -> Void

    @State private var effort: Int?
    /// True once the user has interacted with the rating — until then the pre-selected level
    /// renders as a suggestion. The suggested value still counts at Done (user decision: the
    /// visible pre-selection is the confirmation surface).
    @State private var effortTouched = false

    /// The rating binding, wrapped so any interaction drops the "suggested" affordance.
    private var effortBinding: Binding<Int?> {
        Binding(
            get: { effort },
            set: { effort = $0; effortTouched = true }
        )
    }

    private var distanceText: String? {
        guard let meters = summary.totalDistance, meters > 0 else { return nil }
        return String(format: "%.2f km", meters / 1000)
    }

    private var saveLine: (text: String, color: Color) {
        switch saveState {
        case .saving: ("Saving to Health…", .secondary)
        case .saved: ("Saved to Health", WatchTheme.run)
        case .unconfirmed: ("Check Health for this workout", .secondary)
        }
    }

    /// "6 runs · 5 walks · 62% running" — all engine-owned, instant. Percentage only when
    /// both phases actually happened.
    private var splitLine: String? {
        guard summary.intervalsCompleted > 0 else { return nil }
        var parts = ["\(summary.intervalsCompleted) run\(summary.intervalsCompleted == 1 ? "" : "s")"]
        if summary.walksCompleted > 0 {
            parts.append("\(summary.walksCompleted) walk\(summary.walksCompleted == 1 ? "" : "s")")
        }
        let moving = summary.totalRunDuration + summary.totalWalkDuration
        if moving > 0, summary.totalWalkDuration > 0 {
            parts.append("\(Int((summary.totalRunDuration / moving * 100).rounded()))% running")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Identity moment, compressed — the hero below owns the screen now. An
                // ended-early session drops the celebration grammar entirely (W17): neutral
                // title, no checkmark, no bounce — the save line stays honest either way.
                if summary.endedEarly {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(WatchTheme.textSecondary)
                        Text("Ended early")
                            .font(.title3.bold())
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(WatchTheme.run)
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text("Done")
                            .font(.title3.bold())
                    }
                }
                Text(saveLine.text)
                    .font(.caption2)
                    .foregroundStyle(saveLine.color)
                    .animation(WatchTheme.Motion.settle, value: saveState)

                // HERO: time running — glyph-anchored so the number identifies itself (N5).
                // A session that never reached its first run has no running time to show:
                // "0:00 running" as the hero fabricates a grade out of a mis-tap, so show
                // the honest quantity instead — total elapsed (W18).
                if summary.totalRunDuration == 0 {
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "clock")
                                .font(.body)
                                .foregroundStyle(WatchTheme.textSecondary)
                            Text(summary.totalDuration.clockString)
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        }
                        Text("ended before the first run interval")
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "figure.run")
                            .font(.body)
                            .foregroundStyle(WatchTheme.run)
                        Text(summary.totalRunDuration.clockString)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("running")
                            .font(.caption)
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                }

                if let splitLine {
                    Text(splitLine)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                }

                // Reserved comparison slot: fixed height whether loading, empty, or filled —
                // the layout never jumps when Health answers (or doesn't).
                comparisonSlot
                    .frame(minHeight: 28)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    // Totals owned by the OS appear once the finalize returns; a quiet dash
                    // holds the slot so the layout never jumps.
                    stat("Distance", distanceText ?? "—")
                    stat("Avg HR", summary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                    stat("Longest run", RunComparison.clock(summary.longestRunSeconds))
                    if summary.timeInTargetZone > 0 {
                        stat("In zone", summary.timeInTargetZone.clockString)
                    }
                    if let drop = summary.meanRecoveryDrop {
                        stat("Recovery drop", "\(Int(drop.rounded())) bpm")
                    }
                    if summary.adaptationsApplied > 0 {
                        stat("Adaptations", "\(summary.adaptationsApplied)")
                    }
                    // Quietly explain a cooldown that ran visibly long: adaptation-shortened
                    // intervals were backfilled as easy walking to honor the planned length.
                    if summary.backfilledCooldownSeconds > 60 {
                        stat("Cooldown extended", "+\(summary.backfilledCooldownSeconds.clockString)")
                    }
                }
                .padding(.top, 2)

                EffortRatingControl(effort: effortBinding, tint: WatchTheme.run,
                                    isSuggested: effort != nil && !effortTouched)
                    .padding(.top, 6)
                    .onAppear {
                        // Pre-select the HR-derived suggestion (session-RPE is predictable
                        // from the objective signals); nil when the session was signal-blind —
                        // never suggest from nothing (N6).
                        guard effort == nil, !effortTouched else { return }
                        effort = EffortPredictor.suggestedLevel(from: summary)?.score
                    }

                // The note previews what progression will actually see: an untouched
                // suggestion doesn't gate the policy, so it doesn't move the preview either.
                // Reserved slot (T5): the note comes and goes as the effort level steps —
                // a fixed-height slot keeps the Done button from jumping under the finger.
                Group {
                    if let note = notePreview(effortTouched ? effort : nil) {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.run)
                            .multilineTextAlignment(.center)
                            .animation(WatchTheme.Motion.settle, value: note)
                    } else {
                        Color.clear
                    }
                }
                .frame(minHeight: 26)
                .padding(.top, 2)

                Button("Done") { onDone(effort, effortTouched) }
                    .tint(WatchTheme.run)
                    .padding(.top, 4)

                // The mis-tap exit (W20): quiet, destructive-tinted, below Done — keep is
                // the default. One tap, no confirm sheet: at this size the workout is
                // seconds old and re-doing it costs nothing (N5 — no modal ceremony).
                if canDiscard, let onDiscard {
                    Button("Discard workout", role: .destructive, action: onDiscard)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(WatchTheme.hot)
                        .padding(.top, 2)
                        // Visual stays a quiet caption; the target meets the 44pt floor.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 6)
        }
    }

    /// The comparison lines: facts, never grades. An upward move tints run-green (more
    /// running is the hue's own quantity); a downward one stays neutral secondary — no red,
    /// no shame. Silent while loading and when history is honestly absent.
    @ViewBuilder private var comparisonSlot: some View {
        if let comparisons, !comparisons.isEmpty {
            VStack(spacing: 2) {
                ForEach(comparisons, id: \.self) { line in
                    HStack(spacing: 4) {
                        Text(line.delta)
                            .fontWeight(.semibold)
                            .foregroundStyle(line.improved == true ? WatchTheme.run : Color.primary)
                        Text(line.label)
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    .font(.caption2)
                }
            }
            .transition(.opacity)
            .animation(WatchTheme.Motion.settle, value: comparisons)
        } else {
            Color.clear
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(WatchTheme.textSecondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.footnote)
        .animation(WatchTheme.Motion.settle, value: value)
    }
}
