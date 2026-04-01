import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon

public struct MLXLocalLLMTextPostProcessingConfiguration: Codable, Sendable, Equatable {
    public let modelID: String?
    public let modelPath: String?
    public let maxTokens: Int
    public let temperature: Float
    public let timeoutMs: Int

    public init(
        modelID: String?,
        modelPath: String?,
        maxTokens: Int,
        temperature: Float,
        timeoutMs: Int
    ) {
        self.modelID = modelID
        self.modelPath = modelPath
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutMs = timeoutMs
    }

    public static func from(config: Config) -> MLXLocalLLMTextPostProcessingConfiguration {
        MLXLocalLLMTextPostProcessingConfiguration(
            modelID: config.postProcessingModelPath == nil ? config.effectivePostProcessingModelID : nil,
            modelPath: config.postProcessingModelPath,
            maxTokens: config.effectivePostProcessingMaxTokens,
            temperature: config.effectivePostProcessingTemperature,
            timeoutMs: config.effectivePostProcessingTimeoutMs
        )
    }

    public var sourceDescription: String {
        if let modelPath {
            return modelPath
        }
        return modelID ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    }
}

public struct MLXLocalLLMGenerationInfo: Codable, Sendable, Equatable {
    public let promptTokenCount: Int
    public let generationTokenCount: Int
    public let promptTimeSeconds: Double
    public let generationTimeSeconds: Double
    public let promptTokensPerSecond: Double
    public let tokensPerSecond: Double
    public let stopReason: String

    public init(
        promptTokenCount: Int,
        generationTokenCount: Int,
        promptTimeSeconds: Double,
        generationTimeSeconds: Double,
        promptTokensPerSecond: Double,
        tokensPerSecond: Double,
        stopReason: String
    ) {
        self.promptTokenCount = promptTokenCount
        self.generationTokenCount = generationTokenCount
        self.promptTimeSeconds = promptTimeSeconds
        self.generationTimeSeconds = generationTimeSeconds
        self.promptTokensPerSecond = promptTokensPerSecond
        self.tokensPerSecond = tokensPerSecond
        self.stopReason = stopReason
    }
}

public struct MLXLocalLLMTextPostProcessingMeasurement: Codable, Sendable, Equatable {
    public let output: String
    public let timeToFirstChunkSeconds: Double?
    public let totalDurationSeconds: Double
    public let completionInfo: MLXLocalLLMGenerationInfo?

    public init(
        output: String,
        timeToFirstChunkSeconds: Double?,
        totalDurationSeconds: Double,
        completionInfo: MLXLocalLLMGenerationInfo?
    ) {
        self.output = output
        self.timeToFirstChunkSeconds = timeToFirstChunkSeconds
        self.totalDurationSeconds = totalDurationSeconds
        self.completionInfo = completionInfo
    }
}

