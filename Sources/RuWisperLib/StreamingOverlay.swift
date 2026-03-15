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
            RecordingIndicator()
                .frame(width: 60, height: 60)
                .padding(.leading, 12)

            WaveformCanvas(level: state.audioLevel)
                .frame(width: 130, height: 32)
                .padding(.leading, 10)

            Text(state.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.trailing, 24)
        }
        .frame(width: 560, height: 76)
        .background {
            ZStack {
                // Dark base layer for glassmorphism depth
                RoundedRectangle(cornerRadius: 38)
                    .fill(Color.black.opacity(0.3))

                // Frosted glass material
                RoundedRectangle(cornerRadius: 38)
                    .fill(.ultraThinMaterial)

                // Top-lit edge highlight for glass depth
                RoundedRectangle(cornerRadius: 38)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(state.isLocked ? 0.22 : 0.14),
                                .white.opacity(0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
        .clipShape(.rect(cornerRadius: 38))
        .animation(.easeInOut(duration: 0.4), value: state.isLocked)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording: \(state.text)")
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Outer atmospheric glow — radial for natural falloff
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.red.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .opacity(reduceMotion ? 0.6 : (isPulsing ? 0.85 : 0.35))

            // Mid halo ring
            Circle()
                .fill(.red.opacity(0.12))
                .frame(width: 38, height: 38)
                .opacity(reduceMotion ? 0.4 : (isPulsing ? 0.6 : 0.2))

            // Core recording dot
            Circle()
                .fill(.red)
                .frame(width: 16, height: 16)
                .shadow(color: .red.opacity(0.5), radius: 16)
                .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.85))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Waveform (Canvas for performance at audio-rate updates)

struct WaveformCanvas: View {
    var level: Float

    private let barCount = 30
    private let barWidth: Double = 1.5
    private let spacing: Double = 2.5

    var body: some View {
        Canvas { context, size in
            let totalWidth = Double(barCount) * barWidth + Double(barCount - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            let centerY = size.height / 2

            let normalized = min(1.0, Double(level) / 0.12)
            let scaled = pow(normalized, 0.4)
            let centerIndex = Double(barCount - 1) / 2.0

            for i in 0..<barCount {
                // Bell curve envelope: center bars taller, edges taper
                let distance = abs(Double(i) - centerIndex) / centerIndex
                let envelope = 1.0 - pow(distance, 1.3) * 0.8

                // Organic per-bar variation
                let variation = Double.random(in: 0.85...1.15)
                let targetHeight = max(2.0, scaled * size.height * 0.85 * envelope * variation)
                let barHeight = min(targetHeight, size.height)

                let x = startX + Double(i) * (barWidth + spacing)
                let y = centerY - barHeight / 2

                let opacity = 0.3 + (barHeight / size.height) * 0.45
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
    private let pillHeight: Double = 76

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 76),
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
