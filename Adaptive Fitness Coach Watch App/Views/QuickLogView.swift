import SwiftUI
import AdaptiveCore

/// P6 watch quick-log (B-series sibling): dictate → durably parked for the iPhone → one
/// glanceable confirmation. Always-pending by design: the live draft round trip was removed
/// after real-world use showed the phone (locked, backgrounded) can't run the lookup ladder
/// inside WCSession's reply deadline — the wrist now never waits on a lookup, never invents
/// a number (N6), and `transferUserInfo` guarantees the text reaches the phone's review queue.
struct QuickLogView: View {
    /// Parks the request in the guaranteed-delivery queue — production binds
    /// `WatchConnectivityManager.queueQuickLogOffline`; the `-simulateQuickLog` demo passes
    /// a no-op (paired-sim WC is unreliable; the sim path is the only hardware-free look).
    let queueOffline: (QuickLogRequest) -> Void
    var onDone: (() -> Void)?

    private enum Phase: Equatable {
        case input
        case saved
    }

    @State private var text: String
    @State private var phase: Phase = .input

    /// `initialText` pre-fills the field for the `-simulateQuickLog` demo — watchOS exposes
    /// no automatable path into the dictation/scribble sheet, so typing is the one step a
    /// test can't synthesize. Production passes nothing.
    init(queueOffline: @escaping (QuickLogRequest) -> Void,
         initialText: String = "",
         onDone: (() -> Void)? = nil) {
        self.queueOffline = queueOffline
        self.onDone = onDone
        _text = State(initialValue: initialText)
    }

    var body: some View {
        switch phase {
        case .input:
            inputScreen
        case .saved:
            savedScreen
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
                queueOffline(QuickLogRequest(text: trimmed))
                withAnimation(WatchTheme.Motion.settle) { phase = .saved }
            } label: {
                Label("Log it", systemImage: "arrow.up.circle.fill")
            }
            .tint(WatchTheme.recover)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("quicklog.send")
        }
        .navigationTitle("Log a meal")
    }

    private var savedScreen: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 30))
                .foregroundStyle(WatchTheme.recover)
            Text("Saved for iPhone")
                .font(.headline)
            // The user is the actor — nothing lands in Health until THEY review it there
            // (passive "it'll be looked up" over-promised automation).
            Text("Review it on your iPhone to finish logging.")
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") {
                if let onDone {
                    onDone()   // sheet context: dismiss
                } else {
                    // Standalone (`-simulateQuickLog` demo): reset so the flow can repeat.
                    text = ""
                    phase = .input
                }
            }
            .accessibilityIdentifier("quicklog.done")
        }
    }
}
