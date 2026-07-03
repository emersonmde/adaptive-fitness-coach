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
                // Seed loads are conservative: dumbbell seeds sit in a beginner band; barbell
                // seeds start at the empty 45 lb bar (deadlift with light plates); machine
                // stacks a bit higher. Steps are real increments: 2.5/5 lb plates, or 10 lb
                // for machine stacks and big pulls.
                if let seedWeight {
                    let ceiling: Double = exercise.equipment.contains(.machine) ? 100 : 65
                    #expect(seedWeight.pounds > 0 && seedWeight.pounds <= ceiling)
                    #expect([2.5, 5, 10].contains(exercise.weightStepPounds))
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

    /// Every entry declares its gear (the P3 coach narrows the vocabulary by what the user
    /// has), and loaded movements never claim to be bodyweight-only.
    @Test func equipmentTagsAreCoherent() {
        for exercise in ExerciseLibrary.all {
            #expect(!exercise.equipment.isEmpty)
            if case let .reps(_, seedWeight) = exercise.kind, seedWeight != nil {
                #expect(exercise.equipment != [.bodyweight],
                        "\(exercise.id) has a seed load but claims to need no equipment")
            }
        }
    }

    /// The coach's equipment intake only works if the catalog actually spans the gear it asks
    /// about — every equipment kind must unlock at least one movement.
    @Test func everyEquipmentKindHasMovements() {
        for equipment in Equipment.allCases {
            #expect(ExerciseLibrary.all.contains { $0.equipment.contains(equipment) },
                    "no movement uses \(equipment.rawValue)")
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
