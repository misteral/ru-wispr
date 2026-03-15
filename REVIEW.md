# Code Review: SwiftUI & Modern Swift API (ru-wispr)

В ходе ревью были проанализированы файлы исходного кода на соответствие современным стандартам SwiftUI и Swift 6 (описанным в `swiftui-pro`), включая строгую консистентность данных, отказ от GCD в пользу Swift Concurrency и использование нативных API Foundation.

### Sources/RuWisperLib/StreamingOverlay.swift

**Line 4: `@Observable` classes must be marked `@MainActor` unless default isolated.**

Для обеспечения потокобезопасности при обновлениях UI, модели данных должны быть привязаны к главному актору.

```swift
// Before
@Observable
final class StreamingOverlayState {

// After
@MainActor
@Observable
final class StreamingOverlayState {
```

**Line 26: Do not force specific font sizes. Prefer Dynamic Type.**

Жестко заданные размеры шрифтов ухудшают доступность (Accessibility). Лучше использовать семантические стили или модификаторы веса.

```swift
// Before
Text(state.text)
    .font(.system(size: 16, weight: .light))

// After
Text(state.text)
    .font(.body.weight(.light))
```

### Sources/RuWisperLib/AudioLevelHistory.swift

**Line 14: `@Observable` classes must be marked `@MainActor`.**

Класс напрямую используется в `WaveformCanvas` и `RecordingIndicator`. Если обновления приходят из фонового аудио-потока, следует перевести их на `MainActor`.

```swift
// Before
@Observable
final class AudioLevelHistory {

// After
@MainActor
@Observable
final class AudioLevelHistory {
```

### Sources/RuWisperLib/AppDelegate.swift

**Lines 32, 54, etc.: Never use Grand Central Dispatch (`DispatchQueue`). Always use modern Swift concurrency.**

В проекте повсеместно используется GCD (`DispatchQueue.main.async`, `DispatchQueue.global`). Рекомендуется перейти на `Task` и `async/await`.

```swift
// Before
DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    self?.setup()
}

// After
Task {
    await self.setup()
}
```

### Sources/RuWisperLib/Transcriber.swift

**Line 23: Prefer modern Foundation API (`URL(filePath:)` over `URL(fileURLWithPath:)`).**

Начиная с macOS 13 (проект таргетит macOS 14), `URL(filePath:)` является стандартом для работы с путями файловой системы.

```swift
// Before
process.executableURL = URL(fileURLWithPath: whisperPath)

// After
process.executableURL = URL(filePath: whisperPath)
```

**Line 36: Never use `Thread` or `Thread.sleep()`. Always use modern Swift concurrency.**

Блокирование потоков через `Thread.sleep` и ручное создание `Thread` является антипаттерном в современном Swift. Рекомендуется сделать функцию `transcribe` асинхронной (`async throws`).

```swift
// Before
let stderrThread = Thread {
    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
}
stderrThread.start()
let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
while !stderrThread.isFinished { Thread.sleep(forTimeInterval: 0.01) }

// After (requires async context)
async let stdout = stdoutPipe.fileHandleForReading.readToEnd()
async let stderr = stderrPipe.fileHandleForReading.readToEnd()
let (data, errorData) = try await (stdout, stderr)
```

### Sources/RuWisperLib/TextPostProcessor.swift

**Line 26: Prefer Swift-native string methods over Foundation equivalents.**

Вместо `NSRegularExpression` в Swift 5.7+ предпочтительнее использовать нативный `Regex`. Это безопаснее и читабельнее.

```swift
// Before
guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
result = regex.stringByReplacingMatches(
    in: result,
    range: NSRange(result.startIndex..., in: result),
    withTemplate: replacement
)

// After
if let regex = try? Regex(pattern).ignoresCase() {
    result = result.replacing(regex, with: replacement)
}
```

### Sources/RuWisper/main.swift

**Line 205: Never use C-style number formatting like `String(format:)`.**

Современный подход — использование `FormatStyle` API.

```swift
// Before
print("Model loaded in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")

// After
let duration = CFAbsoluteTimeGetCurrent() - t0
print("Model loaded in \(duration.formatted(.number.precision(.fractionLength(2))))s")
```

### Sources/RuWisperLib/GigaAMTranscriber.swift

**Line 20: Prefer modern Foundation API (`appending(path:)` over `appendingPathComponent()`).**

Современный способ добавления компонентов к URL.

```swift
// Before
Config.configDir.appendingPathComponent("models/gigaam-v3-ctc-mlx")

// After
Config.configDir.appending(path: "models/gigaam-v3-ctc-mlx")
```

### Summary

1. **Concurrency (High):** Полный отказ от `DispatchQueue` и `Thread` в пользу `Task`, `async/await` и акторов. Это ключевое архитектурное изменение для Swift 6.
2. **Data Flow (Medium):** Добавление аннотации `@MainActor` ко всем `@Observable` классам (`StreamingOverlayState`, `AudioLevelHistory`), чтобы исключить гонки данных при обновлении UI.
3. **Modern API (Medium):** Замена старых Foundation API (`URL(fileURLWithPath:)`, `appendingPathComponent`, `NSRegularExpression`, `String(format:)`) на их современные Swift-native аналоги (`URL(filePath:)`, `appending(path:)`, `Regex`, `.formatted()`).
4. **Design / Accessibility (Low):** Использование семантических (Dynamic Type) шрифтов вместо фиксированного размера `16pt` в оверлее.
