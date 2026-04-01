import Foundation
import DiktoLib

struct Options {
    var datasetPath = "eval/datasets/text-postprocessing-v1.jsonl"
    var modelsPath = "eval/models/local-llm-candidates.json"
    var outputPath: String?
    var runs = 1
    var language = "ru"
    var filter: String?
    var limit: Int?
    var maxTokens: Int?
    var temperature: Float?
    var timeoutMs: Int?
    var listModels = false
    var listDataset = false
    var help = false

    static func parse(_ args: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--dataset":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--dataset") }
                options.datasetPath = args[index]
            case "--models":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--models") }
                options.modelsPath = args[index]
            case "--output":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--output") }
                options.outputPath = args[index]
            case "--runs":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--runs") }
                guard let value = Int(args[index]), value > 0 else { throw ParseError.invalidInteger("--runs", args[index]) }
                options.runs = value
            case "--language":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--language") }
                options.language = args[index]
            case "--filter":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--filter") }
                options.filter = args[index]
            case "--limit":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--limit") }
                guard let value = Int(args[index]), value > 0 else { throw ParseError.invalidInteger("--limit", args[index]) }
                options.limit = value
            case "--max-tokens":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--max-tokens") }
                guard let value = Int(args[index]), value > 0 else { throw ParseError.invalidInteger("--max-tokens", args[index]) }
                options.maxTokens = value
            case "--temperature":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--temperature") }
                guard let value = Float(args[index]), value >= 0 else { throw ParseError.invalidFloat("--temperature", args[index]) }
                options.temperature = value
            case "--timeout-ms":
                index += 1
                guard index < args.count else { throw ParseError.missingValue("--timeout-ms") }
                guard let value = Int(args[index]), value > 0 else { throw ParseError.invalidInteger("--timeout-ms", args[index]) }
                options.timeoutMs = value
            case "--list-models":
                options.listModels = true
            case "--list-dataset":
                options.listDataset = true
            case "--help", "-h":
                options.help = true
            default:
                throw ParseError.unknownArgument(arg)
            }
            index += 1
        }
        return options
    }

    static let usage = """
    dikto-eval — evaluate MLX local LLM cleanup models

    USAGE:
        .build/release/dikto-eval [options]

    OPTIONS:
        --dataset <path>       Dataset JSONL (default: eval/datasets/text-postprocessing-v1.jsonl)
        --models <path>        Models JSON (default: eval/models/local-llm-candidates.json)
        --output <path>        Output report JSON path
        --runs <n>             Repeat each case N times (default: 1)
        --language <code>      Language hint for prompts (default: ru)
        --filter <text>        Evaluate only models whose id/path contains the text
        --limit <n>            Evaluate only the first N filtered models
        --max-tokens <n>       Override generation max tokens
        --temperature <n>      Override generation temperature
        --timeout-ms <n>       Override per-case timeout
        --list-models          Print model candidates and exit
        --list-dataset         Print dataset cases and exit
        --help                 Show this help
    """
}

enum ParseError: LocalizedError {
    case missingValue(String)
    case invalidInteger(String, String)
    case invalidFloat(String, String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag): return "Missing value for \(flag)"
        case .invalidInteger(let flag, let value): return "Invalid integer for \(flag): \(value)"
        case .invalidFloat(let flag, let value): return "Invalid float for \(flag): \(value)"
        case .unknownArgument(let argument): return "Unknown argument: \(argument)"
        }
    }
}

struct EvalRunReport: Encodable {
    let createdAt: String
    let runs: Int
    let language: String
    let datasetPath: String
    let modelsPath: String
    let modelReports: [LocalLLMEvalModelReport]
}

func formatSeconds(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return value.formatted(.number.precision(.fractionLength(3))) + "s"
}

func defaultOutputPath() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    return "eval/results/local-llm-eval-\(timestamp).json"
}

func printModels(_ models: [LocalLLMEvalModel]) {
    for model in models {
        print("- [\(model.priority)] \(model.sourceDescription)")
        print("  family=\(model.family), size=\(model.sizeLabel)")
        if let downloads = model.downloads {
            print("  downloads=\(downloads)")
        }
        if let notes = model.notes {
            print("  notes=\(notes)")
        }
    }
}

