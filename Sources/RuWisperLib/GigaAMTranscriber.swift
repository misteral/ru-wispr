import Foundation
import MLX

/// Streaming transcription result.
public struct StreamingResult {
    public let text: String
    public let isFinal: Bool
    public let audioPosition: Double  // seconds
    public let cumulativeText: String
}

/// Native GigaAM v3 transcriber using MLX Swift — no Python dependency.
public class GigaAMTranscriber {
    private var model: GigaAMCTCModel?
    private let modelDir: URL
    private var isLoaded = false

    /// Default model directory: ~/.config/ru-wisper/models/gigaam-v3-ctc-mlx
    public static let defaultModelDir: URL = {
        Config.configDir.appendingPathComponent("models/gigaam-v3-ctc-mlx")
    }()

    public init(modelPath: String? = nil) {
        if let path = modelPath {
            self.modelDir = URL(fileURLWithPath: path)
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
        fputs("GigaAM: model loaded in \(String(format: "%.2f", dt))s\n", stderr)
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

    /// Transcribe a growing audio buffer for live streaming.
    /// Call repeatedly as new audio arrives.
    /// Returns current full transcription.
    public func transcribeLive(samples: [Float]) throws -> StreamingResult {
        try loadModel()
        guard let model = model else {
            throw GigaAMError.modelNotLoaded
        }

        let sr = model.config.sampleRate
        let maxWindow = 30 * sr  // cap at 30 seconds
        let totalSamples = samples.count

        let startIdx = max(0, totalSamples - maxWindow)
        let window = Array(samples[startIdx...])
        let audio = MLXArray(window)

        let text = model.transcribe(audio)

        return StreamingResult(
            text: text,
            isFinal: false,
            audioPosition: Double(totalSamples) / Double(sr),
            cumulativeText: text
        )
    }

    /// Check if the model directory exists and contains required files.
    public static func isAvailable(path: String? = nil) -> Bool {
        let dir: URL
        if let path = path {
            dir = URL(fileURLWithPath: path)
        } else {
            dir = defaultModelDir
        }

        let configFile = dir.appendingPathComponent("config.json")
        let modelFile = dir.appendingPathComponent("model.safetensors")
        let fm = FileManager.default
        return fm.fileExists(atPath: configFile.path) && fm.fileExists(atPath: modelFile.path)
    }

    // MARK: - Audio Loading

    /// Load audio file via ffmpeg → [Float] samples at 16kHz mono.
    private func loadAudioFile(url: URL) throws -> MLXArray {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
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
