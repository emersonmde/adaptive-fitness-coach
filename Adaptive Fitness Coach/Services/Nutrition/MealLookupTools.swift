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
        // Cap count and size — PCC is 32K total (§5); excerpts are already LLM-optimized.
        return excerpts.prefix(5).enumerated().map { index, hit in
            let body = hit.excerpt.count > 2_000 ? String(hit.excerpt.prefix(2_000)) + "…" : hit.excerpt
            return "[\(index + 1)] \(hit.title)\nURL: \(hit.url?.absoluteString ?? "none")\n\(body)"
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

    /// ~3K tokens per fetch after reduction — one page in context at a time (§5).
    static let maxTokensPerFetch = 3_000

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
        let reduced = PageReducer.reduce(blocks: blocks, query: arguments.query, maxTokens: Self.maxTokensPerFetch)
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
