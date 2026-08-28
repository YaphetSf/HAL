/// One page of what the engine currently thinks. Produced by an `InputEngine`, consumed by
/// the renderer; nothing else crosses that boundary (PLAN.md §2.1).
struct EngineState: Equatable {
    struct Page: Equatable {
        var index: Int
        var hasPrev: Bool
        var hasNext: Bool

        static let none = Page(index: 0, hasPrev: false, hasNext: false)
    }

    /// nil when nothing is being composed.
    var composition: Composition?
    var candidates: [Candidate]
    var highlightedIndex: Int
    var page: Page
    /// Non-nil when this key produced text the client must insert.
    var commitText: String?

    static let idle = EngineState(composition: nil, candidates: [], highlightedIndex: 0,
                                  page: .none, commitText: nil)
}

struct Composition: Equatable {
    /// The text shown to the user while composing, e.g. "ni hao".
    var text: String
    /// Cursor position as an offset in `text`'s characters.
    var cursor: Int
}

struct Candidate: Equatable {
    var text: String
    var comment: String?
}
