import Foundation
import Testing
@testable import AdaptiveCore

/// Build-8 package models & math: meal slots, userStated provenance, Codable evolution,
/// stated-calorie / date-phrase / receipt-date parsers, target math, edit/relog semantics.

struct MealSlotTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: hour, minute: 30))!
    }

    @Test func hourBoundaries() {
        #expect(MealSlot.suggested(for: date(hour: 3), calendar: utc) == .snack)
        #expect(MealSlot.suggested(for: date(hour: 4), calendar: utc) == .breakfast)
        #expect(MealSlot.suggested(for: date(hour: 10), calendar: utc) == .breakfast)
        #expect(MealSlot.suggested(for: date(hour: 11), calendar: utc) == .lunch)
        #expect(MealSlot.suggested(for: date(hour: 15), calendar: utc) == .lunch)
        #expect(MealSlot.suggested(for: date(hour: 16), calendar: utc) == .dinner)
        #expect(MealSlot.suggested(for: date(hour: 20), calendar: utc) == .dinner)
        #expect(MealSlot.suggested(for: date(hour: 21), calendar: utc) == .snack)
        #expect(MealSlot.suggested(for: date(hour: 0), calendar: utc) == .snack)
    }

    @Test func timezoneMatters() {
        // 06:00 UTC is breakfast in London but 20:00 the previous evening in Honolulu (UTC−10).
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let sixUTC = date(hour: 6)
        #expect(MealSlot.suggested(for: sixUTC, calendar: utc) == .breakfast)
        #expect(MealSlot.suggested(for: sixUTC, calendar: honolulu) == .dinner)
    }
}

struct ProvenanceEvolutionTests {

    @Test func userStatedRoundTrips() throws {
        let decoded = try JSONDecoder().decode(
            Provenance.self,
            from: JSONEncoder().encode(Provenance.userStated)
        )
        #expect(decoded == .userStated)
        #expect(Provenance.userStated.label == "your number")
        #expect(Provenance.userStated.metadataValue == "userStated")
        #expect(Provenance.userStated.sourceURL == nil)
    }

