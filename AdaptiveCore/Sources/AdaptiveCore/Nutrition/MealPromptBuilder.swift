import Foundation

/// Provider-agnostic prompt text for the meal pipeline (the `CoachPromptBuilder` pattern).
/// Engines may *append* wire-format specifics (tool names, output-schema nudges) but never
/// replace these — the C2/C3 rules live here, once, testable.
public enum MealPromptBuilder {

    // MARK: - Stage 1–3: identify (receipt/label OCR → item list)

    /// System instructions for the identify call over OCR text.
    public static func identifyInstructions() -> String {
        """
        You identify food items from OCR text captured by a phone camera — a store receipt, \
        a restaurant receipt, or a menu board. Extract:
        - the seller (store, restaurant, or brand) and, if you recognize it, the domain of \
        their official website
        - each food or drink line item with its quantity

        Rules:
        - Receipts list non-food items (bags, tax, totals, coupons) — exclude them.
        - Keep item names as printed but expand obvious abbreviations ("CHKN CSR SLD" → \
        "Chicken Caesar Salad").
        - Grocery receipts mix pantry staples with ready-to-eat food. Mark ready-to-eat items \
        as checked; mark pantry/multi-meal items (a jar of sauce, a bag of rice) as unchecked \
        — the user is logging what they're eating now, not their shopping.
        - Ask a clarifying question ONLY when the answer would materially change the calorie \
        count (portion split, size ambiguity). At most one question per item, 2–4 tappable \
        options, with a sensible default. Most items need no question.
        - Never invent items that aren't in the text.
        """
    }

    public static func extractionPrompt(ocrLines: [String]) -> String {
        """
        OCR text (reading order):
        ---
        \(ocrLines.joined(separator: "\n"))
        ---
        Identify the seller and the food items.
        """
    }

    // MARK: - Typed entry (build 8)

    /// System instructions for normalizing a typed/dictated description. The calorie clause
    /// and date words were already stripped deterministically — the model never sees them
    /// (and so can never rewrite them).
    public static func typedEntryInstructions() -> String {
        """
        You clean up a short typed or dictated description of food someone ate. Produce the \
        item (fix spelling, expand shorthand, proper brand capitalization — "chick fil a \
        market salad w grilled chicken" → seller "Chick-fil-A", item "Market Salad with \
        Grilled Chicken") and identify the seller (restaurant/store/brand) when one is named, \
        with its official website domain if you are confident of it.

        Rules:
        - One typed description is usually ONE item; split only when two foods are clearly \
        listed ("burger and fries" stays one meal item only if it's a named combo).
        - Never invent details that aren't in the text; keep unknown foods as written, \
        spelling-corrected.
        - Ask a clarifying question ONLY when the answer would materially change calories.
        """
    }

    public static func typedEntryPrompt(text: String) -> String {
        """
        Typed description:
        ---
        \(text)
        ---
        Identify the seller (if any) and the food item(s).
        """
    }

    // MARK: - Stage 4: search + adjudication (rung 2)

    public static func searchObjective(item: DraftItem, seller: Seller?) -> String {
        var objective = "Find the calories and macros for \(item.name)"
        if let seller {
            objective += " from \(seller.name)"
            if let domain = seller.domainHint {
                objective += " — prefer \(domain), their own published nutrition data"
            }
        }
        objective += ". Official or database nutrition facts, not blog guesses."
        return objective
    }

    public static func searchQueries(item: DraftItem, seller: Seller?) -> [String] {
        var queries: [String] = []
        if let seller {
            queries.append("\(seller.name) \(item.name) calories nutrition")
            if let domain = seller.domainHint {
                queries.append("\(item.name) calories site:\(domain)")
            }
        } else {
            queries.append("\(item.name) calories nutrition facts")
        }
        return queries
    }

