import Foundation

/// Finds a receipt's printed transaction date (and time when adjacent) in OCR lines, so the
/// confirmation screen's when-row can prefill "scanning yesterday's lunch receipt" correctly.
///
/// Deterministic by design — an LLM confidently inventing a date is C3's fabricated-number
/// failure in the time domain. A missed exotic format costs one tap on the editable when-row;
/// a hallucinated date is a wrong record. Sanity clamp: printed dates in the future or more
/// than a year old are rejected (OCR misreads, best-by dates).
public enum ReceiptDateParser {

    private static let datePatterns: [(NSRegularExpression, DateOrder)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return [
            // 07/02/2026, 7/2/26, 07-02-2026
            (regex(#"\b(\d{1,2})[/-](\d{1,2})[/-](\d{2}|\d{4})\b"#), .monthDayYear),
            // 2026-07-02
            (regex(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#), .yearMonthDay),
            // Jul 2, 2026 / July 2 2026 / 02 Jul 2026
            (regex(#"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{4}))\b"#), .monthNameDayYear),
            (regex(#"\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{4})\b"#), .dayMonthNameYear),
        ]
    }()

    private static let timePattern = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?\b"#,
        options: [.caseInsensitive]
    )

    private enum DateOrder { case monthDayYear, yearMonthDay, monthNameDayYear, dayMonthNameYear }

    private static let monthNames = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                     "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    public static func parse(
        ocrLines: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        for line in ocrLines {
            guard var components = dateComponents(in: line) else { continue }
            // A time on the same line refines the timestamp (receipts print them adjacent).
            if let time = timeComponents(in: line) {
                components.hour = time.hour
                components.minute = time.minute
            } else {
                components.hour = 12   // date-only: noon keeps the entry mid-day, slot .lunch-ish
            }
            guard let date = calendar.date(from: components) else { continue }
            // Sanity clamp (allow a few minutes of clock skew on "today" receipts).
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            if date > now.addingTimeInterval(10 * 60) || date < yearAgo { continue }
            return date
        }
        return nil
    }

    // MARK: -

    private static func dateComponents(in line: String) -> DateComponents? {
        let range = NSRange(line.startIndex..., in: line)
        for (regex, order) in datePatterns {
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            func group(_ index: Int) -> String? {
                guard let r = Range(match.range(at: index), in: line) else { return nil }
                return String(line[r]).lowercased()
            }
            var year: Int?, month: Int?, day: Int?
            switch order {
            case .monthDayYear:
                month = group(1).flatMap(Int.init)
                day = group(2).flatMap(Int.init)
                year = group(3).flatMap(Int.init)
            case .yearMonthDay:
                year = group(1).flatMap(Int.init)
                month = group(2).flatMap(Int.init)
                day = group(3).flatMap(Int.init)
            case .monthNameDayYear:
                month = group(1).flatMap { monthNames[String($0.prefix(3))] }
                day = group(2).flatMap(Int.init)
                year = group(3).flatMap(Int.init)
            case .dayMonthNameYear:
                day = group(1).flatMap(Int.init)
                month = group(2).flatMap { monthNames[String($0.prefix(3))] }
                year = group(3).flatMap(Int.init)
            }
            guard var y = year, let m = month, let d = day,
                  (1...12).contains(m), (1...31).contains(d) else { continue }
            if y < 100 { y += 2000 }
            guard y >= 2000, y <= 2100 else { continue }
            return DateComponents(year: y, month: m, day: d)
        }
        return nil
    }

    private static func timeComponents(in line: String) -> (hour: Int, minute: Int)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = timePattern.firstMatch(in: line, range: range) else { return nil }
        func group(_ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: line) else { return nil }
            return String(line[r]).lowercased()
        }
        guard var hour = group(1).flatMap(Int.init),
              let minute = group(2).flatMap(Int.init),
              hour <= 23, minute <= 59 else { return nil }
        if let meridiem = group(3) {
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }
        return (hour, minute)
    }
}
