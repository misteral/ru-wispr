import SwiftUI

// MARK: - Observable State

@MainActor
@Observable
final class StreamingOverlayState {
    var text = ""
    var isLocked = false
    let audio = AudioLevelHistory(capacity: 64)
}

// MARK: - Content View

struct StreamingOverlayContent: View {
    var state: StreamingOverlayState

    var body: some View {
        HStack(spacing: 0) {
            RecordingIndicator(audioLevel: state.audio.currentLevel)
                .frame(width: 44, height: 44)
                .padding(.leading, 12)

            WaveformCanvas(levels: state.audio.levels, offset: state.audio.offset)
                .frame(width: 120, height: 24)
                .padding(.leading, 10)

            Text(state.text)
                .font(.body.weight(.light))
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
        .accessibilityLabel(L10n.recordingAccessibility(state.text))
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
        state.audio.reset()

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
