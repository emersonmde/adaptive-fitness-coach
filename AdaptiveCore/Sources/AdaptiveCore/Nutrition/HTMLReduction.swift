import Foundation

/// §5 context discipline — the model never sees raw HTML, and PCC is 32K *total*. The reducer
/// pipeline is split at a pure boundary:
///
///   HTML  ──(phone: SwiftSoup walker, `HTMLBlockParser`)──▶  [ReducedBlock]  ──(here)──▶  String
///   PDF   ──(phone: PDFKit text → paragraphs)─────────────▶       〃
///
/// Everything after parsing — table→markdown serialization (nutrition facts live in tables;
/// a naive text dump destroys exactly the structure the model needs), query-matched section
/// selection, and the hard token cap — is pure logic here, pinned by `swift test`. SwiftSoup
/// stays a phone-only dependency whose sole job is DOM → blocks.

/// One content block extracted from a page, in document order.
public enum ReducedBlock: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case table(headers: [String], rows: [[String]])
    case list(items: [String])
}

/// Phone-side conformance: SwiftSoup DOM walker (strips script/style/nav/footer/aside first).
public protocol HTMLBlockParser: Sendable {
    func parseBlocks(html: String) throws -> [ReducedBlock]
}

public enum PageReducer {

    /// Serializes blocks to markdown-ish text under a hard token cap, preferring sections
    /// that mention the query terms (head + matched-section selection, §5).
    ///
    /// Strategy: split the document into sections at headings; score each section by query-term
    /// hits (tables get a bonus — that's where the answer lives); emit the document head, then
    /// matched sections in score order, stopping at the cap. `tokens ≈ characters / 4`.
    public static func reduce(blocks: [ReducedBlock], query: String?, maxTokens: Int) -> String {
        guard !blocks.isEmpty else { return "" }
        let maxCharacters = maxTokens * 4

        let sections = sectioned(blocks)
        let terms = queryTerms(query)

        var ordered: [Section] = []
        if terms.isEmpty {
            ordered = sections
        } else {
            // Head section always leads (page identity), then best-matching sections.
            var scored = sections.enumerated().map { index, section in
                (section: section, score: score(section, terms: terms), index: index)
            }
            let head = scored.removeFirst()
            ordered = [head.section] + scored
                .filter { $0.score > 0 }
                .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
                .map(\.section)
            // Nothing matched at all → fall back to document order (still capped).
            if ordered.count == 1, sections.count > 1 {
                ordered = sections
            }
        }

        var output = ""
        for section in ordered {
            let text = serialize(section)
            if output.count + text.count > maxCharacters {
                let remaining = maxCharacters - output.count
                if remaining > 200 {   // a truncated fragment beats nothing, but not a sliver
                    output += String(text.prefix(remaining)) + "\n…"
                }
                break
            }
            output += text
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sections

    private struct Section {
        var heading: (level: Int, text: String)?
        var blocks: [ReducedBlock] = []
    }

    private static func sectioned(_ blocks: [ReducedBlock]) -> [Section] {
        var sections: [Section] = []
        var current = Section()
        for block in blocks {
            if case .heading(let level, let text) = block {
                if current.heading != nil || !current.blocks.isEmpty {
                    sections.append(current)
                }
                current = Section(heading: (level, text))
            } else {
                current.blocks.append(block)
            }
        }
        if current.heading != nil || !current.blocks.isEmpty {
            sections.append(current)
        }
        return sections
    }

    private static func queryTerms(_ query: String?) -> [String] {
        guard let query else { return [] }
        return query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private static func score(_ section: Section, terms: [String]) -> Int {
        var haystackParts: [String] = []
        if let heading = section.heading { haystackParts.append(heading.text) }
        var tableBonus = 0
        for block in section.blocks {
            switch block {
            case .heading(_, let text): haystackParts.append(text)
            case .paragraph(let text): haystackParts.append(text)
            case .list(let items): haystackParts.append(items.joined(separator: " "))
            case .table(let headers, let rows):
                let tableText = (headers + rows.flatMap { $0 }).joined(separator: " ")
                haystackParts.append(tableText)
                tableBonus = 2   // nutrition numbers live in tables
            }
        }
        let haystack = haystackParts.joined(separator: " ").lowercased()
        let hits = terms.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
        return hits == 0 ? 0 : hits + tableBonus
    }

    // MARK: - Serialization

    private static func serialize(_ section: Section) -> String {
        var lines: [String] = []
        if let (level, text) = section.heading {
            lines.append(String(repeating: "#", count: min(level, 6)) + " " + text)
        }
        for block in section.blocks {
            switch block {
            case .heading(let level, let text):
                lines.append(String(repeating: "#", count: min(level, 6)) + " " + text)
            case .paragraph(let text):
                lines.append(text)
            case .list(let items):
                lines.append(items.map { "- " + $0 }.joined(separator: "\n"))
            case .table(let headers, let rows):
                lines.append(markdownTable(headers: headers, rows: rows))
            }
        }
        return lines.joined(separator: "\n\n") + "\n\n"
    }

    private static func markdownTable(headers: [String], rows: [[String]]) -> String {
        let width = max(headers.count, rows.map(\.count).max() ?? 0)
        guard width > 0 else { return "" }
        func pad(_ cells: [String]) -> [String] {
            cells + Array(repeating: "", count: width - cells.count)
        }
        var lines: [String] = []
        let headerCells = headers.isEmpty ? Array(repeating: " ", count: width) : pad(headers)
        lines.append("| " + headerCells.joined(separator: " | ") + " |")
        lines.append("|" + Array(repeating: " --- |", count: width).joined())
        for row in rows {
            lines.append("| " + pad(row).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
