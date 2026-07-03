import Foundation
import Testing
@testable import AdaptiveCore

/// P4 lookup plumbing: models, the OFF and Parallel codecs, the page reducer, and the
/// provenance grader — the pure halves of every rung.
struct NutritionModelTests {

    @Test func rangeMidpoint() {
        let energy = NutritionFacts.Energy.range(lowKcal: 550, highKcal: 750)
        #expect(energy.midpointKcal == 650)
        #expect(energy.isRange)
        #expect(NutritionFacts.Energy.exact(kcal: 460).midpointKcal == 460)
        #expect(!NutritionFacts.Energy.exact(kcal: 460).isRange)
    }

    @Test func mealEntryRoundTripsThroughCodable() throws {
        let entry = MealEntry(
            date: Date(timeIntervalSince1970: 1_780_000_000),
            name: "Chicken Caesar Salad",
            quantity: 2,
            facts: NutritionFacts(
                energy: .exact(kcal: 460),
                proteinGrams: 39,
                carbGrams: 26,
                fatGrams: 23,
                servingDescription: "1 salad (368 g)"
            ),
            provenance: .database(name: "Menu With Nutrition", sourceURL: URL(string: "https://menuwithnutrition.com/x"))
        )
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
    }

    @Test func estimateProvenanceRoundTrips() throws {
        let provenance = Provenance.estimate(assumptions: ["Medium bowl", "Cooked in oil"])
        let decoded = try JSONDecoder().decode(Provenance.self, from: JSONEncoder().encode(provenance))
        #expect(decoded == provenance)
        #expect(provenance.label == "estimate")
        #expect(provenance.sourceURL == nil)
    }

    @Test func clarifyingQuestionFallsBackToFirstOptionForBadDefault() {
        let question = ClarifyingQuestion(
            id: "portion",
            prompt: "How much of it?",
            options: [.init(id: "half", label: "Half"), .init(id: "whole", label: "Whole")],
            defaultOptionID: "missing"
        )
        #expect(question.defaultOption?.id == "half")
    }
}

struct OpenFoodFactsDecodingTests {

    private let servingJSON = """
    {"code":"0049000006346","status":1,"product":{"product_name":"Coca cola can","brands":"Coca cola",
     "serving_size":"355 ml","nutrition_data_per":"100g",
     "nutriments":{"energy-kcal_serving":140,"energy-kcal_100g":39.4,
       "proteins_serving":0,"carbohydrates_serving":39,"fat_serving":0}}}
    """.data(using: .utf8)!

    private let per100gJSON = """
    {"code":"123","status":1,"product":{"product_name":"Mystery Granola","brands":"",
     "nutriments":{"energy-kcal_100g":450,"proteins_100g":10,"carbohydrates_100g":60,"fat_100g":18}}}
    """.data(using: .utf8)!

    @Test func prefersPerServingValues() throws {
        let resolved = try #require(OpenFoodFactsAPI.decode(servingJSON, barcode: "0049000006346"))
        #expect(resolved.facts.energy == .exact(kcal: 140))
        #expect(resolved.facts.carbGrams == 39)
        #expect(resolved.facts.servingDescription == "355 ml")
        guard case .database(let name, let url) = resolved.provenance else {
            Issue.record("expected database provenance"); return
        }
        #expect(name.contains("Open Food Facts"))
        #expect(name.contains("Coca cola"))
        #expect(url?.absoluteString.contains("0049000006346") == true)
    }

    @Test func fallsBackTo100gHonestly() throws {
        let resolved = try #require(OpenFoodFactsAPI.decode(per100gJSON, barcode: "123"))
        #expect(resolved.facts.energy == .exact(kcal: 450))
        #expect(resolved.facts.servingDescription == "per 100 g")   // honest, never invented
    }

    @Test func missingProductReturnsNil() {
        let missing = #"{"status":0,"status_verbose":"product not found"}"#.data(using: .utf8)!
        #expect(OpenFoodFactsAPI.decode(missing, barcode: "000") == nil)
    }

    @Test func productWithoutEnergyReturnsNil() {
        let noEnergy = #"{"status":1,"product":{"product_name":"X","nutriments":{"proteins_100g":5}}}"#
            .data(using: .utf8)!
        #expect(OpenFoodFactsAPI.decode(noEnergy, barcode: "000") == nil)
    }

