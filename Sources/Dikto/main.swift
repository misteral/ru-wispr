import AppKit
import Foundation
import Dispatch
import DiktoLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = Dikto.version

func printUsage() {
    print("""
    dikto v\(version) — Push-to-talk voice dictation for macOS

    USAGE:
        dikto start              Start the dictation daemon
        dikto set-hotkey <key>   Set the push-to-talk hotkey
        dikto get-hotkey         Show current hotkey
        dikto set-model <size>   Set the Whisper model
        dikto download-model [size]  Download a Whisper model
        dikto status             Show configuration and status
        dikto test-foundation-model [options]  Benchmark Apple Foundation Models text cleanup
        dikto test-local-llm [options]  Benchmark MLX local LLM text cleanup
        dikto --help             Show this help message

    HOTKEY EXAMPLES:
        dikto set-hotkey rightoption       Right Option key (default)
        dikto set-hotkey globe             Globe/fn key
        dikto set-hotkey f5                 F5 key
        dikto set-hotkey ctrl+space         Ctrl + Space

    ENGINES:
        whisper    Use whisper-cpp (default)
        gigaam     Use GigaAM v3 via MLX (Russian, fast on Apple Silicon)

    AVAILABLE MODELS (whisper):
        tiny.en, tiny, base.en, base, small.en, small, medium.en, medium, large
    """)
}

func cmdStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping dikto...")
        exit(0)
    }

    app.run()
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'dikto --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetModel(_ size: String) {
    let validSizes = ["tiny.en", "tiny", "base.en", "base", "small.en", "small", "medium.en", "medium", "large"]
    guard validSizes.contains(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \(validSizes.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.modelSize = size

    do {
        try config.save()
        print("Model set to: \(size)")
        if !Transcriber.modelExists(modelSize: size) {
            print("Model will be downloaded on next start.")
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    let config = Config.load()
    let desc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
    print("Current hotkey: \(desc)")
}

func cmdDownloadModel(_ size: String) {
    do {
        try ModelDownloader.download(modelSize: size)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetEngine(_ engine: String) {
    let valid = ["whisper", "gigaam"]
    guard valid.contains(engine) else {
        print("Error: Unknown engine '\(engine)'")
        print("Available: \(valid.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.engine = engine
    if engine == "gigaam" {
        config.language = "ru"
    }

    do {
        try config.save()
        print("Engine set to: \(engine)")
        if engine == "gigaam" {
            if GigaAMTranscriber.isAvailable(path: config.gigaamPath) {
                print("GigaAM: model found (native MLX)")
            } else {
                print("GigaAM: model not found. Set 'gigaamPath' to gigaam-v3-ctc-mlx directory")
            }
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)

    print("dikto v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Data:        \(Config.dataDir.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Engine:      \(config.effectiveEngine)")
    print("Post-proc:   \(TextPostProcessingProviderFactory.make(config: config).name)")
    if config.effectivePostProcessingProvider == "local-llm" {
        let source = config.postProcessingModelPath ?? config.effectivePostProcessingModelID
        print("Post-proc model: \(source)")
        print("Post-proc timeout: \(config.effectivePostProcessingTimeoutMs) ms")
    }
    if config.effectiveEngine == "gigaam" {
        let gigaamReady = GigaAMTranscriber.isAvailable(path: config.gigaamPath)
        print("GigaAM:      \(gigaamReady ? "ready (native MLX)" : "not found")")
        let modelPath = config.gigaamPath ?? GigaAMTranscriber.defaultModelDir.path
        print("GigaAM path: \(modelPath)")
    } else {
        print("Model:       \(config.modelSize)")
        print("Model ready: \(Transcriber.modelExists(modelSize: config.modelSize) ? "yes" : "no")")
        print("whisper-cpp: \(Transcriber.findWhisperBinary() != nil ? "yes" : "no")")
    }
}

func formatSeconds(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return value.formatted(.number.precision(.fractionLength(3))) + "s"
}

final class LocalLLMModelLoadLogState: @unchecked Sendable {
    private let lock = NSLock()
    private var didReportWeightLoading = false

    func markWeightLoadingIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didReportWeightLoading {
            return false
        }
        didReportWeightLoading = true
        return true
    }
}

func cmdTestLocalLLM(_ rawArgs: [String]) {
    do {
        let options = try LocalLLMPostProcessingBenchmarkOptions.parse(rawArgs)
        if options.showHelp {
            print(LocalLLMPostProcessingBenchmarkOptions.help)
            return
        }

        do {
            let metallibURL = try MLXMetalLibSupport.ensureCLICompatibleMetalLibrary { message in
                print(message)
            }
            print("Using MLX Metal library: \(metallibURL.path)")
        } catch {
            print("Error preparing MLX Metal library: \(error.localizedDescription)")
            exit(1)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task {
            defer { semaphore.signal() }
            do {
                let logState = LocalLLMModelLoadLogState()
                let report = try await LocalLLMPostProcessingBenchmarkRunner.run(options: options) { event in
                    switch event {
                    case .loadingModel(let source):
                        print("Loading local LLM model: \(source)")
                        print("Resolving model snapshot (cache or download)...")
                    case .modelDownloadProgress(let completedUnitCount, let totalUnitCount):
                        guard totalUnitCount > 0 else { return }
                        if completedUnitCount >= totalUnitCount, totalUnitCount <= 1024 {
                            print("Model snapshot: already available locally")
                            if logState.markWeightLoadingIfNeeded() {
                                print("Loading model weights into MLX...")
                            }
                        } else {
                            let percent = (Double(completedUnitCount) / Double(totalUnitCount) * 100)
                            print(
                                "Downloading model snapshot: \(percent.formatted(.number.precision(.fractionLength(1))))%"
                            )
                            if completedUnitCount >= totalUnitCount, logState.markWeightLoadingIfNeeded() {
                                print("Loading model weights into MLX...")
                            }
                        }
                    case .modelLoaded(let durationSeconds):
                        if logState.markWeightLoadingIfNeeded() {
                            print("Loading model weights into MLX...")
                        }
                        print("Model ready in \(formatSeconds(durationSeconds))")
                    case .startingCase(let runIndex, let totalRuns, let caseName):
                        print("Starting case [\(runIndex)/\(totalRuns)]: \(caseName)")
                    case .finishedCase(let runIndex, let totalRuns, let caseName, let totalDurationSeconds):
                        print("Finished case [\(runIndex)/\(totalRuns)]: \(caseName) in \(formatSeconds(totalDurationSeconds))")
                    }
                }
                let benchmarkCases = try options.benchmarkCases()
                print("")
                print("Local LLM benchmark")
                print("Model:        \(report.configuration.sourceDescription)")
                print("Language:     \(options.language)")
                print("Load:         \(formatSeconds(report.loadDurationSeconds))")
                print("Cases:        \(benchmarkCases.count) × runs: \(options.runs)")
                print("Temperature:  \(options.temperature)")
                print("Max tokens:   \(options.maxTokens)")
                print("Timeout:      \(options.timeoutMs) ms")
                print("")

                for result in report.results {
                    print("[run \(result.runIndex)] \(result.benchmarkCase.name)")
                    print("Input:    \(result.benchmarkCase.input)")
                    if let expected = result.benchmarkCase.expected {
                        print("Expected: \(expected)")
                    }
                    print("Output:   \(result.output)")
                    print("TTFT:     \(formatSeconds(result.timeToFirstChunkSeconds))")
                    print("Total:    \(formatSeconds(result.totalDurationSeconds))")
                    if let info = result.completionInfo {
                        print("Tokens:   prompt=\(info.promptTokenCount), generated=\(info.generationTokenCount), tok/s=\(info.tokensPerSecond.formatted(.number.precision(.fractionLength(1))))")
                    }
                    if let exactMatch = result.exactMatch, let similarity = result.similarity {
                        let similarityPercent = (similarity * 100).formatted(.number.precision(.fractionLength(1)))
                        print("Quality:  exact=\(exactMatch ? "yes" : "no"), similarity=\(similarityPercent)%")
                    }
                    print("")
                }

                print("Summary")
                print("Average TTFT:  \(formatSeconds(report.averageTimeToFirstChunkSeconds))")
                print("Average total: \(formatSeconds(report.averageTotalDurationSeconds))")
                if report.scoredResults > 0 {
                    print("Exact matches: \(report.exactMatches)/\(report.scoredResults)")
                }
                if let averageSimilarity = report.averageSimilarity {
                    let similarityPercent = (averageSimilarity * 100).formatted(.number.precision(.fractionLength(1)))
                    print("Avg similarity: \(similarityPercent)%")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
                exitCode = 1
            }
        }

        semaphore.wait()
        if exitCode != 0 {
            exit(exitCode)
        }
    } catch {
        print("Error: \(error.localizedDescription)")
        print(LocalLLMPostProcessingBenchmarkOptions.help)
        exit(1)
    }
}

func cmdTestFoundationModel(_ rawArgs: [String]) {
    do {
        let options = try FoundationModelBenchmarkOptions.parse(rawArgs)
        if options.showHelp {
            print(FoundationModelBenchmarkOptions.help)
            return
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let environment = FoundationModelBenchmarkRunner.environment(localeIdentifier: options.localeIdentifier)
            print("Foundation Models benchmark")
            print("Availability: \(environment.availabilityDescription)")
            if let locale = environment.requestedLocaleIdentifier {
                let supported = environment.requestedLocaleSupported == true ? "yes" : "no"
                print("Requested locale: \(locale) (supported: \(supported))")
            }
            print("Supported languages: \(environment.supportedLanguageIdentifiers.joined(separator: ", "))")

            if environment.supportedLanguageIdentifiers.allSatisfy({ !$0.hasPrefix("ru") }) {
                print("Note: Russian is not advertised as a supported Foundation Models language on this system.")
            }

            let semaphore = DispatchSemaphore(value: 0)
            var exitCode: Int32 = 0

            Task {
                defer { semaphore.signal() }
                do {
                    let report = try await FoundationModelBenchmarkRunner.run(options: options)
                    let benchmarkCases = try options.benchmarkCases()
                    print("Cases: \(benchmarkCases.count) × runs: \(options.runs)")
                    print("Prewarm: \(options.prewarm ? "on" : "off")")
                    print("")

                    for result in report.results {
                        print("[run \(result.runIndex)] \(result.benchmarkCase.name)")
                        print("Input:    \(result.benchmarkCase.input)")
                        if let expected = result.benchmarkCase.expected {
                            print("Expected: \(expected)")
                        }
                        print("Output:   \(result.output)")
                        print("TTFT:     \(formatSeconds(result.timeToFirstTokenSeconds))")
                        print("Total:    \(formatSeconds(result.totalDurationSeconds))")
                        if let exactMatch = result.exactMatch, let similarity = result.similarity {
                            let similarityPercent = (similarity * 100).formatted(.number.precision(.fractionLength(1)))
                            print("Quality:  exact=\(exactMatch ? "yes" : "no"), similarity=\(similarityPercent)%")
                        }
                        print("")
                    }

                    print("Summary")
                    print("Average TTFT:  \(formatSeconds(report.averageTimeToFirstTokenSeconds))")
                    print("Average total: \(formatSeconds(report.averageTotalDurationSeconds))")
                    if report.scoredResults > 0 {
                        print("Exact matches: \(report.exactMatches)/\(report.scoredResults)")
                    }
                    if let averageSimilarity = report.averageSimilarity {
                        let similarityPercent = (averageSimilarity * 100).formatted(.number.precision(.fractionLength(1)))
                        print("Avg similarity: \(similarityPercent)%")
                    }
                } catch {
                    print("Error: \(error.localizedDescription)")
                    exitCode = 1
                }
            }

            semaphore.wait()
            if exitCode != 0 {
                exit(exitCode)
            }
            return
        }
        #endif

        print("Foundation Models requires macOS 26 and Xcode 26 SDK.")
        exit(1)
    } catch {
        print("Error: \(error.localizedDescription)")
        print(FoundationModelBenchmarkOptions.help)
        exit(1)
    }
}

let args = CommandLine.arguments

// Filter out macOS launch services arguments (e.g. -NSDocumentRevisionsDebugMode, -psn_...)
let userArgs = args.dropFirst().filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") && !$0.hasPrefix("-psn") }
let command = userArgs.first

// When launched as .app bundle (no arguments), auto-start
let isAppBundle = Bundle.main.bundlePath.hasSuffix(".app")

switch command {
case "start":
    cmdStart()
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: dikto set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-model":
    guard args.count > 2 else {
        print("Usage: dikto set-model <size>")
        exit(1)
    }
    cmdSetModel(args[2])
case "set-engine":
    guard args.count > 2 else {
        print("Usage: dikto set-engine <whisper|gigaam>")
        exit(1)
    }
    cmdSetEngine(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "download-model":
    let size = args.count > 2 ? args[2] : "base.en"
    cmdDownloadModel(size)
case "status":
    cmdStatus()
case "test-foundation-model":
    cmdTestFoundationModel(Array(userArgs.dropFirst()))
case "test-local-llm":
    cmdTestLocalLLM(Array(userArgs.dropFirst()))
case "test-gigaam":
    let audioFile = args.count > 2 ? args[2] : nil
    let config = Config.load()
    let transcriber = GigaAMTranscriber(modelPath: config.gigaamPath)
    do {
        let t0 = CFAbsoluteTimeGetCurrent()
        try transcriber.loadModel()
        let loadDuration = CFAbsoluteTimeGetCurrent() - t0
        print("Model loaded in \(loadDuration.formatted(.number.precision(.fractionLength(2))))s")

        if let file = audioFile {
            let t1 = CFAbsoluteTimeGetCurrent()
            let text = try transcriber.transcribe(audioURL: URL(filePath: file))
            let transcribeDuration = CFAbsoluteTimeGetCurrent() - t1
            print("Transcribed in \(transcribeDuration.formatted(.number.precision(.fractionLength(2))))s")
            print("Result: \(text)")
        } else {
            print("GigaAM: ready (native MLX)")
            print("Usage: dikto test-gigaam <audio-file>")
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
case "--help", "-h", "help":
    printUsage()
case nil:
    if isAppBundle {
        cmdStart()
    } else {
        printUsage()
    }
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
