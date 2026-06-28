import Foundation
import Testing
@testable import AdaptiveCore

/// Invariants the curated catalog must hold so the builder and the watch can trust it.
struct ExerciseLibraryTests {

    @Test func libraryIsNonEmpty() {
        #expect(ExerciseLibrary.all.count >= 8)
    }

    @Test func idsAreUnique() {
        let ids = ExerciseLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyIdResolves() {
        for exercise in ExerciseLibrary.all {
            #expect(ExerciseLibrary.exercise(id: exercise.id)?.id == exercise.id)
        }
    }

    @Test func unknownIdReturnsNil() {
        #expect(ExerciseLibrary.exercise(id: "not_a_real_id") == nil)
    }

    @Test func everyEntryIsWellFormed() {
        for exercise in ExerciseLibrary.all {
            #expect(!exercise.name.isEmpty)
            #expect(!exercise.goodFor.isEmpty)
            #expect(!exercise.muscleTags.isEmpty)
            #expect(exercise.defaultSets >= 1)
            switch exercise.kind {
            case let .reps(defaultReps, seedWeight):
                #expect(defaultReps >= 1)
                // Seed loads are conservative: present ones sit in a sane beginner band.
                if let seedWeight {
                    #expect(seedWeight.pounds > 0 && seedWeight.pounds <= 60)
                }
            case let .hold(defaultSeconds):
                #expect(defaultSeconds >= 10)
            }
        }
    }

    /// Isometric archetype and hold prescription must agree — a plank can't be rep-based, and a
    /// held movement must be tagged isometric so P2's stability-envelope read keys correctly.
    @Test func isometricArchetypeMatchesHoldKind() {
        for exercise in ExerciseLibrary.all {
            #expect(exercise.kind.isHold == (exercise.archetype == .isometric))
        }
    }

    @Test func formDemosAreSymbolPlaceholdersForNow() {
        for exercise in ExerciseLibrary.all {
            if case .symbol(let name) = exercise.formDemo {
                #expect(name.hasPrefix("figure"))
            } else {
                Issue.record("P1 ships SF Symbol placeholders only; \(exercise.id) uses another asset kind")
            }
        }
    }
}
