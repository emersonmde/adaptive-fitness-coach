import SwiftUI
import AdaptiveCore

/// A1 — pre-session. Shows only the next scheduled run and a single Start. No library, no
/// parameters to confirm. Start begins a real workout immediately.
struct LaunchView: View {
    let routine: Routine?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let routine {
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("UP NEXT")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(routine.name)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text("Run / Walk · adaptive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onStart) {
                    Text("Start")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No session scheduled")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Create a routine on your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
    }
}
