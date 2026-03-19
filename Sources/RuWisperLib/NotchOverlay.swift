import SwiftUI
import DynamicNotchKit

// MARK: - Desaturated dot palette (no neon, tinted shadows)

private extension Color {
    static let dotRed = Color(red: 0.88, green: 0.22, blue: 0.21)
    static let dotGreen = Color(red: 0.22, green: 0.78, blue: 0.45)
}

// MARK: - Breathing Red Dot (recording)

private struct BreathingRedDot: View {
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(Color.dotRed)
            .frame(width: 8, height: 8)
            .shadow(color: Color.dotRed.opacity(0.35), radius: 4)
            .opacity(breathing ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { breathing = true }
    }
}

// MARK: - Animated Green Checkmark (done)

private struct AnimatedCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    @State private var circleScale: CGFloat = 0.3
    @State private var circleOpacity: Double = 0

    var body: some View {
        ZStack {
            // Green circle background
            Circle()
                .fill(Color.dotGreen)
                .frame(width: 16, height: 16)
                .shadow(color: Color.dotGreen.opacity(0.3), radius: 4)
                .scaleEffect(circleScale)
                .opacity(circleOpacity)

            // Animated checkmark stroke
            Path { path in
                path.move(to: CGPoint(x: 4.5, y: 8.5))
                path.addLine(to: CGPoint(x: 7, y: 11))
                path.addLine(to: CGPoint(x: 11.5, y: 5.5))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                circleScale = 1.0
                circleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
                trimEnd = 1.0
            }
        }
    }
}

// MARK: - Phase Indicator (red dot during recording, green checkmark on done)

private struct PhaseIndicator: View {
    let phase: OverlayPhase

    var body: some View {
        ZStack {
            if phase == .done {
                AnimatedCheckmark()
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                BreathingRedDot()
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

// MARK: - Notch Content View

struct NotchTranscriptionView: View {
    @ObservedObject var state: NotchOverlayState

    private var isDone: Bool { state.phase == .done }

    private var displayText: String {
        if isDone { return L10n.done }
        return state.text.isEmpty ? L10n.recording : state.text
    }

    var body: some View {
        HStack(spacing: 10) {
            PhaseIndicator(phase: state.phase)

            Text(displayText)
                .font(.system(size: isDone ? 13 : 14, weight: isDone ? .medium : .regular))
                .foregroundStyle(.primary.opacity(isDone ? 0.6 : 0.8))
                .lineLimit(1)
                .truncationMode(.head)
                // During recording: push text to trailing so latest words are visible
                // During done: just sit next to the dot naturally
                .frame(maxWidth: isDone ? nil : .infinity, alignment: .trailing)
        }
        // Dot pinned to leading edge; width animates via withAnimation
        .frame(width: isDone ? 90 : 300, alignment: .leading)
        .clipped()
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - Observable State

@MainActor
final class NotchOverlayState: ObservableObject {
    @Published var text = ""
    @Published var phase: OverlayPhase = .recording
}

// MARK: - Notch Overlay Controller

@MainActor
final class NotchOverlay {
    private let state = NotchOverlayState()
    private var notch: DynamicNotch<NotchTranscriptionView, EmptyView, EmptyView>?
    nonisolated(unsafe) private(set) var isVisible = false

    func updateText(_ text: String) {
        state.text = text
    }

    func updateAudioLevel(_ level: Float) {
        // No waveform — intentional no-op
    }

    func show() {
        state.text = ""
        state.phase = .recording
        isVisible = true

        let s = state
        notch = DynamicNotch(style: .auto) {
            NotchTranscriptionView(state: s)
        }

        Task {
            await notch?.expand()
        }
    }

    func showProcessing() {
        // No separate processing step — stays in recording state
    }

    func showDone(text: String) {
        // Text updates instantly (no cross-fade)
        state.text = text
        // Phase animates (frame width shrinks, dot color morphs)
        withAnimation(.easeInOut(duration: 0.5)) {
            state.phase = .done
        }
    }

    func hide() {
        isVisible = false
        Task {
            await notch?.hide()
            notch = nil
        }
    }

    nonisolated func setLocked(_ locked: Bool) {
        // No lock indicator — intentional no-op
    }
}
