import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach

/// Pins the SwiftSoup → `ReducedBlock` walker (the phone half of the §5 page reducer) with a
/// nutrition-page-shaped fixture: boilerplate stripped, tables kept as tables, headings and
/// lists in order. The pure half (`PageReducer`) is pinned in the package tests.
struct SwiftSoupBlockParserTests {

    private let nutritionHTML = """
    <html><head><style>.x{color:red}</style><script>alert(1)</script></head>
    <body>
      <nav><a href="/">Home</a><a href="/menu">Menu</a></nav>
      <main>
        <h1>Apple Pecan Chicken Salad</h1>
        <p>Our signature salad with grilled chicken.</p>
        <div>
          <h2>Nutrition Facts</h2>
          <table>
            <tr><th>Nutrient</th><th>Amount</th></tr>
            <tr><td>Calories</td><td>460</td></tr>
            <tr><td>Protein</td><td>39 g</td></tr>
          </table>
        </div>
        <ul><li>Contains pecans</li><li>Contains dairy</li></ul>
      </main>
      <footer>© Wendy's</footer>
    </body></html>
    """

    @Test func parsesNutritionPageShape() throws {
        let blocks = try SwiftSoupBlockParser().parseBlocks(html: nutritionHTML)

        // Boilerplate is gone.
        let allText = blocks.map(String.init(describing:)).joined()
        #expect(!allText.contains("alert"))
        #expect(!allText.contains("Home"))
        #expect(!allText.contains("©"))

        // Structure survives, in order.
        guard case .heading(1, "Apple Pecan Chicken Salad") = try #require(blocks.first) else {
            Issue.record("first block should be the h1"); return
        }
        let table = blocks.compactMap { block -> ([String], [[String]])? in
            if case .table(let headers, let rows) = block { return (headers, rows) }
            return nil
        }.first
        let (headers, rows) = try #require(table)
        #expect(headers == ["Nutrient", "Amount"])
        #expect(rows.contains(["Calories", "460"]))

        let list = blocks.compactMap { if case .list(let items) = $0 { items } else { nil } }.first
        #expect(list == ["Contains pecans", "Contains dairy"])
    }

    @Test func parsedBlocksFlowThroughThePageReducer() throws {
        // The whole §5 chain: HTML → blocks → capped, query-selected markdown.
        let blocks = try SwiftSoupBlockParser().parseBlocks(html: nutritionHTML)
        let reduced = PageReducer.reduce(blocks: blocks, query: "salad calories", maxTokens: 500)
        #expect(reduced.contains("| Calories | 460 |"))
        #expect(!reduced.contains("<table>"))
    }

    @Test func emptyAndJunkHTMLAreSafe() throws {
        #expect(try SwiftSoupBlockParser().parseBlocks(html: "").isEmpty)
        let junk = try SwiftSoupBlockParser().parseBlocks(html: "not html at all")
        // SwiftSoup wraps bare text in a body; whatever comes back must be paragraphs, not a crash.
        for block in junk {
            guard case .paragraph = block else {
                Issue.record("junk input should only yield paragraphs"); return
            }
        }
    }
}