public actor MLXLocalLLMTextPostProcessingEngine {
    private let configuration: MLXLocalLLMTextPostProcessingConfiguration
    private var modelContainer: ModelContainer?
    private var device: Device = .gpu

    public init(configuration: MLXLocalLLMTextPostProcessingConfiguration) {
        self.configuration = configuration
    }

    public func ensureLoaded(progressHandler: (@Sendable (Progress) -> Void)? = nil) async throws -> Double {
        if modelContainer != nil {
            return 0
        }

        let handler: @Sendable (Progress) -> Void = progressHandler ?? { _ in }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let preferredDevice: Device = Self.isMetalLibraryAvailable() ? .gpu : .cpu

        if preferredDevice == .cpu {
            fputs("Local LLM: MLX Metal library was not found, using CPU backend.\n", stderr)
        }

        do {
            modelContainer = try await loadModelContainer(on: preferredDevice, progressHandler: handler)
            device = preferredDevice
        } catch {
            if preferredDevice == .gpu && Self.isMissingMetalLibraryError(error) {
                fputs("Local LLM: MLX Metal library is unavailable for the current build, falling back to CPU.\n", stderr)
                modelContainer = try await loadModelContainer(on: .cpu, progressHandler: handler)
                device = .cpu
            } else {
                throw error
            }
        }

        return CFAbsoluteTimeGetCurrent() - startedAt
    }

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        let measurement = try await measure(text, context: context)
        return measurement.output
    }

    public func measure(_ text: String, context: TextPostProcessingContext) async throws -> MLXLocalLLMTextPostProcessingMeasurement {
        let normalizedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInput.isEmpty else {
            return MLXLocalLLMTextPostProcessingMeasurement(
                output: text,
                timeToFirstChunkSeconds: 0,
                totalDurationSeconds: 0,
                completionInfo: nil
            )
        }

        _ = try await ensureLoaded()
        guard let modelContainer else {
            throw MLXLocalLLMTextPostProcessingError.modelNotLoaded
        }

        let configuration = self.configuration
        let device = self.device
        let operation: @Sendable () async throws -> MLXLocalLLMTextPostProcessingMeasurement = {
            try await Self.generateMeasurement(
                text: text,
                context: context,
                modelContainer: modelContainer,
                configuration: configuration,
                device: device
            )
        }

        if configuration.timeoutMs > 0 {
            return try await withTimeout(milliseconds: configuration.timeoutMs, operation: operation)
        }
        return try await operation()
    }

    private static func generateMeasurement(
        text: String,
        context: TextPostProcessingContext,
        modelContainer: ModelContainer,
        configuration: MLXLocalLLMTextPostProcessingConfiguration,
        device: Device
    ) async throws -> MLXLocalLLMTextPostProcessingMeasurement {
        try await Device.withDefaultDevice(device) {
            let session = ChatSession(
                modelContainer,
                instructions: Self.instructions(for: context),
                generateParameters: GenerateParameters(
                    maxTokens: configuration.maxTokens,
                    temperature: configuration.temperature,
                    topP: 1.0,
                    topK: 0,
                    minP: 0.0,
                    repetitionPenalty: nil,
                    presencePenalty: nil,
                    frequencyPenalty: nil
                )
            )

            let startedAt = CFAbsoluteTimeGetCurrent()
            var timeToFirstChunkSeconds: Double?
            var output = ""
            var completionInfo: MLXLocalLLMGenerationInfo?

            for try await generation in session.streamDetails(to: Self.prompt(for: text, context: context), images: [], videos: []) {
                switch generation {
                case .chunk(let chunk):
                    if timeToFirstChunkSeconds == nil && !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        timeToFirstChunkSeconds = CFAbsoluteTimeGetCurrent() - startedAt
                    }
                    output += chunk
                case .info(let info):
                    completionInfo = MLXLocalLLMGenerationInfo(
                        promptTokenCount: info.promptTokenCount,
                        generationTokenCount: info.generationTokenCount,
                        promptTimeSeconds: info.promptTime,
                        generationTimeSeconds: info.generateTime,
                        promptTokensPerSecond: info.promptTokensPerSecond,
                        tokensPerSecond: info.tokensPerSecond,
                        stopReason: String(describing: info.stopReason)
                    )
                case .toolCall:
                    break
                }
            }

            return MLXLocalLLMTextPostProcessingMeasurement(
                output: Self.normalizeOutput(output, fallback: text),
                timeToFirstChunkSeconds: timeToFirstChunkSeconds,
                totalDurationSeconds: CFAbsoluteTimeGetCurrent() - startedAt,
                completionInfo: completionInfo
            )
        }
    }

    private static func instructions(for context: TextPostProcessingContext) -> String {
        """
        You are the final text cleanup layer for voice dictation before insertion into another app.
        Return only the corrected text.

        Make the smallest possible edits:
        - fix spelling and obvious recognition mistakes
        - restore capitalization
        - normalize punctuation and spacing
        - preserve line breaks when they are already present
        - keep product names, code terms, file names, and foreign words in their original language when obvious
        - preserve the original meaning and wording
        - do not add explanations, quotes, bullets, or commentary

        Preferred language hint: \(context.language)
        Spoken punctuation preprocessing already applied: \(context.spokenPunctuationEnabled ? "yes" : "no")
        """
    }

    private static func prompt(for text: String, context: TextPostProcessingContext) -> String {
        """
        Clean up this dictation text for direct insertion. Return only the corrected text.

        Text:
        \(text)
        """
    }

    private static func normalizeOutput(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func loadModelContainer(
        on device: Device,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> ModelContainer {
        try await Device.withDefaultDevice(device) {
            if let modelPath = configuration.modelPath {
                return try await MLXLMCommon.loadModelContainer(
                    directory: URL(fileURLWithPath: modelPath),
                    progressHandler: progressHandler
                )
            } else {
                return try await MLXLMCommon.loadModelContainer(
                    id: configuration.sourceDescription,
                    progressHandler: progressHandler
                )
            }
        }
    }

    private static func isMissingMetalLibraryError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("failed to load the default metallib")
            || message.contains("metallib")
            || message.contains("library not found")
    }

    private static func isMetalLibraryAvailable() -> Bool {
        let fileManager = FileManager.default
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let executableDir = executableURL.deletingLastPathComponent()

        let candidates: [URL] = [
            executableDir.appendingPathComponent("mlx.metallib"),
            executableDir.appendingPathComponent("default.metallib"),
            executableDir.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mlx.metallib")
        ].compactMap { $0 }

        return candidates.contains { fileManager.fileExists(atPath: $0.path) }
    }
}