    /// A build-7 MealEntry (no `meal` key, old provenance cases) must decode — this is what
    /// keeps PendingMealQueue files alive across the upgrade.
    @Test func build7EntryDecodesWithDerivedMealSlot() throws {
        let build7JSON = """
        {"id":"11111111-2222-3333-4444-555555555555",
         "date":773236800,
         "name":"Chicken Caesar Salad","quantity":1,
         "facts":{"energy":{"exact":{"kcal":460}},"proteinGrams":39},
         "provenance":{"database":{"name":"Open Food Facts","sourceURL":null}}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(MealEntry.self, from: build7JSON)
        #expect(entry.name == "Chicken Caesar Salad")
        #expect(entry.meal == MealSlot.suggested(for: entry.date))   // derived, not defaulted
        guard case .database = entry.provenance else {
            Issue.record("old provenance case failed to decode"); return
        }
    }

    @Test func build8EntryRoundTripsWithMeal() throws {
        let entry = MealEntry(
            date: Date(timeIntervalSince1970: 1_780_000_000),
            name: "Latte",
            facts: NutritionFacts(energy: .exact(kcal: 190)),
            provenance: .userStated,
            meal: .snack
        )
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(decoded.meal == .snack)
    }
}

struct TypedSellerParserTests {

    @Test func trailingFromClauseBecomesTheSeller() {
        let r = TypedSellerParser.parse("chicken ceaser salad from salad works")
        #expect(r.cleanText == "chicken ceaser salad")
        #expect(r.seller?.name == "Salad Works")
    }

    @Test func atClauseAndArticlesWork() {
        let r = TypedSellerParser.parse("cobb salad at the Cheesecake Factory")
        #expect(r.cleanText == "cobb salad")
        #expect(r.seller?.name == "Cheesecake Factory")
    }

    @Test func lastMarkerWins() {
        let r = TypedSellerParser.parse("salad from the deli counter at Wegmans")
        #expect(r.seller?.name == "Wegmans")
    }

    @Test func userCapitalizationIsKept() {
        #expect(TypedSellerParser.parse("market salad from Chick-fil-A").seller?.name == "Chick-fil-A")
    }

    @Test func nonSellersDoNotParse() {
        #expect(TypedSellerParser.parse("banana bread from scratch").seller == nil)
        #expect(TypedSellerParser.parse("leftover pasta from home").seller == nil)
        #expect(TypedSellerParser.parse("granola bar from work").seller == nil)
        // Preparation sources aren't sellers.
        #expect(TypedSellerParser.parse("protein shake from powder").seller == nil)
        #expect(TypedSellerParser.parse("pancakes from a mix").seller == nil)
        #expect(TypedSellerParser.parse("lemonade from concentrate").seller == nil)
        #expect(TypedSellerParser.parse("mac and cheese from the box").seller == nil)
        // Digits mean a measurement, not a place.
        #expect(TypedSellerParser.parse("cut sandwich from 6 inch sub").seller == nil)
        // A clause that IS the whole text has no food to log.
        #expect(TypedSellerParser.parse("from Saladworks").seller == nil)
        // Long trailing prose isn't a name.
        #expect(TypedSellerParser.parse("pasta from the place we went last weekend after the game").seller == nil)
    }

    @Test func noClauseIsUntouched() {
        let r = TypedSellerParser.parse("chicken caesar salad")
        #expect(r.cleanText == "chicken caesar salad")
        #expect(r.seller == nil)
    }

    // Mid-sentence clauses: the seller ends at the next connective and the rest of the
    // sentence survives — the shape of "MENU ITEM from SELLER with SIDES".
    @Test func midSentenceSellerBoundedByWith() {
        let r = TypedSellerParser.parse("Rising shine from bob Evans with scrambled eggs, salsa, 3 sausage links")
        #expect(r.seller?.name == "Bob Evans")
        #expect(r.cleanText == "Rising shine with scrambled eggs, salsa, 3 sausage links")
    }

    @Test func midSentenceSellerBoundedByComma() {
        let r = TypedSellerParser.parse("burrito bowl from Chipotle, extra rice")
        #expect(r.seller?.name == "Chipotle")
        #expect(r.cleanText == "burrito bowl, extra rice")
    }

    @Test func midSentenceSellerBoundedByAnd() {
        let r = TypedSellerParser.parse("chicken sandwich from Wendy's and a small frosty")
        #expect(r.seller?.name == "Wendy's")
        #expect(r.cleanText == "chicken sandwich and a small frosty")
    }

    @Test func midSentenceNonSellerStaysUntouched() {
        let r = TypedSellerParser.parse("toast from the oven with butter")
        #expect(r.seller == nil)
        #expect(r.cleanText == "toast from the oven with butter")
    }
}

struct QuestionAnswerPromptTests {

    @Test func answersRenderAsTextInLookupPrompts() {
        let question = ClarifyingQuestion(
            id: "item0",
            prompt: "How many eggs?",
            options: [.init(id: "item0-opt0", label: "2"), .init(id: "item0-opt1", label: "3")],
            defaultOptionID: "item0-opt0"
        )
        let answer = QuestionAnswer(question: question, option: question.options[1])
        #expect(answer.promptDescription == "How many eggs? 3")

        let estimate = MealPromptBuilder.estimatePrompt(
            item: DraftItem(name: "Scrambled eggs"), ocrLines: [], answers: [answer]
        )
        #expect(estimate.contains("How many eggs? 3"))
        #expect(!estimate.contains("item0-opt1"))
    }

    @Test func legacyIDOnlyAnswersStillRender() {
        let answer = QuestionAnswer(questionID: "portion", optionID: "whole")
        #expect(answer.promptDescription == "portion=whole")
    }
}

struct StatedCalorieParserTests {

    @Test func trailingClauseForms() {
        #expect(StatedCalorieParser.parse("salmon caesar salad, 400 calories") == ("salmon caesar salad", 400))
        #expect(StatedCalorieParser.parse("burrito bowl 650 kcal") == ("burrito bowl", 650))
        #expect(StatedCalorieParser.parse("protein bar - 210cal") == ("protein bar", 210))
        #expect(StatedCalorieParser.parse("soup, about 350 calories.") == ("soup", 350))
        #expect(StatedCalorieParser.parse("shake ~ 420 Cals") == ("shake ~", 420) || StatedCalorieParser.parse("shake ~ 420 Cals").kcal == 420)
    }

    @Test func nonCalorieNumbersDoNotParse() {
        #expect(StatedCalorieParser.parse("2 tacos").kcal == nil)
        #expect(StatedCalorieParser.parse("6 inch turkey sub").kcal == nil)
        #expect(StatedCalorieParser.parse("400 calories of regret and a salad").kcal == nil)  // not trailing
        #expect(StatedCalorieParser.parse("plain oatmeal").kcal == nil)
    }

    @Test func bareCalorieTextKeepsAName() {
        let parsed = StatedCalorieParser.parse("400 calories")
        #expect(parsed.kcal == 400)
        #expect(!parsed.name.isEmpty)
    }
}

struct TypedDatePhraseParserTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var now: Date {   // 2026-07-03 01:30 UTC — the "past-1am salad" scenario
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 1, minute: 30))!
    }

    @Test func yesterdayIsStrippedAndDated() {
        let result = TypedDatePhraseParser.parse(
            "chicken caesar salad from wendys from yesterday", now: now, calendar: calendar
        )
        #expect(result.cleanText == "chicken caesar salad from wendys")
        let day = try? #require(result.date)
        #expect(calendar.component(.day, from: day!) == 2)
    }

    @Test func lastNightIsDinnerYesterday() {
        let result = TypedDatePhraseParser.parse("pad thai last night", now: now, calendar: calendar)
        #expect(result.cleanText == "pad thai")
        #expect(result.slot == .dinner)
        #expect(calendar.component(.day, from: result.date!) == 2)
    }

    @Test func mealWordWithoutDateSetsSlotOnly() {
        let result = TypedDatePhraseParser.parse("bagel for breakfast", now: now, calendar: calendar)
        #expect(result.cleanText == "bagel")
        #expect(result.slot == .breakfast)
        #expect(result.date == nil)
    }

    @Test func plainTextPassesThrough() {
        let result = TypedDatePhraseParser.parse("greek yogurt with honey", now: now, calendar: calendar)
        #expect(result.cleanText == "greek yogurt with honey")
        #expect(result.date == nil)
        #expect(result.slot == nil)
    }
}

struct ReceiptDateParserTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 12))!
    }

    @Test func numericDateWithTime() throws {
        let date = try #require(ReceiptDateParser.parse(
            ocrLines: ["TRADER JOE'S", "07/01/2026 6:42 PM", "CHKN CSR SLD 5.99"],
            now: now, calendar: calendar
        ))
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        #expect(parts.month == 7 && parts.day == 1)
        #expect(parts.hour == 18 && parts.minute == 42)
    }

    @Test func writtenMonthAndTwoDigitYear() throws {
        let written = try #require(ReceiptDateParser.parse(
            ocrLines: ["Jul 1, 2026"], now: now, calendar: calendar
        ))
        #expect(calendar.component(.day, from: written) == 1)

        let short = try #require(ReceiptDateParser.parse(
            ocrLines: ["7/1/26 18:42"], now: now, calendar: calendar
        ))
        #expect(calendar.component(.hour, from: short) == 18)
    }

    @Test func futureAndAncientDatesRejected() {
        #expect(ReceiptDateParser.parse(ocrLines: ["12/25/2026"], now: now, calendar: calendar) == nil)
        #expect(ReceiptDateParser.parse(ocrLines: ["01/01/2020"], now: now, calendar: calendar) == nil)
    }

    @Test func pricesAndPhoneNumbersDoNotParse() {
        #expect(ReceiptDateParser.parse(
            ocrLines: ["TOTAL 12.99", "TEL 555-867-5309", "3 ITEMS"],
            now: now, calendar: calendar
        ) == nil)
    }

    @Test func dateOnlyDefaultsToNoon() throws {
        let date = try #require(ReceiptDateParser.parse(
            ocrLines: ["2026-07-01"], now: now, calendar: calendar
        ))
        #expect(calendar.component(.hour, from: date) == 12)
    }
}

struct CalorieTargetCalculatorTests {

    private let profile = BodyProfile(massKg: 80, heightCm: 180, ageYears: 35, sex: .male)

    @Test func mifflinStJeorConstants() {
        // 10·80 + 6.25·180 − 5·35 + 5 = 800 + 1125 − 175 + 5 = 1755
        #expect(CalorieTargetCalculator.bmr(profile) == 1755)
        let female = BodyProfile(massKg: 65, heightCm: 165, ageYears: 30, sex: .female)
        // 650 + 1031.25 − 150 − 161 = 1370.25
        #expect(abs(CalorieTargetCalculator.bmr(female) - 1370.25) < 0.001)
    }

    @Test func suggestionRoundsAndApplysGoal() {
        // TDEE = 1755 × 1.2 = 2106; lose → 1606 → rounds to 1600.
        #expect(CalorieTargetCalculator.suggestedTarget(profile: profile, activity: .sedentary, goal: .lose) == 1600)
        // maintain → 2106 → 2100; gain → 2606 → 2600.
        #expect(CalorieTargetCalculator.suggestedTarget(profile: profile, activity: .sedentary, goal: .maintain) == 2100)
        #expect(CalorieTargetCalculator.suggestedTarget(profile: profile, activity: .sedentary, goal: .gain) == 2600)
    }

    @Test func floorNeverUndershot() {
        let small = BodyProfile(massKg: 45, heightCm: 150, ageYears: 70, sex: .female)
        // BMR = 450 + 937.5 − 350 − 161 = 876.5; sedentary lose would be ~552 → floor 1200.
        #expect(CalorieTargetCalculator.suggestedTarget(profile: small, activity: .sedentary, goal: .lose) == 1200)
    }

    @Test func dayBudgetArithmetic() {
        let under = DayBudget(targetKcal: 2000, consumedKcal: 1420)
        #expect(abs(under.fillFraction - 0.71) < 0.001)
        #expect(under.remainingKcal == 580)
        #expect(under.overKcal == nil)
        #expect(!under.isOver)

        let over = DayBudget(targetKcal: 2000, consumedKcal: 2230)
        #expect(over.fillFraction == 1)          // never a second lap
        #expect(over.overKcal == 230)
        #expect(over.remainingKcal == nil)
    }
}

struct MealEntryEditTests {

    private let original = MealEntry(
        date: Date(timeIntervalSince1970: 1_780_000_000),
        name: "Deli Lentil Curry",
        facts: NutritionFacts(energy: .range(lowKcal: 350, highKcal: 600), proteinGrams: 18),
        provenance: .estimate(assumptions: ["Typical serving"])
    )

    @Test func kcalEditBecomesUserStatedExact() {
        let edited = original.edited(kcal: 500)
        #expect(edited.facts.energy == .exact(kcal: 500))
        #expect(edited.provenance == .userStated)
        #expect(edited.facts.proteinGrams == 18)     // macros kept
        #expect(edited.id == original.id)            // same entry, replaced in Health
    }

    @Test func renameAloneKeepsProvenance() {
        let renamed = original.edited(name: "Lentil Curry (large)")
        #expect(renamed.name == "Lentil Curry (large)")
        guard case .estimate = renamed.provenance else {
            Issue.record("rename must not touch provenance"); return
        }
        #expect(renamed.facts.energy.isRange)
    }

    @Test func reloggedIsAFreshIdentityNow() {
        let now = Date()
        let again = original.relogged(at: now)
        #expect(again.id != original.id)
        #expect(again.date == now)
        #expect(again.meal == MealSlot.suggested(for: now))
        #expect(again.facts == original.facts)
        #expect(again.provenance == original.provenance)
    }
}

struct UserStatedLadderTests {

    private struct FailingEstimator: PlateEstimator {
        func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
            Issue.record("ladder must not reach the estimator")
            throw CocoaError(.featureUnsupported)
        }
    }

    @Test func statedBeatsEverythingIncludingLabel() async {
        let item = DraftItem(
            name: "Salmon Caesar Salad",
            labelFacts: NutritionFacts(energy: .exact(kcal: 999)),
            statedFacts: NutritionFacts(energy: .exact(kcal: 400))
        )
        let resolver = MealResolver(
            barcodeDB: nil, searcher: nil, adjudicator: nil, agent: nil,
            estimator: FailingEstimator()
        )
        let (resolved, rung) = await resolver.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .userStated)
        #expect(resolved.facts.energy == .exact(kcal: 400))
        #expect(resolved.provenance == .userStated)
    }
}
