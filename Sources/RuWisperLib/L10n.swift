/// Lightweight localisation helper.
/// Uses the `language` field from Config: `"ru"` → Russian, everything else → English.
enum L10n {
    /// Current UI language — set once at startup and on config reload.
    static var language: String = "en"

    static var isRussian: Bool { language == "ru" }

    // MARK: - Status bar states

    static var ready: String { isRussian ? "Готово" : "Ready" }
    static var recording: String { isRussian ? "Запись..." : "Recording..." }
    static var transcribing: String { isRussian ? "Распознавание..." : "Transcribing..." }
    static var downloadingModel: String { isRussian ? "Загрузка модели..." : "Downloading model..." }
    static var waitingForAccessibility: String {
        isRussian
            ? "Ожидание разрешения Accessibility..."
            : "Waiting for Accessibility permission..."
    }
    static var copiedToClipboard: String { isRussian ? "Скопировано в буфер" : "Copied to clipboard" }

    // MARK: - Menu items

    static var copyLastDictation: String { isRussian ? "Скопировать последнюю диктовку" : "Copy Last Dictation" }
    static var copied: String { isRussian ? "Скопировано!" : "Copied!" }
    static var recentRecordings: String { isRussian ? "Последние записи" : "Recent Recordings" }
    static var noRecordings: String { isRussian ? "Нет записей" : "No recordings" }
    static var reloadConfiguration: String { isRussian ? "Перезагрузить конфигурацию" : "Reload Configuration" }
    static var openConfiguration: String { isRussian ? "Открыть конфигурацию" : "Open Configuration" }
    static var quit: String { isRussian ? "Выход" : "Quit" }

    static func hotkey(_ value: String) -> String {
        isRussian ? "Клавиша: \(value)" : "Hotkey: \(value)"
    }

    static func engine(_ value: String) -> String {
        isRussian ? "Движок: \(value)" : "Engine: \(value)"
    }

    // MARK: - Overlay / accessibility

    static func recordingAccessibility(_ text: String) -> String {
        isRussian ? "Запись: \(text)" : "Recording: \(text)"
    }

    // MARK: - Downloads

    static func downloadingModelNamed(_ name: String) -> String {
        isRussian ? "Загрузка модели \(name)..." : "Downloading \(name) model..."
    }
}
