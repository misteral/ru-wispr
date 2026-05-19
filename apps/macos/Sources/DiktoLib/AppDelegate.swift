import AppKit
import AudioToolbox

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var transcriber: Transcriber!
    var gigaamTranscriber: GigaAMTranscriber!
    var inserter: TextInserter!
    // Streaming state for GigaAM live transcription
    private var streamingBuffer: [Float] = []
    private var streamingTimer: Timer?
    private var lastStreamingText: String = ""
    private var streamingInsertedText: String = ""
    private var streamingContext = StreamingContext()
    /// Peak RMS observed during the current recording. Used to distinguish
    /// "model didn't recognize speech" from "microphone returned silence".
    private var maxRecordingRMS: Float = 0
    /// Threshold below which we consider input silent (≈-40 dB). Anything
    /// quieter than this almost certainly means CoreAudio/HAL failed to deliver
    /// real samples (e.g. coreaudiod stuck after another app held the mic).
    private static let silentRMSThreshold: Float = 0.01
    var config: Config!
    var overlay: NotchOverlay!
    var isPressed = false
    var isReady = false
    var isLocked = false
    private var tapCount = 0
    private var tapTimer: Timer?
    private var lastKeyDownTime: Date?
    public var lastTranscription: String?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        inserter = TextInserter()
        overlay = NotchOverlay()

        Task {
            await self.setup()
        }
    }

    private func setup() async {
        do {
            try await setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() async throws {
        config = Config.load()
        L10n.language = config.language
        // Warm the dictionary singleton off the hot path.
        _ = DictionaryManager.shared

        // Pro RU: stamp trial state and kick off async re-validation. Status
        // is checked at hotkey-press time so a network blip doesn't stall the
        // launch flow.
        if ProductFlavor.current.requiresLicense {
            LicenseManager.shared.touch()
            if LicenseManager.shared.needsRevalidation {
                Task.detached { await LicenseClient.shared.validateIfPossible() }
            }
        }
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        gigaamTranscriber = GigaAMTranscriber(modelPath: config.gigaamPath)

        await MainActor.run {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.buildMenu()
        }

        if config.effectiveEngine == "gigaam" {
            if !GigaAMTranscriber.isAvailable(path: config.gigaamPath) {
                await presentStartupError(L10n.gigaamModelMissing)
                return
            }
            // Pre-load model for fast first transcription and streaming
            do {
                print("Loading GigaAM v3 MLX model...")
                try gigaamTranscriber.loadModel()
                print("GigaAM: ready")
            } catch {
                await presentStartupError(L10n.gigaamLoadFailed(error.localizedDescription))
                return
            }
        } else {
            if Transcriber.findWhisperBinary() == nil {
                await presentStartupError(L10n.whisperBinaryMissing)
                return
            }
        }

        let wasStale = Permissions.isAccessibilityStale()
        if wasStale {
            print("Accessibility: stale permission detected, resetting...")
            Permissions.resetAccessibility()
            try? await Task.sleep(for: .seconds(1))
        }

        if !AXIsProcessTrusted() {
            await MainActor.run {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(0.5))
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        if config.effectiveEngine == "whisper" && !Transcriber.modelExists(modelSize: config.modelSize) {
            await MainActor.run {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress(L10n.downloadingModelNamed(self.config.modelSize))
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize)
            await MainActor.run {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        await MainActor.run {
            self.startListening()
        }
    }

    /// Surface a fatal startup error: log it, flip the status bar to the
    /// error state (warning icon + message in the dropdown), and pop a modal
    /// alert. Used when we can't proceed past `setupInner` — without this,
    /// the menu bar stays on the default logo and the user has no idea why
    /// the hotkey doesn't respond.
    private func presentStartupError(_ message: String) async {
        print("Error: \(message)")
        await MainActor.run {
            self.statusBar.state = .error(message)
            self.statusBar.buildMenu()

            let alert = NSAlert()
            alert.messageText = L10n.startupErrorTitle
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func startListening() {
        loadSystemSounds()
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )

        hotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("dikto v\(Dikto.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Engine: \(config.effectiveEngine)")
        if config.effectiveEngine == "gigaam" {
            print("GigaAM: \(config.gigaamPath ?? GigaAMTranscriber.defaultModelDir.path) (native MLX)")
        } else {
            print("Model: \(config.modelSize)")
        }
        print("Ready.")
    }

    public func reloadConfig() {
        config = Config.load()
        L10n.language = config.language
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        gigaamTranscriber = GigaAMTranscriber(modelPath: config.gigaamPath)

        hotkeyManager?.stop()
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )
        hotkeyManager?.start(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )

        statusBar.buildMenu()
        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("Config reloaded: hotkey=\(hotkeyDesc) model=\(config.modelSize)")
    }

    private var startSoundID: SystemSoundID = 0
    private var stopSoundID: SystemSoundID = 0

    private func loadSystemSounds() {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "startRecording", withExtension: "mp3", subdirectory: "Audio") {
            AudioServicesCreateSystemSoundID(url as CFURL, &startSoundID)
        }
        if let url = bundle.url(forResource: "stopRecording", withExtension: "mp3", subdirectory: "Audio") {
            AudioServicesCreateSystemSoundID(url as CFURL, &stopSoundID)
        }
        // Fallback to system sounds if bundle resources not found
        if startSoundID == 0, let url = CFURLCreateWithFileSystemPath(nil,
            "/System/Library/Sounds/Tink.aiff" as CFString, .cfurlposixPathStyle, false) {
            AudioServicesCreateSystemSoundID(url, &startSoundID)
        }
        if stopSoundID == 0, let url = CFURLCreateWithFileSystemPath(nil,
            "/System/Library/Sounds/Pop.aiff" as CFString, .cfurlposixPathStyle, false) {
            AudioServicesCreateSystemSoundID(url, &stopSoundID)
        }
    }

    private func playStartSound() {
        guard config.effectiveSoundFeedback, startSoundID != 0 else { return }
        AudioServicesPlaySystemSound(startSoundID)
    }

    private func playStopSound() {
        guard config.effectiveSoundFeedback, stopSoundID != 0 else { return }
        AudioServicesPlaySystemSound(stopSoundID)
    }

    private func handleKeyDown() {
        NSLog("[OW] handleKeyDown called, isReady=%d, isPressed=%d, isLocked=%d", isReady ? 1 : 0, isPressed ? 1 : 0, isLocked ? 1 : 0)
        guard isReady else { return }

        // Pro RU: refuse to record if the trial is over and no license is
        // installed. We surface the activation window instead so the user
        // has a path to unblock themselves without restarting the app.
        if ProductFlavor.current.requiresLicense,
           !LicenseManager.shared.status.allowsRecording {
            Task { @MainActor in
                ActivationWindowController.present(blockingTrialExpired: true)
            }
            return
        }

        if isLocked {
            isLocked = false
            finishRecording()
            return
        }

        guard !isPressed else { return }
        isPressed = true
        lastKeyDownTime = Date()
        
        // Delay recording start by 0.1s to ignore very short jitters
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.1))
            guard let self = self, self.isPressed || self.tapCount > 0 else { return }

            if self.statusBar.state != .recording {
                self.startRecordingFlow()
            }
        }
    }

    private func startRecordingFlow() {
        self.statusBar.state = .recording
        self.playStartSound()
        do {
            let outputURL: URL
            if Config.effectiveMaxRecordings(self.config.maxRecordings) == 0 {
                outputURL = RecordingStore.tempRecordingURL()
            } else {
                outputURL = RecordingStore.newRecordingURL()
            }

            self.maxRecordingRMS = 0

            // Set up streaming for GigaAM
            if self.config.effectiveEngine == "gigaam" && self.config.effectiveStreaming {
                self.streamingBuffer = []
                self.lastStreamingText = ""
                self.streamingInsertedText = ""
                self.streamingContext.reset()
                self.recorder.onAudioSamples = { [weak self] samples in
                    guard let self = self else { return }
                    self.streamingBuffer.append(contentsOf: samples)

                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(1, samples.count)))
                    if rms > self.maxRecordingRMS { self.maxRecordingRMS = rms }
                    Task { @MainActor [weak self] in
                        self?.overlay.updateAudioLevel(rms)
                    }
                }
                self.startStreamingTranscription()
                Task { @MainActor in
                    self.overlay.show()
                }
            } else {
                // Track RMS even when streaming is disabled / engine != gigaam
                self.recorder.onAudioSamples = { [weak self] samples in
                    guard let self = self else { return }
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(1, samples.count)))
                    if rms > self.maxRecordingRMS { self.maxRecordingRMS = rms }
                }
            }

            NSLog("[OW] Starting recording to: %@", outputURL.path)
            try self.recorder.startRecording(to: outputURL)
            NSLog("[OW] Recording started OK")
        } catch {
            NSLog("[OW] Recording start error: %@", error.localizedDescription)
            self.isPressed = false
            self.statusBar.state = .idle
        }
    }

    private func handleKeyUp() {
        NSLog("[OW] handleKeyUp called, isPressed=%d, isLocked=%d", isPressed ? 1 : 0, isLocked ? 1 : 0)
        guard isPressed else { return }
        isPressed = false
        
        let duration = Date().timeIntervalSince(lastKeyDownTime ?? Date())
        
        if duration < 0.4 {
            // It's a short tap. Increment tap count and wait for potential double-tap
            tapCount += 1
            
            tapTimer?.invalidate()
            tapTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.tapCount >= 2 {
                    // Double tap detected! Lock recording.
                    self.isLocked = true
                    self.overlay.setLocked(true)
                    NSLog("[OW] Recording LOCKED")
                } else if !self.isPressed {
                    // Single tap finished and no second tap came. Stop recording.
                    self.finishRecording()
                }
                self.tapCount = 0
            }
        } else {
            // Long press (PTT). Finish immediately on release.
            finishRecording()
        }
    }

    private func finishRecording() {
        NSLog("[OW] finishRecording called")
        
        // Stop streaming transcription timer
        stopStreamingTranscription()
        recorder.onAudioSamples = nil

        // Keep overlay visible while we finalize transcription
        let hadOverlay = overlay.isVisible
        Task { @MainActor in
            self.overlay.setLocked(false)
        }

        guard let audioURL = recorder.stopRecording() else {
            NSLog("[OW] stopRecording returned nil (short press, no recording)")
            statusBar.state = .idle
            Task { @MainActor in self.overlay.hide() }
            return
        }

        NSLog("[OW] Recording stopped, audioURL: %@", audioURL.path)
        playStopSound()

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? UInt64 {
            NSLog("[OW] Audio file size: %llu bytes", size)
        }

        statusBar.state = .transcribing
        NSLog("[OW] Starting transcription with engine: %@", config.effectiveEngine)

        // If overlay wasn't shown (non-streaming engine), show it now
        if !hadOverlay {
            Task { @MainActor in
                self.overlay.show()
            }
        }

        Task { [weak self] in
            guard let self = self else { return }
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
            defer {
                if maxRecordings == 0 {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
            do {
                let raw: String
                if self.config.effectiveEngine == "gigaam" {
                    let bufferCount = self.streamingBuffer.count
                    let wasStreaming = self.config.effectiveStreaming && !self.lastStreamingText.isEmpty

                    if wasStreaming {
                        // Windowed streaming — only process the uncommitted tail
                        NSLog("[OW] Final transcribe on tail (%d total samples, %d committed)", bufferCount, self.streamingContext.committedSamples)
                        raw = try self.gigaamTranscriber.transcribeFinal(samples: self.streamingBuffer, context: self.streamingContext)
                    } else if bufferCount > 4800 {
                        // No streaming — chunked transcription
                        NSLog("[OW] Chunked transcribe on %d samples...", bufferCount)
                        raw = try self.gigaamTranscriber.transcribeChunked(samples: self.streamingBuffer)
                    } else {
                        raw = try self.gigaamTranscriber.transcribe(audioURL: audioURL)
                    }
                    self.streamingBuffer = []
                    self.streamingContext.reset()
                } else {
                    NSLog("[OW] Calling whisper transcribe...")
                    raw = try await self.transcriber.transcribe(audioURL: audioURL)
                }
                NSLog("[OW] Raw transcription: '%@'", raw)
                let dictApplied = DictionaryManager.shared.apply(to: raw)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(dictApplied) : dictApplied
                NSLog("[OW] Final text: '%@'", text)
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                let isMeaningful = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let peakRMS = self.maxRecordingRMS
                await MainActor.run {
                    if isMeaningful {
                        NSLog("[OW] Inserting text...")
                        self.lastTranscription = text
                        self.inserter.insert(text: text)
                        NSLog("[OW] Text inserted OK")
                        self.overlay.showDone(text: text)
                    } else {
                        let reason = peakRMS < AppDelegate.silentRMSThreshold
                            ? L10n.microphoneSilent
                            : L10n.notRecognized
                        NSLog("[OW] Empty result (peak RMS=%.4f) → %@", peakRMS, reason)
                        self.overlay.showEmpty(text: reason)
                    }
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
                let gen = await MainActor.run { self.overlay.generation }
                let displayDuration = isMeaningful ? 1.5 : 2.5
                try? await Task.sleep(for: .seconds(displayDuration))
                await MainActor.run {
                    guard self.overlay.generation == gen else {
                        NSLog("[OW] Skipping stale auto-hide (gen %d vs current %d)", gen, self.overlay.generation)
                        return
                    }
                    self.overlay.hide()
                }
            } catch {
                NSLog("[OW] Transcription error: %@", error.localizedDescription)
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                await MainActor.run {
                    print("Error: \(error.localizedDescription)")
                    self.overlay.hide()
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            }
        }
    }

    // MARK: - Streaming Transcription

    private func startStreamingTranscription() {
        // Transcribe every 0.5 seconds for smooth UI updates
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.performStreamingTranscription()
        }
    }

    private func stopStreamingTranscription() {
        streamingTimer?.invalidate()
        streamingTimer = nil
    }

    private func performStreamingTranscription() {
        let buffer = streamingBuffer
        guard (isPressed || isLocked), buffer.count > 8000 else { return }  // at least 0.5s and still recording
        guard !streamingContext.isProcessing else { return }  // skip if previous call still running

        streamingContext.isProcessing = true
        Task { [weak self] in
            guard let self = self else { return }
            defer { self.streamingContext.isProcessing = false }
            do {
                let result = try self.gigaamTranscriber.transcribeLive(samples: buffer, context: self.streamingContext)
                let currentText = result.cumulativeText

                if !currentText.isEmpty && currentText != self.lastStreamingText {
                    self.lastStreamingText = currentText
                    await MainActor.run {
                        self.overlay.updateText(currentText)
                    }
                }
            } catch {
                NSLog("[OW] Streaming transcription error: %@", error.localizedDescription)
            }
        }
    }

    public func reprocess(audioURL: URL) {
        guard statusBar.state == .idle else { return }

        statusBar.state = .transcribing

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let raw: String
                if self.config.effectiveEngine == "gigaam" {
                    raw = try self.gigaamTranscriber.transcribe(audioURL: audioURL)
                } else {
                    raw = try await self.transcriber.transcribe(audioURL: audioURL)
                }
                let dictApplied = DictionaryManager.shared.apply(to: raw)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(dictApplied) : dictApplied
                await MainActor.run {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                    } else {
                        self.statusBar.state = .idle
                    }
                }
                if !text.isEmpty {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        self.statusBar.state = .idle
                        self.statusBar.buildMenu()
                    }
                }
            } catch {
                await MainActor.run {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
