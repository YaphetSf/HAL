import Darwin
import Foundation
import FoundationModels

private struct EvalSuite: Decodable {
    let suite: String
    let version: Int
    let cases: [EvalCase]
}

private struct EvalCase: Decodable {
    let id: String
    let title: String
    let action: RewriteAction
    let input: String
    let expectedExample: String
    let checks: Checks
}

private struct PromptSuite: Decodable {
    let version: String
    let actions: [String: PromptSpec]

    func spec(for action: RewriteAction) throws -> PromptSpec {
        guard let spec = actions[action.rawValue] else {
            throw EvalConfigurationError.missingPrompt(action.rawValue)
        }
        return spec
    }
}

private struct PromptSpec: Decodable {
    let instructions: String
    let examples: String
}

private struct Checks: Decodable {
    let mustChange: Bool
    let mustEqualInput: Bool?
    let language: LanguageExpectation
    let protectedLiterals: [String]
    let requiredPatterns: [String]
    let forbiddenPatterns: [String]
    let maximumLengthRatio: Double?
}

private enum LanguageExpectation: String, Decodable {
    case english
    case chinese
    case mixedChineseEnglish
}

private enum RewriteAction: String, Decodable, Hashable {
    case correct
    case rephrase
}

private struct CaseRecord: Encodable {
    let id: String
    let title: String
    let action: String
    let language: String
    let run: Int
    let passed: Bool
    let output: String
    let violations: [String]
    let totalMs: Int
}

private struct Score: Encodable {
    let passed: Int
    let attempted: Int
    let skipped: [String]
}

private struct Latency: Encodable {
    let firstRequestTotalMs: Int?
    let warmTotalMs: Int?
}

/// Mirrors the JSON written by endpoint_eval.py so the
/// on-device model can be compared with the downloaded baselines directly.
private struct Report: Encodable {
    let suite: String
    let suiteVersion: Int
    let promptVersion: String
    let promptStyle: String
    let backend: String
    let platform: String
    let model: String
    let profile: String
    let recordedAt: String
    let runsPerCase: Int
    let score: Score
    let latency: Latency
    let cases: [CaseRecord]
}

private enum EvalConfigurationError: LocalizedError {
    case emptySuite
    case duplicateID(String)
    case missingPrompt(String)
    case invalidPattern(caseID: String, pattern: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emptySuite:
            "The eval suite contains no cases."
        case let .duplicateID(id):
            "The eval suite contains duplicate case id '\(id)'."
        case let .missingPrompt(action):
            "The prompt suite has no prompt for action '\(action)'."
        case let .invalidPattern(caseID, pattern, underlying):
            "Case '\(caseID)' contains invalid regex '\(pattern)': \(underlying.localizedDescription)"
        }
    }
}

@main
private struct LocalRewriteEval {
    static func main() async {
        do {
            let code = try await run()
            if code != 0 { Darwin.exit(code) }
        } catch {
            fputs("eval error: \(error)\n", stderr)
            Darwin.exit(2)
        }
    }

