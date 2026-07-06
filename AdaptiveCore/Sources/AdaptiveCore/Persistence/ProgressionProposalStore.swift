import Foundation
import Observation

/// One structural progression move awaiting the user's confirm — a strength load step-up or a
/// run-shape graduation. Exactly one of `update`/`runUpdate` is set (the two wire shapes).
public struct PendingStructuralProposal: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let routineId: UUID
    public let date: Date
    public let update: ProgressionUpdate?
    public let runUpdate: RunProgressionUpdate?
    /// The session's effort rating, carried for the card's context line.
    public let perceivedEffort: Int?

    public init(
        id: UUID = UUID(),
        routineId: UUID,
        date: Date = Date(),
        update: ProgressionUpdate? = nil,
        runUpdate: RunProgressionUpdate? = nil,
        perceivedEffort: Int? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.date = date
        self.update = update
        self.runUpdate = runUpdate
        self.perceivedEffort = perceivedEffort
    }
}

/// Phone-side store of structural proposals. A proposal persists until the user acts — never
/// answered means the routine simply keeps its old seed (hold is the policy's first-class
/// conservative default), so there is no expiry and no nag (Q5).
///
/// `confirm` returns the batch slice to feed through the existing
/// `RoutineStore.applyProgressions` path (which re-broadcasts to the watch); `decline` just
/// removes it. Journaling both outcomes is `ProgressionIntake`'s job, not this store's.
@MainActor
@Observable
public final class ProgressionProposalStore {
    public private(set) var proposals: [PendingStructuralProposal]

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.proposals = Self.load(from: self.fileURL)
    }

    public nonisolated static func defaultFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RoutineStore.appGroupIdentifier) else {
            return documents.appendingPathComponent("pending-proposals.json")
        }
        return container.appendingPathComponent("pending-proposals.json")
    }

    public func add(_ new: [PendingStructuralProposal]) {
        guard !new.isEmpty else { return }
        // One pending structural move per exercise/card: a newer session's proposal for the
        // same target supersedes the stale one (the old seed it was computed from no longer
        // reflects the latest session anyway).
        var kept = proposals.filter { existing in
            !new.contains { $0.targetKey == existing.targetKey && $0.routineId == existing.routineId }
        }
        kept.append(contentsOf: new)
        proposals = kept
        save()
    }

    /// Remove the proposal and hand back the batch to apply. Returns nil if already gone
    /// (double-tap safe).
    public func confirm(id: PendingStructuralProposal.ID) -> ProgressionBatch? {
        guard let proposal = remove(id: id) else { return nil }
        return ProgressionBatch(
            routineId: proposal.routineId,
            updates: proposal.update.map { [$0] } ?? [],
            runUpdates: proposal.runUpdate.map { [$0] } ?? []
        )
    }

    /// Remove the proposal without applying — declining is holding.
    @discardableResult
    public func decline(id: PendingStructuralProposal.ID) -> PendingStructuralProposal? {
        remove(id: id)
    }

    private func remove(id: PendingStructuralProposal.ID) -> PendingStructuralProposal? {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return nil }
        let proposal = proposals.remove(at: index)
        save()
        return proposal
    }

    private static func load(from url: URL) -> [PendingStructuralProposal] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        if let data = try? Data(contentsOf: url),
           let proposals = try? JSONDecoder().decode([PendingStructuralProposal].self, from: data) {
            return proposals
        }
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        return []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(proposals)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("ProgressionProposalStore: failed to persist: %@", String(describing: error))
        }
    }
}

extension PendingStructuralProposal {
    /// What this proposal targets — an exercise slug or a run card id — for supersede matching.
    var targetKey: String {
        update?.exerciseId ?? runUpdate.map { "run:\($0.cardId.uuidString)" } ?? id.uuidString
    }
}
