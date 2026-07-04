import Foundation

/// The only file this feature owns (C5): entries whose lookup/Health-write hadn't finished
/// when the app quit, so the ladder can resume next launch. Rows are deleted the moment the
/// Health write confirms — this is a queue, deliberately NOT a food-history store; deleting
/// the app loses nothing that was logged.
public final class PendingMealQueue: @unchecked Sendable {

    /// One in-flight item: enough context to re-run the ladder if the app died mid-lookup.
    /// `meal` is optional purely for Codable evolution — build-8 rows have no key and fall
    /// back to time-derived slotting on drain.
    public struct PendingItem: Codable, Identifiable, Sendable {
        public var id: UUID
        public var date: Date
        public var item: PendingDraft
        public var seller: Seller?
        public var answers: [QuestionAnswer]
        public var meal: MealSlot?

        public init(id: UUID = UUID(), date: Date, item: PendingDraft, seller: Seller?, answers: [QuestionAnswer], meal: MealSlot? = nil) {
            self.id = id
            self.date = date
            self.item = item
            self.seller = seller
            self.answers = answers
            self.meal = meal
        }
    }

    /// `DraftItem` minus the non-Codable bits we don't need to persist (questions were
    /// already answered by commit time). `statedFacts` MUST survive the round trip: the
    /// user's stated number outranks everything the drain could look up.
    public struct PendingDraft: Codable, Sendable {
        public var name: String
        public var quantity: Int
        public var barcode: String?
        public var labelFacts: NutritionFacts?
        public var statedFacts: NutritionFacts?

        public init(name: String, quantity: Int, barcode: String? = nil, labelFacts: NutritionFacts? = nil, statedFacts: NutritionFacts? = nil) {
            self.name = name
            self.quantity = quantity
            self.barcode = barcode
            self.labelFacts = labelFacts
            self.statedFacts = statedFacts
        }

        public init(from item: DraftItem) {
            self.init(
                name: item.name,
                quantity: item.quantity,
                barcode: item.barcode,
                labelFacts: item.labelFacts,
                statedFacts: item.statedFacts
            )
        }

        public var draftItem: DraftItem {
            DraftItem(name: name, quantity: quantity, labelFacts: labelFacts, statedFacts: statedFacts, barcode: barcode)
        }
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var items: [PendingItem]

    /// Default location mirrors RoutineStore (Application Support). Pass a temp URL for
    /// tests / `-uiTesting`.
    public init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending-meals.json")
        self.fileURL = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PendingItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    public var pending: [PendingItem] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func enqueue(_ item: PendingItem) {
        lock.lock()
        items.append(item)
        persistLocked()
        lock.unlock()
    }

    /// Called when the entry's Health write confirms — the row's whole purpose is over.
    public func remove(id: UUID) {
        lock.lock()
        items.removeAll { $0.id == id }
        persistLocked()
        lock.unlock()
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
