# Dikto — пресс-релиз (черновик)

**Статус:** черновик, к публикации не отправлялся.
**Дата подготовки:** 2026-08-27
**Условие публикации:** релиз можно выпускать только после закрытия P0-блокеров
из [readiness.md](readiness.md) — прежде всего после того, как появится
работающая ссылка на скачивание и работающая оплата. Пресс-релиз, ведущий на
несуществующий сайт, сжигает единственную попытку.

Плейсхолдеры для заполнения перед отправкой: `[ДАТА]`, `[ГОРОД]`,
`[ССЫЛКА НА СКАЧИВАНИЕ]`, `[ИНН]` (если издание запрашивает реквизиты).

---

## Русская версия

---

**ПРЕСС-РЕЛИЗ**

### Dikto: голосовой ввод на русском для Mac, который не отправляет вашу речь в облако

**[ГОРОД], [ДАТА]** — Вышел Dikto Pro — приложение для macOS, которое
превращает речь в текст прямо на компьютере пользователя. Достаточно зажать
клавишу, произнести фразу и отпустить: текст появляется там, где стоит курсор —
в мессенджере, почте, браузере или редакторе кода. Распознавание выполняется
локально, на нейросети GigaAM, работающей на чипах Apple Silicon; ни аудиозапись,
ни расшифровка не покидают компьютер и не попадают ни на какие серверы — ни
разработчика, ни третьих сторон.

Голосовой ввод стал массовой функцией, но почти все популярные решения устроены
одинаково: запись уходит на сервер, там распознаётся и возвращается текстом. Для
переписки с коллегами, черновиков документов, врачебных или юридических заметок
это означает, что содержимое речи оказывается у третьей стороны. Dikto построен
на противоположном принципе: приложение вообще не умеет отправлять аудио или
текст наружу — такого кода в нём нет. Единственные сетевые запросы платной
версии — проверка лицензии при активации и повторно раз в семь дней; в них
передаются только лицензионный ключ и анонимный хэш идентификатора устройства.

Русскоязычная версия использует модель GigaAM v3, адаптированную разработчиком
для фреймворка MLX, — она рассчитана на русскую речь и выполняется нативно на
Apple Silicon. Слова появляются на экране по ходу диктовки, а не после её
окончания. Встроенный редактируемый словарь приводит технические термины и
названия к правильному написанию — «API», «Docker», «Kubernetes», имена, бренды.
Приложение живёт в строке меню и работает в любом приложении, где есть текстовый
курсор, — отдельная интеграция каждому приложению не нужна.

За Dikto стоит один разработчик, а не компания. Бесплатная англоязычная версия
Dikto открыта под лицензией MIT: код можно прочитать и убедиться, что обещание
приватности — свойство программы, а не строчка в маркетинге. Платная русская
редакция Dikto Pro продаётся напрямую, без App Store: сумма — 1 990 рублей
единоразово, лицензия пожизненная, активируется на двух компьютерах. Перед
покупкой доступны 14 дней полнофункциональной работы без привязки карты.

> «Диктовка — это ровно тот случай, когда неудобно объяснять пользователю, почему
> его голос обязан улетать на чужой сервер. Современный Mac считает нейросеть
> локально, и это перестало быть компромиссом по качеству, — говорит Александр
> Бобров, автор Dikto. — Я сделал приложение, которое физически не может слить
> вашу речь: там просто нет кода, который отправляет аудио куда бы то ни было.
> Проверить это можно самому — бесплатная версия открыта».

**Доступность.** Dikto Pro распространяется как подписанный и нотаризованный
Apple DMG-образ с сайта [ССЫЛКА НА СКАЧИВАНИЕ]. Требуется Mac на Apple Silicon
(M1 и новее) и macOS 14 Sonoma или новее; версии для процессоров Intel и для
Windows не планируются. Бесплатная англоязычная редакция доступна на GitHub под
лицензией MIT. Покупателям выдаётся чек самозанятого; возврат в течение 14 дней
без объяснения причин.

**О Dikto.** Dikto — приложение для голосового ввода на macOS, которое выполняет
распознавание речи на устройстве пользователя. Проект развивается независимым
разработчиком Александром Бобровым и существует в двух редакциях: свободной
англоязычной (MIT) и коммерческой русскоязычной Dikto Pro. Основной принцип
проекта зафиксирован в его документации: аудио и текст не покидают компьютер.

