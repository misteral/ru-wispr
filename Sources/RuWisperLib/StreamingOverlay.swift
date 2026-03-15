import AppKit
import Foundation
import QuartzCore

/// A premium, Apple-style dictation HUD.
/// Design: Spotlight-inspired glassmorphism capsule, compact waveform, glowing recording dot.
class StreamingOverlay: NSPanel {

    private let containerView = NSView()
    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()

    private let transcriptionLabel = NSTextField(labelWithString: "")
    private let recordingDot = NSView()
    private let dotGlow = NSView()
    private let dotOuterGlow = NSView()
    private let waveformView = WaveformView()

    // Layout constants
    private let pillWidth: CGFloat = 540
    private let pillHeight: CGFloat = 72
    private let pillCornerRadius: CGFloat = 36

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .mainMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.hasShadow = true
        self.alphaValue = 0

        setupUI()
    }

    private func setupUI() {
        // 1. Main Pill Container — frosted glass capsule
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = pillCornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Subtle outer shadow for depth
        containerView.wantsLayer = true
        containerView.shadow = NSShadow()
        containerView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        containerView.layer?.shadowOffset = NSSize(width: 0, height: -2)
        containerView.layer?.shadowRadius = 20
        containerView.layer?.shadowOpacity = 1.0
        containerView.layer?.cornerRadius = pillCornerRadius

        containerView.addSubview(visualEffectView)

        // 2. Recording Dot & Glow — prominent status anchor
        dotOuterGlow.wantsLayer = true
        dotOuterGlow.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        dotOuterGlow.layer?.cornerRadius = 24
        dotOuterGlow.translatesAutoresizingMaskIntoConstraints = false

        dotGlow.wantsLayer = true
        dotGlow.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
        dotGlow.layer?.cornerRadius = 18
        dotGlow.translatesAutoresizingMaskIntoConstraints = false

        recordingDot.wantsLayer = true
        recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordingDot.layer?.cornerRadius = 7
        recordingDot.layer?.shadowColor = NSColor.systemRed.cgColor
        recordingDot.layer?.shadowOffset = .zero
        recordingDot.layer?.shadowRadius = 16
        recordingDot.layer?.shadowOpacity = 0.7
        recordingDot.translatesAutoresizingMaskIntoConstraints = false

        let dotContainer = NSView()
        dotContainer.addSubview(dotOuterGlow)
        dotContainer.addSubview(dotGlow)
        dotContainer.addSubview(recordingDot)
        dotContainer.translatesAutoresizingMaskIntoConstraints = false

        // 3. Transcription Label — primary content, clean system typography
        transcriptionLabel.font = .systemFont(ofSize: 15.5, weight: .regular)
        transcriptionLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        transcriptionLabel.lineBreakMode = .byTruncatingHead
        transcriptionLabel.maximumNumberOfLines = 2
        transcriptionLabel.cell?.truncatesLastVisibleLine = true
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        // 4. Stack View — three clear zones with breathing room
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 28)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        dotContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        waveformView.setContentCompressionResistancePriority(.required, for: .horizontal)
        transcriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        transcriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(dotContainer)
        contentStack.addArrangedSubview(waveformView)
        contentStack.addArrangedSubview(transcriptionLabel)

        visualEffectView.addSubview(contentStack)
        self.contentView = containerView

        // Constraints
        NSLayoutConstraint.activate([
            // Visual Effect View (Pill) — wide capsule
            visualEffectView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            visualEffectView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            visualEffectView.heightAnchor.constraint(equalToConstant: pillHeight),
            visualEffectView.widthAnchor.constraint(equalToConstant: pillWidth),

            containerView.heightAnchor.constraint(equalToConstant: pillHeight),
            containerView.widthAnchor.constraint(equalToConstant: pillWidth),

            // Content Stack
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),

            // Recording Dot & Glow — larger, more prominent
            recordingDot.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            recordingDot.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            recordingDot.widthAnchor.constraint(equalToConstant: 14),
            recordingDot.heightAnchor.constraint(equalToConstant: 14),

            dotGlow.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            dotGlow.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            dotGlow.widthAnchor.constraint(equalToConstant: 36),
            dotGlow.heightAnchor.constraint(equalToConstant: 36),

            dotOuterGlow.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            dotOuterGlow.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            dotOuterGlow.widthAnchor.constraint(equalToConstant: 48),
            dotOuterGlow.heightAnchor.constraint(equalToConstant: 48),

            dotContainer.widthAnchor.constraint(equalToConstant: 48),
            dotContainer.heightAnchor.constraint(equalToConstant: 48),

            // Waveform — compact secondary element
            waveformView.widthAnchor.constraint(equalToConstant: 90),
            waveformView.heightAnchor.constraint(equalToConstant: 32)
        ])

        startGlowAnimation()
    }

    private func startGlowAnimation() {
        // Dot: smooth opacity breathing
        let dotOpacity = CABasicAnimation(keyPath: "opacity")
        dotOpacity.fromValue = 0.80
        dotOpacity.toValue = 1.0
        dotOpacity.duration = 1.6
        dotOpacity.autoreverses = true
        dotOpacity.repeatCount = .infinity
        dotOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordingDot.layer?.add(dotOpacity, forKey: "dotPulse")

        // Mid glow: soft breathing
        let glowOpacity = CABasicAnimation(keyPath: "opacity")
        glowOpacity.fromValue = 0.15
        glowOpacity.toValue = 0.55
        glowOpacity.duration = 1.6
        glowOpacity.autoreverses = true
        glowOpacity.repeatCount = .infinity
        glowOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotGlow.layer?.add(glowOpacity, forKey: "glow")

        // Outer glow: slower, organic feel
        let outerGlowOpacity = CABasicAnimation(keyPath: "opacity")
        outerGlowOpacity.fromValue = 0.05
        outerGlowOpacity.toValue = 0.30
        outerGlowOpacity.duration = 2.0
        outerGlowOpacity.autoreverses = true
        outerGlowOpacity.repeatCount = .infinity
        outerGlowOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotOuterGlow.layer?.add(outerGlowOpacity, forKey: "outerGlow")
    }

    func updateText(_ text: String) {
        DispatchQueue.main.async {
            self.transcriptionLabel.stringValue = text
        }
    }

    func updateAudioLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }

    func show() {
        centerOnScreen()
        self.transcriptionLabel.stringValue = ""

        self.orderFront(nil)
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
            self.visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        })
    }

    func setLocked(_ locked: Bool) {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                if locked {
                    self.visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
                } else {
                    self.visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
                }
            }
        }
    }

    private func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - pillWidth) / 2
            let y = screenRect.origin.y + 60
            self.setFrame(NSRect(x: x, y: y, width: pillWidth, height: pillHeight), display: true)
        }
    }
}