    @Test func productURLCarriesFieldFilter() throws {
        let url = try #require(OpenFoodFactsAPI.productURL(barcode: "12345"))
        #expect(url.absoluteString.contains("/api/v2/product/12345"))
        #expect(url.absoluteString.contains("fields="))
        #expect(url.absoluteString.contains("nutriments"))
    }
}

struct ParallelSearchCodecTests {

    /// Shape captured from a live keyless call during the CQ1/CQ3 spike. Single line, as the
    /// wire actually sends it (SSE payloads are one complete JSON per `data:` line).
    private let liveShapeResponse = (
        #"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"# + ""
        + #""{\"search_id\":\"s1\",\"results\":[{\"url\":\"https://www.menuwithnutrition.com/x\","# + ""
        + #"\"title\":\"Calories in Salad\",\"excerpts\":[\"|Amount Per Serving |460 Cal |\"]},"# + ""
        + #"{\"url\":\"https://other.example\",\"title\":\"Other\",\"excerpts\":[\"row one\",\"row two\"]}]}"}]}}"#
    ).data(using: .utf8)!

    @Test func decodesExcerptsFromToolCallResult() throws {
        let excerpts = try ParallelSearchProtocol.decodeExcerpts(liveShapeResponse)
        #expect(excerpts.count == 2)
        #expect(excerpts[0].title == "Calories in Salad")
        #expect(excerpts[0].url?.host == "www.menuwithnutrition.com")
        #expect(excerpts[0].excerpt.contains("460 Cal"))
        #expect(excerpts[1].excerpt == "row one\nrow two")
    }

    @Test func decodesSSEWrappedBody() throws {
        let sse = "event: message\ndata: " + String(data: liveShapeResponse, encoding: .utf8)! + "\n\n"
        let excerpts = try ParallelSearchProtocol.decodeExcerpts(sse.data(using: .utf8)!)
        #expect(excerpts.count == 2)
    }

    @Test func rpcErrorSurfaces() {
        let error = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"rate limited"}}"#
            .data(using: .utf8)!
        #expect(throws: ParallelSearchProtocol.DecodeError.rpcError("rate limited")) {
            try ParallelSearchProtocol.decodeExcerpts(error)
        }
    }

    @Test func requestsAreWellFormedJSONRPC() throws {
        let request = ParallelSearchProtocol.webSearchRequest(
            objective: "Find calories", queries: ["salad calories"], id: 7
        )
        let object = try #require(try JSONSerialization.jsonObject(with: request) as? [String: Any])
        #expect(object["method"] as? String == "tools/call")
        let params = try #require(object["params"] as? [String: Any])
        #expect(params["name"] as? String == "web_search")
        let args = try #require(params["arguments"] as? [String: Any])
        #expect(args["search_queries"] as? [String] == ["salad calories"])
    }
}

struct PageReducerTests {

    private let nutritionPage: [ReducedBlock] = [
        .heading(level: 1, text: "Wendy's Menu"),
        .paragraph("Welcome to the menu page with everything we sell."),
        .heading(level: 2, text: "Burgers"),
        .paragraph("Many burgers, much text " + String(repeating: "filler ", count: 200)),
        .heading(level: 2, text: "Apple Pecan Chicken Salad"),
        .paragraph("Our signature salad."),
        .table(
            headers: ["Nutrient", "Amount"],
            rows: [["Calories", "460"], ["Protein", "39 g"], ["Fat", "23 g"]]
        ),
        .heading(level: 2, text: "Drinks"),
        .paragraph("Sodas and more."),
    ]

    @Test func tablesSerializeAsMarkdown() {
        let text = PageReducer.reduce(blocks: nutritionPage, query: nil, maxTokens: 10_000)
        #expect(text.contains("| Nutrient | Amount |"))
        #expect(text.contains("| Calories | 460 |"))
        #expect(text.contains("| --- | --- |"))
    }

    @Test func querySelectionKeepsMatchedSectionUnderTightCap() {
        // Cap small enough that document order would exhaust budget on the burger filler.
        let text = PageReducer.reduce(
            blocks: nutritionPage,
            query: "Apple Pecan Chicken Salad calories",
            maxTokens: 200
        )
        #expect(text.contains("Apple Pecan Chicken Salad"))
        #expect(text.contains("460"))
        #expect(!text.contains("Sodas"))   // unmatched section dropped
    }

