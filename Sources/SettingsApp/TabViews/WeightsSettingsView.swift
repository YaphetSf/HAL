import SwiftUI

/// M8: manual weights. Editing a row saves immediately — the input method re-reads
/// Settings.json on every keystroke, so a new weight applies to the next composition
/// without restarting anything.
struct WeightsSettingsView: View {
    let scheme: CandidateColorScheme

    @State private var rules = SettingsStore.load().weightedCandidates
    @State private var newInput = ""
    @State private var newCandidate = ""

    private var hasInvalidRule: Bool {
        rules.contains { !WeightRule.isValid(input: $0.input, candidate: $0.candidate) }
    }

    private var newRuleIsValid: Bool {
        WeightRule.isValid(input: newInput.trimmingCharacters(in: .whitespaces),
                           candidate: newCandidate.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                weightsCard
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onChange(of: rules) { _, newRules in
            guard !hasInvalidRule else { return }
            SettingsStore.saveWeightedCandidates(newRules)
        }
    }

    private var weightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WEIGHTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            if rules.isEmpty {
                Text("No weights")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            ForEach($rules) { $rule in
                ruleRow($rule)
            }
            addRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func ruleRow(_ rule: Binding<WeightRule>) -> some View {
        let valid = WeightRule.isValid(input: rule.wrappedValue.input,
                                       candidate: rule.wrappedValue.candidate)
        return HStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(rule.wrappedValue.input)
                    .font(.system(.callout, design: .monospaced))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scheme.accentStart.color)
                Text(rule.wrappedValue.candidate)
            }
            .foregroundStyle(valid ? Color.white.opacity(0.88) : Color.red)
            Spacer()
            Button {
                rules.removeAll { $0.id == rule.wrappedValue.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            field("cizu", text: $newInput)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(scheme.accentStart.color)
            field("词组", text: $newCandidate)
            Button {
                addRuleFromFields()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(newRuleIsValid ? scheme.accentStart.color : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!newRuleIsValid)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.callout, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.38)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .frame(width: 132)
            .onSubmit(addRuleFromFields)
    }

    private func addRuleFromFields() {
        guard newRuleIsValid else { return }
        rules.append(WeightRule(input: newInput.trimmingCharacters(in: .whitespaces),
                                candidate: newCandidate.trimmingCharacters(in: .whitespaces)))
        newInput = ""
        newCandidate = ""
    }
}