**Контакты для прессы**
Александр Бобров, разработчик Dikto
Email: support@itbeaver.co
Telegram: @dikto_support
Сайт: dikto.itbeaver.co

*# # #*

---

## English version

---

**PRESS RELEASE**

### Dikto is voice dictation for the Mac that never sends your voice anywhere

**[CITY], [DATE]** — Dikto, a voice dictation app for macOS that runs speech
recognition entirely on the user's own machine, is [available today / opening
sales] at [DOWNLOAD LINK]. Hold a key, speak, release it, and the text appears
wherever the cursor is — in a chat window, an email, a browser field, or a code
editor. No audio recording and no transcript leaves the computer: the app has no
code path that uploads either one.

Most dictation tools work by streaming audio to a server. That is a reasonable
engineering choice and an uncomfortable privacy one — everything dictated,
including drafts, client notes and private messages, passes through somebody
else's infrastructure. Dikto inverts the arrangement. Transcription runs locally
on Apple Silicon, using either whisper.cpp or GigaAM depending on the language,
and the only network requests the paid edition makes are a licence activation
and a repeat check every seven days, carrying nothing but a licence key and an
anonymous device hash.

Dikto ships in two editions. The free edition is open source under the MIT
licence, English-first, and available on GitHub — meaning the privacy claim can
be verified by reading the code rather than trusting a marketing page. Dikto Pro
is a Russian-language commercial edition built from the same code base, using
the GigaAM v3 model adapted for Apple's MLX framework, with streaming
transcription that shows words as they are spoken and an editable dictionary
that normalises technical vocabulary. It sells directly, outside the Mac App
Store, for a one-time 1,990 ₽ (roughly the price of a couple of months of a
subscription competitor), covers two Macs, and includes a 14-day full-feature
trial with no card required.

The project is the work of one developer, and the App Store absence is a
technical consequence rather than a stance: global push-to-talk hotkeys and
inserting text into the frontmost application require entitlements incompatible
with App Sandbox, so Dikto is distributed as a Developer ID-signed, notarised
DMG instead.

> "Dictation is the one feature where it's genuinely hard to justify why a
> person's voice has to travel to someone else's server," says Aleksandr Bobrov,
> the developer behind Dikto. "A current Mac runs the model locally and the
> quality trade-off is gone. So I built the version that physically cannot leak
> your speech — there is no upload code in it at all. And because the free
> edition is open source, that isn't something you have to take my word for."

**Availability.** Dikto requires an Apple Silicon Mac (M1 or later) running
macOS 14 Sonoma or newer; Intel Macs and Windows are not supported and are not
planned. The free English edition is on GitHub under the MIT licence. Dikto Pro
is available at [DOWNLOAD LINK] for the Russian market, with a 14-day trial and
a 14-day refund window.

**About Dikto.** Dikto is a macOS voice dictation app that performs speech
recognition on the user's device. It is developed independently by Aleksandr
Bobrov and comes in two editions: a free, MIT-licensed English edition and Dikto
Pro, a paid Russian-language edition. The project's founding constraint, written
into its own documentation, is that audio and text never leave the machine.

**Press contact**
Aleksandr Bobrov, developer, Dikto
Email: support@itbeaver.co
Telegram: @dikto_support
Web: dikto.itbeaver.co

*# # #*

---

## Фактчек: каждое утверждение — к строке кода

Пресс-релиз проверяется по этой таблице перед отправкой. Если утверждение нельзя
привязать к коду — оно из релиза убирается.

