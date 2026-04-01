import Foundation

public struct FoundationModelBenchmarkCase: Equatable, Sendable {
    public let name: String
    public let input: String
    public let expected: String?

    public init(name: String, input: String, expected: String? = nil) {
        self.name = name
        self.input = input
        self.expected = expected
    }
}

public struct FoundationModelBenchmarkOptions: Equatable, Sendable {
    public var text: String?
    public var filePath: String?
    public var runs: Int
    public var localeIdentifier: String?
    public var maxResponseTokens: Int
    public var prewarm: Bool
    public var showHelp: Bool

    public init(
        text: String? = nil,
        filePath: String? = nil,
        runs: Int = 1,
        localeIdentifier: String? = nil,
        maxResponseTokens: Int = 160,
        prewarm: Bool = true,
        showHelp: Bool = false
    ) {
        self.text = text
        self.filePath = filePath
        self.runs = runs
        self.localeIdentifier = localeIdentifier
        self.maxResponseTokens = maxResponseTokens
        self.prewarm = prewarm
        self.showHelp = showHelp
    }

    public static func parse(_ args: [String]) throws -> FoundationModelBenchmarkOptions {
        var options = FoundationModelBenchmarkOptions()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--help", "-h":
                options.showHelp = true
            case "--text":
                index += 1
                guard index < args.count else {
                    throw FoundationModelBenchmarkOptionsError.missingValue(flag: "--text")
                }
                options.text = args[index]
            case "--file":
                index += 1
                guard index < args.count else {
                    throw FoundationModelBenchmarkOptionsError.missingValue(flag: "--file")
                }
                options.filePath = args[index]
            case "--runs":
                index += 1
                guard index < args.count else {
                    throw FoundationModelBenchmarkOptionsError.missingValue(flag: "--runs")
                }
                guard let runs = Int(args[index]), runs > 0 else {
                    throw FoundationModelBenchmarkOptionsError.invalidInteger(flag: "--runs", value: args[index])
                }
                options.runs = runs
            case "--locale":
                index += 1
                guard index < args.count else {
                    throw FoundationModelBenchmarkOptionsError.missingValue(flag: "--locale")
                }
                options.localeIdentifier = args[index]
            case "--max-tokens":
                index += 1
                guard index < args.count else {
                    throw FoundationModelBenchmarkOptionsError.missingValue(flag: "--max-tokens")
                }
                guard let maxTokens = Int(args[index]), maxTokens > 0 else {
                    throw FoundationModelBenchmarkOptionsError.invalidInteger(flag: "--max-tokens", value: args[index])
                }
                options.maxResponseTokens = maxTokens
            case "--no-prewarm":
                options.prewarm = false
            default:
                throw FoundationModelBenchmarkOptionsError.unknownArgument(arg)
            }
            index += 1
        }

        if options.text != nil && options.filePath != nil {
            throw FoundationModelBenchmarkOptionsError.mutuallyExclusiveInputs
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

        return FoundationModelBenchmarkCase.builtInSuite
    }

    public static let help = """
    Benchmark Apple Foundation Models for dictation text cleanup.

    USAGE:
        dikto test-foundation-model [options]

    OPTIONS:
        --text <text>        Benchmark a single custom text
        --file <path>        Benchmark text loaded from a file
        --runs <count>       Repeat the suite or custom text N times (default: 1)
        --locale <locale>    Expected locale, e.g. en-US or ru-RU
        --max-tokens <n>     Maximum response tokens (default: 160)
        --no-prewarm         Disable session prewarm before the benchmark
        --help               Show this help message

    DEFAULT SUITE:
        Runs built-in dictation cleanup samples focused on capitalization,
        punctuation, spelling normalization, and product names.
    """
}

public enum FoundationModelBenchmarkOptionsError: LocalizedError, Equatable {
    case missingValue(flag: String)
    case invalidInteger(flag: String, value: String)
    case mutuallyExclusiveInputs
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidInteger(let flag, let value):
            return "Invalid integer for \(flag): \(value)"
        case .mutuallyExclusiveInputs:
            return "Use either --text or --file, not both"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

extension FoundationModelBenchmarkCase {
    public static let builtInSuite: [FoundationModelBenchmarkCase] = [
        FoundationModelBenchmarkCase(
            name: "swift_tools",
            input: "i shipped the cli in swift with xcode and github actions",
            expected: "I shipped the CLI in Swift with Xcode and GitHub Actions."
        ),
        FoundationModelBenchmarkCase(
            name: "browser_names",
            input: "the bug only happens in safari but chrome looks fine",
            expected: "The bug only happens in Safari, but Chrome looks fine."
        ),
        FoundationModelBenchmarkCase(
            name: "product_names",
            input: "we need to compare whisper cpp against gigaam on apple silicon",
            expected: "We need to compare whisper.cpp against GigaAM on Apple Silicon."
        ),
        FoundationModelBenchmarkCase(
            name: "team_message",
            input: "please ping denis in slack after the test run finishes",
            expected: "Please ping Denis in Slack after the test run finishes."
        ),
        FoundationModelBenchmarkCase(
            name: "docs_formats",
            input: "send the pdf to aleksandr and keep the original markdown in the repo",
            expected: "Send the PDF to Aleksandr and keep the original Markdown in the repo."
        ),
    ]
}

public enum FoundationModelBenchmarkQuality {
    public static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func exactMatch(expected: String, actual: String) -> Bool {
        normalized(expected) == normalized(actual)
    }

    public static func similarity(expected: String, actual: String) -> Double {
        let lhs = Array(normalized(expected))
        let rhs = Array(normalized(actual))

        if lhs.isEmpty && rhs.isEmpty {
            return 1
        }

        let distance = levenshtein(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        return max(0, 1 - (Double(distance) / Double(maxLength)))
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = lhsIndex + 1

            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let cost = lhsCharacter == rhsCharacter ? 0 : 1
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + cost
                )
            }

            previous = current
        }

        return previous[rhs.count]
    }
}
