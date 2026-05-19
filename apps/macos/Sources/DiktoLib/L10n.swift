/// Lightweight localisation helper.
/// Uses the `language` field from Config: `"ru"` → Russian, everything else → English.
/// The Pro RU build overrides this to always Russian via `ProductFlavor.forcedLanguage`.
enum L10n {
    /// Current UI language — set once at startup and on config reload.
    /// In Pro RU flavor this is forced to "ru" regardless of config.
    static var language: String = ProductFlavor.current.forcedLanguage ?? "en" {
        didSet {
            if let forced = ProductFlavor.current.forcedLanguage, language != forced {
                language = forced
            }
        }
    }

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
    static var openDictionary: String { isRussian ? "Открыть словарь..." : "Open Dictionary..." }
    static var quit: String { isRussian ? "Выход" : "Quit" }

    // MARK: - Dictionary editor

    static var dictionaryTitle: String { isRussian ? "Словарь Dikto" : "Dikto Dictionary" }
    static var dictionaryIntro: String {
        isRussian
            ? "Замените фразу, которую вы говорите, на текст, который Dikto вставит вместо неё."
            : "Replace a phrase you say with the text Dikto should paste in its place."
    }
    static var dictionaryColumnPhrase: String { isRussian ? "Что говорю" : "Spoken phrase" }
    static var dictionaryColumnReplacement: String { isRussian ? "Что вставить" : "Replacement" }
    static var dictionaryDone: String { isRussian ? "Готово" : "Done" }
    static var dictionaryAddTooltip: String { isRussian ? "Добавить замену" : "Add entry" }
    static var dictionaryRemoveTooltip: String { isRussian ? "Удалить выбранные" : "Remove selected" }

    static func hotkey(_ value: String) -> String {
        isRussian ? "Клавиша: \(value)" : "Hotkey: \(value)"
    }

    static func engine(_ value: String) -> String {
        isRussian ? "Движок: \(value)" : "Engine: \(value)"
    }

    // MARK: - Overlay / accessibility

    static var processing: String { isRussian ? "Обработка..." : "Processing..." }
    static var done: String { isRussian ? "Готово" : "Done" }
    static var notRecognized: String { isRussian ? "Не распознано" : "Not recognized" }
    static var microphoneSilent: String { isRussian ? "Микрофон молчит" : "Microphone silent" }

    static func recordingAccessibility(_ text: String) -> String {
        isRussian ? "Запись: \(text)" : "Recording: \(text)"
    }

    // MARK: - Downloads

    static func downloadingModelNamed(_ name: String) -> String {
        isRussian ? "Загрузка модели \(name)..." : "Downloading \(name) model..."
    }

    // MARK: - Startup errors

    static var startupErrorTitle: String {
        isRussian ? "Dikto не смог запуститься" : "Dikto failed to start"
    }

    static var statusError: String {
        isRussian ? "Ошибка" : "Error"
    }

    static var gigaamModelMissing: String {
        isRussian
            ? "Модель GigaAM не найдена. Укажите 'gigaamPath' в config.json или вложите модель в bundle приложения."
            : "GigaAM model not found. Set 'gigaamPath' in config.json or bundle the model with the app."
    }

    static func gigaamLoadFailed(_ detail: String) -> String {
        isRussian
            ? "Не удалось загрузить модель GigaAM: \(detail)"
            : "Failed to load GigaAM model: \(detail)"
    }

    static var whisperBinaryMissing: String {
        isRussian
            ? "whisper-cpp не установлен. Установите через 'brew install whisper-cpp'."
            : "whisper-cpp not found. Install with 'brew install whisper-cpp' or from https://github.com/ggerganov/whisper.cpp."
    }

    // MARK: - License / trial (Pro RU)

    static func trialDaysLeft(_ days: Int) -> String {
        if isRussian {
            // Russian plural — 1 день, 2-4 дня, 5+ дней.
            let mod10 = days % 10
            let mod100 = days % 100
            let unit: String
            if mod10 == 1 && mod100 != 11 { unit = "день" }
            else if (2...4).contains(mod10) && !(12...14).contains(mod100) { unit = "дня" }
            else { unit = "дней" }
            return "Триал: \(days) \(unit)"
        } else {
            return days == 1 ? "Trial: 1 day left" : "Trial: \(days) days left"
        }
    }

    static var trialExpiredBanner: String {
        isRussian ? "Триал закончился — введите ключ" : "Trial expired — enter a license key"
    }

    static var licenseActive: String {
        isRussian ? "Лицензия активна" : "License active"
    }

    static var licenseInvalid: String {
        isRussian ? "Лицензия не подтверждена" : "License not validated"
    }

    static var licenseInvalidKey: String {
        isRussian ? "Неверный ключ лицензии" : "Invalid license key"
    }

    static var licenseDeviceLimit: String {
        isRussian
            ? "Лимит устройств для этого ключа исчерпан"
            : "Device limit reached for this license"
    }

    static var menuBuyLicense: String {
        isRussian ? "Купить лицензию" : "Buy a license"
    }

    static var menuActivate: String {
        isRussian ? "Активировать..." : "Activate..."
    }

    static var menuDeactivate: String {
        isRussian ? "Деактивировать лицензию" : "Deactivate license"
    }

    // MARK: - Activation window

    static var activationTitle: String {
        isRussian ? "Активация Dikto Pro" : "Activate Dikto Pro"
    }

    static var activationIntro: String {
        isRussian
            ? "Введите ключ, который пришёл на e-mail после покупки."
            : "Enter the license key that was sent to you after purchase."
    }

    static var activationKeyPlaceholder: String {
        isRussian ? "XXXX-XXXX-XXXX-XXXX" : "XXXX-XXXX-XXXX-XXXX"
    }

    static var activationButton: String {
        isRussian ? "Активировать" : "Activate"
    }

    static var activationBuyButton: String {
        isRussian ? "Купить ключ" : "Buy a key"
    }

    static var activationLaterButton: String {
        isRussian ? "Позже" : "Later"
    }

    static var activationInProgress: String {
        isRussian ? "Проверка ключа..." : "Verifying..."
    }

    static var activationSuccess: String {
        isRussian ? "Лицензия активирована" : "License activated"
    }

    static var activationPrivacyNote: String {
        isRussian
            ? "Активация — единственный сетевой запрос. Аудио и текст никогда не покидают ваш Mac."
            : "Activation is the only network call. Audio and text never leave your Mac."
    }

    static var trialBlockingTitle: String {
        isRussian ? "Триал Dikto Pro закончился" : "Dikto Pro trial expired"
    }

    static var trialBlockingMessage: String {
        isRussian
            ? "Чтобы продолжить пользоваться диктовкой, активируйте лицензию или купите новую."
            : "To keep dictating, activate a license or buy a new one."
    }
}
