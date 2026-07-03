import Foundation

/// P4 calorie tracking — core value types (spec: docs/calorie-tracking-spec.md).
///
/// Everything here is pure data shared by the pipeline seam (`MealPipeline`), the lookup
/// ladder (`MealResolver`), and the UI state (`MealLogController`). No HealthKit, no Vision —
/// the phone target converts at its edges (Vision output → `MealCapture`,
/// `MealEntry` → HKCorrelation), exactly as the workout engine consumes a plain `Int?` zone.

/// Nutrition numbers for one logged item. Energy is either an exact retrieved value or an
/// honest range — estimates are *structurally* unable to masquerade as facts (C3).
public struct NutritionFacts: Sendable, Hashable, Codable {
    public enum Energy: Sendable, Hashable, Codable {
        case exact(kcal: Double)
        /// Estimates only. The UI renders the range; Health stores the midpoint scalar
        /// (HealthKit has no range type) with the bounds preserved in sample metadata.
        case range(lowKcal: Double, highKcal: Double)

        public var midpointKcal: Double {
            switch self {
            case .exact(let kcal): kcal
            case .range(let low, let high): (low + high) / 2
            }
        }

        public var isRange: Bool {
            if case .range = self { return true }
            return false
        }
    }

    public var energy: Energy
    public var proteinGrams: Double?
    public var carbGrams: Double?
    public var fatGrams: Double?
    /// Human portion text, e.g. "1 salad (368 g)" or the honest "per 100 g" fallback when a
    /// database had no serving data — never an invented portion (C3).
    public var servingDescription: String?

    public init(
        energy: Energy,
        proteinGrams: Double? = nil,
        carbGrams: Double? = nil,
        fatGrams: Double? = nil,
        servingDescription: String? = nil
    ) {
        self.energy = energy
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
        self.servingDescription = servingDescription
    }
}

/// Where a number came from (C3). Every logged entry carries one; the UI language is quiet
/// but always present. `estimate` is the only case allowed to pair with `Energy.range`,
/// and estimates must *always* be ranges (pinned by tests). `userStated` pairs with `.exact`
/// — a stated number is exact by definition.
public enum Provenance: Sendable, Hashable, Codable {
    /// The seller's own published data (their domain) or their printed nutrition label.
    case verified(sourceURL: URL?)
    /// An open database or aggregator (Open Food Facts, USDA, menu aggregators…).
    case database(name: String, sourceURL: URL?)
    /// A model's guess, shown as a range with its assumptions on display.
    case estimate(assumptions: [String])
    /// The user's own number — a stated calorie count ("…, 400 calories") or a post-hoc
    /// edit. Honest by construction: "the user said so" is a legitimate source, distinct
    /// from anything retrieved or guessed (build 8).
    case userStated

    /// The quiet UI phrase ("verified" / "database" / "estimate" / "your number").
    public var label: String {
        switch self {
        case .verified: "verified"
        case .database: "database"
        case .estimate: "estimate"
        case .userStated: "your number"
        }
    }

    /// Stable machine string for Health metadata (never the UI label).
    public var metadataValue: String {
        switch self {
        case .verified: "verified"
        case .database: "database"
        case .estimate: "estimate"
        case .userStated: "userStated"
        }
    }

    public var sourceURL: URL? {
        switch self {
        case .verified(let url): url
        case .database(_, let url): url
        case .estimate, .userStated: nil
        }
    }
}

/// Who sold the food — store, restaurant, or manufacturer. `domainHint` feeds the provenance
/// grader (seller's own domain → verified) and the lookup prompts ("prefer wendys.com").
public struct Seller: Sendable, Hashable, Codable {
    public var name: String
    public var domainHint: String?

    public init(name: String, domainHint: String? = nil) {
        self.name = name
        self.domainHint = domainHint
    }
}

/// Pipeline stage 1 output: what kind of thing the camera saw (or the keyboard produced).
public enum CaptureClassification: String, Sendable, Codable {
    case barcode
    case receipt
    case nutritionLabel
    case plate
    /// Typed or dictated text (build 8) — no camera involved.
    case typed
    case unknown
}

/// The phone's Vision output, as plain values the package can reason about. `imageData` is
/// carried for the plate-estimate fallback and future multimodal calls; the retrieval path
/// never needs pixels.
public struct MealCapture: Sendable {
    /// Detected barcode payloads (EAN/UPC strings). Non-empty ⇒ classification is decided
    /// deterministically, no model call.
    public var barcodes: [String]
    /// Recognized text lines in reading order.
    public var ocrLines: [String]
    public var imageData: Data?
    /// Typed or Siri-dictated description ("salmon caesar salad, 400 calories") — the
    /// keyboard path (build 8). Non-nil ⇒ classification `.typed`.
    public var typedText: String?

    public init(
        barcodes: [String] = [],
        ocrLines: [String] = [],
        imageData: Data? = nil,
        typedText: String? = nil
    ) {
        self.barcodes = barcodes
        self.ocrLines = ocrLines
        self.imageData = imageData
        self.typedText = typedText
    }
}

