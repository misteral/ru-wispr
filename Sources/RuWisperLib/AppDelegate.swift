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
    var config: Config!
    var overlay: StreamingOverlay!
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
        overlay = StreamingOverlay()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        gigaamTranscriber = GigaAMTranscriber(modelPath: config.gigaamPath)

        DispatchQueue.main.async {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.buildMenu()
        }

        if config.effectiveEngine == "gigaam" {
            if !GigaAMTranscriber.isAvailable(path: config.gigaamPath) {
                print("Error: GigaAM model not found. Set 'gigaamPath' in config (path to gigaam-v3-ctc-mlx directory).")
                return
            }
            // Pre-load model for fast first transcription and streaming
            do {
                print("Loading GigaAM v3 MLX model...")
                try gigaamTranscriber.loadModel()
                print("GigaAM: ready")
            } catch {
                print("Error loading GigaAM model: \(error.localizedDescription)")
                return
            }
        } else {
            if Transcriber.findWhisperBinary() == nil {
                print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
                return
            }
        }

        let wasStale = Permissions.isAccessibilityStale()
        if wasStale {
            print("Accessibility: stale permission detected, resetting...")
            Permissions.resetAccessibility()
            Thread.sleep(forTimeInterval: 1)
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
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
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        if config.effectiveEngine == "whisper" && !Transcriber.modelExists(modelSize: config.modelSize) {
            DispatchQueue.main.async {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress("Downloading \(self.config.modelSize) model...")
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize)
            DispatchQueue.main.async {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
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
        print("ru-wisper v\(RuWisper.version)")
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
        
        if isLocked {
            isLocked = false
            finishRecording()
            return
        }
        
        guard !isPressed else { return }
        isPressed = true
        lastKeyDownTime = Date()
        
        // Delay recording start by 0.1s to ignore very short jitters
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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

            // Set up streaming for GigaAM
            if self.config.effectiveEngine == "gigaam" && self.config.effectiveStreaming {
                self.streamingBuffer = []
                self.lastStreamingText = ""
                self.streamingInsertedText = ""
                self.recorder.onAudioSamples = { [weak self] samples in
                    self?.streamingBuffer.append(contentsOf: samples)
                    
                    // Calculate audio level for waveform visualizer
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(1, samples.count)))
                    DispatchQueue.main.async {
                        self?.overlay.updateAudioLevel(rms)
                    }
                }
                self.startStreamingTranscription()
                DispatchQueue.main.async {
                    self.overlay.show()
                }
            } else {
                self.recorder.onAudioSamples = nil
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
        DispatchQueue.main.async {
            self.overlay.setLocked(false)
            self.overlay.hide()
        }

        guard let audioURL = recorder.stopRecording() else {
            NSLog("[OW] stopRecording returned nil (short press, no recording)")
            statusBar.state = .idle
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                    // For GigaAM, do final transcription from the accumulated buffer
                    NSLog("[OW] Calling gigaam final transcribe on %d samples...", self.streamingBuffer.count)
                    if self.streamingBuffer.count > 4800 {
                        raw = try self.gigaamTranscriber.transcribe(samples: self.streamingBuffer)
                    } else {
                        raw = try self.gigaamTranscriber.transcribe(audioURL: audioURL)
                    }
                    self.streamingBuffer = []
                } else {
                    NSLog("[OW] Calling whisper transcribe...")
                    raw = try self.transcriber.transcribe(audioURL: audioURL)
                }
                NSLog("[OW] Raw transcription: '%@'", raw)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                NSLog("[OW] Final text: '%@'", text)
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        NSLog("[OW] Inserting text...")
                        self.lastTranscription = text
                        self.inserter.insert(text: text)
                        NSLog("[OW] Text inserted OK")
                    } else {
                        NSLog("[OW] Text is empty, skipping insert")
                    }
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            } catch {
                NSLog("[OW] Transcription error: %@", error.localizedDescription)
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try self.gigaamTranscriber.transcribeLive(samples: buffer)
                let currentText = result.cumulativeText
                
                if !currentText.isEmpty && currentText != self.lastStreamingText {
                    self.lastStreamingText = currentText
                    self.overlay.updateText(currentText)
                }
            } catch {
                NSLog("[OW] Streaming transcription error: %@", error.localizedDescription)
            }
        }
    }

    public func reprocess(audioURL: URL) {
        guard statusBar.state == .idle else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw: String
                if self.config.effectiveEngine == "gigaam" {
                    raw = try self.gigaamTranscriber.transcribe(audioURL: audioURL)
                } else {
                    raw = try self.transcriber.transcribe(audioURL: audioURL)
                }
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    } else {
                        self.statusBar.state = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
