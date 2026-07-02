import Foundation

/// A contiguous run of cards that share one Apple workout. The watch starts an `HKWorkoutSession`
/// of `kind` for the block, performs its `cards` in order, then ends it before the next block —
/// so a routine that mixes a run and strength records as one Health workout per block, switching
/// automatically on card type (the app's core convenience).
public struct WorkoutBlock: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var kind: WorkoutKind
    public var cards: [WorkoutCard]

    public init(id: UUID = UUID(), kind: WorkoutKind, cards: [WorkoutCard]) {
        self.id = id
        self.kind = kind
        self.cards = cards
    }
}

public extension Sequence where Element == WorkoutCard {
    /// Split a card sequence into workout blocks by `workoutKind`. Consecutive cards of the same
    /// kind merge into one block; a kind change starts a new block. Rest cards have no kind of
    /// their own — they attach to the surrounding block (or the next one, if they lead).
    func workoutBlocks() -> [WorkoutBlock] {
        var blocks: [WorkoutBlock] = []
        var leadingRests: [WorkoutCard] = []

        for card in self {
            guard let kind = card.workoutKind else {
                // Rest: attach to the current block, or buffer it until the first block exists.
                if blocks.isEmpty {
                    leadingRests.append(card)
                } else {
                    blocks[blocks.count - 1].cards.append(card)
                }
                continue
            }

            if blocks.isEmpty {
                blocks.append(WorkoutBlock(kind: kind, cards: leadingRests + [card]))
                leadingRests = []
            } else if blocks[blocks.count - 1].kind == kind {
                blocks[blocks.count - 1].cards.append(card)
            } else {
                blocks.append(WorkoutBlock(kind: kind, cards: [card]))
            }
        }

        // A routine of only rest cards (degenerate) has no workout to attach them to — drop them
        // rather than invent a session with no exercise (N6).
        return blocks
    }
}