    @Test func headAlwaysLeads() {
        let text = PageReducer.reduce(blocks: nutritionPage, query: "salad", maxTokens: 400)
        #expect(text.hasPrefix("# Wendy's Menu"))
    }

    @Test func capIsRespected() {
        let text = PageReducer.reduce(blocks: nutritionPage, query: nil, maxTokens: 100)
        #expect(text.count <= 100 * 4 + 2)   // +2 for the truncation ellipsis line
    }

    @Test func noQueryMatchesFallsBackToDocumentOrder() {
        let text = PageReducer.reduce(blocks: nutritionPage, query: "zzz qqq xxx", maxTokens: 10_000)
        #expect(text.contains("Burgers"))
    }

    @Test func emptyInputIsEmptyOutput() {
        #expect(PageReducer.reduce(blocks: [], query: "x", maxTokens: 100) == "")
    }
}

struct ProvenanceGraderTests {

    private let wendys = Seller(name: "Wendy's", domainHint: "wendys.com")

    @Test func sellerDomainGradesVerified() throws {
        let url = try #require(URL(string: "https://www.wendys.com/nutrition/salad"))
        guard case .verified(let sourceURL) = ProvenanceGrader.grade(sourceURL: url, seller: wendys) else {
            Issue.record("expected verified"); return
        }
        #expect(sourceURL == url)
    }

    @Test func knownDatabaseGradesNamed() throws {
        let url = try #require(URL(string: "https://world.openfoodfacts.org/product/1"))
        guard case .database(let name, _) = ProvenanceGrader.grade(sourceURL: url, seller: wendys) else {
            Issue.record("expected database"); return
        }
        #expect(name == "Open Food Facts")
    }

    @Test func knownAggregatorGradesByFriendlyName() throws {
        let url = try #require(URL(string: "https://www.menuwithnutrition.com/x"))
        guard case .database(let name, _) = ProvenanceGrader.grade(sourceURL: url, seller: wendys) else {
            Issue.record("expected database"); return
        }
        #expect(name == "Menu With Nutrition")
    }

    @Test func unknownAggregatorGradesDatabaseByHost() throws {
        let url = try #require(URL(string: "https://www.some-random-recipes.example/x"))
        guard case .database(let name, _) = ProvenanceGrader.grade(sourceURL: url, seller: wendys) else {
            Issue.record("expected database"); return
        }
        #expect(name == "some-random-recipes.example")
    }

    @Test func lookalikeDomainDoesNotGradeVerified() throws {
        // "notwendys.com" must not pass the wendys.com suffix check.
        let url = try #require(URL(string: "https://notwendys.com/nutrition"))
        if case .verified = ProvenanceGrader.grade(sourceURL: url, seller: wendys) {
            Issue.record("lookalike domain graded verified")
        }
    }

    @Test func missingURLNeverGradesVerified() {
        if case .verified = ProvenanceGrader.grade(sourceURL: nil, seller: wendys) {
            Issue.record("nil URL graded verified")
        }
    }
}

struct MealResolverLadderTests {

    // MARK: - Rung fakes

    private struct FakeBarcodeDB: BarcodeNutritionDatabase {
        var result: ResolvedNutrition?
        var error = false
        func lookup(barcode: String) async throws -> ResolvedNutrition? {
            if error { throw URLError(.timedOut) }
            return result
        }
    }

    private struct FakeSearcher: NutritionWebSearcher {
        var excerpts: [SearchExcerpt] = [SearchExcerpt(title: "hit", excerpt: "460 Cal")]
        func search(objective: String, queries: [String]) async throws -> [SearchExcerpt] { excerpts }
    }

    private struct FakeAdjudicator: ExcerptAdjudicator {
        var result: ResolvedNutrition?
        func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? { result }
    }

    private struct FakeAgent: AgenticLookup {
        var result: ResolvedNutrition?
        func research(item: DraftItem, seller: Seller?) async throws -> ResolvedNutrition? { result }
    }

