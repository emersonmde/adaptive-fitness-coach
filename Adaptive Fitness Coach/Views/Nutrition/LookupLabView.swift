import SwiftUI
import AdaptiveCore

/// The CQ1/CQ3 spike instrument — and the standing regression harness for prompt changes.
/// Runs a fixed table of real-world items through each lookup rung *independently* (not the
/// ladder: the point is measuring every rung's coverage, not the first success) and reports
/// kcal / provenance / latency per rung plus a coverage summary.
///
/// Reachable via the `-lookupLab` launch arg. Never linked from product UI.
struct LookupLabView: View {

    struct LabItem: Identifiable {
        let id = UUID()
        var label: String
        var item: DraftItem
        var seller: Seller?
    }

    /// A representative week of "on the go" food: barcodes (rung 1), chain items (rung 2/3),
    /// grocery deli, coffee, and one unresolvable homemade dish (should fail honestly).
    static let defaultItems: [LabItem] = [
        LabItem(label: "Coca-Cola 12oz can (barcode)",
                item: DraftItem(name: "Coca-Cola Classic 12 fl oz", barcode: "049000006346")),
        LabItem(label: "Clif Bar Chocolate Chip (barcode)",
                item: DraftItem(name: "Clif Bar Chocolate Chip", barcode: "722252100900")),
        LabItem(label: "Wendy's Apple Pecan Chicken Salad",
                item: DraftItem(name: "Apple Pecan Chicken Salad, full size"),
                seller: Seller(name: "Wendy's", domainHint: "wendys.com")),
        LabItem(label: "Chipotle Chicken Burrito Bowl",
                item: DraftItem(name: "Chicken Burrito Bowl with white rice, black beans, mild salsa, cheese"),
                seller: Seller(name: "Chipotle", domainHint: "chipotle.com")),
        LabItem(label: "Starbucks Grande Caffè Latte (2% milk)",
                item: DraftItem(name: "Caffè Latte, Grande, 2% milk"),
                seller: Seller(name: "Starbucks", domainHint: "starbucks.com")),
        LabItem(label: "McDonald's Big Mac",
                item: DraftItem(name: "Big Mac"),
                seller: Seller(name: "McDonald's", domainHint: "mcdonalds.com")),
        LabItem(label: "Subway 6\" Turkey Breast sub",
                item: DraftItem(name: "6 inch Turkey Breast sandwich on Italian bread"),
                seller: Seller(name: "Subway", domainHint: "subway.com")),
        LabItem(label: "Trader Joe's Chicken Caesar Salad (deli)",
                item: DraftItem(name: "Chicken Caesar Salad with dressing"),
                seller: Seller(name: "Trader Joe's", domainHint: "traderjoes.com")),
        LabItem(label: "Panera Broccoli Cheddar Soup (bowl)",
                item: DraftItem(name: "Broccoli Cheddar Soup, bowl"),
                seller: Seller(name: "Panera Bread", domainHint: "panerabread.com")),
        LabItem(label: "Homemade lentil curry (no published data)",
                item: DraftItem(name: "Homemade red lentil curry with rice"),
                seller: nil),
    ]

    struct RungResult: Identifiable {
        let id = UUID()
        var rung: String
        var outcome: String     // "460 kcal · database(menuwithnutrition.com)" / "no answer" / error
        var seconds: Double
        var resolved: Bool
    }

    @State private var results: [UUID: [RungResult]] = [:]
    @State private var running = false
    @State private var progress = ""

    private let items = Self.defaultItems

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard
                        ForEach(items) { labItem in
                            itemCard(labItem)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Lookup Lab")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(running ? "Running…" : "Run") { Task { await runAll() } }
                        .disabled(running)
                        .accessibilityIdentifier("lookupLab.run")
                }
            }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("CQ1/CQ3 SPIKE — PER-RUNG COVERAGE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(summaryText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                if !progress.isEmpty {
                    Text(progress)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryText: String {
        let all = results.values.flatMap { $0 }
        guard !all.isEmpty else { return "Not run yet. Tap Run (needs network + Apple Intelligence)." }
        func line(_ rung: String) -> String {
            let rungResults = all.filter { $0.rung == rung }
            guard !rungResults.isEmpty else { return "\(rung): –" }
            let hit = rungResults.filter(\.resolved).count
            let avg = rungResults.map(\.seconds).reduce(0, +) / Double(rungResults.count)
            return "\(rung): \(hit)/\(rungResults.count) · avg \(String(format: "%.1f", avg))s"
        }
        return [line("barcode"), line("search+adjudicate"), line("agentic")].joined(separator: "\n")
    }

    private func itemCard(_ labItem: LabItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(labItem.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let rungResults = results[labItem.id] {
                    ForEach(rungResults) { result in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: result.resolved ? "checkmark.circle.fill" : "minus.circle")
                                .font(.caption)
                                .foregroundStyle(result.resolved ? Theme.accent : Theme.textTertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(result.rung) · \(String(format: "%.1f", result.seconds))s")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                Text(result.outcome)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The measurement

    private func runAll() async {
        running = true
        defer { running = false }
        results = [:]

        let barcodeDB = OpenFoodFactsClient()
        let searcher = ParallelSearchClient()
        let adjudicator = FoundationModelsAdjudicator()
        let agent = FoundationModelsAgenticLookup(searcher: searcher)

        for (index, labItem) in items.enumerated() {
            progress = "Item \(index + 1)/\(items.count): \(labItem.label)"
            var rungResults: [RungResult] = []

            if let barcode = labItem.item.barcode {
                rungResults.append(await measure("barcode") {
                    try await barcodeDB.lookup(barcode: barcode)
                })
                results[labItem.id] = rungResults
            }

            rungResults.append(await measure("search+adjudicate") {
                let excerpts = try await searcher.search(
                    objective: MealPromptBuilder.searchObjective(item: labItem.item, seller: labItem.seller),
                    queries: MealPromptBuilder.searchQueries(item: labItem.item, seller: labItem.seller)
                )
                guard !excerpts.isEmpty else { return nil }
                return try await adjudicator.adjudicate(item: labItem.item, seller: labItem.seller, excerpts: excerpts)
            })
            results[labItem.id] = rungResults

            rungResults.append(await measure("agentic") {
                try await agent.research(item: labItem.item, seller: labItem.seller)
            })
            results[labItem.id] = rungResults
        }
        progress = "Done. Screenshot this screen for PROJECT-STATUS."
    }

    private func measure(_ rung: String, _ work: () async throws -> ResolvedNutrition?) async -> RungResult {
        let start = Date()
        do {
            let resolved = try await work()
            let elapsed = Date().timeIntervalSince(start)
            if let resolved {
                return RungResult(rung: rung, outcome: describe(resolved), seconds: elapsed, resolved: true)
            }
            return RungResult(rung: rung, outcome: "no answer (honest miss)", seconds: elapsed, resolved: false)
        } catch {
            return RungResult(
                rung: rung,
                outcome: "error: \(error.localizedDescription)",
                seconds: Date().timeIntervalSince(start),
                resolved: false
            )
        }
    }

    private func describe(_ resolved: ResolvedNutrition) -> String {
        let kcal: String
        switch resolved.facts.energy {
        case .exact(let value): kcal = "\(Int(value)) kcal"
        case .range(let low, let high): kcal = "\(Int(low))–\(Int(high)) kcal"
        }
        var provenance = resolved.provenance.label
        if case .database(let name, _) = resolved.provenance { provenance += "(\(name))" }
        if let serving = resolved.facts.servingDescription { provenance += " · \(serving)" }
        return "\(kcal) · \(provenance)"
    }
}
