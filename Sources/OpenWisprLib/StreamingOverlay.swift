import AppKit
import Foundation
import QuartzCore

/// A beautiful floating overlay for real-time transcription preview.
/// Designed with "Frontend Taste": Liquid Glass, premium typography, and spring motion.
class StreamingOverlay: NSPanel {
    
    private let label = NSTextField(labelWithString: "")
    private let visualEffectView = NSVisualEffectView()
    private let containerView = NSView()
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
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
        centerOnScreen()
    }
    
    private func setupUI() {
        // 1. Container with Liquid Glass refraction
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 24
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1.0
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        
        // 2. Backdrop blur
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .hudWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 24
        
        // 3. Typography (Deterministic & Premium)
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        
        // Layout
        visualEffectView.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        label.frame = NSRect(x: 24, y: 12, width: 552, height: 56)
        
        containerView.addSubview(visualEffectView)
        containerView.addSubview(label)
        self.contentView = containerView
    }
    
    func updateText(_ text: String) {
        DispatchQueue.main.async {
            // Add a subtle "typing" feel or just smooth update
            self.label.stringValue = text
            
            // Adjust width based on text length (Dynamic Island feel)
            let attributes = [NSAttributedString.Key.font: self.label.font!]
            let size = (text as NSString).size(withAttributes: attributes)
            let newWidth = min(max(size.width + 80, 200), 800)
            
            var frame = self.frame
            let oldWidth = frame.size.width
            frame.size.width = newWidth
            frame.origin.x += (oldWidth - newWidth) / 2 // keep centered
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(frame, display: true)
                self.containerView.subviews.first?.animator().frame = NSRect(x: 0, y: 0, width: newWidth, height: 80)
                self.label.animator().frame = NSRect(x: 24, y: 12, width: newWidth - 48, height: 56)
            }
        }
    }
    
    func show() {
        centerOnScreen()
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) // Spring-like
            self.animator().alphaValue = 1
            
            // Subtle pop-up motion
            var frame = self.frame
            let targetY = frame.origin.y
            self.setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY - 20))
            self.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.label.stringValue = ""
            self.containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        })
    }

    func setLocked(_ locked: Bool) {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                if locked {
                    // Accent color for locked mode (subtle amber/orange)
                    self.containerView.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.5).cgColor
                } else {
                    self.containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
                }
            }
        }
    }
    
    private func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - 600) / 2
            let y = screenRect.origin.y + 100 // Slightly above bottom
            self.setFrame(NSRect(x: x, y: y, width: 600, height: 80), display: true)
        }
    }
}
