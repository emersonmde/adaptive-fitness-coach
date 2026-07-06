import Foundation
import Observation

/// One line of the phone's progression journal — a seed change (or a declined one) with its
/// why, rendered from the receiving phone's point of view. Append-only, newest first.
public struct ProgressionJournalEntry: Codable, Sendable, Hashable, Identifiable {
    /// How the change landed. Micro-steps apply automatically (N3); structural moves land as
    /// `confirmed` or `declined` when the user acts on the proposal card.
    public enum Kind: String, Codable, Sendable {
        case micro
        case confirmed
        case declined
    }

    public let id: UUID
    public let date: Date
    public let routineId: UUID
    public let routineName: String
    /// What moved — an exercise name ("Bicep Curl") or "Run intervals".
    public let subject: String
    /// The change itself, old → new ("12 → 13 reps", "2:00 → 2:30 run · 2:00 walk").
    public let changeText: String
    /// The policy's clause ("clean session"), nil for manual adjustments and pre-v4 senders.
    public let reason: String?
    public let kind: Kind
    /// The session's post-workout effort rating, when one was given.
    public let perceivedEffort: Int?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        routineId: UUID,
        routineName: String,
        subject: String,
        changeText: String,
        reason: String?,
        kind: Kind,
        perceivedEffort: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.routineId = routineId
        self.routineName = routineName
        self.subject = subject
        self.changeText = changeText
        self.reason = reason
        self.kind = kind
        self.perceivedEffort = perceivedEffort
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, routineId, routineName, subject, changeText, reason, kind, perceivedEffort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        routineId = try c.decode(UUID.self, forKey: .routineId)
        routineName = try c.decode(String.self, forKey: .routineName)
        subject = try c.decode(String.self, forKey: .subject)
        changeText = try c.decode(String.self, forKey: .changeText)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        // An unknown future kind decodes as micro rather than dropping the row.
        kind = Kind(rawValue: try c.decode(String.self, forKey: .kind)) ?? .micro
        perceivedEffort = try c.decodeIfPresent(Int.self, forKey: .perceivedEffort)
    }
}

/// The phone-side progression journal: every seed change with its why, newest first.
///
/// The phone is the **single writer** — entries are appended where inbound progression
/// batches land (`ProgressionIntake`) and where proposals are confirmed/declined, so there is
/// no cross-device merge. Persistence mirrors `RoutineStore`: JSON file (App Group container
/// when available), atomic writes, a `.corrupt` sidecar instead of silent data loss.
@MainActor
@Observable
public final class ProgressionJournal {
    /// Newest first.
    public private(set) var entries: [ProgressionJournalEntry]

    private let fileURL: URL
    /// Oldest rows fall off past this — the journal is a readable history, not an archive.
    private let cap: Int

    public init(fileURL: URL? = nil, cap: Int = 500) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.cap = cap
        self.entries = Self.load(from: self.fileURL)
    }

    public nonisolated static func defaultFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RoutineStore.appGroupIdentifier) else {
            return documents.appendingPathComponent("progression-journal.json")
        }
        return container.appendingPathComponent("progression-journal.json")
    }

    /// Prepend new entries (they render newest-first) and persist.
    public func append(_ new: [ProgressionJournalEntry]) {
        guard !new.isEmpty else { return }
        entries = Array((new.sorted { $0.date > $1.date } + entries).prefix(cap))
        save()
    }

    private static func load(from url: URL) -> [ProgressionJournalEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        if let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([ProgressionJournalEntry].self, from: data) {
            return entries
        }
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        return []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("ProgressionJournal: failed to persist: %@", String(describing: error))
        }
    }
}
