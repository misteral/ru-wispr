import XCTest
@testable import DiktoLib

final class TextPostProcessingProviderTests: XCTestCase {

    func testFactoryReturnsPassthroughWhenSpokenPunctuationDisabled() {
        var config = Config.defaultConfig
        config.spokenPunctuation = FlexBool(false)

        let provider = TextPostProcessingProviderFactory.make(config: config)
        XCTAssertEqual(provider.name, "passthrough")
    }

    func testFactoryReturnsSpokenPunctuationProviderWhenEnabled() {
        var config = Config.defaultConfig
        config.spokenPunctuation = FlexBool(true)

        let provider = TextPostProcessingProviderFactory.make(config: config)
        XCTAssertEqual(provider.name, "spoken-punctuation")
    }

    func testFactoryReturnsLocalLLMProviderWhenConfigured() {
        var config = Config.defaultConfig
        config.postProcessingProvider = "local-llm"

        let provider = TextPostProcessingProviderFactory.make(config: config)
        XCTAssertEqual(provider.name, "local-llm")
    }

    func testFactoryBuildsSequentialPipeline() {
        var config = Config.defaultConfig
        config.spokenPunctuation = FlexBool(true)
        config.postProcessingProvider = "local-llm"

        let provider = TextPostProcessingProviderFactory.make(config: config)
        XCTAssertEqual(provider.name, "spoken-punctuation + local-llm")
    }

    func testContextReflectsConfig() {
        var config = Config.defaultConfig
        config.language = "ru"
        config.spokenPunctuation = FlexBool(true)

        let context = TextPostProcessingProviderFactory.context(config: config)
        XCTAssertEqual(context, TextPostProcessingContext(language: "ru", spokenPunctuationEnabled: true))
    }
}
