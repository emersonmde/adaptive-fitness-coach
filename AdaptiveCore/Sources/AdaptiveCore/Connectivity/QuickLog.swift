import Foundation

/// P6 watch quick-log transport. Since the always-pending rework (2026-07): the watch
/// dictates text and the raw request rides `transferUserInfo` into the phone's
/// pending-REVIEW flow — queued text is never auto-committed into Health (N2/N6: no number
/// the user never saw). The phone (the brain — the model never runs on watch) looks it up
/// when the user opens the review card.
///
/// `QuickLogDraft`/`QuickLogConfirm`/`QuickLogOutcome` belong to the retired *live*
/// (request/reply) channel — build-≤17 watches still send it, so the shapes and the phone's
/// handler survive for compatibility until that floor rises. New watches never use them.
public struct QuickLogRequest: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// The dictated/scribbled text, verbatim.
    public let text: String
    /// When it was spoken — the meal's date, and the slot derives from it.
    public let date: Date

    public init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// The compact reply the watch renders: one line of truth (kcal is the hero), never the full
/// confirmation sheet. Ranges stay ranges (C3).
public struct QuickLogDraft: Codable, Sendable, Hashable {
    public let requestId: UUID
    /// Display name — a single item's name, or the items joined for a multi-item meal.
    public let name: String
    public let itemCount: Int
    /// Total kcal across items (midpoints for ranges).
    public let totalKcal: Int
    /// True when any item's number is an estimate range — the watch labels it "≈".
    public let isEstimate: Bool
    /// The provenance line ("Open Food Facts", "verified · saladworks.com", "3 items").
    public let sourceLabel: String

    public init(requestId: UUID, name: String, itemCount: Int, totalKcal: Int,
                isEstimate: Bool, sourceLabel: String) {
        self.requestId = requestId
        self.name = name
        self.itemCount = itemCount
        self.totalKcal = totalKcal
        self.isEstimate = isEstimate
        self.sourceLabel = sourceLabel
    }
}

public struct QuickLogConfirm: Codable, Sendable, Hashable {
    public let requestId: UUID
    public let accept: Bool

    public init(requestId: UUID, accept: Bool) {
        self.requestId = requestId
        self.accept = accept
    }
}

public struct QuickLogOutcome: Codable, Sendable, Hashable {
    public let requestId: UUID
    /// True only when every item's Health write confirmed (N6 — "Logged" is never a hope).
    public let saved: Bool

    public init(requestId: UUID, saved: Bool) {
        self.requestId = requestId
        self.saved = saved
    }
}

/// The one quick-log wire envelope — a single codec channel, discriminated inside the blob,
/// so the version constant covers every message shape at once.
public enum QuickLogMessage: Codable, Sendable, Hashable {
    case request(QuickLogRequest)
    case draft(QuickLogDraft)
    case confirm(QuickLogConfirm)
    case outcome(QuickLogOutcome)
}
