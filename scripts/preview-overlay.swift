#!/usr/bin/env swift
/// Renders StreamingOverlay to PNG screenshots for design comparison.
/// Usage:  swift scripts/preview-overlay.swift [output_dir]
/// Output: overlay-idle.png, overlay-recording.png, overlay-locked.png

import AppKit
import SwiftUI
import Observation

// ─────────────────────────────────────────────
// MARK: - Copied from StreamingOverlay.swift
// ─────────────────────────────────────────────

@Observable
final class StreamingOverlayState {
    var text = ""
    var audioLevel: Float = 0
    var isLocked = false
    fileprivate var smoothedLevel: Float = 0
}

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
    }
}

struct RecordingIndicator: View {
    var audioLevel: Float

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
                .opacity(0.15 + intensity * 0.55)

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
                .scaleEffect(1.0 + intensity * 0.15)
                .shadow(color: .red.opacity(0.4 + intensity * 0.3), radius: 4 + intensity * 4)
        }
    }
}

struct WaveformCanvas: View {
    var level: Float

    private let barCount = 30
    private let barWidth: Double = 1.5
    private let spacing: Double = 2.5

    // Pre-computed organic pattern — mimics real speech waveform shape
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

// ─────────────────────────────────────────────
// MARK: - Preview wrapper (adds desktop-like background)
// ─────────────────────────────────────────────

struct PreviewScene: View {
    var state: StreamingOverlayState
    var label: String

    var body: some View {
        ZStack {
            // Simulated macOS desktop background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.12, green: 0.10, blue: 0.25),
                    Color(red: 0.08, green: 0.06, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Spacer()
                StreamingOverlayContent(state: state)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                Spacer().frame(height: 60)
            }

            // State label
            VStack {
                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(6)
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(width: 640, height: 200)
        .environment(\.colorScheme, .dark)
    }
}

// ─────────────────────────────────────────────
// MARK: - Rendering
// ─────────────────────────────────────────────

func renderView<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> NSImage? {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)

    // Force layout
    hostingView.layoutSubtreeIfNeeded()

    // Render at 2x for Retina
    let bitmapSize = NSSize(width: size.width * scale, height: size.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bitmapSize.width),
        pixelsHigh: Int(bitmapSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    hostingView.displayIgnoringOpacity(hostingView.bounds, in: NSGraphicsContext.current!)
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

func saveImage(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        print("❌ Failed to encode PNG: \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✅ Saved: \(path)")
    } catch {
        print("❌ Write error: \(error)")
    }
}

// ─────────────────────────────────────────────
// MARK: - Main
// ─────────────────────────────────────────────

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "."
}

// Create output directory
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// Need NSApplication for SwiftUI/AppKit rendering
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // headless, no dock icon

let size = CGSize(width: 640, height: 200)

// --- State 1: Idle (silence, no text) ---
let idleState = StreamingOverlayState()
idleState.audioLevel = 0.005
idleState.text = ""
if let img = renderView(PreviewScene(state: idleState, label: "state: idle (silence)"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-idle.png")
}

// --- State 2: Quiet speech ---
let quietState = StreamingOverlayState()
quietState.audioLevel = 0.03
quietState.text = "Тихая речь..."
if let img = renderView(PreviewScene(state: quietState, label: "state: quiet speech (0.03)"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-quiet.png")
}

// --- State 3: Normal speech ---
let recordingState = StreamingOverlayState()
recordingState.audioLevel = 0.06
recordingState.text = "Привет, это тестовый текст для превью оверлея"
if let img = renderView(PreviewScene(state: recordingState, label: "state: normal speech (0.06)"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-recording.png")
}

// --- State 4: Loud speech ---
let loudState = StreamingOverlayState()
loudState.audioLevel = 0.12
loudState.text = "Громкая речь, пульсация на максимуме!"
if let img = renderView(PreviewScene(state: loudState, label: "state: loud speech (0.12)"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-loud.png")
}

// --- State 5: Locked mode ---
let lockedState = StreamingOverlayState()
lockedState.audioLevel = 0.05
lockedState.text = "Заблокированный режим записи"
lockedState.isLocked = true
if let img = renderView(PreviewScene(state: lockedState, label: "state: locked"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-locked.png")
}

// --- State 6: Long text ---
let longState = StreamingOverlayState()
longState.audioLevel = 0.06
longState.text = "Очень длинный текст который должен обрезаться с помощью truncation mode потому что не помещается в оверлей полностью и нужно проверить как это выглядит"
if let img = renderView(PreviewScene(state: longState, label: "state: long text"), size: size) {
    saveImage(img, to: "\(outputDir)/overlay-longtext.png")
}

print("\n📸 All overlay previews rendered to: \(outputDir)/")
