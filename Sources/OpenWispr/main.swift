import AppKit
import Foundation
import OpenWisprLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = OpenWispr.version

func printUsage() {
    print("""
    open-wispr v\(version) — Push-to-talk voice dictation for macOS

    USAGE:
        open-wispr start              Start the dictation daemon
        open-wispr set-hotkey <key>   Set the push-to-talk hotkey
        open-wispr get-hotkey         Show current hotkey
        open-wispr set-model <size>   Set the Whisper model
        open-wispr download-model [size]  Download a Whisper model
        open-wispr status             Show configuration and status
        open-wispr --help             Show this help message

    HOTKEY EXAMPLES:
        open-wispr set-hotkey globe             Globe/fn key (default)
        open-wispr set-hotkey rightoption        Right Option key
        open-wispr set-hotkey f5                 F5 key
        open-wispr set-hotkey ctrl+space         Ctrl + Space

    ENGINES:
        whisper    Use whisper-cpp (default)
        gigaam     Use GigaAM v3 via MLX (Russian, fast on Apple Silicon)

    AVAILABLE MODELS (whisper):
        tiny.en, tiny, base.en, base, small.en, small, medium.en, medium, large
    """)
}

func cmdStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping open-wispr...")
        exit(0)
    }

    app.run()
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'open-wispr --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetModel(_ size: String) {
    let validSizes = ["tiny.en", "tiny", "base.en", "base", "small.en", "small", "medium.en", "medium", "large"]
    guard validSizes.contains(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \(validSizes.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.modelSize = size

    do {
        try config.save()
        print("Model set to: \(size)")
        if !Transcriber.modelExists(modelSize: size) {
            print("Model will be downloaded on next start.")
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    let config = Config.load()
    let desc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
    print("Current hotkey: \(desc)")
}

func cmdDownloadModel(_ size: String) {
    do {
        try ModelDownloader.download(modelSize: size)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetEngine(_ engine: String) {
    let valid = ["whisper", "gigaam"]
    guard valid.contains(engine) else {
        print("Error: Unknown engine '\(engine)'")
        print("Available: \(valid.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.engine = engine
    if engine == "gigaam" {
        config.language = "ru"
    }

    do {
        try config.save()
        print("Engine set to: \(engine)")
        if engine == "gigaam" {
            if GigaAMTranscriber.isAvailable(path: config.gigaamPath) {
                print("GigaAM: model found (native MLX)")
            } else {
                print("GigaAM: model not found. Set 'gigaamPath' to gigaam-v3-ctc-mlx directory")
            }
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)

    print("open-wispr v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Engine:      \(config.effectiveEngine)")
    if config.effectiveEngine == "gigaam" {
        let gigaamReady = GigaAMTranscriber.isAvailable(path: config.gigaamPath)
        print("GigaAM:      \(gigaamReady ? "ready (native MLX)" : "not found")")
        let modelPath = config.gigaamPath ?? GigaAMTranscriber.defaultModelDir.path
        print("GigaAM path: \(modelPath)")
    } else {
        print("Model:       \(config.modelSize)")
        print("Model ready: \(Transcriber.modelExists(modelSize: config.modelSize) ? "yes" : "no")")
        print("whisper-cpp: \(Transcriber.findWhisperBinary() != nil ? "yes" : "no")")
    }
}

let args = CommandLine.arguments

// Filter out macOS launch services arguments (e.g. -NSDocumentRevisionsDebugMode, -psn_...)
let userArgs = args.dropFirst().filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") && !$0.hasPrefix("-psn") }
let command = userArgs.first

// When launched as .app bundle (no arguments), auto-start
let isAppBundle = Bundle.main.bundlePath.hasSuffix(".app")

switch command {
case "start":
    cmdStart()
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: open-wispr set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-model":
    guard args.count > 2 else {
        print("Usage: open-wispr set-model <size>")
        exit(1)
    }
    cmdSetModel(args[2])
case "set-engine":
    guard args.count > 2 else {
        print("Usage: open-wispr set-engine <whisper|gigaam>")
        exit(1)
    }
    cmdSetEngine(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "download-model":
    let size = args.count > 2 ? args[2] : "base.en"
    cmdDownloadModel(size)
case "status":
    cmdStatus()
case "test-gigaam":
    let audioFile = args.count > 2 ? args[2] : nil
    let config = Config.load()
    let transcriber = GigaAMTranscriber(modelPath: config.gigaamPath)
    do {
        let t0 = CFAbsoluteTimeGetCurrent()
        try transcriber.loadModel()
        print("Model loaded in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")

        if let file = audioFile {
            let t1 = CFAbsoluteTimeGetCurrent()
            let text = try transcriber.transcribe(audioURL: URL(fileURLWithPath: file))
            print("Transcribed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t1))s")
            print("Result: \(text)")
        } else {
            print("GigaAM: ready (native MLX)")
            print("Usage: open-wispr test-gigaam <audio-file>")
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
case "--help", "-h", "help":
    printUsage()
case nil:
    if isAppBundle {
        cmdStart()
    } else {
        printUsage()
    }
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
