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
public struct QuestionAnswer: Sendable, Hashable, Codable {
    public var questionID: String
    public var optionID: String

    public init(questionID: String, optionID: String) {
        self.questionID = questionID
        self.optionID = optionID
    }
}
