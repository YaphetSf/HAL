import Foundation

/// Where one displayed candidate comes from: a position in the page librime produced, or
/// text only HAL knows about — a weight rule whose target librime cannot produce at all (D25).
enum CandidateSlot: Equatable {
    case engine(Int)
    case literal(Candidate)
}

/// One step of candidate post-processing (M8). The pipeline is the single ranking entry
/// for every source of candidates — Chinese pages today, EN+ suggestions when they grow
/// a ranking need.
protocol CandidateProcessor {
    /// Takes the display list the previous step produced and returns the next one.
    func arrange(_ slots: [CandidateSlot], of candidates: [Candidate], input: String,
                 page: EngineState.Page) -> [CandidateSlot]
}

extension CandidateSlot {
    func text(in candidates: [Candidate]) -> String {
        switch self {
        case .engine(let index): return candidates[index].text
        case .literal(let candidate): return candidate.text
        }
    }
}

/// The words the user removed with Shift+⌫ (D29) never reach the page. A page made only of
/// removed words stays as it is: an empty row would leave space nothing to commit.
struct RemovedWordsProcessor: CandidateProcessor {
    let words: Set<String>

    func arrange(_ slots: [CandidateSlot], of candidates: [Candidate], input: String,
                 page: EngineState.Page) -> [CandidateSlot] {
        let kept = slots.filter { !words.contains($0.text(in: candidates)) }
        return kept.isEmpty ? slots : kept
    }
}

/// The user's manual weights (M8, D25): when the composed input matches a rule exactly, its
/// candidate moves to the front of the current page — and when no dictionary librime reads
/// contains that candidate, HAL puts the rule's own text in front instead.
struct WeightTableProcessor: CandidateProcessor {
    let rules: [WeightRule]

    func arrange(_ slots: [CandidateSlot], of candidates: [Candidate], input: String,
                 page: EngineState.Page) -> [CandidateSlot] {
        let normalized = input.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty,
              let rule = rules.first(where: { $0.input.lowercased() == normalized })
        else { return slots }

        guard let position = slots.firstIndex(where: { $0.text(in: candidates) == rule.candidate }) else {
            // The word is in no dictionary librime is reading, so there is nothing to move
            // and HAL supplies it. Only on the first page: one rule stays one candidate.
            guard page.index == 0 else { return slots }
            return [.literal(Candidate(text: rule.candidate, comment: nil))] + slots
        }
        var arranged = slots
        arranged.insert(arranged.remove(at: position), at: 0)
        return arranged
    }
}

struct CandidatePipeline {
    let processors: [CandidateProcessor]

    /// nil when no step changed librime's own page.
    func arrange(candidates: [Candidate], input: String, page: EngineState.Page) -> [CandidateSlot]? {
        let original = candidates.indices.map(CandidateSlot.engine)
        let slots = processors.reduce(original) { slots, processor in
            processor.arrange(slots, of: candidates, input: input, page: page)
        }
        return slots == original ? nil : slots
    }
}
