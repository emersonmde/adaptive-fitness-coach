import SwiftUI
import AdaptiveCore

/// Wraps a `CoachIntent` so an entry point can drive a `.sheet(item:)`.
struct CoachLaunch: Identifiable {
    let id = UUID()
    let intent: CoachIntent
}

/// The coach conversation sheet (P3). Not a chatbot tab: opened for one job (build a plan /
/// rework routines), it walks a short trainer intake and ends in a proposal the user reviews
/// through the same `ImportRoutinesSheet` path as a manual Claude import — the coach never
/// writes to the store silently.
///
/// Design (per DESIGN-PRINCIPLES): the dominant element is the coach's *current* message,
/// rendered large; history recedes above it in secondary text. The streaming reply lives in the
/// same slot the finished message will occupy, so nothing jumps mid-stream. Failed turns render
/// with a Retry — a wedged conversation always has an exit.
struct CoachChatView: View {
    let store: RoutineStore
    let intent: CoachIntent

    @Environment(\.dismiss) private var dismiss

    @State private var conversation: CoachConversation?
    @State private var unavailableReason: String?
    @State private var input = ""
    @State private var pendingImport: ImportCandidate?
    /// Honest post-apply status ("Updated 1, added 2"), shown quietly under the proposal.
    @State private var applyResult: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let reason = unavailableReason {
                    unavailableState(reason)
                } else {
                    chat
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("coachDone")
                }
            }
            .sheet(item: $pendingImport) { candidate in
                ImportRoutinesSheet(candidate: candidate,
                                    existingNames: Set(store.routines.map(\.name))) { incoming in
                    let result = store.importRoutines(incoming)
                    Task { await CalendarService.shared.syncAll(store.routines) }
                    applyResult = "Applied — updated \(result.updated), added \(result.added)."
                }
            }
        }
        .task { start() }
        .onDisappear { conversation?.cancel() }
    }

    private var title: String {
        switch intent {
        case .buildNewPlan: "Build a Plan"
        case .reviseRoutine: "Rework Routine"
        case .reviseAll: "Rework My Week"
        }
    }

    /// The sheet opens with a deterministic, app-authored first question (the model replies
    /// from the user's answer on) — the coach speaks first without a fabricated model turn.
    private var greeting: String {
        switch intent {
        case .buildNewPlan:
            return "Let's build your week. First — what equipment do you have access to?"
        case .reviseRoutine:
            let name = store.routines.first { $0.id == focusRoutineID }?.name ?? "this routine"
            return "What's changed since you built \(name)? New equipment, more experience, less time?"
        case .reviseAll:
            return "What do you want out of this review — balance, progression, a new goal?"
        }
    }

    private var focusRoutineID: Routine.ID? {
        if case let .reviseRoutine(id) = intent { return id }
        return nil
    }

    /// Quick one-tap answers to the greeting, shown until the user has said something.
    private var suggestionChips: [String] {
        switch intent {
        case .buildNewPlan:
            ["Dumbbells and a bench", "Just bodyweight at home", "A full gym"]
        case .reviseRoutine:
            ["I've gotten stronger", "I have less time now", "Something's bugging me"]
        case .reviseAll:
            ["Check my balance", "Push progression", "New goal"]
        }
    }

    // MARK: - Chat

    private func start() {
        guard conversation == nil, unavailableReason == nil else { return }
        let engine = CoachEngineProvider.makeEngine()
        if case let .unavailable(reason) = engine.availability {
            unavailableReason = reason
            return
        }
        do {
            conversation = try CoachConversation(
                engine: engine,
                intent: intent,
                context: CoachContextBuilder.context(for: intent, routines: store.routines)
            )
        } catch {
            unavailableReason = "The coach couldn't start. \(error.localizedDescription)"
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        coachBubble(greeting, isCurrent: currentCoachEntryID == nil)

                        if let conversation {
                            ForEach(conversation.transcript) { entry in
                                entryView(entry, conversation: conversation)
                                    .id(entry.id)
                            }
                            // The in-flight reply streams into the slot the finished message
                            // will occupy — same style, no reflow when it folds (principle 7).
                            if conversation.isResponding {
                                coachBubble(
                                    conversation.streamingText.isEmpty ? "…" : conversation.streamingText,
                                    isCurrent: true
                                )
                                .id("streaming")
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: conversation?.transcript.count ?? 0) {
                    if let last = conversation?.transcript.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: conversation?.streamingText ?? "") {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            inputBar
        }
    }

    @ViewBuilder
    private func entryView(_ entry: CoachConversation.Entry, conversation: CoachConversation) -> some View {
        switch entry.kind {
        case let .user(text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case let .coach(text):
            coachBubble(text, isCurrent: entry.id == currentCoachEntryID)
        case let .proposal(proposal):
            proposalCard(proposal)
        case let .failure(message, _):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Retry") { conversation.retry(entry) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("coachRetry")
            }
            .padding(14)
            .background(Theme.hot.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// The latest coach message is the screen's dominant element; earlier ones recede.
    private func coachBubble(_ text: String, isCurrent: Bool) -> some View {
        Text(text)
            .font(isCurrent ? .title3.weight(.medium) : .subheadline)
            .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(nil, value: isCurrent)
    }

    /// The id of the transcript's last coach prose entry — the one rendered dominant. While a
    /// reply streams, the streaming slot is dominant instead.
    private var currentCoachEntryID: UUID? {
        guard let conversation, !conversation.isResponding else { return nil }
        return conversation.transcript.last {
            if case .coach = $0.kind { true } else { false }
        }?.id
    }

    // MARK: - Proposal

    private func proposalCard(_ proposal: CoachProposal) -> some View {
        let existingNames = Set(store.routines.map(\.name))
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(proposal.routines) { routine in
                HStack(spacing: 10) {
                    Image(systemName: routine.type == .strength ? "dumbbell.fill" : "figure.run")
                        .font(.caption)
                        .foregroundStyle(routine.type == .strength ? Theme.strength : Theme.run)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(routineSummary(routine))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(existingNames.contains(routine.name) ? "UPDATES" : "NEW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(existingNames.contains(routine.name) ? Theme.recover : Theme.accent)
                }
            }

            if proposal.droppedCardCount > 0 {
                // Honesty line (N6): validation removed movements the app can't coach yet.
                Text("\(proposal.droppedCardCount) movement\(proposal.droppedCardCount == 1 ? " was" : "s were") left out — the app can't coach them yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            if let applyResult {
                Text(applyResult)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            } else {
                Button {
                    pendingImport = ImportCandidate(routines: proposal.routines)
                } label: {
                    Text("Review & apply")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coachProposalReview")
            }
        }
        .padding(14)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func routineSummary(_ routine: Routine) -> String {
        var parts: [String] = ["~\(routine.estimatedMinutes) min"]
        if !routine.repeatDays.isEmpty {
            parts.append(routine.repeatDays.sorted().map(\.shortName).joined(separator: " "))
        }
        let exercises = routine.exerciseItems.count
        if exercises > 0 { parts.append("\(exercises) exercise\(exercises == 1 ? "" : "s")") }
        if routine.hasRun { parts.append("adaptive run") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let conversation {
                if conversation.transcript.isEmpty {
                    // One-tap answers to the greeting; gone after the first message.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestionChips, id: \.self) { chip in
                                Button(chip) { conversation.send(chip) }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Theme.surface2, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.hairline))
                            }
                        }
                    }
                } else if conversation.latestProposal == nil, !conversation.isResponding {
                    // Quiet skip-ahead for users done talking (the model normally decides).
                    Button("Draft the plan now") {
                        conversation.send("Draft the plan now with what you know so far.")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityIdentifier("coachDraftNow")
                }
            }

            HStack(spacing: 10) {
                TextField("Answer the coach…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("coachInput")

                Button {
                    conversation?.send(input)
                    input = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityIdentifier("coachSend")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        guard let conversation else { return false }
        return !conversation.isResponding
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Degradation

    /// The model isn't available: say why, and point at the manual loop — never a dead end.
    private func unavailableState(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("Coach unavailable")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityIdentifier("coachUnavailable")
    }
}
