import SwiftUI
import DynamicNotchKit

// MARK: - Notch Content View (just text, 2 lines)

struct NotchTranscriptionView: View {
    @ObservedObject var state: NotchOverlayState

    var body: some View {
        Text(displayText)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.primary.opacity(0.8))
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(width: 280, height: 44)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.15), value: state.text)
            .animation(.easeInOut(duration: 0.25), value: state.phase)
    }

    private var displayText: String {
        switch state.phase {
        case .recording:
            return state.text.isEmpty ? L10n.recording : state.text
        case .processing:
            return L10n.processing
        case .done:
            return state.text
        }
    }
}

// MARK: - Observable State (ObservableObject for DynamicNotchKit compatibility)

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
        // No waveform in notch overlay — intentional no-op
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
        state.phase = .processing
    }

    func showDone(text: String) {
        state.phase = .done
        state.text = text
    }

    func hide() {
        isVisible = false
        Task {
            await notch?.hide()
            notch = nil
        }
    }

    nonisolated func setLocked(_ locked: Bool) {
        // No lock indicator in notch UI — intentional no-op
    }
}
