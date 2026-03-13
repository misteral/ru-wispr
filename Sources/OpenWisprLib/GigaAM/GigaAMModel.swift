import Foundation
import MLX
import MLXNN
import MLXFFT

// MARK: - Activation module (needed for array indexing to match Python weight keys)

/// ReLU as a Module so it occupies an index in arrays (matching Python weight key paths).
private class ReLUModule: Module, UnaryLayer {
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        relu(x)
    }
}

// MARK: - Conv1d Subsampling

/// Conv1d striding subsampling: 2 conv1d layers with stride=2, ReLU.
/// Python structure: self.conv = [Conv1d, ReLU, Conv1d, ReLU]
/// Weight keys: encoder.pre_encode.conv.0.*, encoder.pre_encode.conv.2.*
class Conv1dSubsampling: Module {
    /// Array of [Conv1d, ReLU, Conv1d, ReLU] — indices must match Python keys.
    let conv: [Module]
    let nSubs: Int
    let kernelSize: Int
    let pad: Int

    init(_ cfg: GigaAMConfig) {
        let ks = cfg.subsKernelSize
        let p = (ks - 1) / 2
        let n = Int(log2(Double(cfg.subsamplingFactor)))

        var layers: [Module] = []
        var inCh = cfg.featIn
        for _ in 0 ..< n {
            layers.append(Conv1d(inputChannels: inCh, outputChannels: cfg.dModel,
                                 kernelSize: ks, stride: 2, padding: p))
            layers.append(ReLUModule())
            inCh = cfg.dModel
        }
        self.conv = layers
        self.nSubs = n
        self.kernelSize = ks
        self.pad = p
    }

    func callAsFunction(_ x: MLXArray, lengths: MLXArray) -> (MLXArray, MLXArray) {
        var out = x
        for layer in conv {
            if let c = layer as? Conv1d {
                out = c(out)
            } else if let r = layer as? ReLUModule {
                out = r(out)
            }
        }
        // Compute output lengths
        var lens = lengths.asType(.float32)
        for _ in 0 ..< nSubs {
            lens = MLX.floor((lens + Float(2 * pad - kernelSize)) / 2 + 1)
        }
        return (out, lens.asType(.int32))
    }
}

// MARK: - Rotary Positional Embedding

/// Compute RoPE cos/sin tables for a given sequence length.
func ropeEmbedding(seqLen: Int, dim: Int, base: Float = 10000) -> (MLXArray, MLXArray) {
    let halfDim = dim / 2
    // inv_freq: [halfDim]
    let indices = MLXArray.arange(0, halfDim).asType(.float32)
    let invFreq = 1.0 / MLX.pow(MLXArray(base), indices / Float(halfDim))

    // t: [seqLen]
    let t = MLXArray.arange(seqLen).asType(.float32)

    // freqs: [seqLen, halfDim]
    let freqs = outer(t, invFreq)

    // emb: [seqLen, dim] = [freqs, freqs]
    let emb = concatenated([freqs, freqs], axis: -1)

    return (MLX.cos(emb), MLX.sin(emb))
}

/// Rotate half the hidden dims.
private func rotateHalf(_ x: MLXArray) -> MLXArray {
    let d = x.dim(-1) / 2
    let x1 = x[.ellipsis, ..<d]
    let x2 = x[.ellipsis, d...]
    return concatenated([-x2, x1], axis: -1)
}

// MARK: - Multi-Head Attention with RoPE

/// GigaAM applies RoPE BEFORE linear projections.
class RotaryMultiHeadAttention: Module {
    @ModuleInfo(key: "linear_q") var linearQ: Linear
    @ModuleInfo(key: "linear_k") var linearK: Linear
    @ModuleInfo(key: "linear_v") var linearV: Linear
    @ModuleInfo(key: "linear_out") var linearOut: Linear
    let nHeads: Int
    let dk: Int

    init(dModel: Int, nHeads: Int) {
        self.nHeads = nHeads
        self.dk = dModel / nHeads
        self._linearQ.wrappedValue = Linear(dModel, dModel)
        self._linearK.wrappedValue = Linear(dModel, dModel)
        self._linearV.wrappedValue = Linear(dModel, dModel)
        self._linearOut.wrappedValue = Linear(dModel, dModel)
    }

    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let B = x.dim(0), T = x.dim(1), D = x.dim(2)
        let H = nHeads, dK = dk

        // 1. Reshape raw input to multi-head for RoPE: [B, T, H, dk]
        let xHeads = x.reshaped(B, T, H, dK)