func printDataset(_ dataset: [LocalLLMEvalCase]) {
    for item in dataset {
        print("- \(item.id): \(item.input)")
        print("  expected: \(item.expected)")
        if !item.tags.isEmpty {
            print("  tags: \(item.tags.joined(separator: ", "))")
        }
    }
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

@main
struct Main {
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            if options.help {
                print(Options.usage)
                return
            }

            let datasetURL = URL(fileURLWithPath: options.datasetPath)
            let modelsURL = URL(fileURLWithPath: options.modelsPath)

            let dataset = try LocalLLMEvaluationLoader.loadDataset(from: datasetURL)
            let allModels = try LocalLLMEvaluationLoader.loadModels(from: modelsURL)

            if options.listDataset {
                printDataset(dataset)
                return
            }

            if options.listModels {
                printModels(allModels)
                return
            }

            var models = allModels
            if let filter = options.filter?.lowercased(), !filter.isEmpty {
                models = models.filter { $0.sourceDescription.lowercased().contains(filter) }
            }
            if let limit = options.limit {
                models = Array(models.prefix(limit))
            }

            guard !models.isEmpty else {
                print("No models selected")
                exit(1)
            }

            print("Dataset: \(datasetURL.path) (\(dataset.count) cases)")
            print("Models:  \(modelsURL.path) (\(models.count) selected)")
            print("Runs:    \(options.runs)")
            print("Language:\(options.language)")
            do {
                let metallibURL = try MLXMetalLibSupport.ensureCLICompatibleMetalLibrary { message in
                    print(message)
                }
                print("Metal lib: \(metallibURL.path)")
            } catch {
                fputs("Error preparing MLX Metal library: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            print("")

            var reports: [LocalLLMEvalModelReport] = []
            for (index, model) in models.enumerated() {
                print("=== Model \(index + 1)/\(models.count): \(model.sourceDescription) ===")
                let logState = LocalLLMModelLoadLogState()
                let report = try await LocalLLMEvaluator.evaluate(
                    model: model,
                    dataset: dataset,
                    language: options.language,
                    runs: options.runs,
                    maxTokens: options.maxTokens,
                    temperature: options.temperature,
                    timeoutMs: options.timeoutMs
                ) { event in
                    switch event {
                    case .loadingModel(let model):
                        print("Loading model: \(model.sourceDescription)")
                        print("Resolving model snapshot (cache or download)...")
                    case .modelDownloadProgress(_, let completedUnitCount, let totalUnitCount):
                        guard totalUnitCount > 0 else { return }
                        if completedUnitCount >= totalUnitCount, totalUnitCount <= 1024 {
                            print("Model snapshot: already available locally")
                            if logState.markWeightLoadingIfNeeded() {
                                print("Loading model weights into MLX...")
                            }
                        } else {
                            let percent = Double(completedUnitCount) / Double(totalUnitCount) * 100
                            print("Downloading model snapshot: \(percent.formatted(.number.precision(.fractionLength(1))))%")
                            if completedUnitCount >= totalUnitCount, logState.markWeightLoadingIfNeeded() {
                                print("Loading model weights into MLX...")
                            }
                        }
                    case .modelLoaded(_, let durationSeconds):
                        if logState.markWeightLoadingIfNeeded() {
                            print("Loading model weights into MLX...")
                        }
                        print("Model ready in \(formatSeconds(durationSeconds))")
                    case .startingCase(_, let evalCase, let runIndex, let totalRuns):
                        print("Starting [\(runIndex)/\(totalRuns)] \(evalCase.id)")
                    case .finishedCase(_, let evalCase, let runIndex, let totalRuns, let durationSeconds):
                        print("Finished [\(runIndex)/\(totalRuns)] \(evalCase.id) in \(formatSeconds(durationSeconds))")
                    }
                }

                reports.append(report)
                let exactRate = (report.exactMatchRate * 100).formatted(.number.precision(.fractionLength(1)))
                let avgSimilarity = (report.averageSimilarity * 100).formatted(.number.precision(.fractionLength(1)))
                print("Summary: exact=\(exactRate)% similarity=\(avgSimilarity)% avgTotal=\(formatSeconds(report.averageDurationSeconds)) avgTTFT=\(formatSeconds(report.averageTimeToFirstChunkSeconds))")
                print("")
            }

            let sorted = reports.sorted {
                if $0.averageSimilarity == $1.averageSimilarity {
                    return $0.averageDurationSeconds < $1.averageDurationSeconds
                }
                return $0.averageSimilarity > $1.averageSimilarity
            }

            print("=== Final ranking ===")
            for (rank, report) in sorted.enumerated() {
                let exactRate = (report.exactMatchRate * 100).formatted(.number.precision(.fractionLength(1)))
                let avgSimilarity = (report.averageSimilarity * 100).formatted(.number.precision(.fractionLength(1)))
                print("\(rank + 1). \(report.model.sourceDescription)")
                print("   exact=\(exactRate)% similarity=\(avgSimilarity)% avgTotal=\(formatSeconds(report.averageDurationSeconds)) avgTTFT=\(formatSeconds(report.averageTimeToFirstChunkSeconds))")
            }

            let outputPath = options.outputPath ?? defaultOutputPath()
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let payload = EvalRunReport(
                createdAt: ISO8601DateFormatter().string(from: Date()),
                runs: options.runs,
                language: options.language,
                datasetPath: datasetURL.path,
                modelsPath: modelsURL.path,
                modelReports: reports
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: outputURL)
            print("")
            print("Wrote report: \(outputURL.path)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            fputs(Options.usage + "\n", stderr)
            exit(1)
        }
    }
}
