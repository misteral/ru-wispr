import SwiftUI

// MARK: - Waveform Canvas (audio history timeline)

/// Draws a mirrored bar waveform from a rolling audio level history.
/// Left = oldest samples, right = most recent — like a recording timeline.
struct WaveformCanvas: View {
    /// Rolling audio level history from AudioLevelHistory
    var levels: [Float]
    var offset: Int = 0

    private let barWidth: Double = 1.0
    private let spacing: Double = 0.8

    var body: some View {
        Canvas { context, size in
            let barCount = levels.count
            guard barCount > 0 else { return }

            let totalWidth = Double(barCount) * barWidth + Double(barCount - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            let centerY = size.height / 2
            let maxHalf = size.height / 2

            for i in 0..<barCount {
                let raw = Double(levels[i])
                let normalized = min(1.0, raw / 0.12)
                let scaled = pow(normalized, 0.45)

                let absoluteIndex = i + offset
                // Deterministic micro-jitter per bar for organic look
                let jitter = 0.88 + Double((absoluteIndex * 13 + 5) % 17) / 17.0 * 0.24
                let halfH = max(1.0, scaled * maxHalf * 0.92 * jitter)

                let x = startX + Double(i) * (barWidth + spacing)

                // Mirrored: bar extends above and below center
                let rect = CGRect(x: x, y: centerY - halfH, width: barWidth, height: halfH * 2)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                let opacity = 0.30 + (halfH / maxHalf) * 0.55
                context.fill(path, with: .color(.white.opacity(opacity)))
            }
        }
    }
}

// MARK: - Recording Indicator (pulsing red dot)

/// Red recording dot inside a dark circle. Pulses with audio level.
struct RecordingIndicator: View {
    var audioLevel: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensity: Double {
        let normalized = min(1.0, Double(audioLevel) / 0.10)
        return pow(normalized, 0.5)
    }

    var body: some View {
        ZStack {
            // Outer glow — pulses with audio level
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.red.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 24
                    )
                )
                .frame(width: 44, height: 44)
                .opacity(reduceMotion ? 0.3 : 0.15 + intensity * 0.55)

            // Gray circular background (button-like, matching design)
            Circle()
                .fill(Color(white: 0.40))
                .frame(width: 38, height: 38)

            // Dark ring around the circle (inset look from design)
            Circle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1.0)
                .frame(width: 38, height: 38)

            // Core recording dot — scales slightly with audio
            Circle()
                .fill(.red)
                .frame(width: 11, height: 11)
                .scaleEffect(reduceMotion ? 1.0 : 1.0 + intensity * 0.15)
                .shadow(color: .red.opacity(0.4 + intensity * 0.3), radius: 4 + intensity * 4)
        }
        .animation(.easeOut(duration: 0.08), value: audioLevel)
    }
}
