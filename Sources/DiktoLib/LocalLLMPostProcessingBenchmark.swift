import Foundation

public struct LocalLLMPostProcessingBenchmarkOptions: Equatable, Sendable {
    public var text: String?
    public var filePath: String?
    public var runs: Int
    public var language: String
    public var modelID: String?
    public var modelPath: String?
    public var maxTokens: Int
    public var temperature: Float
    public var timeoutMs: Int
    public var showHelp: Bool

    public init(
        text: String? = nil,
        filePath: String? = nil,
        runs: Int = 1,
        language: String = "ru",
        modelID: String? = nil,
        modelPath: String? = nil,
        maxTokens: Int = 96,
        temperature: Float = 0,
        timeoutMs: Int = 10_000,
        showHelp: Bool = false
    ) {
        self.text = text
        self.filePath = filePath
        self.runs = runs
        self.language = language
        self.modelID = modelID
        self.modelPath = modelPath
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutMs = timeoutMs
        self.showHelp = showHelp
    }

    public static func parse(_ args: [String]) throws -> LocalLLMPostProcessingBenchmarkOptions {
        var options = LocalLLMPostProcessingBenchmarkOptions()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--help", "-h":
                options.showHelp = true
            case "--text":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--text") }
                options.text = args[index]
            case "--file":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--file") }
                options.filePath = args[index]
            case "--runs":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--runs") }
                guard let value = Int(args[index]), value > 0 else {
                    throw LocalLLMPostProcessingBenchmarkOptionsError.invalidInteger(flag: "--runs", value: args[index])
                }
                options.runs = value
            case "--language":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--language") }
                options.language = args[index]
            case "--model-id":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--model-id") }
                options.modelID = args[index]
            case "--model-path":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--model-path") }
                options.modelPath = args[index]
            case "--max-tokens":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--max-tokens") }
                guard let value = Int(args[index]), value > 0 else {
                    throw LocalLLMPostProcessingBenchmarkOptionsError.invalidInteger(flag: "--max-tokens", value: args[index])
                }
                options.maxTokens = value
            case "--temperature":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--temperature") }
                guard let value = Float(args[index]), value >= 0 else {
                    throw LocalLLMPostProcessingBenchmarkOptionsError.invalidFloat(flag: "--temperature", value: args[index])
                }
                options.temperature = value
            case "--timeout-ms":
                index += 1
                guard index < args.count else { throw LocalLLMPostProcessingBenchmarkOptionsError.missingValue(flag: "--timeout-ms") }
                guard let value = Int(args[index]), value > 0 else {
                    throw LocalLLMPostProcessingBenchmarkOptionsError.invalidInteger(flag: "--timeout-ms", value: args[index])
                }
                options.timeoutMs = value
            default:
                throw LocalLLMPostProcessingBenchmarkOptionsError.unknownArgument(arg)
            }
            index += 1
        }

        if options.text != nil && options.filePath != nil {
            throw LocalLLMPostProcessingBenchmarkOptionsError.mutuallyExclusiveInputs
        }
        if options.modelID != nil && options.modelPath != nil {
            throw LocalLLMPostProcessingBenchmarkOptionsError.mutuallyExclusiveModelSource
        }

        return options
    }

    public func benchmarkCases() throws -> [FoundationModelBenchmarkCase] {
        if let text {
            return [FoundationModelBenchmarkCase(name: "custom", input: text, expected: nil)]
        }

        if let filePath {
            let url = URL(fileURLWithPath: filePath)
            let contents = try String(contentsOf: url, encoding: .utf8)
            return [FoundationModelBenchmarkCase(name: url.lastPathComponent, input: contents, expected: nil)]
        }

        return FoundationModelBenchmarkCase.builtInSuite + [
            FoundationModelBenchmarkCase(
                name: "ru_mixed_terms",
                input: "сейчас мы тестируем исправление текста в xcode и github actions",
                expected: "Сейчас мы тестируем исправление текста в Xcode и GitHub Actions."
            ),
            FoundationModelBenchmarkCase(
                name: "ru_typo_cleanup",
                input: "превет мир это тест орфографичесике ошибки и пунктуация",
                expected: "Привет, мир! Это тест: орфографические ошибки и пунктуация."
            ),
        ]
    }

    public var configuration: MLXLocalLLMTextPostProcessingConfiguration {
        MLXLocalLLMTextPostProcessingConfiguration(
            modelID: modelPath == nil ? (modelID ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit") : nil,
            modelPath: modelPath,
            maxTokens: maxTokens,
            temperature: temperature,
            timeoutMs: timeoutMs
        )
    }

    public static let help = """
    Benchmark the MLX local LLM post-processing layer.

    USAGE:
        dikto test-local-llm [options]

    OPTIONS:
        --text <text>         Benchmark a single custom text
        --file <path>         Benchmark text loaded from a file
        --runs <count>        Repeat the suite N times (default: 1)
        --language <code>     Language hint passed to the prompt (default: ru)
        --model-id <id>       Hugging Face / mlx-community model id
        --model-path <path>   Local MLX model directory
        --max-tokens <n>      Maximum generated tokens (default: 96)
        --temperature <n>     Sampling temperature (default: 0)
        --timeout-ms <n>      Timeout per request in milliseconds (default: 10000)
        --help                Show this help message

    DEFAULT MODEL:
        mlx-community/Qwen2.5-1.5B-Instruct-4bit
    """
}

