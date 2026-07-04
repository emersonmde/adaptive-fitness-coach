import Foundation

/// C4 — structured clarification, never chat. When a lookup or estimate needs input that
/// *materially* changes the number ("Half or whole?", "With dressing?"), the pipeline emits
/// one of these and the UI renders tappable option chips — the Claude Code option-picker
/// spirit, as native SwiftUI. The user answers by tapping, never typing.
public struct ClarifyingQuestion: Identifiable, Sendable, Hashable, Codable {
    public struct Option: Identifiable, Sendable, Hashable, Codable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public var id: String
    /// One line, e.g. "How much of it?" — never a paragraph.
    public var prompt: String
    /// 2–4 options. Enforced softly here (the pipeline's DTO guides constrain generation);
    /// the UI lays out whatever arrives.
    public var options: [Option]
    /// Skippable by construction (C1): when the user never touches the chips, the controller
    /// answers with this default — a question is a refinement, never a gate.
    public var defaultOptionID: String

    public init(id: String, prompt: String, options: [Option], defaultOptionID: String) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.defaultOptionID = defaultOptionID
    }

    public var defaultOption: Option? {
        options.first { $0.id == defaultOptionID } ?? options.first
    }
}

/// A tapped (or defaulted) answer, fed to the stage-4 lookup for the owning item.
///
/// Carries the human-readable text alongside the IDs: the answer outlives its question (the
/// pending queue persists answers but not questions), and the lookup prompts render the text
/// — "How many eggs? 3" means something to the model where "item0=item0-opt2" does not.
/// Both fields are optional purely for Codable evolution (pre-build-13 queue rows).
public struct QuestionAnswer: Sendable, Hashable, Codable {
    public var questionID: String
    public var optionID: String
    public var questionPrompt: String?
    public var optionLabel: String?

    public init(questionID: String, optionID: String, questionPrompt: String? = nil, optionLabel: String? = nil) {
        self.questionID = questionID
        self.optionID = optionID
        self.questionPrompt = questionPrompt
        self.optionLabel = optionLabel
    }

    /// The convenience most call sites want: answer a question with one of its own options.
    public init(question: ClarifyingQuestion, option: ClarifyingQuestion.Option) {
        self.init(
            questionID: question.id,
            optionID: option.id,
            questionPrompt: question.prompt,
            optionLabel: option.label
        )
    }

    /// What the model reads. Falls back to the IDs only for legacy rows with no text.
    public var promptDescription: String {
        if let questionPrompt, let optionLabel {
            return "\(questionPrompt) \(optionLabel)"
        }
        return "\(questionID)=\(optionID)"
    }
}