/// One identified item on the confirmation screen. The user can uncheck it (no lookup is
/// spent — §5), fix the name inline, and answer at most one material question (C4).
public struct DraftItem: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    /// Receipt line quantity; multiplies the resolved facts at record time.
    public var quantity: Int
    /// Pre-checked for the obvious case (spec §4.3); pantry items arrive unchecked.
    public var isChecked: Bool
    /// At most one, asked only when the answer materially moves the number (C4).
    public var question: ClarifyingQuestion?
    /// Set when a nutrition label was parsed directly — short-circuits the lookup ladder
    /// as `.verified` (the seller's own printed data).
    public var labelFacts: NutritionFacts?
    /// Set when the user *stated* the number ("…, 400 calories") — short-circuits the ladder
    /// as `.userStated`, above even the printed label. Deliberately distinct from
    /// `labelFacts`: reusing it would launder a user's number as "verified" (C3).
    public var statedFacts: NutritionFacts?
    /// The barcode this item came from, when the capture was a barcode scan (rung-1 key).
    public var barcode: String?

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Int = 1,
        isChecked: Bool = true,
        question: ClarifyingQuestion? = nil,
        labelFacts: NutritionFacts? = nil,
        statedFacts: NutritionFacts? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isChecked = isChecked
        self.question = question
        self.labelFacts = labelFacts
        self.statedFacts = statedFacts
        self.barcode = barcode
    }
}

public extension DraftItem {
    /// The plate-photo fallback's single item (stage 5's entry): a placeholder name the user
    /// fixes inline, plus the portion question — the one assumption that most moves an
    /// estimate, asked up front as a deterministic C4 question rather than assumed silently.
    static func plateFallback() -> DraftItem {
        DraftItem(
            name: "Plate of food (tap to name it)",
            question: ClarifyingQuestion(
                id: "plate-portion",
                prompt: "How big a portion?",
                options: [
                    .init(id: "light", label: "Light"),
                    .init(id: "regular", label: "Regular"),
                    .init(id: "large", label: "Large"),
                ],
                defaultOptionID: "regular"
            )
        )
    }
}

/// Stages 1–3 output = the confirmation screen's model. The item list (not chat history) is
/// the state that flows between pipeline stages (§5).
public struct MealDraft: Sendable {
    public var classification: CaptureClassification
    public var seller: Seller?
    public var items: [DraftItem]
    /// When the capture itself carries a timestamp — a receipt's printed date/time
    /// (`ReceiptDateParser`) or a typed "yesterday" — the confirmation screen's when-row
    /// prefills from it (labeled, editable). Nil means "now".
    public var capturedAt: Date?

    public init(
        classification: CaptureClassification,
        seller: Seller? = nil,
        items: [DraftItem],
        capturedAt: Date? = nil
    ) {
        self.classification = classification
        self.seller = seller
        self.items = items
        self.capturedAt = capturedAt
    }
}

/// Stage 4/5 output for one item: the number plus where it came from, inseparably.
public struct ResolvedNutrition: Sendable, Hashable {
    public var facts: NutritionFacts
    public var provenance: Provenance

    public init(facts: NutritionFacts, provenance: Provenance) {
        self.facts = facts
        self.provenance = provenance
    }
}

/// What gets recorded to Health (and queued while lookups are in flight). Codable so the
/// pending queue can persist in-flight entries across launches — deliberately NOT a food
/// history store (C5): rows exist only until the Health write confirms.
public struct MealEntry: Identifiable, Sendable, Codable, Hashable {
    public var id: UUID
    public var date: Date
    public var name: String
    public var quantity: Int
    public var facts: NutritionFacts
    public var provenance: Provenance
    /// Day-screen grouping (build 8). Auto-suggested from the entry's time; user-correctable.
    public var meal: MealSlot

    public init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        quantity: Int = 1,
        facts: NutritionFacts,
        provenance: Provenance,
        meal: MealSlot? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.quantity = quantity
        self.facts = facts
        self.provenance = provenance
        self.meal = meal ?? MealSlot.suggested(for: date)
    }

    // Custom decode only: build-7 PendingMealQueue rows have no `meal` key — derive it from
    // the date instead of failing the whole queue at upgrade. Encoding stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case id, date, name, quantity, facts, provenance, meal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(Date.self, forKey: .date)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            date: date,
            name: try container.decode(String.self, forKey: .name),
            quantity: try container.decode(Int.self, forKey: .quantity),
            facts: try container.decode(NutritionFacts.self, forKey: .facts),
            provenance: try container.decode(Provenance.self, forKey: .provenance),
            meal: try container.decodeIfPresent(MealSlot.self, forKey: .meal)
        )
    }
}

public extension MealEntry {
    /// A post-hoc edit (the day screen's edit sheet). Changing the calorie value makes the
    /// number the user's — energy becomes `.exact(kcal)` and provenance `.userStated`
    /// (macros are kept: the user restated energy, not composition). Name/slot/day edits
    /// alone preserve the original facts and provenance.
    func edited(
        name: String? = nil,
        kcal: Double? = nil,
        meal: MealSlot? = nil,
        date: Date? = nil
    ) -> MealEntry {
        var copy = self
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.name = name.trimmingCharacters(in: .whitespaces)
        }
        if let kcal, kcal > 0, kcal != facts.energy.midpointKcal || facts.energy.isRange {
            copy.facts.energy = .exact(kcal: kcal)
            copy.provenance = .userStated
        }
        if let meal { copy.meal = meal }
        if let date { copy.date = date }
        return copy
    }

    /// "Log again": the same food as a brand-new entry, now. Fresh identity (delete-by-id
    /// must never collide), slot re-suggested from the new time; facts/provenance copied.
    func relogged(at now: Date = Date()) -> MealEntry {
        MealEntry(
            date: now,
            name: name,
            quantity: quantity,
            facts: facts,
            provenance: provenance
        )
    }
}
