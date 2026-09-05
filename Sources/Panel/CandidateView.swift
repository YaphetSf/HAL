import AppKit
import SwiftUI

/// One horizontal row of candidates. Reworked per user request (PLAN.md M5, pulled
/// forward from M6): sliding gradient highlight with spring motion + glow, entrance
/// pop when the panel goes from hidden to visible. The colors come from a
/// `CandidateColorScheme` (D21) — user-picked, not idle/continuous animation, to
/// keep this cheap while composing.
struct CandidateView: View {
    let candidates: [Candidate]
    let highlightedIndex: Int
    let page: EngineState.Page
    /// True only on the show() call that takes the panel from hidden to visible;
    /// drives the entrance pop so retyping/paging doesn't replay it every keystroke.
    var justAppeared: Bool = false
    var scheme: CandidateColorScheme = .aurora
    /// Hard cap on the row width (D21). When set, a candidate longer than the remaining
    /// room is ellipsized instead of stretching the row off screen; nil keeps the old
    /// unlimited "fit everything" behavior.
    var maxWidth: CGFloat? = nil

    @Namespace private var highlight
    @State private var appear: CGFloat = 0

    private var accent: LinearGradient {
        LinearGradient(colors: [scheme.accentStart.color, scheme.accentEnd.color],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var glow: Color { scheme.glow.color }

    var body: some View {
        let capped = maxWidth != nil
        return HStack(spacing: 4) {
            arrow("chevron.left", visible: page.hasPrev)
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                // Descending priority: when the cap leaves the page short of room, the
                // candidates most likely to be picked keep their text and the tail
                // ellipsizes, instead of every candidate losing an equal slice.
                item(index: index, candidate: candidate)
                    .layoutPriority(Double(candidates.count - index))
            }
            arrow("chevron.right", visible: page.hasNext)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // The cap binds the row inside the window, not the window itself, so an overlong
        // page ellipsizes within a whole rounded panel instead of one sliced off at the cap.
        .frame(maxWidth: maxWidth.map { $0 - 20 }, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.55), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(10)
        .shadow(color: glow.opacity(0.35), radius: 10, y: 2)
        // Capped: flex up to maxWidth and let overlong candidates ellipsize. Uncapped:
        // the old fixed natural size, everything always visible.
        .fixedSize(horizontal: !capped, vertical: true)
        .scaleEffect(0.85 + 0.15 * appear)
        .opacity(appear)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: highlightedIndex)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: page.index)
        .onChange(of: justAppeared, initial: true) { _, isFresh in
            guard isFresh else { return }
            appear = 0
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) { appear = 1 }
        }
    }

    private func item(index: Int, candidate: Candidate) -> some View {
        let isHighlighted = index == highlightedIndex
        return HStack(spacing: 3) {
            // Selection keys are 1-9 then 0, matching what librime accepts.
            Text("\((index + 1) % 10)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isHighlighted ? .white.opacity(0.85) : .secondary)
                .fixedSize()
                .layoutPriority(1)
            Text(candidate.text)
                .font(.system(size: 16, weight: isHighlighted ? .semibold : .regular))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent)
                    .shadow(color: glow.opacity(0.6), radius: 6)
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            }
        }
        .scaleEffect(isHighlighted ? 1.06 : 1.0)
    }

    private func arrow(_ name: String, visible: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(visible ? AnyShapeStyle(accent) : AnyShapeStyle(.clear))
            .opacity(visible ? 1 : 0)
            .frame(width: visible ? nil : 0)
            .layoutPriority(Double(candidates.count + 1))
    }
}

/// EN+ is intentionally quieter than the Chinese chooser: one completion, no selection
/// number, and a small reminder that accepting it is optional (D22).
struct EnglishCompletionView: View {
    let prefix: String
    let suggestions: [String]
    let highlightedIndex: Int
    var justAppeared: Bool = false
    var scheme: CandidateColorScheme = .aurora

    @State private var appear: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                EnglishSuggestionItem(prefix: prefix,
                                      suggestion: suggestion,
                                      isHighlighted: index == highlightedIndex,
                                      scheme: scheme)
            }

            Text("← →  Tab")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(scheme.accentEnd.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .font(.system(size: 15, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(scheme.accentStart.color.opacity(0.32), lineWidth: 1)
                }
        )
        .padding(8)
        .shadow(color: scheme.glow.color.opacity(0.18), radius: 7, y: 2)
        .fixedSize()
        .scaleEffect(0.94 + 0.06 * appear)
        .opacity(appear)
        .animation(.snappy(duration: 0.16), value: highlightedIndex)
        .onChange(of: justAppeared, initial: true) { _, isFresh in
            guard isFresh else {
                appear = 1
                return
            }
            appear = 0
            withAnimation(.snappy(duration: 0.2)) { appear = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("English suggestions: \(suggestions.joined(separator: ", ")). Use left and right arrows, then press Tab to accept.")
    }
}

private struct EnglishSuggestionItem: View {
    let prefix: String
    let suggestion: String
    let isHighlighted: Bool
    let scheme: CandidateColorScheme

    private var suffix: String {
        let split = suggestion.index(suggestion.startIndex,
                                     offsetBy: prefix.count,
                                     limitedBy: suggestion.endIndex) ?? suggestion.endIndex
        return String(suggestion[split...])
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(isHighlighted ? .white.opacity(0.7) : .secondary)
            Text(suffix)
                .foregroundStyle(isHighlighted ? .white : .primary)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [scheme.accentStart.color,
                                                  scheme.accentEnd.color],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            }
        }
    }
}

extension RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
