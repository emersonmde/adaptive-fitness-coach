import Foundation
import AdaptiveCore

/// Backend selection for the meal pipeline — `CoachEngineProvider`'s sibling. One place
/// decides scripted vs production, so tests, the simulator demo, and the real app differ by
/// exactly one launch argument (`-simulateMealScan`).
@MainActor
enum MealPipelineProvider {

    static var isSimulated: Bool {
        ProcessInfo.processInfo.arguments.contains("-simulateMealScan")
    }

    /// ONE pending queue per launch, shared by the controller, the watch quick-log
    /// coordinator, and the review UI (P6) — two instances over the same file would hold
    /// stale in-memory copies of each other's rows. Ephemeral under `-uiTesting`.
    static let sharedQueue: PendingMealQueue = {
        let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let queueURL = ephemeral
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-pending-\(UUID().uuidString).json")
            : nil
        return PendingMealQueue(fileURL: queueURL)
    }()

    /// The typed/scanned identify pipeline — shared by the controller and the quick-log
    /// coordinator (same scripted-vs-production split everywhere).
    static func makePipeline() -> any MealPipeline {
        isSimulated ? ScriptedMealPipeline.demo(delays: true) : FoundationModelsMealPipeline()
    }

    /// The app-level controller (one per launch; the capture flow resets it per session).
    static func makeController() -> MealLogController {
        if isSimulated {
            let pipeline = ScriptedMealPipeline.demo(delays: true)
            return MealLogController(
                pipeline: pipeline,
                resolver: pipeline.scriptedResolver(),
                recorder: sharedRecorder,
                queue: sharedQueue
            )
        }
        let pipeline = FoundationModelsMealPipeline()
        let resolver = MealResolver(
            barcodeDB: OpenFoodFactsClient(),
            searcher: ParallelSearchClient(),
            adjudicator: FoundationModelsAdjudicator(),
            // Rung 3 ships disabled until the LookupLab spike justifies it (CQ1); the
            // resolver tolerates the nil and falls through to the honest estimate.
            agent: nil,
            estimator: FoundationModelsEstimator()
        )
        return MealLogController(
            pipeline: pipeline,
            resolver: resolver,
            recorder: sharedRecorder,
            queue: sharedQueue
        )
    }

    /// The lookup ladder on its own — the edit sheet's "Look up again" re-resolves an
    /// already-logged entry against an edited name/seller. Same wiring as the controller's.
    static func makeResolver() -> MealResolver {
        if isSimulated {
            return ScriptedMealPipeline.demo(delays: true).scriptedResolver()
        }
        return MealResolver(
            barcodeDB: OpenFoodFactsClient(),
            searcher: ParallelSearchClient(),
            adjudicator: FoundationModelsAdjudicator(),
            agent: nil,
            estimator: FoundationModelsEstimator()
        )
    }

    /// One recorder per launch, shared by the controller and the daily line: in-memory under
    /// simulation (the sim can't grant HealthKit auth, and demos shouldn't write real data),
    /// HealthKit otherwise.
    static let sharedRecorder: any NutritionRecorder = {
        guard isSimulated else { return HealthKitNutritionRecorder() }
        let recorder = InMemoryNutritionRecorder()
        // Seed a day with activity so the demo budget shows the base + active composition
        // (the real signal comes from the watch; the sim generates none).
        recorder.setActiveEnergy(524, on: Date())
        return recorder
    }()

    /// The daily target setting — one instance drives the gauge and the hub line. Carries its
    /// own body-profile + energy-history sources so it can refresh the learned TDEE calibration.
    static let sharedTargetStore = CalorieTargetStore(
        bodyProfileSource: makeBodyProfileSource(),
        energyHistorySource: makeEnergyHistorySource()
    )

    /// Body data for the target suggestion: fixed fixture in the sim (stable suggested
    /// numbers for demos/UI tests), HealthKit on device.
    static func makeBodyProfileSource() -> any BodyProfileSource {
        isSimulated ? FixedBodyProfileSource() : HealthKitBodyProfileSource()
    }

    /// Trailing weight / intake / active-energy series for the TDEE calibration: a seeded
    /// in-memory fake under simulation (so `-simulateMealScan` can demo a tuned budget), the
    /// HealthKit collection queries on device.
    static func makeEnergyHistorySource() -> any EnergyHistorySource {
        isSimulated ? InMemoryEnergyHistorySource(SimulatedEnergyHistory.demo) : HealthKitEnergyHistorySource()
    }
}