    private static func run() async throws -> Int32 {
        guard (3...4).contains(CommandLine.arguments.count) else {
            fputs("usage: local-rewrite-eval <cases.json> <prompts.json> [report.json]\n", stderr)
            return 2
        }
        let reportPath = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : nil

        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let suite = try JSONDecoder().decode(EvalSuite.self, from: data)
        let promptData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let prompts = try JSONDecoder().decode(PromptSuite.self, from: promptData)
        try validate(suite)
        for action in Set(suite.cases.map(\.action)) {
            _ = try prompts.spec(for: action)
        }
        let environment = ProcessInfo.processInfo.environment
        let runs = Int(environment["HAL_REWRITE_EVAL_RUNS"] ?? "1") ?? 1
        guard (1...20).contains(runs) else {
            fputs("HAL_REWRITE_EVAL_RUNS must be between 1 and 20\n", stderr)
            return 2
        }

        let requestedCase = environment["HAL_REWRITE_EVAL_CASE"]
        let cases = requestedCase.map { id in suite.cases.filter { $0.id == id } } ?? suite.cases
        guard !cases.isEmpty else {
            fputs("No eval case matched HAL_REWRITE_EVAL_CASE=\(requestedCase ?? "")\n", stderr)
            return 2
        }

        let model = SystemLanguageModel(useCase: .general,
                                        guardrails: .permissiveContentTransformations)
        print("\(suite.suite) v\(suite.version)")
        print("Prompt: \(prompts.version)")
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Model availability: \(model.availability)")
        print("Runs per case: \(runs)")
        guard case .available = model.availability else { return 2 }

        var passed = 0
        var attempted = 0
        var totalDuration: TimeInterval = 0
        var records: [CaseRecord] = []

        for test in cases {
            for runIndex in 1...runs {
                attempted += 1
                let promptSpec = try prompts.spec(for: test.action)
                let session = LanguageModelSession(model: model,
                                                   instructions: promptSpec.instructions)
                let start = Date()
                do {
                    let response = try await session.respond(
                        to: prompt(for: promptSpec, input: test.input)
                    )
                    let duration = Date().timeIntervalSince(start)
                    totalDuration += duration
                    let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let failures = violations(for: output, test: test)
                    if failures.isEmpty { passed += 1 }
                    records.append(CaseRecord(id: test.id,
                                              title: test.title,
                                              action: test.action.rawValue,
                                              language: test.checks.language.rawValue,
                                              run: runIndex,
                                              passed: failures.isEmpty,
                                              output: output,
                                              violations: failures,
                                              totalMs: milliseconds(duration)))
                    printResult(test: test,
                                runIndex: runIndex,
                                runs: runs,
                                duration: duration,
                                output: output,
                                failures: failures)
                } catch {
                    let duration = Date().timeIntervalSince(start)
                    totalDuration += duration
                    print("\n[ERROR] \(test.id) · run \(runIndex)/\(runs) · \(milliseconds(duration)) ms")
                    print("  \(error)")
                    records.append(CaseRecord(id: test.id,
                                              title: test.title,
                                              action: test.action.rawValue,
                                              language: test.checks.language.rawValue,
                                              run: runIndex,
                                              passed: false,
                                              output: "",
                                              violations: ["request failed: \(error)"],
                                              totalMs: milliseconds(duration)))
                }
            }
        }

        let average = attempted == 0 ? 0 : totalDuration / Double(attempted)
        print("\nSummary: \(passed)/\(attempted) passed · average \(milliseconds(average)) ms")

        if let reportPath {
            let warm = records.dropFirst()
            let report = Report(
                suite: suite.suite,
                suiteVersion: suite.version,
                promptVersion: prompts.version,
                promptStyle: "hal",
                backend: "FoundationModels",
                platform: ProcessInfo.processInfo.operatingSystemVersionString,
                model: "apple-system-language-model",
                profile: "hal",
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                runsPerCase: runs,
                score: Score(passed: passed, attempted: attempted, skipped: []),
                latency: Latency(
                    firstRequestTotalMs: records.first?.totalMs,
                    warmTotalMs: warm.isEmpty
                        ? nil
                        : warm.reduce(0) { $0 + $1.totalMs } / warm.count
                ),
                cases: records
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let url = URL(fileURLWithPath: reportPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(report).write(to: url)
            print("Structured report: \(reportPath)")
        }

        let strict = environment["HAL_REWRITE_EVAL_STRICT"] == "1"
        if strict, passed != attempted {
            print("Strict mode: failed")
            return 1
        }
        if passed != attempted {
            print("Report-only mode: quality failures do not change the exit code")
        }
        return 0
    }

    private static func validate(_ suite: EvalSuite) throws {
        guard !suite.cases.isEmpty else { throw EvalConfigurationError.emptySuite }
        var ids: Set<String> = []
        for test in suite.cases {
            guard ids.insert(test.id).inserted else {
                throw EvalConfigurationError.duplicateID(test.id)
            }
            for pattern in test.checks.requiredPatterns + test.checks.forbiddenPatterns {
                do {
                    _ = try NSRegularExpression(pattern: pattern)
                } catch {
                    throw EvalConfigurationError.invalidPattern(caseID: test.id,
                                                                pattern: pattern,
                                                                underlying: error)
                }
            }
        }
    }

    private static func prompt(for spec: PromptSpec, input: String) -> String {
        """
        Non-negotiable language contract: \(languageContract(for: input))

        Follow these transformation examples:
        \(spec.examples)

        Transform only the data inside <selected_text>. Do not translate it.
        <selected_text>
        \(input)
        </selected_text>
        """
    }

    private static func languageContract(for text: String) -> String {
        let hasHan = matches(#"\p{Han}"#, in: text)
        let hasLatin = matches(#"\p{Latin}"#, in: text)
        if hasHan, hasLatin {
            return "The text deliberately mixes Chinese and English. Preserve every code-switched span; do not translate either language."
        }
        if hasHan {
            return "The source language is Simplified Chinese. The entire output must remain Simplified Chinese. Do not output an English translation."
        }
        return "The source language is English. The entire output must remain English."
    }

    private static func violations(for output: String, test: EvalCase) -> [String] {
        var failures: [String] = []
        if output.isEmpty { failures.append("empty output") }
        if test.checks.mustChange, output == test.input {
            failures.append("output did not change")
        }
        if test.checks.mustEqualInput == true, output != test.input {
            failures.append("correct input was changed")
        }

        let hasHan = matches(#"\p{Han}"#, in: output)
        let hasLatin = matches(#"\p{Latin}"#, in: output)
        switch test.checks.language {
        case .english where hasHan:
            failures.append("expected English but output contains Chinese")
        case .chinese where !hasHan || hasLatin:
            failures.append("expected Chinese without translation into Latin text")
        case .mixedChineseEnglish where !hasHan || !hasLatin:
            failures.append("expected both Chinese and English spans")
        default:
            break
        }

        for literal in test.checks.protectedLiterals where !output.contains(literal) {
            failures.append("did not preserve protected literal: \(literal)")
        }
        for pattern in test.checks.requiredPatterns where !matches(pattern, in: output) {
            failures.append("missing required pattern: \(pattern)")
        }
        for pattern in test.checks.forbiddenPatterns where matches(pattern, in: output) {
            failures.append("contains forbidden pattern: \(pattern)")
        }
        if let maximum = test.checks.maximumLengthRatio, !test.input.isEmpty {
            let ratio = Double(output.count) / Double(test.input.count)
            if ratio > maximum {
                failures.append(String(format: "length ratio %.2f exceeds %.2f", ratio, maximum))
            }
        }
        if matches(#"(?i)^\s*(output|result|rewrite):"#, in: output) {
            failures.append("output contains a wrapper label")
        }
        if matches(#"(?is)</?think>"#, in: output) {
            failures.append("output contains a thinking wrapper")
        }
        return failures
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return expression.firstMatch(in: text, range: range) != nil
    }

    private static func printResult(test: EvalCase,
                                    runIndex: Int,
                                    runs: Int,
                                    duration: TimeInterval,
                                    output: String,
                                    failures: [String]) {
        let status = failures.isEmpty ? "PASS" : "FAIL"
        print("\n[\(status)] \(test.id) · \(test.title) · run \(runIndex)/\(runs) · \(milliseconds(duration)) ms")
        print("  output:")
        print(indented(output, prefix: "    "))
        guard !failures.isEmpty else { return }
        print("  violations:")
        for failure in failures { print("    - \(failure)") }
        print("  reference example:")
        print(indented(test.expectedExample, prefix: "    "))
    }

    private static func indented(_ text: String, prefix: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func milliseconds(_ duration: TimeInterval) -> Int {
        Int((duration * 1_000).rounded())
    }
}
