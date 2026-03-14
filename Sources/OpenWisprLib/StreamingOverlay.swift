import AppKit
import Foundation
import QuartzCore

/// A premium, Apple-style dictation HUD.
/// Design: Fixed-size ultra-compact glassmorphism pill, minimal animated waveform, glowing recording dot.
class StreamingOverlay: NSPanel {
    
    private let containerView = NSView()
    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()
    
    private let transcriptionLabel = NSTextField(labelWithString: "")
    private let recordingDot = NSView()
    private let dotGlow = NSView()
    private let waveformView = WaveformView()
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 40),
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
        // 1. Main Pill Container (Fixed Size)
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 20 // Full pill shape for 40px height
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(visualEffectView)
        
        // 2. Recording Dot & Glow
        dotGlow.wantsLayer = true
        dotGlow.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
        dotGlow.layer?.cornerRadius = 8
        dotGlow.translatesAutoresizingMaskIntoConstraints = false
        
        recordingDot.wantsLayer = true
        recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordingDot.layer?.cornerRadius = 4
        recordingDot.translatesAutoresizingMaskIntoConstraints = false
        
        let dotContainer = NSView()
        dotContainer.addSubview(dotGlow)
        dotContainer.addSubview(recordingDot)
        dotContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // 3. Transcription Label (Fixed width, truncates head to show progress)
        transcriptionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        transcriptionLabel.textColor = .white
        transcriptionLabel.lineBreakMode = .byTruncatingHead
        transcriptionLabel.maximumNumberOfLines = 1
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // 4. Stack View
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentStack.addArrangedSubview(dotContainer)
        contentStack.addArrangedSubview(waveformView)
        contentStack.addArrangedSubview(transcriptionLabel)
        
        visualEffectView.addSubview(contentStack)
        self.contentView = containerView
        
        // Constraints
        NSLayoutConstraint.activate([
            // Visual Effect View (Pill) - Fixed Size
            visualEffectView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            visualEffectView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            visualEffectView.heightAnchor.constraint(equalToConstant: 40),
            visualEffectView.widthAnchor.constraint(equalToConstant: 500),
            
            containerView.heightAnchor.constraint(equalToConstant: 40),
            containerView.widthAnchor.constraint(equalToConstant: 500),
            
            // Content Stack
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            
            // Dot & Glow
            recordingDot.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            recordingDot.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            recordingDot.widthAnchor.constraint(equalToConstant: 8),
            recordingDot.heightAnchor.constraint(equalToConstant: 8),
            
            dotGlow.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            dotGlow.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            dotGlow.widthAnchor.constraint(equalToConstant: 16),
            dotGlow.heightAnchor.constraint(equalToConstant: 16),
            
            dotContainer.widthAnchor.constraint(equalToConstant: 16),
            dotContainer.heightAnchor.constraint(equalToConstant: 16),
            
            // Waveform (Smaller)
            waveformView.widthAnchor.constraint(equalToConstant: 60),
            waveformView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        startGlowAnimation()
    }
    
    private func startGlowAnimation() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.3
        anim.toValue = 0.8
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotGlow.layer?.add(anim, forKey: "glow")
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
            self.setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY - 15))
            self.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        })
    }
    
    func setLocked(_ locked: Bool) {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                if locked {
                    self.visualEffectView.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.5).cgColor
                } else {
                    self.visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
                }
            }
        }
    }
    
    private func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let width: CGFloat = 500
            let height: CGFloat = 40
            let x = screenRect.origin.x + (screenRect.width - width) / 2
            let y = screenRect.origin.y + 60
            self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }
}

// MARK: - Waveform View

class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let barCount = 20
    private let spacing: CGFloat = 2.5
    
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
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            bar.cornerRadius = 1.0
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }
    
    override func layout() {
        super.layout()
        let barWidth: CGFloat = 2.0
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (frame.width - totalWidth) / 2
        
        for (i, bar) in bars.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + spacing)
            bar.frame = NSRect(x: x, y: frame.height / 2 - 1, width: barWidth, height: 2)
        }
    }
    
    func updateLevel(_ level: Float) {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1)
            for bar in self.bars {
                let randomFactor = Float.random(in: 0.7...1.3)
                let height = CGFloat(max(2, level * 80 * randomFactor))
                let clampedHeight = min(height, self.frame.height)
                
                let barWidth = bar.frame.width
                let x = bar.frame.origin.x
                bar.frame = NSRect(x: x, y: (self.frame.height - clampedHeight) / 2, width: barWidth, height: clampedHeight)
                bar.backgroundColor = NSColor.white.withAlphaComponent(0.4 + Double(clampedHeight / self.frame.height) * 0.6).cgColor
            }
            CATransaction.commit()
        }
    }
}
