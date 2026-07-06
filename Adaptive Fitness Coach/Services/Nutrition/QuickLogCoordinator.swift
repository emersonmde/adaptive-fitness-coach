import Foundation
import UserNotifications
import OSLog
import AdaptiveCore

/// What `PhoneConnectivityManager` needs from the quick-log side — a seam so the manager
/// stays a dumb transport (mirrors its `weak var store` shape).
@MainActor
protocol QuickLogHandling: AnyObject {
    /// A live `sendMessage` round trip: request → draft, confirm → outcome. nil = no reply
    /// (the watch times out into its honest failure state).
    func handleLive(_ message: QuickLogMessage) async -> QuickLogMessage?
    /// An offline `transferUserInfo` delivery — park for review, never auto-commit.
    func handleOffline(_ message: QuickLogMessage)
}

/// Phone-side owner of the watch quick-log (P6): wraps the package `QuickLogService` with
/// the app's pipeline wiring, exposes the pending-REVIEW rows to the UI, and fires the one
/// (single, non-repeating) "waiting for review" notification for the offline path.
@MainActor
@Observable
final class QuickLogCoordinator: QuickLogHandling {
    private let service: QuickLogService
    private let queue: PendingMealQueue

    /// Offline quick-log rows awaiting the user's review, oldest first.
    private(set) var reviewItems: [PendingMealQueue.PendingItem] = []

    init(queue: PendingMealQueue = MealPipelineProvider.sharedQueue) {
        self.queue = queue
        let pipeline = MealPipelineProvider.makePipeline()
        self.service = QuickLogService(
            pipeline: pipeline,
            resolver: MealPipelineProvider.makeResolver(),
            recorder: MealPipelineProvider.sharedRecorder,
            queue: queue
        )
        refreshReviewItems()
    }

    func handleLive(_ message: QuickLogMessage) async -> QuickLogMessage? {
        switch message {
        case .request(let request):
            if let draft = await service.draft(for: request) { return .draft(draft) }
            return nil
        case .confirm(let confirm):
            return .outcome(await service.commit(confirm))
        case .draft, .outcome:
            return nil   // phone-authored shapes; never valid inbound
        }
    }

    func handleOffline(_ message: QuickLogMessage) {
        guard case .request(let request) = message else { return }
        service.enqueueForReview(request)
        refreshReviewItems()
        scheduleReviewNotification()
    }

    func refreshReviewItems() {
        reviewItems = queue.pending.filter(\.needsReview)
    }

    /// The reviewed row's job is done once its review flow committed (or the user deleted it).
    func completeReview(id: UUID) {
        queue.remove(id: id)
        refreshReviewItems()
        if reviewItems.isEmpty {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        }
    }

    // MARK: - The one review notification

    private static let notificationID = "quicklog-needs-review"

    /// One non-repeating nudge ~4h after arrival, only while something still waits — the
    /// badge on the week screen is the primary surface; this catches the forgotten-pending
    /// case the user flagged. First arrival requests notification auth (deferred-contextual,
    /// first UNUserNotificationCenter use in the app); denial degrades to the badge alone.
    private func scheduleReviewNotification() {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
            guard granted else { return }
            let pending = await center.pendingNotificationRequests()
            guard !pending.contains(where: { $0.identifier == Self.notificationID }) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Meal waiting for review"
            content.body = "A meal you logged on your watch is ready to finish on your iPhone."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4 * 3600, repeats: false)
            let request = UNNotificationRequest(identifier: Self.notificationID,
                                                content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                Logger(subsystem: "com.memerson.Adaptive-Fitness-Coach", category: "quicklog")
                    .error("Review notification failed: \(error)")
            }
        }
    }
}
