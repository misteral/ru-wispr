import AppKit

/// Modal-ish AppKit window for license activation. Shown when:
///   - the user clicks "Activate..." from the menu bar
///   - the trial has expired and `AppDelegate` blocks the hotkey
///
/// Only present in the Pro RU flavor — the free build never instantiates this.
@MainActor
public final class ActivationWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static var shared: ActivationWindowController?

    private let keyField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let activateButton = NSButton(title: "", target: nil, action: nil)
    private let buyButton = NSButton(title: "", target: nil, action: nil)
    private let laterButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    public var onActivated: (() -> Void)?

    /// Display the window. Re-uses the singleton if already on screen.
    public static func present(blockingTrialExpired: Bool = false) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.refreshStatus(blocking: blockingTrialExpired)
            return
        }
        let controller = ActivationWindowController()
        controller.configure(blocking: blockingTrialExpired)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.activationTitle
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(blocking: Bool) {
        guard let window = window, let content = window.contentView else { return }

        let titleLabel = NSTextField(labelWithString: L10n.activationTitle)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let introLabel = NSTextField(wrappingLabelWithString: L10n.activationIntro)
        introLabel.font = .systemFont(ofSize: 13)
        introLabel.textColor = .secondaryLabelColor

        keyField.placeholderString = L10n.activationKeyPlaceholder
        keyField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        keyField.delegate = self

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 420

        activateButton.title = L10n.activationButton
        activateButton.bezelStyle = .rounded
        activateButton.keyEquivalent = "\r"
        activateButton.target = self
        activateButton.action = #selector(activateTapped)

        buyButton.title = L10n.activationBuyButton
        buyButton.bezelStyle = .rounded
        buyButton.target = self
        buyButton.action = #selector(buyTapped)

        laterButton.title = blocking ? L10n.quit : L10n.activationLaterButton
        laterButton.bezelStyle = .rounded
        laterButton.target = self
        laterButton.action = #selector(laterTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let privacyLabel = NSTextField(wrappingLabelWithString: L10n.activationPrivacyNote)
        privacyLabel.font = .systemFont(ofSize: 11)
        privacyLabel.textColor = .tertiaryLabelColor
        privacyLabel.preferredMaxLayoutWidth = 420

        let buttonRow = NSStackView(views: [laterButton, NSView(), buyButton, activateButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [
            titleLabel, introLabel, keyField, statusLabel, spinner, buttonRow, privacyLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            keyField.widthAnchor.constraint(equalToConstant: 420),
        ])

        refreshStatus(blocking: blocking)
    }

    private func refreshStatus(blocking: Bool) {
        switch LicenseManager.shared.status {
        case .trial(let daysLeft):
            statusLabel.stringValue = L10n.trialDaysLeft(daysLeft)
            statusLabel.textColor = .secondaryLabelColor
        case .active:
            statusLabel.stringValue = L10n.licenseActive
            statusLabel.textColor = NSColor.systemGreen
        case .trialExpired:
            statusLabel.stringValue = L10n.trialBlockingMessage
            statusLabel.textColor = NSColor.systemOrange
        case .invalid(let reason):
            statusLabel.stringValue = "\(L10n.licenseInvalid): \(reason)"
            statusLabel.textColor = NSColor.systemRed
        case .notRequired:
            statusLabel.stringValue = ""
        }
        laterButton.title = blocking ? L10n.quit : L10n.activationLaterButton
    }

    // MARK: - Actions

    @objc private func activateTapped() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        setBusy(true)
        statusLabel.stringValue = L10n.activationInProgress
        statusLabel.textColor = .secondaryLabelColor

        Task { [weak self] in
            do {
                _ = try await LicenseClient.shared.activate(licenseKey: key)
                await MainActor.run {
                    guard let self = self else { return }
                    self.setBusy(false)
                    self.statusLabel.stringValue = L10n.activationSuccess
                    self.statusLabel.textColor = NSColor.systemGreen
                    self.onActivated?()
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1.0))
                        self?.close()
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    self.setBusy(false)
                    self.statusLabel.stringValue = error.localizedDescription
                    self.statusLabel.textColor = NSColor.systemRed
                }
            }
        }
    }

    @objc private func buyTapped() {
        NSWorkspace.shared.open(ProductFlavor.current.buyURL)
    }

    @objc private func laterTapped() {
        if case .trialExpired = LicenseManager.shared.status {
            NSApp.terminate(nil)
            return
        }
        close()
    }

    private func setBusy(_ busy: Bool) {
        if busy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        activateButton.isEnabled = !busy
        buyButton.isEnabled = !busy
        keyField.isEnabled = !busy
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        ActivationWindowController.shared = nil
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidChange(_ obj: Notification) {
        activateButton.isEnabled = !keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
