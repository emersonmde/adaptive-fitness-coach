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

    /// The app-level controller (one per launch; the capture flow resets it per session).
    static func makeController() -> MealLogController {
        if isSimulated {
            let pipeline = ScriptedMealPipeline.demo(delays: true)
            let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            let queueURL = ephemeral
                ? FileManager.default.temporaryDirectory
                    .appendingPathComponent("ephemeral-pending-\(UUID().uuidString).json")
                : nil
            return MealLogController(
                pipeline: pipeline,
                resolver: pipeline.scriptedResolver(),
                recorder: sharedRecorder,
                queue: PendingMealQueue(fileURL: queueURL)
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
            queue: PendingMealQueue()
        )
    }

    /// One recorder per launch, shared by the controller and the daily line: in-memory under
    /// simulation (the sim can't grant HealthKit auth, and demos shouldn't write real data),
    /// HealthKit otherwise.
    static let sharedRecorder: any NutritionRecorder = isSimulated
        ? InMemoryNutritionRecorder()
        : HealthKitNutritionRecorder()

    /// The daily target setting (build 8) — one instance drives the gauge and the hub line.
    static let sharedTargetStore = CalorieTargetStore()

    /// Body data for the target suggestion: fixed fixture in the sim (stable suggested
    /// numbers for demos/UI tests), HealthKit on device.
    static func makeBodyProfileSource() -> any BodyProfileSource {
        isSimulated ? FixedBodyProfileSource() : HealthKitBodyProfileSource()
    }
}