// MARK: - Waveform View

class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let barCount = 18
    private let spacing: CGFloat = 2.5
    private var currentLevel: Float = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBars()
    }

    private func setupBars() {
        self.wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
            bar.cornerRadius = 0.75
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    override func layout() {
        super.layout()
        let barWidth: CGFloat = 1.5
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (frame.width - totalWidth) / 2

        for (i, bar) in bars.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + spacing)
            bar.frame = NSRect(x: x, y: frame.height / 2 - 1, width: barWidth, height: 2)
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async {
            // Smooth: fast attack, moderate release
            self.currentLevel = self.currentLevel * 0.35 + level * 0.65

            // Logarithmic scaling for speech range
            let normalized = min(1.0, CGFloat(self.currentLevel) / 0.12)
            let scaled = pow(normalized, 0.45)

            let centerIndex = Float(self.barCount - 1) / 2.0

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            for (i, bar) in self.bars.enumerated() {
                // Bell curve envelope: center bars taller, edges shorter
                let distance = abs(Float(i) - centerIndex) / centerIndex
                let envelope = CGFloat(1.0 - pow(distance, 1.3) * 0.8)

                let randomFactor = CGFloat(Float.random(in: 0.88...1.12))
                let targetHeight = max(2, scaled * self.frame.height * 0.85 * envelope * randomFactor)
                let clampedHeight = min(targetHeight, self.frame.height)

                let barWidth = bar.frame.width
                let x = bar.frame.origin.x
                bar.frame = NSRect(x: x, y: (self.frame.height - clampedHeight) / 2, width: barWidth, height: clampedHeight)
                bar.backgroundColor = NSColor.white.withAlphaComponent(0.35 + Double(clampedHeight / self.frame.height) * 0.5).cgColor
            }
            CATransaction.commit()
        }
    }
}