    private struct FakeEstimator: PlateEstimator {
        func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
            ResolvedNutrition(
                facts: NutritionFacts(energy: .range(lowKcal: 300, highKcal: 500)),
                provenance: .estimate(assumptions: ["fake"])
            )
        }
    }

    private let databaseHit = ResolvedNutrition(
        facts: NutritionFacts(energy: .exact(kcal: 140)),
        provenance: .database(name: "Open Food Facts", sourceURL: nil)
    )
    private let searchHit = ResolvedNutrition(
        facts: NutritionFacts(energy: .exact(kcal: 460)),
        provenance: .database(name: "menuwithnutrition.com", sourceURL: nil)
    )
    private let agentHit = ResolvedNutrition(
        facts: NutritionFacts(energy: .exact(kcal: 520)),
        provenance: .verified(sourceURL: URL(string: "https://wendys.com/n"))
    )

    private func resolver(
        barcode: FakeBarcodeDB? = nil,
        adjudicator: FakeAdjudicator? = nil,
        agent: FakeAgent? = nil
    ) -> MealResolver {
        MealResolver(
            barcodeDB: barcode,
            searcher: adjudicator != nil ? FakeSearcher() : nil,
            adjudicator: adjudicator,
            agent: agent,
            estimator: FakeEstimator()
        )
    }

    @Test func printedLabelShortCircuitsEverything() async {
        let labeled = DraftItem(
            name: "Greek Yogurt",
            labelFacts: NutritionFacts(energy: .exact(kcal: 120)),
            barcode: "123"
        )
        let full = resolver(
            barcode: FakeBarcodeDB(result: databaseHit),
            adjudicator: FakeAdjudicator(result: searchHit),
            agent: FakeAgent(result: agentHit)
        )
        let (nutrition, rung) = await full.resolve(item: labeled, seller: nil, capture: nil, answers: [])
        #expect(rung == .printedLabel)
        #expect(nutrition.facts.energy == .exact(kcal: 120))
        guard case .verified = nutrition.provenance else {
            Issue.record("label must grade verified"); return
        }
    }

    @Test func barcodeRungWinsWhenItResolves() async {
        let item = DraftItem(name: "Cola", barcode: "0049000006346")
        let ladder = resolver(
            barcode: FakeBarcodeDB(result: databaseHit),
            adjudicator: FakeAdjudicator(result: searchHit)
        )
        let (nutrition, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .barcodeDatabase)
        #expect(nutrition == databaseHit)
    }

    @Test func barcodeMissFallsToSearch() async {
        let item = DraftItem(name: "Cola", barcode: "000")
        let ladder = resolver(
            barcode: FakeBarcodeDB(result: nil),
            adjudicator: FakeAdjudicator(result: searchHit)
        )
        let (nutrition, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .searchExcerpts)
        #expect(nutrition == searchHit)
    }

    @Test func barcodeErrorIsFallThroughNotFailure() async {
        let item = DraftItem(name: "Cola", barcode: "000")
        let ladder = resolver(
            barcode: FakeBarcodeDB(result: databaseHit, error: true),
            adjudicator: FakeAdjudicator(result: searchHit)
        )
        let (_, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .searchExcerpts)
    }

    @Test func adjudicatorDeclineFallsToAgent() async {
        let item = DraftItem(name: "Local Special")
        let ladder = resolver(adjudicator: FakeAdjudicator(result: nil), agent: FakeAgent(result: agentHit))
        let (nutrition, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .agenticLookup)
        #expect(nutrition == agentHit)
    }

    @Test func nilRungsSkipToEstimate() async {
        // The shipping default until the spike justifies rung 3: no agent; here no search either.
        let item = DraftItem(name: "Homemade Curry")
        let ladder = resolver()
        let (nutrition, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .estimate)
        #expect(nutrition.facts.energy.isRange)   // C3: estimates are always ranges
        guard case .estimate = nutrition.provenance else {
            Issue.record("bottom rung must grade estimate"); return
        }
    }

    @Test func noBarcodeSkipsBarcodeRung() async {
        let item = DraftItem(name: "Salad")   // no barcode on the item
        let ladder = resolver(
            barcode: FakeBarcodeDB(result: databaseHit),
            adjudicator: FakeAdjudicator(result: searchHit)
        )
        let (_, rung) = await ladder.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .searchExcerpts)
    }
}
