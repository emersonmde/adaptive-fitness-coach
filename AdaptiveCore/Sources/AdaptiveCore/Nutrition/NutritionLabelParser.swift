import Foundation

/// Parses a US "Nutrition Facts" panel out of OCR lines — deterministically, no model call
/// (§5 stage 1 prefers system capabilities; a printed label is the one source that needs no
/// lookup at all). A successful parse short-circuits the whole ladder as `.verified`: the
/// manufacturer's own printed data (C2/C3).
///
/// OCR reality: Vision returns one line per visual row, but columns can split ("Calories"
/// and "230" as separate lines) and units hug values ("8g", "230mg"). The parser is
/// deliberately forgiving — but it only returns facts when it found BOTH the panel heading
/// and a calorie value; half-parses return nil and the item flows to the normal ladder.
public enum NutritionLabelParser {

    public struct ParsedLabel: Sendable, Equatable {
        public var facts: NutritionFacts
        /// A guess at the product name: the most name-like line *above* the panel heading
        /// (labels sit under the product name on most packaging). Often absent — the user
        /// can fix the name inline on the confirmation screen.
        public var nameGuess: String?
    }

    public static func parse(ocrLines: [String]) -> ParsedLabel? {
        let lines = ocrLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let headingIndex = lines.firstIndex(where: { $0.lowercased().contains("nutrition facts") })
        else { return nil }

        let panel = Array(lines[headingIndex...])
        guard let kcal = value(after: "calories", in: panel) else { return nil }

        let facts = NutritionFacts(
            energy: .exact(kcal: kcal),
            proteinGrams: value(after: "protein", in: panel),
            carbGrams: value(after: "total carbohydrate", in: panel) ?? value(after: "total carb", in: panel),
            fatGrams: value(after: "total fat", in: panel),
            servingDescription: servingSize(in: panel)
        )
        return ParsedLabel(facts: facts, nameGuess: nameGuess(above: headingIndex, in: lines))
    }

    // MARK: -

    /// Finds the first number following the field name — same line ("Calories 230") or the
    /// next line (columns split by OCR). Percent values (daily value) are skipped.
    private static func value(after field: String, in lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() {
            let lowered = line.lowercased()
            guard lowered.contains(field) else { continue }
            // Pre-2016 US panels print "Calories from Fat 40" — a substring match on
            // "calories" must never read that 40 as the item's energy.
            if field == "calories", lowered.contains("calories from") { continue }
            // "Total Fat 8g 10%" → first number after the field name, not the %DV.
            let tail = lowered.range(of: field).map { String(lowered[$0.upperBound...]) } ?? ""
            if let number = firstNumber(in: tail, excludingPercent: true) {
                return number
            }
            // Column-split OCR: the value is the next line ("Calories" / "230").
            if index + 1 < lines.count,
               let number = firstNumber(in: lines[index + 1].lowercased(), excludingPercent: true),
               // Only trust a bare-ish value line, not an unrelated sentence.
               lines[index + 1].count <= 12 {
                return number
            }
        }
        return nil
    }

    private static func firstNumber(in text: String, excludingPercent: Bool) -> Double? {
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char.isNumber || (char == "." && !current.isEmpty) {
                current.append(char)
            } else if !current.isEmpty {
                if excludingPercent && char == "%" {
                    current = ""   // that was a %DV — keep scanning
                } else {
                    break
                }
            }
            index = text.index(after: index)
        }
        return current.isEmpty ? nil : Double(current)
    }

    private static func servingSize(in lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            if let range = lowered.range(of: "serving size") {
                let tail = line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                if !tail.isEmpty { return tail }
            }
        }
        return nil
    }

    /// The longest mostly-letters line above the heading — crude, but names beat "Labeled
    /// item" and misses are inline-editable.
    private static func nameGuess(above headingIndex: Int, in lines: [String]) -> String? {
        lines[..<headingIndex]
            .filter { line in
                line.count >= 4 && line.count <= 60
                    && line.filter(\.isLetter).count * 2 > line.count   // mostly letters
            }
            .max { $0.count < $1.count }
    }
}
