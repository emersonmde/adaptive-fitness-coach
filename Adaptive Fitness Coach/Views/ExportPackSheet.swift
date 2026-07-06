import SwiftUI
import UIKit
import AdaptiveCore

/// P6 "Export to Claude": pick a use case, scope what goes in, copy one paste-able pack.
/// The includes-line is always visible and always honest; the first health-inclusive export
/// shows a one-time plain-words disclosure. Engine-agnostic by design — the same pack a
/// future Claude-API engine would consume.
struct ExportPackSheet: View {
    let store: RoutineStore
    let journal: ProgressionJournal
    var initialUseCase: ContextPackUseCase = .programDesign

    @Environment(\.dismiss) private var dismiss
    @State private var useCase: ContextPackUseCase
    @State private var scope: ContextPackScope
    @State private var isBuilding = false
    @State private var copiedToast = false
    @State private var showingDisclosure = false
    /// The export the disclosure is holding, resumed on Continue.
    @State private var pendingExport: ExportKind?
    /// Built lazily for ShareLink previews after the first build.
    @State private var sharePack: ContextPack?

    private let snapshotBuilder = HealthSnapshotBuilder()
    private let recorder = MealPipelineProvider.sharedRecorder
    private let targetStore = MealPipelineProvider.sharedTargetStore

    enum ExportKind { case copy, share }

