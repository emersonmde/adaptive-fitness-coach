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
            #expect(!exercise.howTo.isEmpty)   // the help screen needs a how-to for every entry
            #expect(!exercise.muscleTags.isEmpty)
            #expect(exercise.defaultSets >= 1)
            switch exercise.kind {
            case let .reps(repRange, seedWeight):
                // Every band supports double progression: sane bottom, real headroom.
                #expect(repRange.lowerBound >= 1)
                #expect(repRange.count >= 3)
                // Seed loads are conservative: present ones sit in a sane beginner band, and
                // the load step is a real increment (2.5 or 5 lb) only for weighted moves.
                if let seedWeight {
                    #expect(seedWeight.pounds > 0 && seedWeight.pounds <= 60)
                    #expect(exercise.weightStepPounds == 2.5 || exercise.weightStepPounds == 5)
                }
            case let .hold(defaultSeconds):
                // Hold seeds start inside the policy's [floor, cap] band.
                #expect(defaultSeconds >= 15 && defaultSeconds <= 120)
            }
            #expect(exercise.restSeedSeconds >= 45 && exercise.restSeedSeconds <= 180)
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
