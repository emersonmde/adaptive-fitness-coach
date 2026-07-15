import SwiftUI
import AdaptiveCore

/// The quiet daily line (spec §4.5 / CQ5): one glyph-anchored number, not a dashboard.
/// Trailing status lives in ONE reserved slot (principle 7): "Looking up N…" → "Saved" →
/// the camera entry. Hidden until the feature has ever been used (C6: absence, not shame —
/// a missed day shows nothing, never a zero or a streak).
struct DailyIntakeLine: View {
    @Bindable var controller: MealLogController
    let recorder: any NutritionRecorder
    var targetStore: CalorieTargetStore?
    let onCapture: () -> Void
    let onShowEntries: () -> Void

    @State private var intake: DailyIntake = DailyIntake()
    @State private var everUsed = Self.isEphemeral ? false : UserDefaults.standard.bool(forKey: Self.everUsedKey)
    @State private var refreshTick = 0

    static let everUsedKey = "mealLoggingEverUsed"
    /// UI tests get a clean first-use state every launch (UserDefaults outlives the
    /// throwaway stores `-uiTesting` provides).
    private static let isEphemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some View {
        Group {
            if everUsed || !intake.entries.isEmpty || isWorking {
                line
            } else {
                // First-run entry point: opens the FOOD SCREEN (Scan/Type/target live there) —
                // camera-direct entry belongs to the widget/Siri, not the discovery path
                // (build 8.1 fix: camera-direct here hid the food screen from new installs).
                Button(action: onShowEntries) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                        Text("Food")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal.dailyLine.firstUse")
            }
        }
        .task(id: refreshTick) { await refresh() }
        .task {
            // The stream ends when this task is cancelled on disappear — no leaked observers.
            for await _ in recorder.changes() { refreshTick += 1 }
        }
        .onChange(of: controller.phase) {
            refreshTick += 1
            if controller.phase == .logging {
                everUsed = true
                if !Self.isEphemeral {
                    UserDefaults.standard.set(true, forKey: Self.everUsedKey)
                }
            }
        }
        .onChange(of: controller.itemStatuses.map(\.state)) { refreshTick += 1 }
    }

    private var line: some View {
        HStack(spacing: 8) {
            Button(action: onShowEntries) {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(totalText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("meal.dailyLine.total")
                    if hasEstimates {
                        Circle()   // the one quiet estimate signal (C3, not a trust dashboard)
                            .fill(Theme.textTertiary)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("includes estimates")
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // One reserved slot: status when working, camera when idle — no layout jumps.
            ZStack(alignment: .trailing) {
                if hasFailedItems {
                    // P13: a failed Health write is a warning with an exit, not a caption in
                    // the same quiet tier as "Saved". Tap = retry the failed items in place.
                    Button {
                        Task { await controller.retryPending() }
                    } label: {
                        Label("Some didn't save", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.heat)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal.dailyLine.status")
                    .accessibilityHint("Retries saving to Health")
                } else if let status = statusText {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("meal.dailyLine.status")
                } else {
                    Button(action: onCapture) {
                        Image(systemName: "camera.viewfinder")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal.dailyLine.capture")
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.hairline))
        // .contain, not a bare identifier: a bare id on a stack half-registers and can
        // swallow the total/camera buttons from VoiceOver + XCUI (the build-15 bug class).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal.dailyLine")
    }

    private var isWorking: Bool {
        controller.phase == .logging
    }

    private var totalText: String {
        let kcal = Int(intake.totalKcal.rounded())
        // With a target: quiet arithmetic on the same single line — no new channel (build 8).
        if let target = targetStore?.target, kcal > 0 {
            return "\(kcal.formatted()) / \(target.formatted()) kcal"
        }
        return kcal == 0 ? "No meals logged today" : "\(kcal.formatted()) kcal today"
    }

    private var hasEstimates: Bool {
        intake.entries.contains { if case .estimate = $0.provenance { true } else { false } }
    }

    /// Failed writes settled (nothing still in flight) — the slot becomes the P13 warning.
    /// In-flight statuses outrank it, so a retry honestly reads "Looking up N…" again.
    private var hasFailedItems: Bool {
        let statuses = controller.itemStatuses
        let inFlight = statuses.contains { $0.state == .waiting || $0.state == .lookingUp }
        return !inFlight
            && statuses.contains { if case .failed = $0.state { true } else { false } }
    }

    /// Honest, minimal: counts still in flight, or a brief "Saved".
    private var statusText: String? {
        let statuses = controller.itemStatuses
        guard !statuses.isEmpty else { return nil }
        let inFlight = statuses.filter {
            $0.state == .waiting || $0.state == .lookingUp
        }.count
        if inFlight > 0 { return "Looking up \(inFlight)…" }
        if controller.phase == .done { return "Saved" }
        return nil
    }

    private func refresh() async {
        if let fresh = try? await recorder.todayIntake() {
            intake = fresh
        }
        // Read denial is invisible by design (HealthKit): on failure we keep whatever the
        // controller session knows and claim nothing about the full day.
    }
}
