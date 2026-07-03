import Foundation

/// Extracts and strips relative-date and meal words from typed/dictated text (build 8, for
/// the typed field and Siri): "chicken caesar salad from wendys from yesterday" →
/// (clean: "chicken caesar salad from wendys", date: yesterday-ish, slot: nil).
/// Deterministic and Calendar-based — a misheard date is one editable chip on the when-row;
/// a hallucinated one would be a wrong record (C3 in the time domain).
public enum TypedDatePhraseParser {

    public struct Result: Equatable {
        public var cleanText: String
        /// A representative timestamp for the referenced day/moment; nil = "now".
        public var date: Date?
        /// A meal slot when the phrase named one ("at lunch"); nil = derive from time.
        public var slot: MealSlot?
    }

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        var working = text
        var date: Date?
        var slot: MealSlot?

        func strip(_ phrases: [String]) -> Bool {
            for phrase in phrases {
                // Match as a whole trailing-or-embedded phrase, optionally led by "from"/"for".
                let pattern = "(?i)\\s*(?:\\bfrom\\b|\\bfor\\b|\\bat\\b)?\\s*\\b" +
                    NSRegularExpression.escapedPattern(for: phrase) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
                   let range = Range(match.range, in: working) {
                    working.removeSubrange(range)
                    return true
                }
            }
            return false
        }

        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }

        // Order matters: multi-word phrases before their substrings.
        if strip(["yesterday morning"]) { date = day(-1, hour: 8); slot = .breakfast }
        else if strip(["yesterday at lunch", "yesterday lunch"]) { date = day(-1, hour: 12); slot = .lunch }
        else if strip(["yesterday at dinner", "yesterday dinner", "yesterday evening"]) { date = day(-1, hour: 18); slot = .dinner }
        else if strip(["last night"]) { date = day(-1, hour: 20); slot = .dinner }
        else if strip(["yesterday"]) { date = day(-1, hour: 12) }
        else if strip(["this morning"]) { date = day(0, hour: 8); slot = .breakfast }
        else if strip(["at breakfast", "for breakfast"]) { slot = .breakfast }
        else if strip(["at lunch", "for lunch"]) { slot = .lunch }
        else if strip(["at dinner", "for dinner"]) { slot = .dinner }

        let clean = working
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-"))
        return Result(cleanText: clean.isEmpty ? text : clean, date: date, slot: slot)
    }
}
