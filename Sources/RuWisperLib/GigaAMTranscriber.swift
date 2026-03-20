import Foundation
import MLX

/// Streaming transcription result.
public struct StreamingResult {
    public let text: String
    public let isFinal: Bool
    public let audioPosition: Double  // seconds
    public let cumulativeText: String
}

/// Maintains state for windowed streaming transcription.
/// Tracks committed (finalized) text from older audio and the active window text.
public class StreamingContext {
    /// Finalized text from committed (older) audio chunks.
    var committedText: String = ""
    /// Number of audio samples whose transcription has been committed.
    var committedSamples: Int = 0
    /// Text from the most recent active window (may change on next tick).
    var lastWindowText: String = ""
    /// Guard against concurrent transcription calls.
    var isProcessing: Bool = false

    /// Full cumulative text = committed + window.
    var fullText: String {
        if committedText.isEmpty { return lastWindowText }
        if lastWindowText.isEmpty { return committedText }
        return committedText + " " + lastWindowText
    }

    func reset() {
        committedText = ""
        committedSamples = 0
        lastWindowText = ""
        isProcessing = false
    }
}

/// Native GigaAM v3 transcriber using MLX Swift — no Python dependency.
/// Supports both CTC and RNNT models (auto-detected from config.json).
public class GigaAMTranscriber {
    private var model: (any GigaAMModelProtocol)?
    private let modelDir: URL
    private var isLoaded = false

    // Windowed streaming configuration (seconds)
    private static let windowSeconds = 5
    private static let overlapSeconds = 1
    private static let commitThresholdSeconds = 8

    /// Default model directory (search order):
    /// 1. App bundle: Contents/Resources/gigaam-v3-rnnt-mlx/
    /// 2. User data: ~/Library/Application Support/RuWispr/models/gigaam-v3-rnnt-mlx/
    public static let defaultModelDir: URL = {
        // 1. Resolve via executable path: .app/Contents/MacOS/binary → .app/Contents/Resources/
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execURL = URL(filePath: execPath).resolvingSymlinksInPath().deletingLastPathComponent()
        let resourcesDir = execURL.deletingLastPathComponent().appending(path: "Resources")
        let bundled = resourcesDir.appending(path: "gigaam-v3-rnnt-mlx")
        if FileManager.default.fileExists(atPath: bundled.appending(path: "config.json").path) {
            fputs("GigaAM: using bundled RNNT model at \(bundled.path)\n", stderr)
            return bundled
        }
        // 2. Fallback to user data directory
        let userDir = Config.dataDir.appending(path: "models/gigaam-v3-rnnt-mlx")
        if FileManager.default.fileExists(atPath: userDir.appending(path: "config.json").path) {
            fputs("GigaAM: using user RNNT model at \(userDir.path)\n", stderr)
            return userDir
        }
        // 3. Legacy CTC fallback
        let ctcDir = Config.dataDir.appending(path: "models/gigaam-v3-ctc-mlx")
        fputs("GigaAM: RNNT model not found, falling back to \(ctcDir.path)\n", stderr)
        return ctcDir
    }()

    public init(modelPath: String? = nil) {
        if let path = modelPath {
            self.modelDir = URL(filePath: path)
        } else {
            self.modelDir = GigaAMTranscriber.defaultModelDir
        }
    }

    /// Load the model into memory. Call once before transcribing.
    public func loadModel() throws {
        guard !isLoaded else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        model = try loadGigaAMModel(from: modelDir)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let headType = model?.config.headType ?? "unknown"
        fputs("GigaAM: \(headType.uppercased()) model loaded in \(dt.formatted(.number.precision(.fractionLength(2))))s\n", stderr)
        isLoaded = true
    }

    /// Transcribe an audio file (WAV, 16kHz mono).
    public func transcribe(audioURL: URL) throws -> String {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        let audio = try loadAudioFile(url: audioURL)
        return model.transcribe(audio)
    }

    /// Transcribe raw audio samples (Float32, 16kHz mono).
    public func transcribe(samples: [Float]) throws -> String {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        let audio = MLXArray(samples)
        return model.transcribe(audio)
    }

