import Foundation

public enum MLXMetalLibSupportError: LocalizedError {
    case fullXcodeRequired
    case metalToolchainMissing
    case xcodebuildFailed(logPath: String)
    case metallibNotProduced(String)

    public var errorDescription: String? {
        switch self {
        case .fullXcodeRequired:
            return "Full Xcode is required to build MLX Metal shaders. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        case .metalToolchainMissing:
            return "Xcode Metal Toolchain is not installed. Run: xcodebuild -downloadComponent MetalToolchain"
        case .xcodebuildFailed(let logPath):
            return "xcodebuild failed while building MLX Metal shaders. Log: \(logPath)"
        case .metallibNotProduced(let path):
            return "MLX Metal library was not produced at: \(path)"
        }
    }
}

public enum MLXMetalLibSupport {
    public static func executableDirectory(commandPath: String = CommandLine.arguments[0]) -> URL {
        URL(fileURLWithPath: commandPath).resolvingSymlinksInPath().deletingLastPathComponent()
    }

    public static func candidateMetalLibraryURLs(executableDirectory: URL = executableDirectory()) -> [URL] {
        [
            executableDirectory.appendingPathComponent("mlx.metallib"),
            executableDirectory.appendingPathComponent("default.metallib"),
            executableDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mlx.metallib")
        ].compactMap { $0 }
    }

    public static func existingMetalLibraryURL(executableDirectory: URL = executableDirectory()) -> URL? {
        let fm = FileManager.default
        return candidateMetalLibraryURLs(executableDirectory: executableDirectory).first {
            fm.fileExists(atPath: $0.path)
        }
    }

    public static func ensureCLICompatibleMetalLibrary(
        projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        executableDirectory: URL = executableDirectory(),
        progress: ((String) -> Void)? = nil
    ) throws -> URL {
        if let existing = existingMetalLibraryURL(executableDirectory: executableDirectory) {
            return existing
        }

        let devDir = (try? runProcess("/usr/bin/xcode-select", arguments: ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        guard !devDir.isEmpty, devDir != "/Library/Developer/CommandLineTools" else {
            throw MLXMetalLibSupportError.fullXcodeRequired
        }

        let metalStatus = (try? runProcess("/usr/bin/xcodebuild", arguments: ["-showComponent", "MetalToolchain"])) ?? ""
        if metalStatus.contains("Status: uninstalled") {
            throw MLXMetalLibSupportError.metalToolchainMissing
        }

        let configuration = executableDirectory.lastPathComponent.lowercased() == "debug" ? "Debug" : "Release"
        let derivedDataPath = projectRoot.appendingPathComponent(".build/xcode-metal")
        let logPath = derivedDataPath.appendingPathComponent("xcodebuild-metallib.log")

        try FileManager.default.createDirectory(at: derivedDataPath, withIntermediateDirectories: true)
        progress?("Building MLX Metal library with xcodebuild (configuration: \(configuration))")

        do {
            _ = try runProcess(
                "/usr/bin/xcodebuild",
                arguments: [
                    "-scheme", "dikto",
                    "-configuration", configuration,
                    "-destination", "platform=macOS",
                    "-derivedDataPath", derivedDataPath.path,
                    "build"
                ],
                captureTo: logPath
            )
        } catch {
            throw MLXMetalLibSupportError.xcodebuildFailed(logPath: logPath.path)
        }

        let metallibURL = derivedDataPath
            .appendingPathComponent("Build/Products/\(configuration)/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw MLXMetalLibSupportError.metallibNotProduced(metallibURL.path)
        }

        let destination = executableDirectory.appendingPathComponent("mlx.metallib")
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: metallibURL, to: destination)
        progress?("Copied MLX Metal library to \(destination.path)")
        return destination
    }

    @discardableResult
    private static func runProcess(_ launchPath: String, arguments: [String], captureTo file: URL? = nil) throws -> String {
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            let command = ([launchPath] + arguments).map(shellEscape).joined(separator: " ")
            process.arguments = ["-lc", "set -o pipefail; \(command) 2>&1 | tee \(shellEscape(file.path))"]
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()

            let combined = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if process.terminationStatus != 0 {
                throw NSError(domain: "MLXMetalLibSupport", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: combined])
            }
            return combined
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        var combinedData = Data()
        combinedData.append(outData)
        combinedData.append(errData)
        let combined = String(data: combinedData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(domain: "MLXMetalLibSupport", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: combined])
        }

        return combined
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
