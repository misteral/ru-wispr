import Foundation

public struct LocalLLMEvalCase: Codable, Equatable, Sendable {
    public let id: String
    public let input: String
    public let expected: String
    public let tags: [String]
    public let notes: String?

    public init(id: String, input: String, expected: String, tags: [String] = [], notes: String? = nil) {
        self.id = id
        self.input = input
        self.expected = expected
        self.tags = tags
        self.notes = notes
    }
}

public struct LocalLLMEvalModel: Codable, Equatable, Sendable {
    public let id: String?
    public let path: String?
    public let family: String
    public let sizeLabel: String
    public let priority: Int
    public let maxTokens: Int?
    public let temperature: Float?
    public let timeoutMs: Int?
    public let notes: String?
    public let sourceURL: String?
    public let downloads: Int?
    public let likes: Int?

    public init(
        id: String?,
        path: String?,
        family: String,
        sizeLabel: String,
        priority: Int,
        maxTokens: Int? = nil,
        temperature: Float? = nil,
        timeoutMs: Int? = nil,
        notes: String? = nil,
        sourceURL: String? = nil,
        downloads: Int? = nil,
        likes: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.family = family
        self.sizeLabel = sizeLabel
        self.priority = priority
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutMs = timeoutMs
        self.notes = notes
        self.sourceURL = sourceURL
        self.downloads = downloads
        self.likes = likes
    }

    public var sourceDescription: String {
        path ?? id ?? "unknown"
    }

    public func configuration(
        maxTokens overrideMaxTokens: Int?,
        temperature overrideTemperature: Float?,
        timeoutMs overrideTimeoutMs: Int?
    ) -> MLXLocalLLMTextPostProcessingConfiguration {
        MLXLocalLLMTextPostProcessingConfiguration(
            modelID: path == nil ? id : nil,
            modelPath: path,
            maxTokens: overrideMaxTokens ?? maxTokens ?? 96,
            temperature: overrideTemperature ?? temperature ?? 0,
            timeoutMs: overrideTimeoutMs ?? timeoutMs ?? 10_000
        )
    }
}

public struct LocalLLMEvalCaseResult: Encodable, Equatable, Sendable {
    public let caseID: String
    public let runIndex: Int
    public let output: String
    public let timeToFirstChunkSeconds: Double?
    public let totalDurationSeconds: Double
    public let similarity: Double
    public let exactMatch: Bool
    public let completionInfo: MLXLocalLLMGenerationInfo?

    public init(
        caseID: String,
        runIndex: Int,
        output: String,
        timeToFirstChunkSeconds: Double?,
        totalDurationSeconds: Double,
        similarity: Double,
        exactMatch: Bool,
        completionInfo: MLXLocalLLMGenerationInfo?
    ) {
        self.caseID = caseID
        self.runIndex = runIndex
        self.output = output
        self.timeToFirstChunkSeconds = timeToFirstChunkSeconds
        self.totalDurationSeconds = totalDurationSeconds
        self.similarity = similarity
        self.exactMatch = exactMatch
        self.completionInfo = completionInfo
    }
}

public struct LocalLLMEvalModelReport: Encodable, Equatable, Sendable {
    public let model: LocalLLMEvalModel
    public let configuration: MLXLocalLLMTextPostProcessingConfiguration
    public let loadDurationSeconds: Double
    public let caseResults: [LocalLLMEvalCaseResult]

    public init(
        model: LocalLLMEvalModel,
        configuration: MLXLocalLLMTextPostProcessingConfiguration,
        loadDurationSeconds: Double,
        caseResults: [LocalLLMEvalCaseResult]
    ) {
        self.model = model
        self.configuration = configuration
        self.loadDurationSeconds = loadDurationSeconds
        self.caseResults = caseResults
    }

    public var averageSimilarity: Double {
        guard !caseResults.isEmpty else { return 0 }
        return caseResults.map(\.similarity).reduce(0, +) / Double(caseResults.count)
    }

    public var averageDurationSeconds: Double {
        guard !caseResults.isEmpty else { return 0 }
        return caseResults.map(\.totalDurationSeconds).reduce(0, +) / Double(caseResults.count)
    }

