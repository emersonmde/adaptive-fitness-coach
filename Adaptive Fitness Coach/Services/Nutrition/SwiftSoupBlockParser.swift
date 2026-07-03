import Foundation
import SwiftSoup
import AdaptiveCore

/// The phone half of the §5 page reducer: SwiftSoup DOM → `[ReducedBlock]`. Deliberately
/// thin — everything with rules worth testing (table→markdown, query selection, the token
/// cap) is the package's pure `PageReducer`; this walker just extracts structure. Pinned by
/// fixture tests in the phone unit target.
struct SwiftSoupBlockParser: HTMLBlockParser {

    func parseBlocks(html: String) throws -> [ReducedBlock] {
        let document = try SwiftSoup.parse(html)
        // Boilerplate never contains nutrition data; drop it before walking.
        try document.select("script, style, nav, footer, header, aside, noscript, iframe, form").remove()
        guard let body = document.body() else { return [] }

        var blocks: [ReducedBlock] = []
        try walk(body, into: &blocks)
        return blocks
    }

    private func walk(_ element: Element, into blocks: inout [ReducedBlock]) throws {
        for child in element.children() {
            let tag = child.tagName()
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let text = try child.text()
                if !text.isEmpty {
                    blocks.append(.heading(level: Int(String(tag.dropFirst())) ?? 2, text: text))
                }
            case "table":
                if let table = try parseTable(child) {
                    blocks.append(table)
                }
            case "ul", "ol":
                let items = try child.select("li").compactMap { li -> String? in
                    let text = try li.text()
                    return text.isEmpty ? nil : text
                }
                if !items.isEmpty {
                    blocks.append(.list(items: items))
                }
            case "p", "blockquote", "pre":
                let text = try child.text()
                if !text.isEmpty {
                    blocks.append(.paragraph(text))
                }
            default:
                // Container elements (div/section/article/main/…): recurse. Bare text inside
                // a container that has no element children becomes a paragraph.
                if child.children().isEmpty() {
                    let text = try child.ownText()
                    if text.count > 1 {
                        blocks.append(.paragraph(text))
                    }
                } else {
                    try walk(child, into: &blocks)
                }
            }
        }
    }

    private func parseTable(_ table: Element) throws -> ReducedBlock? {
        var headers: [String] = []
        var rows: [[String]] = []
        for row in try table.select("tr") {
            let headerCells = try row.select("th").map { try $0.text() }
            let dataCells = try row.select("td").map { try $0.text() }
            if !headerCells.isEmpty && headers.isEmpty && rows.isEmpty {
                headers = headerCells
            } else {
                let cells = headerCells + dataCells
                if cells.contains(where: { !$0.isEmpty }) {
                    rows.append(cells)
                }
            }
        }
        guard !rows.isEmpty || !headers.isEmpty else { return nil }
        return .table(headers: headers, rows: rows)
    }
}
