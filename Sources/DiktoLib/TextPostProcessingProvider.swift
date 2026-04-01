import Foundation

public struct TextPostProcessingContext: Sendable, Equatable {
    public let language: String
    public let spokenPunctuationEnabled: Bool

    public init(language: String, spokenPunctuationEnabled: Bool) {
        self.language = language
        self.spokenPunctuationEnabled = spokenPunctuationEnabled
    }
}

public protocol TextPostProcessingProvider: Sendable {
    var name: String { get }
    func process(_ text: String, context: TextPostProcessingContext) async throws -> String
}

public struct PassthroughTextPostProcessingProvider: TextPostProcessingProvider {
    public let name = "passthrough"

    public init() {}

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        text
    }
}

public struct SpokenPunctuationTextPostProcessingProvider: TextPostProcessingProvider {
    public let name = "spoken-punctuation"

    public init() {}

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        TextPostProcessor.process(text)
    }
}

public struct SequentialTextPostProcessingProvider: TextPostProcessingProvider {
    public let providers: [any TextPostProcessingProvider]
    public let name: String

    public init(providers: [any TextPostProcessingProvider]) {
        self.providers = providers
        self.name = providers.map(\.name).joined(separator: " + ")
    }

    public func process(_ text: String, context: TextPostProcessingContext) async throws -> String {
        var current = text
        for provider in providers {
            current = try await provider.process(current, context: context)
        }
        return current
    }
}

public enum TextPostProcessingProviderFactory {
    public static func make(config: Config) -> any TextPostProcessingProvider {
        var providers: [any TextPostProcessingProvider] = []

        if config.spokenPunctuation?.value ?? false {
            providers.append(SpokenPunctuationTextPostProcessingProvider())
        }

        if config.effectivePostProcessingProvider == "local-llm" {
            providers.append(MLXLocalLLMTextPostProcessingProvider(configuration: .from(config: config)))
        }

        switch providers.count {
        case 0:
            return PassthroughTextPostProcessingProvider()
        case 1:
            return providers[0]
        default:
            return SequentialTextPostProcessingProvider(providers: providers)
        }
    }

    public static func context(config: Config) -> TextPostProcessingContext {
        TextPostProcessingContext(
            language: config.language,
            spokenPunctuationEnabled: config.spokenPunctuation?.value ?? false
        )
    }
}