    public var averageTimeToFirstChunkSeconds: Double? {
        let values = caseResults.compactMap(\.timeToFirstChunkSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public var exactMatchRate: Double {
        guard !caseResults.isEmpty else { return 0 }
        return Double(caseResults.filter { $0.exactMatch }.count) / Double(caseResults.count)
    }
}

public enum LocalLLMEvaluationLoader {
    public static func loadDataset(from url: URL) throws -> [LocalLLMEvalCase] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        let lines = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        return try lines.map { line in
            guard let data = line.data(using: .utf8) else {
                throw NSError(domain: "LocalLLMEvaluationLoader", code: 1)
            }
            return try decoder.decode(LocalLLMEvalCase.self, from: data)
        }
    }

    public static func loadModels(from url: URL) throws -> [LocalLLMEvalModel] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([LocalLLMEvalModel].self, from: data)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.sourceDescription < rhs.sourceDescription
                }
                return lhs.priority < rhs.priority
            }
    }
}

public enum LocalLLMEvaluatorEvent: Sendable {
    case loadingModel(LocalLLMEvalModel)
    case modelDownloadProgress(LocalLLMEvalModel, completedUnitCount: Int64, totalUnitCount: Int64)
    case modelLoaded(LocalLLMEvalModel, durationSeconds: Double)
    case startingCase(LocalLLMEvalModel, LocalLLMEvalCase, runIndex: Int, totalRuns: Int)
    case finishedCase(LocalLLMEvalModel, LocalLLMEvalCase, runIndex: Int, totalRuns: Int, durationSeconds: Double)
}

public enum LocalLLMEvaluator {
    public static func evaluate(
        model: LocalLLMEvalModel,
        dataset: [LocalLLMEvalCase],
        language: String,
        runs: Int,
        maxTokens: Int? = nil,
        temperature: Float? = nil,
        timeoutMs: Int? = nil,
        eventHandler: (@Sendable (LocalLLMEvaluatorEvent) -> Void)? = nil
    ) async throws -> LocalLLMEvalModelReport {
        let configuration = model.configuration(
            maxTokens: maxTokens,
            temperature: temperature,
            timeoutMs: timeoutMs
        )
        let engine = MLXLocalLLMTextPostProcessingEngine(configuration: configuration)
        let context = TextPostProcessingContext(language: language, spokenPunctuationEnabled: false)

        eventHandler?(.loadingModel(model))
        let loadDurationSeconds = try await engine.ensureLoaded { progress in
            eventHandler?(
                .modelDownloadProgress(
                    model,
                    completedUnitCount: progress.completedUnitCount,
                    totalUnitCount: progress.totalUnitCount
                )
            )
        }
        eventHandler?(.modelLoaded(model, durationSeconds: loadDurationSeconds))

        var caseResults: [LocalLLMEvalCaseResult] = []
        for runIndex in 1...runs {
            for evalCase in dataset {
                eventHandler?(.startingCase(model, evalCase, runIndex: runIndex, totalRuns: runs))
                let measurement = try await engine.measure(evalCase.input, context: context)
                let exactMatch = FoundationModelBenchmarkQuality.exactMatch(
                    expected: evalCase.expected,
                    actual: measurement.output
                )
                let similarity = FoundationModelBenchmarkQuality.similarity(
                    expected: evalCase.expected,
                    actual: measurement.output
                )
                caseResults.append(
                    LocalLLMEvalCaseResult(
                        caseID: evalCase.id,
                        runIndex: runIndex,
                        output: measurement.output,
                        timeToFirstChunkSeconds: measurement.timeToFirstChunkSeconds,
                        totalDurationSeconds: measurement.totalDurationSeconds,
                        similarity: similarity,
                        exactMatch: exactMatch,
                        completionInfo: measurement.completionInfo
                    )
                )
                eventHandler?(
                    .finishedCase(
                        model,
                        evalCase,
                        runIndex: runIndex,
                        totalRuns: runs,
                        durationSeconds: measurement.totalDurationSeconds
                    )
                )
            }
        }

        return LocalLLMEvalModelReport(
            model: model,
            configuration: configuration,
            loadDurationSeconds: loadDurationSeconds,
            caseResults: caseResults
        )
    }
}