| Утверждение в релизе | Подтверждение |
|---|---|
| Аудио и текст не покидают устройство | Единственные исходящие запросы во всей кодовой базе: `LicenseClient.swift` (activate/validate) и `ModelDownloader.swift` (скачивание модели Whisper). Ни в `AudioRecorder.swift`, ни в `Transcriber.swift`, ни в `GigaAMTranscriber.swift`, ни в `TextInserter.swift` сетевых вызовов нет |
| Активация + проверка раз в 7 дней, в запросе только ключ и хэш устройства | `LicenseManager.revalidateInterval = 7 * 24 * 3600`; тело запроса — `ActivateRequest` в `LicenseClient.swift`: `licenseKey`, `fingerprint` (SHA-256 от `IOPlatformUUID`), `deviceId`, `appVersion`, `os` |
| Push-to-talk: зажал → сказал → отпустил | `HotkeyManager.swift` + `AppDelegate.swift`; hotkey по умолчанию — правый Option (`ProductFlavor` / `Config`) |
| Текст появляется в позиции курсора в любом приложении | `TextInserter.swift` — сохранение буфера обмена, симуляция ⌘V, восстановление буфера. Работает через системный ввод, а не через интеграции с приложениями |
| GigaAM v3, нативно на Apple Silicon через MLX | `GigaAMTranscriber.swift` + `GigaAM/GigaAMModel.swift`, зависимости `MLX`, `MLXNN`, `MLXFFT` в `Package.swift`; веса — `Resources/gigaam-v3-rnnt-mlx/` (423 МБ) |
| Стриминг — слова по ходу диктовки | `StreamingOverlay.swift`, `GigaAMTranscriber` со стриминговым режимом |
| Редактируемый словарь техтерминов | `DictionaryManager.swift`, `DictionaryWindowController.swift`, `Resources/dictionary.json` |
| Только Apple Silicon, macOS 14+ | `Package.swift` → `platforms: [.macOS(.v14)]`; `docs/ARCHITECTURE.md` → «Apple Silicon only (Intel not supported)» |
| Подписанный, нотаризуемый DMG вне App Store | `scripts/release-pro-ru.sh` — прогнан, `codesign` → `Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)`, `spctl` → `accepted`. Причина отказа от App Store — `docs/RELEASING.md`: «App Sandbox is incompatible with core functionality» |
| Free-редакция открыта под MIT | `LICENSE` в корне репозитория (см. B25 в readiness.md — держателя копирайта стоит сверить) |
| 1 990 ₽, пожизненно, 2 устройства, триал 14 дней | Лендинг, `README_RU.md`, роадмап; `ProductFlavor.trialDays = 14`; `schema.ts` → `deviceLimit.default(2)` |
| Чек самозанятого, возврат 14 дней | `legal/refund.html` (ст. 26.1 ЗоЗПП), `backend-prd.md` FR-3. **Осторожно:** механика чеков ещё не реализована (B8) — до релиза убедиться, что чек реально выдаётся |

## Чего в этом релизе намеренно нет

- **Никаких цифр точности и скорости.** Ни «97% точности», ни «в 3 раза быстрее
  печати», ни «текст за 0,8 секунды». Замеров в репозитории нет; выдуманное
  число — первое, на чём ловит технический журналист, и единственное, чего
  нельзя будет отозвать.
- **Никаких сравнений в лоб с конкурентами по качеству.** На лендинге есть
  таблица сравнения с Wispr Flow и Apple Dictation по фактам (цена, локальность,
  push-to-talk) — в пресс-релизе оставлено только собственное позиционирование.
  Цену конкурента упоминаем лишь как порядок величины.
- **Никаких заявлений о числе пользователей, загрузок и выручки.** Их нет.
- **Никакого «первое в мире» / «единственное решение».** Локальная диктовка на
  Mac существует не только у Dikto; уникальна комбинация (русская модель +
  локально + push-to-talk + разовая оплата), а не факт локальности.
- **Никакой заявленной поддержки диктовки в конкретных корпоративных
  сценариях** (медицина, юриспруденция) сверх примера использования — сертификаций
  под это у продукта нет.
- **Формулировка о доступности выбирается по факту.** Пока нет работающей ссылки
  на скачивание, «available today» ставить нельзя — либо дата в будущем, либо
  «opening sales».

## Заметки по адаптации под площадки

- **Habr / vc.ru** — пресс-релиз в чистом виде там читается как реклама. Нужен
  разбор от первого лица: как GigaAM конвертировали под MLX, почему App Sandbox
  несовместим с глобальным hotkey, во что обошлась продажа софта самозанятым.
  Пресс-релиз идёт справочным блоком в конце.
- **Product Hunt / Hacker News** — англоязычные, и там важнее free MIT-редакция,
  чем российская платная. Заход: «local-first dictation, MIT, no cloud», а не
  «купите за 1 990 ₽».
- **Приватностные площадки** — сильнее всего работает третий абзац (что именно
  уходит в сеть и что не уходит). Его стоит выносить вперёд.
- **Русскоязычные Mac-каналы в Telegram** — нужен вариант на 600–800 знаков плюс
  короткое видео/GIF с диктовкой; полный релиз туда не влезает.