    init(store: RoutineStore, journal: ProgressionJournal,
         initialUseCase: ContextPackUseCase = .programDesign) {
        self.store = store
        self.journal = journal
        self.initialUseCase = initialUseCase
        _useCase = State(initialValue: initialUseCase)
        _scope = State(initialValue: initialUseCase.preset)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        useCasePicker
                        scopeSection
                        includesFooter
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Export to Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { exportBar }
            .sheet(isPresented: $showingDisclosure) {
                HealthExportDisclosureSheet(
                    onContinue: {
                        HealthExportDisclosure.markShown()
                        showingDisclosure = false
                        if let kind = pendingExport { Task { await export(kind) } }
                        pendingExport = nil
                    },
                    onCancel: {
                        showingDisclosure = false
                        pendingExport = nil
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Copied for Claude", isPresented: $copiedToast) {
                Button("OK") {}
            } message: {
                Text("Paste it into the Claude app. If Claude returns updated routine JSON, copy that and use Import from clipboard on the week screen.")
            }
        }
    }

    // MARK: - Sections

    private var useCasePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("WHAT FOR")
            ForEach(ContextPackUseCase.allCases) { candidate in
                Button {
                    Theme.Haptics.selection()
                    withAnimation(Theme.Motion.settle) {
                        useCase = candidate
                        scope = candidate.preset
                    }
                } label: {
                    Card(padding: 12, cornerRadius: Theme.radiusInset) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(candidate.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: useCase == candidate ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(useCase == candidate ? Theme.accent : Theme.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export.usecase.\(candidate.rawValue)")
            }
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("WHAT GOES IN")
            Card(padding: 12, cornerRadius: Theme.radiusInset) {
                VStack(spacing: 10) {
                    Toggle("Routines", isOn: $scope.includeRoutines)
                        .accessibilityIdentifier("export.scope.routines")
                    if scope.includeRoutines, store.routines.count > 1 {
                        routineChecklist
                    }
                    Divider().overlay(Theme.hairline)
                    Toggle("Fitness snapshot", isOn: $scope.includeFitnessSnapshot)
                        .accessibilityIdentifier("export.scope.snapshot")
                    Divider().overlay(Theme.hairline)
                    HStack {
                        Text("Progression history")
                        Spacer()
                        Picker("Progression history", selection: $scope.journalDays) {
                            Text("Off").tag(Int?.none)
                            Text("30d").tag(Int?.some(30))
                            Text("90d").tag(Int?.some(90))
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                    Divider().overlay(Theme.hairline)
                    Toggle("Recent meals", isOn: $scope.includeNutrition)
                        .accessibilityIdentifier("export.scope.meals")
                }
                .font(.subheadline)
                .tint(Theme.accent)
            }
        }
    }

    private var routineChecklist: some View {
        VStack(spacing: 6) {
            ForEach(store.routines) { routine in
                Button {
                    toggleRoutine(routine.id)
                } label: {
                    HStack {
                        Text(routine.name)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: isIncluded(routine.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isIncluded(routine.id) ? Theme.accent : Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
    }

    private var includesFooter: some View {
        Label(currentIncludesLine, systemImage: "list.bullet.rectangle")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("export.includesLine")
    }

    private var exportBar: some View {
        HStack(spacing: 10) {
            Button {
                requestExport(.copy)
            } label: {
                if isBuilding {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Copy for Claude", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isBuilding)
            .accessibilityIdentifier("export.copy")

            Button {
                requestExport(.share)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isBuilding)
            .accessibilityIdentifier("export.share")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    // MARK: - Logic

    private var currentIncludesLine: String {
        ContextPackComposer.includesLine(
            useCase: useCase, scope: scope,
            input: ContextPackInput(routines: store.routines, journal: journal.entries)
        )
    }

    private func isIncluded(_ id: UUID) -> Bool {
        scope.routineIds?.contains(id) ?? true
    }

    private func toggleRoutine(_ id: UUID) {
        var ids = scope.routineIds ?? Set(store.routines.map(\.id))
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        scope.routineIds = ids == Set(store.routines.map(\.id)) ? nil : ids
    }

    private func requestExport(_ kind: ExportKind) {
        if scope.includesHealthData && !HealthExportDisclosure.wasShown {
            pendingExport = kind
            showingDisclosure = true
            return
        }
        Task { await export(kind) }
    }

    @MainActor
    private func export(_ kind: ExportKind) async {
        isBuilding = true
        defer { isBuilding = false }

        var snapshot: HealthSnapshot?
        var nutrition: NutritionDigest?
        if scope.includeFitnessSnapshot {
            try? await snapshotBuilder.requestAuthorization()
            snapshot = await snapshotBuilder.snapshot()
        }
        if scope.includeNutrition {
            nutrition = await NutritionDigestBuilder.digest(
                recorder: recorder, target: targetStore.target)
        }
        let pack = ContextPackComposer.pack(
            useCase: useCase, scope: scope,
            input: ContextPackInput(
                routines: store.routines,
                journal: journal.entries,
                snapshot: snapshot,
                nutrition: nutrition
            )
        )
        sharePack = pack
        switch kind {
        case .copy:
            UIPasteboard.general.string = pack.promptText
            Theme.Haptics.success()
            copiedToast = true
        case .share:
            presentShare(pack)
        }
    }

    /// ShareLink can't be triggered programmatically after an async build; the classic
    /// activity controller does the job for the one share path.
    private func presentShare(_ pack: ContextPack) {
        let activity = UIActivityViewController(activityItems: [pack.promptText],
                                                applicationActivities: nil)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first?.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(activity, animated: true)
    }
}

/// Sheet driver: which use case the export sheet opens on (mirrors `CoachLaunch`).
struct ExportLaunch: Identifiable {
    let id = UUID()
    let useCase: ContextPackUseCase
}

/// The one-time flag behind the first health-inclusive export. UI tests get a per-launch
/// in-memory flag so the disclosure is deterministic.
enum HealthExportDisclosure {
    private static let key = "healthExportDisclosureShown"
    private static var ephemeralShown = false
    private static var isEphemeral: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    static var wasShown: Bool {
        isEphemeral ? ephemeralShown : UserDefaults.standard.bool(forKey: key)
    }

    static func markShown() {
        if isEphemeral { ephemeralShown = true } else {
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

/// Honest, Oura/Whoop-register, never scary: what leaves, in plain words, once.
struct HealthExportDisclosureSheet: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Label("Your health data, as text", systemImage: "heart.text.square")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("This export copies the health numbers you selected — as plain text on your clipboard or share sheet. Once you paste it somewhere, that app's own privacy terms govern it. Share with apps you trust.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text("The includes-line on the export screen always shows exactly what's going in.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Continue", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("export.disclosure.continue")
                }
            }
            .padding(20)
        }
    }
}