    /// Transcribe raw audio samples in 30-second chunks for long recordings.
    /// Avoids heavy single-pass processing — consistent with streaming window size.
    public func transcribeChunked(samples: [Float], chunkSeconds: Int = 30) throws -> String {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        let sr = model.config.sampleRate
        let chunkSize = chunkSeconds * sr

        // Short recording — single pass
        if samples.count <= chunkSize {
            let audio = MLXArray(samples)
            return model.transcribe(audio)
        }

        // Long recording — split into chunks
        var results: [String] = []
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset..<end])
            // Skip very short trailing chunks (< 0.5s)
            guard chunk.count >= sr / 2 else { break }
            let audio = MLXArray(chunk)
            let text = model.transcribe(audio)
            if !text.isEmpty {
                results.append(text)
            }
            offset = end
        }

        return results.joined(separator: " ")
    }

    /// Windowed streaming transcription: processes only the recent audio window
    /// and commits older audio progressively. Each call does at most one model
    /// inference (~5-8s of audio) instead of re-processing the entire buffer.
    public func transcribeLive(samples: [Float], context: StreamingContext) throws -> StreamingResult {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        let sr = model.config.sampleRate
        let windowSize = Self.windowSeconds * sr
        let overlapSize = Self.overlapSeconds * sr
        let commitThreshold = Self.commitThresholdSeconds * sr
        let totalSamples = samples.count

        // Short recording: process everything (no windowing needed)
        if totalSamples <= windowSize {
            let text = model.transcribe(MLXArray(samples))
            context.lastWindowText = text
            return StreamingResult(
                text: context.fullText, isFinal: false,
                audioPosition: Double(totalSamples) / Double(sr),
                cumulativeText: context.fullText
            )
        }

        // Check if uncommitted audio exceeds the threshold — commit older audio
        let uncommitted = totalSamples - context.committedSamples
        if uncommitted > commitThreshold {
            let commitEnd = totalSamples - windowSize
            if commitEnd > context.committedSamples {
                let chunk = Array(samples[context.committedSamples..<commitEnd])
                let chunkText = model.transcribe(MLXArray(chunk))
                if !chunkText.isEmpty {
                    context.committedText = context.committedText.isEmpty
                        ? chunkText
                        : context.committedText + " " + chunkText
                }
                context.committedSamples = commitEnd
                // Return current result without re-processing window this tick
                return StreamingResult(
                    text: context.fullText, isFinal: false,
                    audioPosition: Double(totalSamples) / Double(sr),
                    cumulativeText: context.fullText
                )
            }
        }

        // Process active window with overlap into committed region for stitching
        let windowStart = max(context.committedSamples - overlapSize, 0)
        let windowSamples = Array(samples[windowStart...])
        let windowText = model.transcribe(MLXArray(windowSamples))

        // Stitch: remove overlap text that duplicates committed text
        if context.committedSamples > 0 && windowStart < context.committedSamples && !context.committedText.isEmpty {
            context.lastWindowText = Self.stitchTexts(committed: context.committedText, window: windowText)
        } else {
            context.lastWindowText = windowText
        }

        return StreamingResult(
            text: context.fullText, isFinal: false,
            audioPosition: Double(totalSamples) / Double(sr),
            cumulativeText: context.fullText
        )
    }

    /// Final transcription when recording stops. Only processes the uncommitted
    /// tail (at most ~8s) for near-instant results.
    public func transcribeFinal(samples: [Float], context: StreamingContext) throws -> String {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        guard context.committedSamples < samples.count else {
            return context.committedText
        }

        let sr = model.config.sampleRate
        let overlapSize = Self.overlapSeconds * sr

        // Process remaining samples with overlap into committed region
        let tailStart = max(context.committedSamples - overlapSize, 0)
        let tail = Array(samples[tailStart...])
        let tailText = model.transcribe(MLXArray(tail))

        if context.committedText.isEmpty {
            return tailText
        }
        if tailText.isEmpty {
            return context.committedText
        }

        // Stitch tail with committed text
        if tailStart < context.committedSamples {
            let newPart = Self.stitchTexts(committed: context.committedText, window: tailText)
            return newPart.isEmpty ? context.committedText : context.committedText + " " + newPart
        }

        return context.committedText + " " + tailText
    }

    /// Find new text in window that doesn't overlap with committed text.
    /// Uses word-level suffix-prefix matching to remove duplicated overlap.
    static func stitchTexts(committed: String, window: String) -> String {
        let committedWords = committed.split(separator: " ").map(String.init)
        let windowWords = window.split(separator: " ").map(String.init)

        guard !committedWords.isEmpty, !windowWords.isEmpty else {
            return window
        }

        // Find longest suffix of committed that matches a prefix of window
        let maxOverlap = min(committedWords.count, windowWords.count, 15)

        for overlapLen in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = Array(committedWords.suffix(overlapLen))
            let prefix = Array(windowWords.prefix(overlapLen))
            if suffix == prefix {
                let newWords = windowWords.dropFirst(overlapLen)
                return newWords.joined(separator: " ")
            }
        }

        // No overlap found — return full window text
        return window
    }

    /// Check if the model directory exists and contains required files.
    public static func isAvailable(path: String? = nil) -> Bool {
        let dir: URL
        if let path = path {
            dir = URL(filePath: path)
        } else {
            dir = defaultModelDir
        }

        let configFile = dir.appending(path: "config.json")
        let modelFile = dir.appending(path: "model.safetensors")
        let fm = FileManager.default
        return fm.fileExists(atPath: configFile.path) && fm.fileExists(atPath: modelFile.path)
    }

    // MARK: - Audio Loading

    /// Load audio file via ffmpeg → [Float] samples at 16kHz mono.
    private func loadAudioFile(url: URL) throws -> MLXArray {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [
            "ffmpeg", "-nostdin", "-threads", "0", "-i", url.path,
            "-f", "s16le", "-ac", "1", "-acodec", "pcm_s16le",
            "-ar", "16000", "-",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            throw GigaAMError.audioLoadFailed
        }

        // Convert Int16 PCM to Float32 normalized
        let int16Count = data.count / 2
        let samples: [Float] = data.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            return (0 ..< int16Count).map { Float(int16Ptr[$0]) / 32768.0 }
        }

        return MLXArray(samples)
    }
}

public enum GigaAMError: LocalizedError {
    case modelNotLoaded
    case modelNotFound
    case audioLoadFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "GigaAM model not loaded"
        case .modelNotFound:
            return "GigaAM model not found. Set 'modelPath' in config."
        case .audioLoadFailed:
            return "Failed to load audio file"
        case .transcriptionFailed:
            return "GigaAM transcription failed"
        }
    }
}
