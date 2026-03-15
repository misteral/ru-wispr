import SwiftUI

// MARK: - Observable State

@Observable
final class StreamingOverlayState {
    var text = ""
    var audioLevel: Float = 0
    var isLocked = false
    fileprivate var smoothedLevel: Float = 0
}

// MARK: - Content View

struct StreamingOverlayContent: View {
    var state: StreamingOverlayState

    var body: some View {
        HStack(spacing: 0) {
            RecordingIndicator(audioLevel: state.audioLevel)
                .frame(width: 44, height: 44)
                .padding(.leading, 12)

            WaveformCanvas(level: state.audioLevel)
                .frame(width: 120, height: 24)
                .padding(.leading, 10)

            Text(state.text)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color(white: 0.72))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.trailing, 24)
        }
        .frame(width: 560, height: 56)
        .background {
            ZStack {
                // Solid dark base — slightly lighter gray per design ref
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(white: 0.22).opacity(0.94))

                // Subtle frosted glass on top for depth
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial.opacity(0.25))

                // Visible border stroke matching the design reference
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(
                        .white.opacity(state.isLocked ? 0.30 : 0.22),
                        lineWidth: 1.0
                    )
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .animation(.easeInOut(duration: 0.4), value: state.isLocked)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording: \(state.text)")
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    var audioLevel: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Normalize audio level to 0...1 range for visual response
    private var intensity: Double {
        let normalized = min(1.0, Double(audioLevel) / 0.10)
        return pow(normalized, 0.5) // compress dynamic range
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

// MARK: - Waveform (Canvas for performance at audio-rate updates)

struct WaveformCanvas: View {
    var level: Float

    private let barCount = 30
    private let barWidth: Double = 1.5
    private let spacing: Double = 2.5

    // Pre-computed organic pattern — mimics real speech waveform shape
    // Low edges, irregular peaks in the center-left, natural falloff
    private static let waveformPattern: [Double] = [
        0.10, 0.14, 0.12, 0.18, 0.22, 0.15, 0.30, 0.55, 0.70, 0.50,
        0.85, 1.00, 0.75, 0.90, 0.60, 0.80, 0.95, 0.70, 0.55, 0.65,
        0.45, 0.35, 0.50, 0.30, 0.20, 0.25, 0.15, 0.12, 0.10, 0.08,
    ]

    var body: some View {
        Canvas { context, size in
            let totalWidth = Double(barCount) * barWidth + Double(barCount - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            let centerY = size.height / 2

            let normalized = min(1.0, Double(level) / 0.12)
            let scaled = pow(normalized, 0.4)

            for i in 0..<barCount {
                let pattern = Self.waveformPattern[i]
                // Organic variation seeded by bar index for stability
                let variation = 0.85 + Double((i * 7 + 3) % 11) / 11.0 * 0.30
                let targetHeight = max(2.0, scaled * size.height * 0.9 * pattern * variation)
                let barHeight = min(targetHeight, size.height)

                let x = startX + Double(i) * (barWidth + spacing)
                let y = centerY - barHeight / 2

                let opacity = 0.35 + (barHeight / size.height) * 0.50
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(path, with: .color(.white.opacity(opacity)))
            }
        }
    }
}

// MARK: - NSPanel Host (required for floating non-activating overlay)

class StreamingOverlay: NSPanel {
    private let state = StreamingOverlayState()
    private let pillWidth: Double = 560
    private let pillHeight: Double = 56

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        alphaValue = 0

        contentView = NSHostingView(rootView: StreamingOverlayContent(state: state))
    }

    func updateText(_ text: String) {
        Task { @MainActor in
            self.state.text = text
        }
    }

    func updateAudioLevel(_ level: Float) {
        state.smoothedLevel = state.smoothedLevel * 0.35 + level * 0.65
        state.audioLevel = state.smoothedLevel
    }

    func show() {
        centerOnScreen()
        state.text = ""
        state.audioLevel = 0
        state.smoothedLevel = 0

        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            self.animator().alphaValue = 1

            let frame = self.frame
            let targetY = frame.origin.y
            self.setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY - 12))
            self.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.state.isLocked = false
        })
    }

    func setLocked(_ locked: Bool) {
        state.isLocked = locked
    }

    private func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - pillWidth) / 2
            let y = screenRect.origin.y + 60
            setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        }
    }
}
