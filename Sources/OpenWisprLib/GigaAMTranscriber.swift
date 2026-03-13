import Foundation

public class GigaAMTranscriber {
    private let binaryPath: String
    private let modelPath: String?

    public init(gigaamPath: String? = nil, modelPath: String? = nil) {
        self.binaryPath = gigaamPath ?? GigaAMTranscriber.findGigaAMBinary() ?? ""
        self.modelPath = modelPath
    }

    public func transcribe(audioURL: URL) throws -> String {
        guard !binaryPath.isEmpty else {
            throw GigaAMError.binaryNotFound
        }

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw GigaAMError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        var args = ["-f", audioURL.path, "--no-prints"]
        if let modelPath = modelPath {
            args += ["-m", modelPath]
        }
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        var stderrData = Data()
        let stderrThread = Thread {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        stderrThread.start()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        while !stderrThread.isFinished { Thread.sleep(forTimeInterval: 0.01) }
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderr.isEmpty {
                fputs("gigaam: \(stderr)\n", Foundation.stderr)
            }
            throw GigaAMError.transcriptionFailed
        }

        return output
    }

    public static func isAvailable(path: String? = nil) -> Bool {
        if let path = path {
            return FileManager.default.fileExists(atPath: path)
        }
        return findGigaAMBinary() != nil
    }

    public static func findGigaAMBinary() -> String? {
        let candidates = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Developer/cloned/GigaAM/mlx_convert/gigaam-transcribe",
            "/usr/local/bin/gigaam-transcribe",
            "/opt/homebrew/bin/gigaam-transcribe",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try which
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["gigaam-transcribe"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()

        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let result = result, !result.isEmpty {
            return result
        }

        return nil
    }
}

enum GigaAMError: LocalizedError {
    case binaryNotFound
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "gigaam-transcribe not found. Set 'gigaamPath' in config or install to PATH."
        case .transcriptionFailed:
            return "GigaAM transcription failed"
        }
    }
}
