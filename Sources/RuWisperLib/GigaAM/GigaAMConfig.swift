import Foundation

/// Configuration for GigaAM v3 CTC model.
public struct GigaAMConfig: Decodable {
    let modelType: String
    let modelName: String
    let sampleRate: Int

    // Preprocessor
    let features: Int
    let winLength: Int
    let hopLength: Int
    let nFFT: Int
    let center: Bool

    // Encoder
    let featIn: Int
    let nLayers: Int
    let dModel: Int
    let subsKernelSize: Int
    let subsamplingFactor: Int
    let ffExpansionFactor: Int
    let nHeads: Int
    let convKernelSize: Int

    // Head
    let numClasses: Int

    // Vocabulary
    let vocabulary: [String]

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case modelName = "model_name"
        case sampleRate = "sample_rate"
        case preprocessor, encoder, head
        case vocabulary
    }

    struct PreprocessorConfig: Decodable {
        let features: Int
        let winLength: Int
        let hopLength: Int
        let nFFT: Int
        let center: Bool

        enum CodingKeys: String, CodingKey {
            case features
            case winLength = "win_length"
            case hopLength = "hop_length"
            case nFFT = "n_fft"
            case center
        }
    }

    struct EncoderConfig: Decodable {
        let featIn: Int
        let nLayers: Int
        let dModel: Int
        let subsKernelSize: Int
        let subsamplingFactor: Int
        let ffExpansionFactor: Int
        let nHeads: Int
        let convKernelSize: Int

        enum CodingKeys: String, CodingKey {
            case featIn = "feat_in"
            case nLayers = "n_layers"
            case dModel = "d_model"
            case subsKernelSize = "subs_kernel_size"
            case subsamplingFactor = "subsampling_factor"
            case ffExpansionFactor = "ff_expansion_factor"
            case nHeads = "n_heads"
            case convKernelSize = "conv_kernel_size"
        }
    }

    struct HeadConfig: Decodable {
        let numClasses: Int

        enum CodingKeys: String, CodingKey {
            case numClasses = "num_classes"
        }
    }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decode(String.self, forKey: .modelType)
        modelName = try container.decode(String.self, forKey: .modelName)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        vocabulary = try container.decode([String].self, forKey: .vocabulary)

        let pre = try container.decode(PreprocessorConfig.self, forKey: .preprocessor)
        features = pre.features
        winLength = pre.winLength
        hopLength = pre.hopLength
        nFFT = pre.nFFT
        center = pre.center

        let enc = try container.decode(EncoderConfig.self, forKey: .encoder)
        featIn = enc.featIn
        nLayers = enc.nLayers
        dModel = enc.dModel
        subsKernelSize = enc.subsKernelSize
        subsamplingFactor = enc.subsamplingFactor
        ffExpansionFactor = enc.ffExpansionFactor
        nHeads = enc.nHeads
        convKernelSize = enc.convKernelSize

        let hd = try container.decode(HeadConfig.self, forKey: .head)
        numClasses = hd.numClasses
    }

    /// Load config from a directory containing config.json.
    static func load(from directory: URL) throws -> GigaAMConfig {
        let configURL = directory.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(GigaAMConfig.self, from: data)
    }
}
