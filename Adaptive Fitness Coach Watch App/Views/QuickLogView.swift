import SwiftUI
import AdaptiveCore

/// The transport seam behind the quick-log screen — live WatchConnectivity in production, a
/// canned script under `-simulateQuickLog` (paired-sim WC is unreliable; the sim path is the
/// only way to see this flow without hardware).
struct QuickLogTransport {
    var send: (QuickLogRequest) async -> QuickLogDraft?
    var confirm: (QuickLogConfirm) async -> Bool
    var queueOffline: (QuickLogRequest) -> Void

    @MainActor
    static func live(_ connectivity: WatchConnectivityManager) -> QuickLogTransport {
        QuickLogTransport(
            send: { await connectivity.sendQuickLog($0) },
            confirm: { await connectivity.confirmQuickLog($0) },
            queueOffline: { connectivity.queueQuickLogOffline($0) }
        )
    }

    /// Canned draft for the Simulator/demo: every request drafts to a fixed salad.
    static var scripted: QuickLogTransport {
        QuickLogTransport(
            send: { request in
                try? await Task.sleep(for: .milliseconds(600))
                return QuickLogDraft(requestId: request.id,
                                     name: "Chicken Caesar Salad", itemCount: 1,
                                     totalKcal: 460, isEstimate: false,
                                     sourceLabel: "Open Food Facts")
            },
            confirm: { _ in
                try? await Task.sleep(for: .milliseconds(300))
                return true
            },
            queueOffline: { _ in }
        )
    }
}

/// P6 watch quick-log (B-series sibling): dictate → the phone drafts → one glanceable
/// confirm — kcal is the hero, provenance the quiet line. Offline is honest: the text is
/// queued and reviewed on the iPhone; the wrist never invents a number (N6), and "Logged"
/// renders only after the phone confirmed the Health write.
struct QuickLogView: View {
    let transport: QuickLogTransport
    var onDone: (() -> Void)?

    private enum Phase: Equatable {
        case input
        case sending(QuickLogRequest)
        case draft(QuickLogDraft)
        case committing(QuickLogDraft)
        case logged
        case queuedOffline
        case unreachable(QuickLogRequest)
        case failed
    }

    @State private var text = ""
    @State private var phase: Phase = .input

    var body: some View {
        switch phase {
        case .input:
            inputScreen
        case .sending:
            statusScreen(spinner: true, title: "Looking up…", subtitle: nil)
        case .draft(let draft), .committing(let draft):
            draftScreen(draft, committing: {
                if case .committing = phase { return true } else { return false }
            }())
        case .logged:
            confirmationScreen(symbol: "checkmark.circle.fill", tint: WatchTheme.run,
                               title: "Logged", subtitle: "Saved to Health")
        case .queuedOffline:
            confirmationScreen(symbol: "clock.badge.checkmark", tint: WatchTheme.recover,
                               title: "Saved for iPhone",
                               subtitle: "It'll be looked up when your iPhone is nearby — finish it there.")
        case .unreachable(let request):
            unreachableScreen(request)
        case .failed:
            confirmationScreen(symbol: "exclamationmark.triangle", tint: WatchTheme.heat,
                               title: "Couldn't log it",
                               subtitle: "Nothing was saved. Try again on your iPhone.")
        }
    }

    // MARK: - Screens

    private var inputScreen: some View {
        VStack(spacing: 10) {
            // On watchOS a TextField opens dictation/scribble — free input UI.
            TextField("What did you eat?", text: $text)
                .accessibilityIdentifier("quicklog.field")
            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let request = QuickLogRequest(text: trimmed)
                phase = .sending(request)
                Task {
                    if let draft = await transport.send(request) {
                        withAnimation(WatchTheme.Motion.settle) { phase = .draft(draft) }
                    } else {
                        withAnimation(WatchTheme.Motion.settle) { phase = .unreachable(request) }
                    }
                }
            } label: {
                Label("Log it", systemImage: "arrow.up.circle.fill")
            }
            .tint(WatchTheme.recover)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("quicklog.send")
        }
        .navigationTitle("Log a meal")
    }

    private func draftScreen(_ draft: QuickLogDraft, committing: Bool) -> some View {
        VStack(spacing: 6) {
            Text(draft.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(draft.isEstimate ? "≈ " : "")\(draft.totalKcal) kcal")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(draft.sourceLabel)
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
            HStack(spacing: 8) {
                Button(role: .cancel) {
                    Task {
                        _ = await transport.confirm(QuickLogConfirm(requestId: draft.requestId, accept: false))
                    }
                    phase = .input
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityIdentifier("quicklog.cancel")

                Button {
                    phase = .committing(draft)
                    Task {
                        let saved = await transport.confirm(
                            QuickLogConfirm(requestId: draft.requestId, accept: true))
                        withAnimation(WatchTheme.Motion.settle) {
                            phase = saved ? .logged : .failed
                        }
                    }
                } label: {
                    if committing {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .tint(WatchTheme.run)
                .disabled(committing)
                .accessibilityIdentifier("quicklog.confirm")
            }
            .padding(.top, 2)
        }
    }

    /// The phone couldn't draft (unreachable / timed out / lookup failed): offer the honest
    /// offline park, never a made-up number.
    private func unreachableScreen(_ request: QuickLogRequest) -> some View {
        VStack(spacing: 8) {
            Text("iPhone not reachable")
                .font(.headline)
            Text("Save it to finish on your iPhone later?")
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Save for iPhone") {
                transport.queueOffline(request)
                withAnimation(WatchTheme.Motion.settle) { phase = .queuedOffline }
            }
            .tint(WatchTheme.recover)
            .accessibilityIdentifier("quicklog.queue")
            Button("Cancel") { phase = .input }
        }
    }

    private func statusScreen(spinner: Bool, title: String, subtitle: String?) -> some View {
        VStack(spacing: 8) {
            if spinner { ProgressView().tint(WatchTheme.recover) }
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func confirmationScreen(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(tint)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { onDone?() }
                .accessibilityIdentifier("quicklog.done")
        }
    }
}
