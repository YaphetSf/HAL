import AppKit
import SwiftUI

/// D21: the universal speller-rule editor. Rules live in local state until the single
/// top-right Apply & Restart button persists them (Settings.json + custom.yaml) and
/// restarts the input method to redeploy.
struct FuzzySettingsView: View {
    let scheme: CandidateColorScheme

    @State private var rules = SettingsStore.load().spellerRules
    @State private var phrases = SettingsStore.load().asciiPhrases
    @State private var newInput = ""
    @State private var newMatch = ""
    @State private var newPhrase = ""
    @State private var applyState = ApplyState.idle

    private enum ApplyState {
        case idle
        case applying
        case applied
        case failed
    }

    private var hasInvalidRule: Bool {
        rules.contains { !SpellerRule.isValid(input: $0.input, match: $0.match) }
    }

    private var newRuleIsValid: Bool {
        SpellerRule.isValid(input: newInput.trimmingCharacters(in: .whitespaces),
                            match: newMatch.trimmingCharacters(in: .whitespaces))
    }

    private var hasInvalidPhrase: Bool {
        phrases.contains { !RimeSpellerPatch.isValidAsciiPhrase($0) }
    }

    private var newPhraseIsValid: Bool {
        RimeSpellerPatch.isValidAsciiPhrase(newPhrase.trimmingCharacters(in: .whitespaces))
            && Array(newPhrase.trimmingCharacters(in: .whitespaces)).count > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    applyButton
                }
                rulesCard
                asciiCard
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    // MARK: Apply & Restart

    private var applyButton: some View {
        Button {
            apply()
        } label: {
            HStack(spacing: 8) {
                switch applyState {
                case .idle, .failed:
                    Image(systemName: applyState == .failed ? "exclamationmark.triangle" : "arrow.clockwise")
                case .applying:
                    ProgressView()
                        .controlSize(.small)
                case .applied:
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(applyState == .failed ? "Failed" : applyState == .applied ? "Applied" : "Apply & Restart")
            }
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(applyState == .applying || hasInvalidRule || hasInvalidPhrase)
        .opacity(applyState == .applying || hasInvalidRule || hasInvalidPhrase ? 0.45 : 1)
    }

    private func apply() {
        applyState = .applying
        RimeApplyRestart.apply {
            SettingsStore.saveSpellerRules(rules)
            SettingsStore.saveAsciiPhrases(phrases)
            RimeSpellerPatch.write(rules: rules, asciiPhrases: phrases,
                                   pageSize: SettingsStore.load().candidatePageSize,
                                   in: RimeSpellerPatch.userDirectory)
        } completion: { success in
            applyState = success ? .applied : .failed
            resetApplyState()
        }
    }

    private func resetApplyState() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if applyState != .applying { applyState = .idle }
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RULES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            if rules.isEmpty {
                Text("No rules")
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

    private func ruleRow(_ rule: Binding<SpellerRule>) -> some View {
        let valid = SpellerRule.isValid(input: rule.wrappedValue.input,
                                        match: rule.wrappedValue.match)
        return HStack(spacing: 14) {
            Toggle("", isOn: rule.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
            HStack(spacing: 10) {
                Text(rule.wrappedValue.input)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scheme.accentStart.color)
                Text(rule.wrappedValue.match)
            }
            .font(.system(.callout, design: .monospaced))
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
            ruleField("din", text: $newInput)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(scheme.accentStart.color)
            ruleField("ding", text: $newMatch)
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

    private func ruleField(_ placeholder: String, text: Binding<String>) -> some View {
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
        rules.append(SpellerRule(input: newInput.trimmingCharacters(in: .whitespaces),
                                 match: newMatch.trimmingCharacters(in: .whitespaces)))
        newInput = ""
        newMatch = ""
    }

    // MARK: ASCII passthrough (D23)

    private var asciiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ASCII PASS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            if phrases.isEmpty {
                Text("No phrases")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            ForEach(phrases, id: \.self) { phrase in
                HStack(spacing: 14) {
                    Text(phrase)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(RimeSpellerPatch.isValidAsciiPhrase(phrase)
                                         ? Color.white.opacity(0.88) : Color.red)
                    Spacer()
                    Button {
                        phrases.removeAll { $0 == phrase }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 10) {
                phraseField("e.g.", text: $newPhrase)
                Button {
                    let trimmed = newPhrase.trimmingCharacters(in: .whitespaces)
                    guard newPhraseIsValid, !phrases.contains(trimmed) else { return }
                    phrases.append(trimmed)
                    newPhrase = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(newPhraseIsValid ? scheme.accentStart.color : Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!newPhraseIsValid)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func phraseField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.callout, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.38)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .frame(width: 132)
            .onSubmit {
                let trimmed = newPhrase.trimmingCharacters(in: .whitespaces)
                guard newPhraseIsValid, !phrases.contains(trimmed) else { return }
                phrases.append(trimmed)
                newPhrase = ""
            }
    }
}