        // 2. Apply RoPE to query and key
        // cos, sin: [T, dk] → [1, T, 1, dk]
        let cosE = cos[0..<T].reshaped(1, T, 1, dK)
        let sinE = sin[0..<T].reshaped(1, T, 1, dK)
        let qRot = (xHeads * cosE + rotateHalf(xHeads) * sinE).reshaped(B, T, D)
        let kRot = (xHeads * cosE + rotateHalf(xHeads) * sinE).reshaped(B, T, D)

        // 3. Project through linear layers
        let q = linearQ(qRot).reshaped(B, T, H, dK).transposed(0, 2, 1, 3)  // [B,H,T,dk]
        let k = linearK(kRot).reshaped(B, T, H, dK).transposed(0, 2, 1, 3)
        let v = linearV(x).reshaped(B, T, H, dK).transposed(0, 2, 1, 3)

        // 4. Scaled dot-product attention
        let scale = MLXArray(Float(1.0 / sqrt(Double(dK))))
        let attn = softmax(q.matmul(k.transposed(0, 1, 3, 2)) * scale, axis: -1)
        let out = attn.matmul(v)  // [B, H, T, dk]
        let outReshaped = out.transposed(0, 2, 1, 3).reshaped(B, T, -1)
        return linearOut(outReshaped)
    }
}

// MARK: - Conformer Convolution

/// Conformer convolution module with LayerNorm.
class ConformerConvolution: Module {
    @ModuleInfo(key: "pointwise_conv1") var pointwiseConv1: Conv1d
    @ModuleInfo(key: "depthwise_conv") var depthwiseConv: Conv1d
    @ModuleInfo(key: "batch_norm") var batchNorm: LayerNorm  // GigaAM v3 uses LayerNorm
    @ModuleInfo(key: "pointwise_conv2") var pointwiseConv2: Conv1d

    init(dModel: Int, kernelSize: Int) {
        let pad = (kernelSize - 1) / 2
        self._pointwiseConv1.wrappedValue = Conv1d(
            inputChannels: dModel, outputChannels: dModel * 2, kernelSize: 1)
        self._depthwiseConv.wrappedValue = Conv1d(
            inputChannels: dModel, outputChannels: dModel, kernelSize: kernelSize,
            padding: pad, groups: dModel)
        self._batchNorm.wrappedValue = LayerNorm(dimensions: dModel)
        self._pointwiseConv2.wrappedValue = Conv1d(
            inputChannels: dModel, outputChannels: dModel, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var out = pointwiseConv1(x)  // [B, T, 2*D]
        let half = out.dim(-1) / 2
        out = out[.ellipsis, ..<half] * sigmoid(out[.ellipsis, half...])  // GLU
        out = depthwiseConv(out)
        out = batchNorm(out)
        out = silu(out)
        out = pointwiseConv2(out)
        return out
    }
}

// MARK: - Conformer Feed-Forward

class ConformerFeedForward: Module {
    @ModuleInfo var linear1: Linear
    @ModuleInfo var linear2: Linear

    init(dModel: Int, dFF: Int) {
        self._linear1.wrappedValue = Linear(dModel, dFF)
        self._linear2.wrappedValue = Linear(dFF, dModel)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        linear2(silu(linear1(x)))
    }
}

// MARK: - Conformer Layer

class ConformerLayer: Module {
    @ModuleInfo(key: "norm_feed_forward1") var normFeedForward1: LayerNorm
    @ModuleInfo(key: "feed_forward1") var feedForward1: ConformerFeedForward
    @ModuleInfo(key: "norm_self_att") var normSelfAtt: LayerNorm
    @ModuleInfo(key: "self_attn") var selfAttn: RotaryMultiHeadAttention
    @ModuleInfo(key: "norm_conv") var normConv: LayerNorm
    let conv: ConformerConvolution
    @ModuleInfo(key: "norm_feed_forward2") var normFeedForward2: LayerNorm
    @ModuleInfo(key: "feed_forward2") var feedForward2: ConformerFeedForward
    @ModuleInfo(key: "norm_out") var normOut: LayerNorm