public actor MLXLocalLLMTextPostProcessingProvider: TextPostProcessingProvider {
    public nonisolated let name = "local-llm"

    private let engine: MLXLocalLLMTextPostProcessingEngine

    public init(configuration: MLXLocalLLMTextPostProcessingConfiguration) {
        self.engine = MLXLocalLLMTextPostProcessingEngine(configuration: configuration)
    }

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        try await engine.process(text, context: context)
    }
}

public enum MLXLocalLLMTextPostProcessingError: LocalizedError {
    case modelNotLoaded
    case timedOut(milliseconds: Int)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local LLM post-processing model is not loaded"
        case .timedOut(let milliseconds):
            return "Local LLM post-processing timed out after \(milliseconds) ms"
        }
    }
}

private func withTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            throw MLXLocalLLMTextPostProcessingError.timedOut(milliseconds: milliseconds)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

#else
public struct MLXLocalLLMTextPostProcessingConfiguration: Codable, Sendable, Equatable {
    public let modelID: String?
    public let modelPath: String?
    public let maxTokens: Int
    public let temperature: Float
    public let timeoutMs: Int

    public init(
        modelID: String?,
        modelPath: String?,
        maxTokens: Int,
        temperature: Float,
        timeoutMs: Int
    ) {
        self.modelID = modelID
        self.modelPath = modelPath
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutMs = timeoutMs
    }

    public static func from(config: Config) -> MLXLocalLLMTextPostProcessingConfiguration {
        MLXLocalLLMTextPostProcessingConfiguration(
            modelID: config.effectivePostProcessingModelID,
            modelPath: config.postProcessingModelPath,
            maxTokens: config.effectivePostProcessingMaxTokens,
            temperature: config.effectivePostProcessingTemperature,
            timeoutMs: config.effectivePostProcessingTimeoutMs
        )
    }
}

public actor MLXLocalLLMTextPostProcessingProvider: TextPostProcessingProvider {
    public nonisolated let name = "local-llm"

    public init(configuration: MLXLocalLLMTextPostProcessingConfiguration) {}

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        throw NSError(domain: "MLXLocalLLMTextPostProcessingProvider", code: 1)
    }
}
#endif
