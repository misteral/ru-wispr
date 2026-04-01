import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
public struct FoundationModelBenchmarkEnvironment: Sendable {
    public let availabilityDescription: String
    public let supportedLanguageIdentifiers: [String]
    public let requestedLocaleIdentifier: String?
    public let requestedLocaleSupported: Bool?

    public init(
        availabilityDescription: String,
        supportedLanguageIdentifiers: [String],
        requestedLocaleIdentifier: String?,
        requestedLocaleSupported: Bool?
    ) {
        self.availabilityDescription = availabilityDescription
        self.supportedLanguageIdentifiers = supportedLanguageIdentifiers
        self.requestedLocaleIdentifier = requestedLocaleIdentifier
        self.requestedLocaleSupported = requestedLocaleSupported
    }
}

@available(macOS 26.0, *)
public struct FoundationModelBenchmarkMeasurement: Sendable {
    public let output: String
    public let timeToFirstTokenSeconds: Double?
    public let totalDurationSeconds: Double

    public init(output: String, timeToFirstTokenSeconds: Double?, totalDurationSeconds: Double) {
        self.output = output
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.totalDurationSeconds = totalDurationSeconds
    }
}

@available(macOS 26.0, *)
public struct FoundationModelBenchmarkCaseResult: Sendable {
    public let benchmarkCase: FoundationModelBenchmarkCase
    public let runIndex: Int
    public let output: String
    public let timeToFirstTokenSeconds: Double?
    public let totalDurationSeconds: Double
    public let exactMatch: Bool?
    public let similarity: Double?

    public init(
        benchmarkCase: FoundationModelBenchmarkCase,
        runIndex: Int,
        output: String,
        timeToFirstTokenSeconds: Double?,
        totalDurationSeconds: Double,
        exactMatch: Bool?,
        similarity: Double?
    ) {
        self.benchmarkCase = benchmarkCase
        self.runIndex = runIndex
        self.output = output
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.totalDurationSeconds = totalDurationSeconds
        self.exactMatch = exactMatch
        self.similarity = similarity
    }
}

@available(macOS 26.0, *)
public struct FoundationModelBenchmarkReport: Sendable {
    public let environment: FoundationModelBenchmarkEnvironment
    public let results: [FoundationModelBenchmarkCaseResult]

    public init(environment: FoundationModelBenchmarkEnvironment, results: [FoundationModelBenchmarkCaseResult]) {
        self.environment = environment
        self.results = results
    }

    public var averageTimeToFirstTokenSeconds: Double? {
        let values = results.compactMap(\.timeToFirstTokenSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public var averageTotalDurationSeconds: Double {
        guard !results.isEmpty else { return 0 }
        return results.map(\.totalDurationSeconds).reduce(0, +) / Double(results.count)
    }

    public var exactMatches: Int {
        results.compactMap(\.exactMatch).filter { $0 }.count
    }

    public var scoredResults: Int {
        results.compactMap(\.exactMatch).count
    }

    public var averageSimilarity: Double? {
        let values = results.compactMap(\.similarity)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

@available(macOS 26.0, *)
public enum FoundationModelBenchmarkRunner {
    public static func environment(localeIdentifier: String?) -> FoundationModelBenchmarkEnvironment {
        let model = configuredModel()
        let requestedLocaleSupported = localeIdentifier.map { model.supportsLocale(Locale(identifier: $0)) }
        return FoundationModelBenchmarkEnvironment(
            availabilityDescription: describeAvailability(model.availability),
            supportedLanguageIdentifiers: model.supportedLanguages.map(\.maximalIdentifier).sorted(),
            requestedLocaleIdentifier: localeIdentifier,
            requestedLocaleSupported: requestedLocaleSupported
        )
    }

    public static func run(options: FoundationModelBenchmarkOptions) async throws -> FoundationModelBenchmarkReport {
        let cases = try options.benchmarkCases()
        let environment = environment(localeIdentifier: options.localeIdentifier)
        let model = configuredModel()

        guard model.isAvailable else {
            throw FoundationModelBenchmarkRunnerError.modelUnavailable(environment.availabilityDescription)
        }

        let session = LanguageModelSession(model: model, instructions: correctionInstructions)
        if options.prewarm {
            session.prewarm()
        }

        var results: [FoundationModelBenchmarkCaseResult] = []

        for runIndex in 1...options.runs {
            for benchmarkCase in cases {
                let measurement = try await measureResponse(
                    session: session,
                    input: benchmarkCase.input,
                    maxResponseTokens: options.maxResponseTokens
                )

                let exactMatch = benchmarkCase.expected.map {
                    FoundationModelBenchmarkQuality.exactMatch(expected: $0, actual: measurement.output)
                }
                let similarity = benchmarkCase.expected.map {
                    FoundationModelBenchmarkQuality.similarity(expected: $0, actual: measurement.output)
                }

                results.append(
                    FoundationModelBenchmarkCaseResult(
                        benchmarkCase: benchmarkCase,
                        runIndex: runIndex,
                        output: measurement.output,
                        timeToFirstTokenSeconds: measurement.timeToFirstTokenSeconds,
                        totalDurationSeconds: measurement.totalDurationSeconds,
                        exactMatch: exactMatch,
                        similarity: similarity
                    )
                )
            }
        }

        return FoundationModelBenchmarkReport(environment: environment, results: results)
    }

    private static let correctionInstructions = """
    You are the final text cleanup layer for voice dictation before insertion into another app.
    Return only the corrected text.

    Make the smallest possible edits:
    - fix spelling and obvious recognition mistakes
    - restore capitalization
    - normalize punctuation and spacing
    - keep product names, technical terms, and foreign words in their original language when obvious
    - preserve the original meaning and wording
    - do not add explanations, quotes, bullets, or commentary
    """

    private static func measureResponse(
        session: LanguageModelSession,
        input: String,
        maxResponseTokens: Int
    ) async throws -> FoundationModelBenchmarkMeasurement {
        let stream = session.streamResponse(
            to: correctionPrompt(for: input),
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0,
                maximumResponseTokens: maxResponseTokens
            )
        )

        let startedAt = CFAbsoluteTimeGetCurrent()
        var firstTokenSeconds: Double?
        var latestOutput = ""

        for try await snapshot in stream {
            let candidate = snapshot.content
            if firstTokenSeconds == nil && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                firstTokenSeconds = CFAbsoluteTimeGetCurrent() - startedAt
            }
            latestOutput = candidate
        }

        let totalDurationSeconds = CFAbsoluteTimeGetCurrent() - startedAt
        return FoundationModelBenchmarkMeasurement(
            output: latestOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            timeToFirstTokenSeconds: firstTokenSeconds,
            totalDurationSeconds: totalDurationSeconds
        )
    }

    private static func configuredModel() -> SystemLanguageModel {
        SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
    }

    private static func correctionPrompt(for input: String) -> String {
        """
        Clean up this dictation text for direct insertion. Return only the corrected text.

        Input:
        \(input)
        """
    }

    private static func describeAvailability(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "unavailable (device not eligible for Apple Intelligence)"
            case .appleIntelligenceNotEnabled:
                return "unavailable (Apple Intelligence is not enabled)"
            case .modelNotReady:
                return "unavailable (model assets are not ready yet)"
            @unknown default:
                return "unavailable (unknown reason)"
            }
        }
    }
}

@available(macOS 26.0, *)
public enum FoundationModelBenchmarkRunnerError: LocalizedError {
    case modelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let description):
            return "Foundation Models unavailable: \(description)"
        }
    }
}
#endif