    init(_ cfg: GigaAMConfig) {
        let d = cfg.dModel
        let dFF = d * cfg.ffExpansionFactor

        self._normFeedForward1.wrappedValue = LayerNorm(dimensions: d)
        self._feedForward1.wrappedValue = ConformerFeedForward(dModel: d, dFF: dFF)
        self._normSelfAtt.wrappedValue = LayerNorm(dimensions: d)
        self._selfAttn.wrappedValue = RotaryMultiHeadAttention(dModel: d, nHeads: cfg.nHeads)
        self._normConv.wrappedValue = LayerNorm(dimensions: d)
        self.conv = ConformerConvolution(dModel: d, kernelSize: cfg.convKernelSize)
        self._normFeedForward2.wrappedValue = LayerNorm(dimensions: d)
        self._feedForward2.wrappedValue = ConformerFeedForward(dModel: d, dFF: dFF)
        self._normOut.wrappedValue = LayerNorm(dimensions: d)
    }

    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        // FF1
        var residual = x
        var h = normFeedForward1(x)
        h = feedForward1(h)
        residual = residual + h * 0.5

        // Self-attention
        h = normSelfAtt(residual)
        h = selfAttn(h, cos: cos, sin: sin)
        residual = residual + h

        // Conv
        h = normConv(residual)
        h = conv(h)
        residual = residual + h

        // FF2
        h = normFeedForward2(residual)
        h = feedForward2(h)
        residual = residual + h * 0.5

        return normOut(residual)
    }
}

// MARK: - Conformer Encoder

class ConformerEncoder: Module {
    @ModuleInfo(key: "pre_encode") var preEncode: Conv1dSubsampling
    let layers: [ConformerLayer]
    let headDim: Int

    init(_ cfg: GigaAMConfig) {
        self._preEncode.wrappedValue = Conv1dSubsampling(cfg)
        self.layers = (0 ..< cfg.nLayers).map { _ in ConformerLayer(cfg) }
        self.headDim = cfg.dModel / cfg.nHeads
    }

    func callAsFunction(_ features: MLXArray, lengths: MLXArray) -> (MLXArray, MLXArray) {
        var (x, lens) = preEncode(features, lengths: lengths)
        let T = x.dim(1)
        let (cos, sin) = ropeEmbedding(seqLen: T, dim: headDim)
        for layer in layers {
            x = layer(x, cos: cos, sin: sin)
        }
        return (x, lens)
    }
}

// MARK: - CTC Head

/// CTC decoder head: Conv1d(d_model, num_classes, kernel=1).
class CTCHead: Module {
    @ModuleInfo(key: "decoder_layers") var decoderLayers: [Conv1d]

    init(featIn: Int, numClasses: Int) {
        self._decoderLayers.wrappedValue = [
            Conv1d(inputChannels: featIn, outputChannels: numClasses, kernelSize: 1)
        ]
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        softmax(decoderLayers[0](x), axis: -1)
    }
}

// MARK: - Full GigaAM CTC Model

class GigaAMCTCModel: Module {
    let encoder: ConformerEncoder
    let head: CTCHead
    let config: GigaAMConfig

    // Preprocessing arrays (loaded from weights, not Module parameters)
    var melFilterbank: MLXArray?
    var stftWindow: MLXArray?

    init(_ cfg: GigaAMConfig) {
        self.config = cfg
        self.encoder = ConformerEncoder(cfg)
        self.head = CTCHead(featIn: cfg.dModel, numClasses: cfg.numClasses)
    }

    func callAsFunction(_ features: MLXArray, lengths: MLXArray) -> (MLXArray, MLXArray) {
        let (encoded, encLengths) = encoder(features, lengths: lengths)
        let logProbs = head(encoded)
        return (logProbs, encLengths)
    }

    // MARK: - Audio Preprocessing

    func computeFeatures(_ audio: MLXArray) -> (MLXArray, MLXArray) {
        let mel = logMelSpectrogram(audio)
        let melBatched = expandedDimensions(mel, axis: 0)  // [1, T, features]
        let lengths = MLXArray([Int32(mel.dim(0))])
        return (melBatched, lengths)
    }

    private func logMelSpectrogram(_ audio: MLXArray) -> MLXArray {
        let window = stftWindow ?? hanningWindow(config.winLength)
        let spec = stft(audio, window: window)
        let power = spec.abs().square()  // |spec|^2, [T, n_fft/2+1]
        let filters = melFilterbank ?? buildMelFilters()
        let mel = power.matmul(filters)  // [T, n_mels]
        return MLX.log(clip(mel, min: 1e-9, max: 1e9))
    }

