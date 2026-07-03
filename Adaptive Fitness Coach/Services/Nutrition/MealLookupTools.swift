import Foundation
import FoundationModels
import AdaptiveCore

/// The rung-3 agentic loop's client-side tools (CQ1a): FoundationModels custom `Tool`s are
/// app-executed and round-trip mid-generation — the model says "search this" / "fetch that",
/// the app does it, generation continues. Apple ships no web tools of its own; these are ours.
/// Bad arguments return corrective strings to the *model* (ProposePlanTool pattern), never
/// errors to the user.

struct WebSearchTool: Tool {
    let name = "web_search"
    let description = """
    Search the web. Returns result excerpts that usually contain nutrition numbers directly — \
    answer from them when they do, without fetching.
    """

    let searcher: any NutritionWebSearcher
    /// Sized by the model the session runs on (on-device = 4,096 tokens *total* — the tool's
    /// output shares that with instructions, the loop's history, and the answer).
    var budget: ExcerptBudget = FoundationModelsMealPipeline.excerptBudget

    @Generable
    struct Arguments {
        @Guide(description: "What you are trying to find, one sentence.")
        var objective: String
        @Guide(description: "1 to 3 search queries.", .count(1...3))
        var queries: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        let excerpts: [SearchExcerpt]
        do {
            excerpts = try await searcher.search(objective: arguments.objective, queries: arguments.queries)
        } catch {
            return "Search is unavailable right now (\(error.localizedDescription)). If you cannot answer without it, report that the lookup failed."
        }
        guard !excerpts.isEmpty else {
            return "No results. Try a differently-worded query, or report that the lookup failed."
        }
        // Query-aware reduction (§5): keep the nutrition-bearing lines, fit the budget. In a
        // tool loop the budget is halved — history accumulates across calls.
        let toolBudget = ExcerptBudget(
            maxExcerpts: budget.maxExcerpts,
            perExcerptCharacters: budget.perExcerptCharacters / 2,
            totalCharacters: budget.totalCharacters / 2
        )
        let reduced = ExcerptReducer.reduce(excerpts, query: arguments.objective, budget: toolBudget)
        return reduced.enumerated().map { index, hit in
            "[\(index + 1)] \(hit.title)\nURL: \(hit.url?.absoluteString ?? "none")\n\(hit.excerpt)"
        }.joined(separator: "\n\n")
    }
}

struct FetchPageTool: Tool {
    let name = "fetch_page"
    let description = """
    Fetch one web page (HTML or PDF) and return its reduced text. Use only when search \
    excerpts are insufficient. Pass the item you're looking for as the query so the relevant \
    sections are kept.
    """

    /// Per-fetch cap after reduction — one page in context at a time (§5), sized by the
    /// running model (PCC affords ~3K tokens; the 4,096-total on-device model far less).
    var maxTokensPerFetch: Int = PCCEntitlement.isGranted ? 3_000 : 900

    @Generable
    struct Arguments {
        @Guide(description: "The absolute http(s) URL to fetch.")
        var url: String
        @Guide(description: "The item you are looking for on the page, e.g. 'Apple Pecan Chicken Salad calories'.")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = URL(string: arguments.url), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return "That is not a fetchable http(s) URL. Provide a full URL from the search results."
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("AdaptiveFitnessCoach/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return "Fetch failed (\(error.localizedDescription)). Try a different page or answer from search excerpts."
        }
        if let status = (response as? HTTPURLResponse)?.statusCode, status >= 400 {
            return "The page returned HTTP \(status). Try a different page."
        }

        let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""

        let blocks: [ReducedBlock]
        if contentType.contains("pdf") || url.pathExtension.lowercased() == "pdf" {
            blocks = Self.pdfBlocks(data)
        } else if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            blocks = (try? SwiftSoupBlockParser().parseBlocks(html: html)) ?? []
        } else {
            return "The page could not be decoded as text. Try a different page."
        }
        guard !blocks.isEmpty else {
            return "The page had no readable content. Try a different page."
        }
        let reduced = PageReducer.reduce(blocks: blocks, query: arguments.query, maxTokens: maxTokensPerFetch)
        return reduced.isEmpty ? "Nothing relevant found on that page." : reduced
    }

    private static func pdfBlocks(_ data: Data) -> [ReducedBlock] {
        #if canImport(PDFKit)
        guard let document = PDFKitText.extract(data) else { return [] }
        return document
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { .paragraph($0) }
        #else
        return []
        #endif
    }
}

#if canImport(PDFKit)
import PDFKit

/// Chains love publishing nutrition PDFs; PDFKit extraction is built-in — no dependency (§5).
enum PDFKitText {
    static func extract(_ data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        // Nutrition PDFs are long; cap pages defensively — the reducer caps tokens anyway.
        let pages = min(document.pageCount, 20)
        var text = ""
        for index in 0..<pages {
            if let page = document.page(at: index), let content = page.string {
                text += content + "\n"
            }
        }
        return text.isEmpty ? nil : text
    }
}
#endif