    /// The single structured call judging search excerpts (rung 2b). Embeds the C3 grading
    /// rules so every engine grades identically. Excerpts are reduced to `budget` here —
    /// query-aware, nutrition lines kept — so the prompt fits the *running* model's context
    /// (the on-device model is 4,096 tokens total; oversized prompts were the spike's top
    /// failure).
    public static func adjudicationPrompt(
        item: DraftItem,
        seller: Seller?,
        answers: [QuestionAnswer],
        excerpts rawExcerpts: [SearchExcerpt],
        budget: ExcerptBudget
    ) -> String {
        let query = [item.name, seller?.name].compactMap { $0 }.joined(separator: " ")
        let excerpts = ExcerptReducer.reduce(rawExcerpts, query: query, budget: budget)
        var lines: [String] = []
        lines.append("Item: \(item.name)\(item.quantity > 1 ? " ×\(item.quantity) (give values for ONE)" : "")")
        if let seller {
            lines.append("Seller: \(seller.name)\(seller.domainHint.map { " (official site: \($0))" } ?? "")")
        }
        if !answers.isEmpty {
            lines.append("User clarified: " + answers.map { "\($0.questionID)=\($0.optionID)" }.joined(separator: ", "))
        }
        lines.append("""

        Search results:
        ---
        \(excerpts.enumerated().map { i, e in
            "[\(i + 1)] \(e.title)\n\(e.url?.absoluteString ?? "no url")\n\(e.excerpt)"
        }.joined(separator: "\n\n"))
        ---

        From these excerpts only, determine the calories (kcal) and macros for one serving of \
        this exact item. Rules:
        - Use a number only if an excerpt actually states it for this item (same seller, same \
        size). Do not average unrelated items or guess.
        - Prefer the seller's own site; otherwise a nutrition database or menu aggregator is \
        acceptable — report which source URL you used.
        - If the excerpts do not contain a defensible number for this item, say the lookup \
        failed rather than approximating. A wrong-but-confident number is the one \
        unacceptable failure.
        """)
        return lines.joined(separator: "\n")
    }

    // MARK: - Stage 4: agentic loop (rung 3)

    public static func agentInstructions(item: DraftItem, seller: Seller?) -> String {
        var sellerLine = ""
        if let seller {
            sellerLine = " from \(seller.name)"
            if let domain = seller.domainHint {
                sellerLine += " (their site: \(domain))"
            }
        }
        return """
        Find the published calorie and macro information for: \(item.name)\(sellerLine).

        Method:
        - Search first. Answer from search excerpts when they contain the number — do not \
        fetch pages you don't need.
        - Prefer the seller's own website or nutrition PDF; open databases are acceptable.
        - Fetch at most one page at a time, and only when the excerpts are insufficient. \
        Pass the item name as the fetch query so the relevant section is returned.
        - When you have the number, report kcal, macros if published, the source URL, and \
        nothing else. If you cannot find a published number, say so plainly — do not estimate.
        """
    }

    // MARK: - Stage 5: estimate fallback

    public static func estimateInstructions() -> String {
        """
        You estimate calories for a food item that has no published nutrition data — a \
        homemade or local-restaurant dish. Rules:
        - Always give a RANGE (low–high kcal), never a single number. The range should be \
        honest about portion uncertainty, not falsely tight.
        - State the assumptions the estimate rests on (portion size, cooking fat, common \
        additions), each as one short line.
        - If an assumption would swing the estimate by more than roughly 25%, phrase it as a \
        clarifying question with 2–4 tappable options and a sensible default instead of \
        assuming silently.
        """
    }

    public static func estimatePrompt(item: DraftItem, ocrLines: [String], answers: [QuestionAnswer]) -> String {
        var lines = ["Item: \(item.name)"]
        if !ocrLines.isEmpty {
            lines.append("Context text from the photo: \(ocrLines.prefix(12).joined(separator: " · "))")
        }
        if !answers.isEmpty {
            lines.append("User clarified: " + answers.map { "\($0.questionID)=\($0.optionID)" }.joined(separator: ", "))
        }
        lines.append("Estimate the calorie range and macros for one serving.")
        return lines.joined(separator: "\n")
    }
}