public enum LocalLLMPostProcessingBenchmarkOptionsError: LocalizedError, Equatable {
    case missingValue(flag: String)
    case invalidInteger(flag: String, value: String)
    case invalidFloat(flag: String, value: String)
    case mutuallyExclusiveInputs
    case mutuallyExclusiveModelSource
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidInteger(let flag, let value):
            return "Invalid integer for \(flag): \(value)"
        case .invalidFloat(let flag, let value):
            return "Invalid float for \(flag): \(value)"
        case .mutuallyExclusiveInputs:
            return "Use either --text or --file, not both"
        case .mutuallyExclusiveModelSource:
            return "Use either --model-id or --model-path, not both"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

public struct LocalLLMPostProcessingBenchmarkCaseResult: Sendable {
    public let benchmarkCase: FoundationModelBenchmarkCase
    public let runIndex: Int
    public let output: String
    public let timeToFirstChunkSeconds: Double?
    public let totalDurationSeconds: Double
    public let completionInfo: MLXLocalLLMGenerationInfo?
    public let exactMatch: Bool?
    public let similarity: Double?
}

public struct LocalLLMPostProcessingBenchmarkReport: Sendable {
    public let configuration: MLXLocalLLMTextPostProcessingConfiguration
    public let loadDurationSeconds: Double
    public let results: [LocalLLMPostProcessingBenchmarkCaseResult]

    public var averageTimeToFirstChunkSeconds: Double? {
        let values = results.compactMap(\.timeToFirstChunkSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public var averageTotalDurationSeconds: Double {
        guard !results.isEmpty else { return 0 }
        return results.map(\.totalDurationSeconds).reduce(0, +) / Double(results.count)
    }

    public var averageSimilarity: Double? {
        let values = results.compactMap(\.similarity)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public var exactMatches: Int {
        results.compactMap(\.exactMatch).filter { $0 }.count
    }

    public var scoredResults: Int {
        results.compactMap(\.exactMatch).count
    }
}

public enum LocalLLMPostProcessingBenchmarkEvent: Sendable {
    case loadingModel(source: String)
    case modelDownloadProgress(completedUnitCount: Int64, totalUnitCount: Int64)
    case modelLoaded(durationSeconds: Double)
    case startingCase(runIndex: Int, totalRuns: Int, caseName: String)
    case finishedCase(runIndex: Int, totalRuns: Int, caseName: String, totalDurationSeconds: Double)
}

public enum LocalLLMPostProcessingBenchmarkRunner {
    public static func run(
        options: LocalLLMPostProcessingBenchmarkOptions,
        eventHandler: (@Sendable (LocalLLMPostProcessingBenchmarkEvent) -> Void)? = nil
    ) async throws -> LocalLLMPostProcessingBenchmarkReport {
        let cases = try options.benchmarkCases()
        let context = TextPostProcessingContext(language: options.language, spokenPunctuationEnabled: false)
        let engine = MLXLocalLLMTextPostProcessingEngine(configuration: options.configuration)

        eventHandler?(.loadingModel(source: options.configuration.sourceDescription))
        let loadDurationSeconds = try await engine.ensureLoaded { progress in
            eventHandler?(
                .modelDownloadProgress(
                    completedUnitCount: progress.completedUnitCount,
                    totalUnitCount: progress.totalUnitCount
                )
            )
        }
        eventHandler?(.modelLoaded(durationSeconds: loadDurationSeconds))

        var results: [LocalLLMPostProcessingBenchmarkCaseResult] = []
        for runIndex in 1...options.runs {
            for benchmarkCase in cases {
                eventHandler?(
                    .startingCase(
                        runIndex: runIndex,
                        totalRuns: options.runs,
                        caseName: benchmarkCase.name
                    )
                )

                let measurement = try await engine.measure(benchmarkCase.input, context: context)
                let exactMatch = benchmarkCase.expected.map {
                    FoundationModelBenchmarkQuality.exactMatch(expected: $0, actual: measurement.output)
                }
                let similarity = benchmarkCase.expected.map {
                    FoundationModelBenchmarkQuality.similarity(expected: $0, actual: measurement.output)
                }

                results.append(
                    LocalLLMPostProcessingBenchmarkCaseResult(
                        benchmarkCase: benchmarkCase,
                        runIndex: runIndex,
                        output: measurement.output,
                        timeToFirstChunkSeconds: measurement.timeToFirstChunkSeconds,
                        totalDurationSeconds: measurement.totalDurationSeconds,
                        completionInfo: measurement.completionInfo,
                        exactMatch: exactMatch,
                        similarity: similarity
                    )
                )

                eventHandler?(
                    .finishedCase(
                        runIndex: runIndex,
                        totalRuns: options.runs,
                        caseName: benchmarkCase.name,
                        totalDurationSeconds: measurement.totalDurationSeconds
                    )
                )
            }
        }

        return LocalLLMPostProcessingBenchmarkReport(
            configuration: options.configuration,
            loadDurationSeconds: loadDurationSeconds,
            results: results
        )
    }
}
