import SwiftUI
import AdaptiveCore

/// Today's logged meals, read back from Apple Health (C5 — Health is the record; this is a
/// window onto it). Each row: name, honest number (ranges stay ranges — C3), a quiet
/// provenance word with its source link. Swipe-to-delete deletes the Health sample.
struct TodayEntriesSheet: View {
    let recorder: any NutritionRecorder
    @State private var intake = DailyIntake()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if intake.entries.isEmpty {
                    Text("Nothing logged today.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    List {
                        ForEach(intake.entries) { entry in
                            row(entry)
                                .listRowBackground(Theme.surface1)
                        }
                        .onDelete { offsets in
                            Task { await delete(at: offsets) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await refresh() }
    }

    private var titleText: String {
        let kcal = Int(intake.totalKcal.rounded())
        return kcal == 0 ? "Today" : "Today · \(kcal.formatted()) kcal"
    }

    private func row(_ entry: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.quantity > 1 ? "\(entry.name) ×\(entry.quantity)" : entry.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(energyText(entry))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Text(provenanceText(entry.provenance))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                if let url = entry.provenance.sourceURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func energyText(_ entry: MealEntry) -> String {
        let servings = Double(max(1, entry.quantity))
        switch entry.facts.energy {
        case .exact(let kcal):
            return "\(Int((kcal * servings).rounded())) kcal"
        case .range(let low, let high):
            return "\(Int((low * servings).rounded()))–\(Int((high * servings).rounded())) kcal"
        }
    }

    private func provenanceText(_ provenance: Provenance) -> String {
        switch provenance {
        case .verified: "verified"
        case .database(let name, _): "database · \(name)"
        case .estimate(let assumptions):
            assumptions.isEmpty ? "estimate" : "estimate · \(assumptions.joined(separator: " · "))"
        }
    }

    private func refresh() async {
        if let fresh = try? await recorder.todayIntake() {
            intake = fresh
        }
    }

    private func delete(at offsets: IndexSet) async {
        for index in offsets {
            guard intake.entries.indices.contains(index) else { continue }
            try? await recorder.delete(entryID: intake.entries[index].id)
        }
        await refresh()
    }
}