    private func stft(_ signal: MLXArray, window: MLXArray) -> MLXArray {
        let winLen = config.winLength
        let hop = config.hopLength
        let nFFT = config.nFFT
        let length = signal.dim(-1)
        let nFrames = 1 + (length - winLen) / hop

        // Build frame indices: [nFrames, winLen]
        let frameOffsets = MLXArray.arange(nFrames) * Int32(hop)  // [nFrames]
        let winIndices = MLXArray.arange(winLen)  // [winLen]
        let indices = expandedDimensions(frameOffsets, axis: 1) + expandedDimensions(winIndices, axis: 0)

        // Gather frames and apply window
        var frames = signal.take(indices.flattened(), axis: 0).reshaped(nFrames, winLen) * window

        // Zero-pad to n_fft if needed
        if winLen < nFFT {
            frames = padded(frames, widths: [.init((0, 0)), .init((0, nFFT - winLen))])
        }

        // Real FFT along last axis
        return MLXFFT.rfft(frames, axis: -1)  // [nFrames, nFFT/2+1]
    }

    private func hanningWindow(_ size: Int) -> MLXArray {
        let n = MLXArray.arange(size).asType(.float32)
        return 0.5 - 0.5 * MLX.cos(2.0 * Float.pi * n / Float(size))
    }

    private func buildMelFilters() -> MLXArray {
        let sr = Float(config.sampleRate)
        let nFFT = config.nFFT
        let nMels = config.features

        func hzToMel(_ f: Float) -> Float { 2595.0 * log10(1.0 + f / 700.0) }
        func melToHz(_ m: Float) -> Float { 700.0 * (pow(10.0, m / 2595.0) - 1.0) }

        let melMin = hzToMel(0)
        let melMax = hzToMel(sr / 2)

        var melPoints = [Float]()
        for i in 0 ..< nMels + 2 {
            melPoints.append(melMin + Float(i) * (melMax - melMin) / Float(nMels + 1))
        }
        let hzPoints = melPoints.map { melToHz($0) }
        let bins = hzPoints.map { Int(floor(Float(nFFT + 1) * $0 / sr)) }

        var fb = [[Float]](repeating: [Float](repeating: 0, count: nMels), count: nFFT / 2 + 1)
        for i in 0 ..< nMels {
            let lo = bins[i], mid = bins[i + 1], hi = bins[i + 2]
            for k in lo ..< mid where mid != lo {
                fb[k][i] = Float(k - lo) / Float(mid - lo)
            }
            for k in mid ..< hi where hi != mid {
                fb[k][i] = Float(hi - k) / Float(hi - mid)
            }
        }

        return MLXArray(fb.flatMap { $0 }, [nFFT / 2 + 1, nMels])
    }

    // MARK: - CTC Decoding

    func ctcDecode(_ logProbs: MLXArray, encLength: Int) -> String {
        let vocab = config.vocabulary
        let blankId = vocab.count  // blank is index after vocabulary

        let labels = logProbs.argMax(axis: -1)  // [T]
        eval(labels)

        var result: [Int] = []
        var prev = -1
        for t in 0 ..< min(labels.dim(0), encLength) {
            let label = labels[t].item(Int.self)
            if label == blankId {
                prev = label
                continue
            }
            if label == prev {
                continue
            }
            result.append(label)
            prev = label
        }

        return result.map { idx in
            idx < vocab.count ? vocab[idx] : ""
        }.joined()
    }

    // MARK: - Transcribe

    func transcribe(_ audio: MLXArray) -> String {
        let (mel, lengths) = computeFeatures(audio)
        let (logProbs, encLengths) = self(mel, lengths: lengths)
        eval(logProbs, encLengths)
        return ctcDecode(logProbs[0], encLength: encLengths[0].item(Int.self))
    }
}

// MARK: - Model Loading

func loadGigaAMModel(from directory: URL) throws -> GigaAMCTCModel {
    let cfg = try GigaAMConfig.load(from: directory)
    let model = GigaAMCTCModel(cfg)

    let weightsURL = directory.appendingPathComponent("model.safetensors")
    var weights = try loadArrays(url: weightsURL)

    // Extract preprocessing arrays (not part of Module tree)
    let melFB = weights.removeValue(forKey: "mel_filterbank")
    let stftWin = weights.removeValue(forKey: "stft_window")

    if let melFB {
        model.melFilterbank = melFB.asType(.float32)
    }
    if let stftWin {
        model.stftWindow = stftWin.asType(.float32)
    }

    // Build nested parameter dictionary from flat "a.b.c" keys
    let parameters = ModuleParameters.unflattened(weights)

    try model.update(parameters: parameters, verify: .noUnusedKeys)
    eval(model)
    return model
}
