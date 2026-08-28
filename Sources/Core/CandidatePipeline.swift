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
    /// Returns the display list, one slot per display position. Identity (nil) means
    /// "leave the page alone".
    func arrange(candidates: [Candidate], input: String, page: EngineState.Page) -> [CandidateSlot]?
}

/// The user's manual weights (M8, D25): when the composed input matches a rule exactly, its
/// candidate moves to the front of the current page — and when no dictionary librime reads
/// contains that candidate, HAL puts the rule's own text in front instead.
struct WeightTableProcessor: CandidateProcessor {
    let rules: [WeightRule]

    func arrange(candidates: [Candidate], input: String, page: EngineState.Page) -> [CandidateSlot]? {
        let normalized = input.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty,
              let rule = rules.first(where: { $0.input.lowercased() == normalized })
        else { return nil }

        let engineSlots = candidates.indices.map { CandidateSlot.engine($0) }
        guard let engineIndex = candidates.firstIndex(where: { $0.text == rule.candidate }) else {
            // The word is in no dictionary librime is reading, so there is nothing to move
            // and HAL supplies it. Only on the first page: one rule stays one candidate.
            guard page.index == 0 else { return nil }
            return [.literal(Candidate(text: rule.candidate, comment: nil))] + engineSlots
        }
        guard engineIndex > 0 else { return nil }
        var slots = engineSlots
        slots.remove(at: engineIndex)
        slots.insert(.engine(engineIndex), at: 0)
        return slots
    }
}

struct CandidatePipeline {
    let processors: [CandidateProcessor]

    func arrange(candidates: [Candidate], input: String, page: EngineState.Page) -> [CandidateSlot]? {
        for processor in processors {
            if let slots = processor.arrange(candidates: candidates, input: input, page: page) {
                return slots
            }
        }
        return nil
    }
}
