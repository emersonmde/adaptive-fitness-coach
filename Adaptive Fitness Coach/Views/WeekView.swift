import SwiftUI
import UIKit
import AdaptiveCore

/// P1 — the hub, rebuilt dark/neon. Top to bottom: an "Up Next" hero (what's next), a
/// week-at-a-glance strip, then one card per routine (a routine owns its days, shown once —
/// no more day-section duplication). "New routine" is the focal lime CTA.
struct WeekView: View {
    let store: RoutineStore
    @State private var showingNewRoutine = false

    // P3 coach: a tapped entry point stages an intent; the sheet owns the conversation.
    @State private var coachLaunch: CoachLaunch?

    // Manual Claude round-trip (RoutineExchange) — kept as the coach's fallback path.
    @State private var pendingImport: ImportCandidate?
    @State private var copied = false
    @State private var importError: String?
    @State private var importResult: String?

    // P4 meal logging: one controller + recorder per launch (provider decides scripted vs
    // production); capture is a full-screen cover, confirmation a sheet driven by phase.
    // Build 8: the daily line pushes FoodDayView; typed entry is a sibling sheet.
    @State private var mealController = MealPipelineProvider.makeController()
    @State private var showingMealCapture = false
    @State private var showingFoodDay = false
    @State private var showingTypedEntry = false
    /// The day the Food screen was showing when Scan/Type was tapped — prefills the
    /// when-row so browsing Tuesday + Add means backfilling Tuesday, not silently today.
    /// nil for every other entry point (daily line, widgets, Siri).
    @State private var mealCaptureContext: Date?
    private let mealRecorder = MealPipelineProvider.sharedRecorder
    private let mealTargetStore = MealPipelineProvider.sharedTargetStore
    @ObservedObject private var mealCaptureRequest = MealCaptureRequest.shared
    /// Programmatic pushes (the widget's afcoach://start/<id> deep link).
    @State private var navigationPath = NavigationPath()
    /// Days this week with a completed workout of ours (Health read-back → strip checks).
    @State private var doneDays: Set<DayOfWeek> = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if store.routines.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Your Week")
            // Large deliberately: the hub is the one root screen; every pushed/presented
            // screen is .inline.
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    claudeMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewRoutine = true
                    } label: {
                        Label("New routine", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newRoutineToolbar")
                }
            }
            .sheet(isPresented: $showingNewRoutine) {
                NewRoutineView(store: store)
            }
            .sheet(item: $coachLaunch) { launch in
                CoachChatView(store: store, intent: launch.intent) {
                    // Coach unavailable → the manual builder is the working exit.
                    showingNewRoutine = true
                }
            }
            .sheet(item: $pendingImport) { candidate in
                ImportRoutinesSheet(candidate: candidate,
                                    existingNames: Set(store.routines.map(\.name))) { incoming in
                    let result = store.importRoutines(incoming)
                    Task { await CalendarService.shared.syncAll(store.routines) }
                    importResult = "Updated \(result.updated), added \(result.added)."
                }
            }
            .alert("Copied for Claude", isPresented: $copied) {
                Button("OK") {}
            } message: {
                Text("Paste it into the Claude app to discuss changes. When Claude returns updated JSON, copy it and choose Import from clipboard.")
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Routines imported", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
                Button("OK") {}
            } message: {
                Text(importResult ?? "")
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(store: store, routineID: routine.id)
            }
            .fullScreenCover(isPresented: $showingMealCapture) {
                MealCaptureView { capture in
                    Task { await mealController.beginCapture(capture, preferredDate: mealCaptureContext) }
                }
            }
            // One continuous surface for the whole capture→confirm flow: the sheet appears
            // the moment identify starts (progress), becomes the confirmation, and holds a
            // failure honestly (retry) — never a silent gap where nothing seems to happen.
            .sheet(isPresented: Binding(
                get: { [.identifying, .confirming, .failed].contains(mealController.phase) },
                set: { presented in
                    if !presented && [.identifying, .confirming, .failed].contains(mealController.phase) {
                        mealController.cancel()
                    }
                }
            )) {
                MealConfirmationSheet(controller: mealController)
            }
            .sheet(isPresented: $showingTypedEntry) {
                TypedEntryView { capture in
                    Task { await mealController.beginCapture(capture, preferredDate: mealCaptureContext) }
                }
            }
            .navigationDestination(isPresented: $showingFoodDay) {
                FoodDayView(
                    controller: mealController,
                    recorder: mealRecorder,
                    targetStore: mealTargetStore,
                    bodyProfileSource: MealPipelineProvider.makeBodyProfileSource(),
                    onScan: { day in
                        mealCaptureContext = day
                        showingMealCapture = true
                    },
                    onType: { day in
                        mealCaptureContext = day
                        showingTypedEntry = true
                    }
                )
            }
            .task {
                // The App Intent / deep link may have fired before the scene existed.
                routeCaptureRequest()
                doneDays = await WorkoutWeekHistory.shared.doneDays()
                // Finish any lookups that were mid-flight when the app last quit (C5 queue).
                await mealController.resumePending()
            }
            .onChange(of: scenePhase) {
                // A workout finished on the watch while we were backgrounded → re-glance.
                if scenePhase == .active {
                    Task { doneDays = await WorkoutWeekHistory.shared.doneDays() }
                }
            }
            .onReceive(mealCaptureRequest.$pending) { pending in
                // Warm start: the intent/link fires while the week is on screen. @Published
                // publishes during willSet, so `pending` (the new value) arrives as a
                // parameter while the property still holds the OLD one — consuming
                // synchronously here read nil and stranded the request (Siri "Log a meal"
                // did nothing on a warm app). Defer one main-actor turn so consume() sees it.
                if pending != nil {
                    Task { @MainActor in routeCaptureRequest() }
                }
            }
            .onOpenURL { url in
                mealCaptureRequest.handle(url: url)   // afcoach://log/scan | /type (widgets)
                routeCaptureRequest()
                routeStartLink(url)                   // afcoach://start/<id> (next-workout widget)
            }
        }
    }

    /// The next-workout widget deep-links the routine it shows. The phone can't start the
    /// watch session, so "start" here means: land the user on that routine's detail.
    /// (Previously the id was parsed by nobody — the tap just opened the app.)
    private func routeStartLink(_ url: URL) {
        guard url.scheme == "afcoach", url.host == "start",
              let id = UUID(uuidString: url.lastPathComponent),
              let routine = store.routines.first(where: { $0.id == id }) else { return }
        navigationPath = NavigationPath([routine])
    }

    private func routeCaptureRequest() {
        switch mealCaptureRequest.consume() {
        case .scan:
            mealCaptureContext = nil   // widget/Siri entry points always mean "now"
            showingMealCapture = true
        case .type:
            mealCaptureContext = nil
            showingTypedEntry = true
        case .typed(let text):
            // Siri already collected the description — straight to identify → confirm.
            Task { await mealController.beginCapture(MealCapture(typedText: text)) }
        case nil:
            break
        }
    }

    private var dailyIntakeLine: some View {
        DailyIntakeLine(
            controller: mealController,
            recorder: mealRecorder,
            targetStore: mealTargetStore,
            onCapture: {
                mealCaptureContext = nil   // the daily line is a today surface
                showingMealCapture = true
            },
            onShowEntries: { showingFoodDay = true }
        )
    }

    /// The coach menu (P3): the native trainer conversation first, with the manual Claude-app
    /// round-trip retained underneath as the fallback when the model isn't available.
    private var claudeMenu: some View {
        Menu {
            Button {
                coachLaunch = CoachLaunch(intent: .buildNewPlan)
            } label: {
                Label("Plan my week", systemImage: "wand.and.stars")
            }
            .accessibilityIdentifier("coachPlanWeek")
            if !store.routines.isEmpty {
                Button {
                    coachLaunch = CoachLaunch(intent: .reviseAll)
                } label: {
                    Label("Rework my routines", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("coachReviseAll")
            }
            Section("Manual (Claude app)") {
                if !store.routines.isEmpty {
                    ShareLink(item: RoutineExchange.primingPrompt(store.routines)) {
                        Label("Share for Claude", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = RoutineExchange.primingPrompt(store.routines)
                        copied = true
                    } label: {
                        Label("Copy Claude prompt", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    importFromClipboard()
                } label: {
                    Label("Import from clipboard", systemImage: "square.and.arrow.down")
                }
            }
        } label: {
            Label("Coach", systemImage: "sparkles")
        }
        .accessibilityIdentifier("claudeMenu")
    }

    /// Parse the clipboard as RoutineExchange JSON and stage it for confirmation.
    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "Your clipboard is empty. Copy the JSON Claude gave you, then try again."
            return
        }
        do {
            let routines = try RoutineExchange.importRoutines(fromJSON: text)
            pendingImport = ImportCandidate(routines: routines)
        } catch RoutineExchange.ExchangeError.notJSON {
            importError = "That doesn't look like routine JSON. Copy the JSON code block Claude produced (including the braces)."
        } catch RoutineExchange.ExchangeError.unrecognizedSchema {
            importError = "That JSON isn't in this app's routine format. Ask Claude to return the set in the exact schema from the prompt."
        } catch RoutineExchange.ExchangeError.noRoutines {
            importError = "No routines could be read — the exercises may be ones this app doesn't have yet."
        } catch RoutineExchange.ExchangeError.malformedRoutines(let detail) {
            importError = "The JSON is in this app's format but part of it couldn't be read (\(detail)). Ask Claude to fix that field and copy it again."
        } catch {
            importError = "Couldn't read that import."
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let next = store.nextOccurrence() {
                    NavigationLink(value: next.routine) {
                        UpNextCard(routine: next.routine, date: next.date)
                    }
                    .buttonStyle(.plain)
                }

                WeekStrip(store: store, doneDays: doneDays)
                    .padding(.horizontal, 2)

                dailyIntakeLine

                VStack(alignment: .leading, spacing: 10) {
                    Text("ROUTINES")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)

                    ForEach(store.routines) { routine in
                        NavigationLink(value: routine) {
                            RoutineCard(routine: routine)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition { [reduceMotion] view, phase in
                            // Scale-on-scroll is a Reduce Motion target; the opacity
                            // de-emphasis alone survives it.
                            view.opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.97)
                        }
                    }
                }

                // No bottom "New routine" hero once routines exist: you create a routine a
                // handful of times ever, and the toolbar's + already owns the action — the
                // glow slot stays reserved for things done daily. (The empty state keeps
                // its big CTA; that's where it earns the prominence.)
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("No routines yet")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Build your week. Adaptive runs build themselves from your heart rate.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "New routine", systemImage: "plus") {
                showingNewRoutine = true
            }
            .accessibilityIdentifier("newRoutineEmptyState")
            .padding(.top, 4)
            // Quiet secondary door to the coach — the manual builder stays dominant (the app
            // is fully usable without AI).
            Button {
                coachLaunch = CoachLaunch(intent: .buildNewPlan)
            } label: {
                Label("Or let the coach build your week", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachEmptyState")

            // Meal logging is independent of routines — keep its door open on an empty week
            // (also what lets the meal UI tests run against the clean -uiTesting store).
            dailyIntakeLine
                .padding(.top, 12)
        }
        .padding(32)
    }
}
