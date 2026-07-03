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
/// and estimates must *always* be ranges (pinned by tests).
public enum Provenance: Sendable, Hashable, Codable {
    /// The seller's own published data (their domain) or their printed nutrition label.
    case verified(sourceURL: URL?)
    /// An open database or aggregator (Open Food Facts, USDA, menu aggregators…).
    case database(name: String, sourceURL: URL?)
    /// A model's guess, shown as a range with its assumptions on display.
    case estimate(assumptions: [String])

    /// The one-word UI label ("verified" / "database" / "estimate").
    public var label: String {
        switch self {
        case .verified: "verified"
        case .database: "database"
        case .estimate: "estimate"
        }
    }

    public var sourceURL: URL? {
        switch self {
        case .verified(let url): url
        case .database(_, let url): url
        case .estimate: nil
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

/// Pipeline stage 1 output: what kind of thing the camera saw.
public enum CaptureClassification: String, Sendable, Codable {
    case barcode
    case receipt
    case nutritionLabel
    case plate
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

    public init(barcodes: [String] = [], ocrLines: [String] = [], imageData: Data? = nil) {
        self.barcodes = barcodes
        self.ocrLines = ocrLines
        self.imageData = imageData
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
    /// The barcode this item came from, when the capture was a barcode scan (rung-1 key).
    public var barcode: String?

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Int = 1,
        isChecked: Bool = true,
        question: ClarifyingQuestion? = nil,
        labelFacts: NutritionFacts? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isChecked = isChecked
        self.question = question
        self.labelFacts = labelFacts
        self.barcode = barcode
    }
}

/// Stages 1–3 output = the confirmation screen's model. The item list (not chat history) is
/// the state that flows between pipeline stages (§5).
public struct MealDraft: Sendable {
    public var classification: CaptureClassification
    public var seller: Seller?
    public var items: [DraftItem]

    public init(classification: CaptureClassification, seller: Seller? = nil, items: [DraftItem]) {
        self.classification = classification
        self.seller = seller
        self.items = items
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

    public init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        quantity: Int = 1,
        facts: NutritionFacts,
        provenance: Provenance
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.quantity = quantity
        self.facts = facts
        self.provenance = provenance
    }
}
