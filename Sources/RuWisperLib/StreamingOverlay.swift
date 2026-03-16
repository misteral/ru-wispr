import SwiftUI

// MARK: - Overlay Phase

enum OverlayPhase: Equatable {
    case recording
    case processing
    case done
}

// MARK: - Observable State

@MainActor
@Observable
final class StreamingOverlayState {
    var text = ""
    var isLocked = false
    var phase: OverlayPhase = .recording
    let audio = AudioLevelHistory(capacity: 64)
}

// MARK: - Content View

struct StreamingOverlayContent: View {
    var state: StreamingOverlayState

    private var borderOpacity: Double {
        switch state.phase {
        case .recording: state.isLocked ? 0.30 : 0.22
        case .processing: 0.25
        case .done: 0.35
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            switch state.phase {
            case .recording:
                RecordingIndicator(audioLevel: state.audio.currentLevel)
                    .frame(width: 44, height: 44)
                    .padding(.leading, 12)

                WaveformCanvas(levels: state.audio.levels, offset: state.audio.offset)
                    .frame(width: 120, height: 24)
                    .padding(.leading, 10)

            case .processing:
                ProcessingIndicator()
                    .frame(width: 44, height: 44)
                    .padding(.leading, 12)

            case .done:
                DoneIndicator()
                    .frame(width: 44, height: 44)
                    .padding(.leading, 12)
            }

            Text(state.text)
                .font(.body.weight(.light))
                .foregroundStyle(Color(white: 0.72))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, state.phase == .recording ? 18 : 12)
                .padding(.trailing, 24)
        }
        .frame(width: 560, height: 56)
        .background {
            ZStack {
                // Solid dark base
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(white: 0.22).opacity(0.94))

                // Subtle frosted glass on top for depth
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial.opacity(0.25))

                // Visible border stroke
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(
                        .white.opacity(borderOpacity),
                        lineWidth: 1.0
                    )
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .animation(.easeInOut(duration: 0.35), value: state.phase)
        .animation(.easeInOut(duration: 0.4), value: state.isLocked)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.recordingAccessibility(state.text))
    }
}

// MARK: - Processing Indicator (spinning arc)

struct ProcessingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Gray circular background (matching RecordingIndicator style)
            Circle()
                .fill(Color(white: 0.40))
                .frame(width: 38, height: 38)

            Circle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1.0)
                .frame(width: 38, height: 38)

            // Spinning arc
            Circle()
                .trim(from: 0, to: 0.65)
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Done Indicator (green checkmark)

struct DoneIndicator: View {
    @State private var scale: Double = 0.5
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            // Green glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 24
                    )
                )
                .frame(width: 44, height: 44)

            // Green circular background
            Circle()
                .fill(Color.green.opacity(0.85))
                .frame(width: 38, height: 38)

            Circle()
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1.0)
                .frame(width: 38, height: 38)

            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
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
        state.audio.push(level)
    }

    func show() {
        centerOnScreen()
        state.text = ""
        state.phase = .recording
        state.audio.reset()

        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            self.animator().alphaValue = 1

            let frame = self.frame
            let targetY = frame.origin.y
            // Slide down from behind the menu bar
            self.setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY + 12))
            self.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }
    }

    func showProcessing() {
        Task { @MainActor in
            self.state.phase = .processing
            self.state.text = L10n.processing
        }
    }

    func showDone(text: String) {
        Task { @MainActor in
            self.state.phase = .done
            self.state.text = text
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            Task { @MainActor in
                self.state.isLocked = false
                self.state.phase = .recording
            }
        })
    }

    func setLocked(_ locked: Bool) {
        state.isLocked = locked
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            NSLog("[OW] StreamingOverlay: no screen found")
            return
        }
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        // Place just below the menu bar (top of visibleFrame), with a small gap
        let x = fullFrame.origin.x + (fullFrame.width - pillWidth) / 2
        let y = visibleFrame.maxY - pillHeight - 8
        NSLog("[OW] StreamingOverlay position: x=%.0f y=%.0f (visibleFrame.maxY=%.0f)", x, y, visibleFrame.maxY)
        setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
    }
}
