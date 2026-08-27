# Dikto — Go-to-market readiness

**Дата аудита:** 2026-08-27
**Ветка:** `main` @ `a1af263` (последний коммит — 2026-05-20, последний тег — `v0.19.0`)
**Автор аудита:** агентная проверка репозитория с прогоном команд, не по документации

Этот документ отвечает на один вопрос: **что стоит между текущим состоянием
репозитория и первым рублём выручки.** Каждая строка таблицы блокеров
подтверждена либо командой, которую я выполнил, либо строкой кода, которую
я прочитал. Гипотезы помечены отдельно.

---

## 0. Краткий вывод

Продукт **технически работает**, но **продать его сегодня невозможно ни одним
способом** — и дело не в одной поломке, а в том, что вся цепочка от «увидел» до
«активировал» разорвана в пяти местах одновременно:

| Звено цепочки | Состояние |
|---|---|
| Узнать о продукте | ✗ `dikto.itbeaver.co` не резолвится в DNS |
| Скачать приложение | ✗ ни одного GitHub Release; все ссылки на скачивание → 404 |
| Заплатить | ✗ в `buy.html` плейсхолдер `REPLACE_ME`, продукт в Lava.top не создан |
| Получить ключ | ✗ веб-хук — заглушка, email-отправки нет, бэкенд нигде не развёрнут |
| Активировать ключ | ✗ `POST /v1/activate` возвращает `501 not_implemented` |

При этом само приложение собирается, все 99 тестов проходят, GigaAM работает
нативно, а 14-дневный триал полностью локален и **уже сегодня работает без
сервера**. Это важно: до денег ближе, чем кажется, если сменить схему
лицензирования (см. §8).

**Минимальный путь до первой продажи — 3–5 рабочих дней разработки** (вариант Б,
оффлайн-лицензии) **или 9–14 дней** (вариант А, текущий онлайн-бэкенд), плюс
внешние задержки, которые от разработки не зависят: регистрация в Lava.top,
получение ИНН самозанятого, нотаризация у Apple, юридическая вычитка оферты.

---

## 1. Собирается ли и запускается ли macOS-приложение сегодня? — **Да**

Проверено по `docs/TESTING.md` и `AGENTS.md → Quick Commands`, всё запускалось
на этой машине (Apple M4 Pro, macOS 26.x, Xcode 26.5):

| Команда | Результат |
|---|---|
| `swift build -c release` | ✅ `Build complete! (153.71s)`, exit 0 |
| `swift test` | ✅ `Executed 99 tests, with 7 tests skipped and 0 failures` |
| `DIKTO_FLAVOR=pro_ru swift test` | ✅ `Executed 99 tests, with 1 test skipped and 0 failures` |
| `.build/release/dikto --help` | ✅ `dikto v1.0.0 — Push-to-talk voice dictation for macOS` |
| `.build/release/dikto status` | ✅ `Engine: gigaam`, `GigaAM: ready (native MLX)` |
| `.build/release/dikto get-hotkey` | ✅ `Current hotkey: rightalt` |

Пропущенные тесты — это тесты транскрипции, которым нужен внешний WAV-файл
(`Test audio not found at .../GigaAM/mlx_convert/test_ru.wav, skipping`), а не
поломки.

Заметки по окружению:

- `whisper-cpp` **не установлен** на этой машине — движок Whisper здесь
  нерабочий. Для Pro RU это не блокер: Pro RU по умолчанию GigaAM, а модель
  (423 МБ) лежит в `apps/macos/Resources/gigaam-v3-rnnt-mlx/` и вшивается в
  DMG. Для free-редакции на английском Whisper — основной путь, и он требует
  от пользователя `brew install whisper-cpp` (это уже описано в README).
- Приложение — menu-bar агент (`LSUIElement`), `dikto start` требует TCC-разрешений
  (микрофон + Accessibility). Я намеренно **не** запускал `start`: в headless-сессии
  это дало бы только зависшие диалоги разрешений. Проверка «работает у живого
  пользователя» осталась за человеком; косвенно в пользу неё — установленный
  на этой машине `/Applications/Dikto.app`, то есть цикл сборки и установки
  исторически проходил.

---

## 2. Лицензионный бэкенд: в каком он состоянии и что реально происходит при покупке

### 2.1. Состояние кода — рабочий каркас, нулевая бизнес-логика

`apps/backend/README.md` честно пишет **«Status: scaffold (Sprint 0)»**, и это
подтверждается прогоном. Что я сделал: `npm install` (отработал pnpm 10.33,
14.2 с), `npx tsc --noEmit` (**чисто, 0 ошибок**), `npm test`, затем поднял
сервер локально и постучался во все эндпоинты.

```
$ npm test
No test files found, exiting with code 1
```

**Тестов у бэкенда нет вообще** — при том что `AGENTS.md → Critical Rules`
требует «New pure logic → unit test … backend → `apps/backend/src/**/*.test.ts`».

```
$ NODE_ENV=production DATABASE_URL=... TOKEN_HASH_PEPPER=... npx tsx src/server.ts
$ curl localhost:3111/healthz
{"status":"ok","uptime":6.45}                                            HTTP 200

$ curl -X POST localhost:3111/v1/activate -d '{...валидное тело...}'
{"error":"not_implemented","message":"Activation endpoint stub — реализуем в Sprint 1 backend"}   HTTP 501

$ curl "localhost:3111/v1/validate?deviceId=..." -H "Authorization: Bearer tok_test"
{"error":"not_implemented","message":"Validate endpoint stub — реализуем в Sprint 1 backend"}     HTTP 501

$ curl -X POST localhost:3111/webhooks/lava -H "x-api-signature: deadbeef" -d '{"a":1}'
{"statusCode":500,"code":"ERR_CRYPTO_TIMING_SAFE_EQUAL_LENGTH", ...}                              HTTP 500
```

Схема БД (`src/db/schema.ts`) описана полностью и грамотно — `licenses`,
`activations`, `payments`, `webhook_events` с уникальными индексами под
идемпотентность. Но **миграции не сгенерированы** (`drizzle/` в репозитории
нет), Postgres нигде не поднят, а ни один запрос из кода в БД не идёт: в
`src/` нет ни одного `import { db }`, только `TODO Sprint 1` в трёх местах.

Три дефекта, найденные при прогоне (не «стиль», а реально ломающееся):

1. **`npm run dev` падает из коробки.** `src/server.ts:14` в
   `NODE_ENV=development` включает `transport: { target: 'pino-pretty' }`, но
   `pino-pretty` отсутствует в `package.json`. Итог:
   `Error: unable to determine transport target for "pino-pretty"` — процесс
   умирает до `listen`. Любой, кто впервые следует `apps/backend/README.md`,
   упирается в это на первой команде. Починка — одна строка в `devDependencies`.
2. **Веб-хук Lava 500-ит на кривой подписи.** `src/routes/webhooks.ts:23`
   вызывает `crypto.timingSafeEqual` на буферах разной длины, а он в этом
   случае бросает `RangeError`. Правильное поведение — `401`; сейчас любой
   мусор в заголовке `x-api-signature` даёт `500` и шум в логах (и, что важнее
   для PSP, Lava будет ретраить 500-ки).
3. **Подпись веб-хука не сойдётся с реальной.** Там же, строка 21:
   `JSON.stringify(req.body)` — HMAC считается по **пересобранному** JSON, а не
   по сырому телу запроса. Порядок ключей, пробелы и Unicode-экранирование у
   отправителя и у нас почти наверняка разойдутся. Нужен raw-body хук Fastify
   (`addContentTypeParser` с сохранением буфера). Это тот класс бага, который
   вылезает уже в проде, когда деньги пришли, а ключ не выдан.

### 2.2. Клиент — полностью готов и ждёт сервера

Клиентская половина сделана и оттестирована, в отличие от серверной:

- `Sources/DiktoLib/LicenseManager.swift` — триал в
  `~/Library/Application Support/Dikto/license.json`, лицензия в Keychain,
  защита от перевода часов назад (`effectiveNow = max(now, file.lastSeen)`),
  ревалидация раз в 7 дней. Покрыт `Tests/DiktoTests/LicenseManagerTests.swift`.
- `Sources/DiktoLib/LicenseClient.swift` — `POST /v1/activate`, `GET /v1/validate`,
  fingerprint = SHA-256 от `IOPlatformUUID`, при сетевой ошибке лицензия
  **не** отзывается (`validateIfPossible` молча выходит) — правильное поведение.
- `Sources/DiktoLib/ActivationWindowController.swift` — окно ввода ключа с
  кнопками «Активировать» / «Купить».
- `Sources/DiktoLib/AppDelegate.swift:257-263` — гейт: в Pro RU при
  `!status.allowsRecording` запись блокируется и принудительно показывается
  окно активации.

**Вывод по §2:** сервер — единственная недостающая половина, и она же самая
дорогая. Клиент к ней готов на 100%.

### 2.3. Сквозная трассировка «пользователь платит» — где рвётся

| # | Шаг | Что происходит сегодня |
|---|---|---|
| 1 | Пользователь открывает `dikto.itbeaver.co/buy` | ✗ **Домен не резолвится.** `dig +short dikto.itbeaver.co` → пусто. `itbeaver.co` живёт на Cloudflare (`dilbert/nora.ns.cloudflare.com`), но поддомена нет. |
| 2 | Жмёт «Купить за 1 990 ₽» | ✗ `buy.html:24` — `content="https://app.lava.top/products/REPLACE_ME"`. Скрипт на `buy.html:315` это ловит и подменяет кнопку на неактивную «Покупка скоро откроется» + mailto. То есть заглушка отработает корректно, но денег не возьмёт. |
| 3 | Платит в Lava.top | ✗ Продукт в Lava.top не создан (требуется регистрация самозанятого — действие человека). |
| 4 | Lava шлёт веб-хук | ✗ `api.dikto.itbeaver.co` не резолвится, бэкенд нигде не развёрнут. Даже локально: подпись считается по пересобранному JSON (§2.1.3), а обработчик — заглушка с `202 accepted` и `TODO`. |
| 5 | Пользователь получает ключ на email | ✗ Кода отправки писем нет вообще: `RESEND_API_KEY` есть в `.env.example`, но `resend` не в `package.json` и нигде не импортируется. Генерации ключа (`XXXX-XXXX-XXXX-XXXX` по PRD FR-2) в коде тоже нет. |
| 6 | Получает чек НПД | ✗ `NPD_INN` / `NPD_REFRESH_TOKEN` объявлены в `src/config.ts`, но не используются ни разу. Нужен либо авточек от Lava, либо интеграция с `lknpd.nalog.ru`. **Требует решения человека** — см. §5. |
| 7 | Скачивает DMG | ✗ Скачать неоткуда. См. §3. |
| 8 | Вводит ключ в приложении | ✗ `501 not_implemented` (проверено curl'ом). Пользователь видит ошибку активации. |

Каждое из восьми звеньев сегодня нерабочее. `success.html:107` при этом уже
обещает покупателю: «В течение минуты на ваш email придут два письма:
лицензионный ключ и чек НПД» — обещание, которое сейчас нечем исполнить.

---

## 3. Отдельно: дистрибуции нет ни у одной редакции

Это не подпункт бэкенда, это самостоятельный блокер, который легко упустить.

```
$ gh release list --repo misteral/ru-wispr
(пусто — ни одного релиза)

$ git ls-remote --tags origin | grep v0.19
b22b6ef...  refs/tags/v0.19.0        # тег запушен, релиза под ним нет

$ curl -sIL https://github.com/misteral/dikto/releases/latest -o /dev/null -w "%{http_code}"
404
$ gh repo view misteral/dikto
GraphQL: Could not resolve to a Repository with the name 'misteral/dikto'
```

Репозиторий по-прежнему называется **`ru-wispr`**, а весь маркетинг ссылается
на несуществующий `misteral/dikto`:

| Файл | Строка | Битая ссылка |
|---|---|---|
| `apps/macos/README.md` | 16 | `github.com/misteral/dikto/releases` — «Download the latest DMG» |
| `apps/macos/Sources/DiktoLib/ProductFlavor.swift` | 68 | `supportURL` free-редакции → `github.com/misteral/dikto/issues` |
| `apps/landing/en/index.html` | 621 | `curl -fsSL https://raw.githubusercontent.com/misteral/dikto/main/scripts/install.sh \| bash` |
| `docs/index.html` | 195 | `⬇ Download DMG` на **живом** сайте (см. ниже) |

И — неожиданная находка — **живой сайт у продукта уже есть**, только не тот:
GitHub Pages отдаёт `main:/docs` по адресу `https://misteral.github.io/ru-wispr/`
(`gh api repos/misteral/ru-wispr/pages` → `"status":"built"`, `"cname":null`).
Это старый английский лендинг Dikto, он возвращает `200`, и его главная кнопка
«Download DMG» ведёт в 404. То есть единственная публичная витрина продукта
сегодня — страница с нерабочей кнопкой скачивания под старым именем репозитория.

Ещё одна поломка в доставке лендинга: `.github/workflows/deploy.yml` фильтрует
пуши по путям `index.html`, `demo.html`, `robots.txt`… — файлам **в корне
репозитория**, которых после перехода на монорепу там больше нет (всё уехало в
`apps/landing/`). Плюс сама команда — `pages deploy .` из корня, то есть
задеплоила бы весь репозиторий вместо лендинга. Последний запуск этого workflow
(2026-05-19, коммит реструктуризации) — **failure**, и с тех пор он больше не
триггерился ни разу.

---

## 4. Как Pro RU вообще предполагается продавать — решение принято, но с трещиной

**Принято и задокументировано:** прямая продажа DMG + лицензионный ключ, без
Mac App Store, без подписки. `docs/exec-plans/dikto-pro-ru-roadmap.md` в разделе
«What this plan deliberately does NOT do» перечисляет явно: не MAS
(«продаём прямой DMG»), не подписка («выбран one-time + триал»), не мобильные
клиенты, не облачная транскрипция. `backend-prd.md` §2 повторяет то же.
Обоснование отказа от App Store — техническое и убедительное:
App Sandbox несовместим с глобальным hotkey и вставкой текста через Accessibility
(`docs/RELEASING.md`: «App Sandbox is incompatible with core functionality»).

**Трещина:** *как* проверять лицензию — решено дважды и по-разному.

- `dikto-pro-ru-roadmap.md` + `backend-prd.md` + весь написанный код →
  **онлайн-активация с сервером и БД**.
- `docs/exec-plans/licensing-research.md` (статус: «research, не решение») →
  **оффлайн-проверка подписи Ed25519**, и прямым текстом про онлайн-вариант:
  «план долгосрочно (Sprint 2-3 нашего PRD), но **не сейчас**», а про
  оффлайн — «**рекомендуемый вариант для первых продаж** … ~50 строк Swift +
  ~30 строк CLI, можно реализовать за полдня».

Судя по датам, research-документ появился **после** того, как онлайн-клиент был
написан, и его вывод так и не был перенесён в роадмап (сам документ этого и
требует: «После прочтения нужно сделать выбор и обновить `dikto-pro-ru-roadmap.md`»).
Это **единственное открытое архитектурное решение**, и именно оно определяет,
9–14 дней до первой продажи или 3–5. Разбор обоих путей — §8.

---

## 5. Платёжный рельс: что подключено, чего не хватает

**Выбор сделан:** Lava.top как primary PSP, ЮKassa как backup. Обоснование в
`licensing-research.md` — из всех рассмотренных (Paddle, Lemon Squeezy, Gumroad,
Keygen, Cryptolens) **только Lava.top работает с самозанятым из РФ**, остальные
отсеяны по этому признаку. Комиссия ~5%.

Что уже написано в коде:

| Элемент | Где | Состояние |
|---|---|---|
| Кнопка оплаты | `apps/landing/buy.html:24, 305-325` | Каркас + корректный fallback, ждёт URL продукта |
| Redirect-страницы | `success.html`, `cancel.html` | Готовы, свёрстаны |
| Веб-хук Lava | `src/routes/webhooks.ts:10-40` | Заглушка, 2 бага (§2.1) |
| Веб-хук ЮKassa | `src/routes/webhooks.ts:42-46` | `501`, помечен «Sprint 3» |
| Env-переменные | `.env.example` | Объявлены: `LAVA_API_KEY`, `LAVA_WEBHOOK_SECRET`, `YOOKASSA_*`, `NPD_*`, `RESEND_API_KEY`, `TELEGRAM_*` — **все пустые** |
| Оферта / политика / возврат | `apps/landing/legal/*.html` | Написаны, помечены «Черновик — требует юридической проверки» |

**Чего не хватает и что требует человека — я это не делал и делать не должен:**

| # | Действие | Почему только человек |
|---|---|---|
| H1 | Регистрация самозанятого в «Мой налог», получение ИНН | Персональные данные, госсервис. Без ИНН оферта неполна: `legal/terms.html:61` → `ИНН: __________ (заполняется)` |
| H2 | Регистрация в Lava.top (`app.lava.top/business`), создание продукта «Dikto Pro — пожизненная лицензия» за 1 990 ₽, копирование URL продукта в `buy.html` | Регистрация аккаунта + модерация продукта |
| H3 | **Выяснить у Lava.top, кто выдаёт чек НПД** — сам PSP или мы через `lknpd.nalog.ru` | От ответа зависит, нужен ли отдельный модуль чеков в бэкенде (это разница в несколько дней работы). В репозитории есть оба сценария и нет ответа; проверять это по памяти или по устаревшим статьям нельзя — только в кабинете Lava |
| H4 | Аккаунт Resend (или альтернативы) + верификация домена `itbeaver.co` для писем с ключами | Аккаунт + DNS-записи |
| H5 | Телеграм-бот/канал `@dikto_support` | `curl https://t.me/dikto_support` отдаёт пустой `og:description` без заголовка профиля — так выглядит **незанятый** username. Ссылка на него уже стоит в футере лендинга, в `buy.html:236` и в `success.html:140` |
| H6 | Юридическая вычитка трёх legal-страниц | Все три помечены черновиками; дистанционная продажа ПО самозанятым, 152-ФЗ и ст. 26.1 ЗоЗПП |
| H7 | Подключить `dikto.itbeaver.co` и `api.dikto.itbeaver.co` в Cloudflare | Доступ к панели Cloudflare. Домен `itbeaver.co` уже там — это настройка, а не покупка |
| H8 | Проверить лицензию модели GigaAM на перепродажу | В DMG вшивается 423 МБ весов (`Resources/gigaam-v3-rnnt-mlx/`), рядом с ними **нет файла лицензии**, и нигде в репозитории условия использования модели не зафиксированы. README ссылается на `github.com/salute-developers/GigaAM` и HF-конверсию `al-bo/gigaam-v3-rnnt-mlx`. Прежде чем брать за это деньги, условия нужно прочитать в первоисточнике — утверждать что-либо по памяти здесь нельзя |

Почтовая часть, что можно проверить не отправляя писем: у `itbeaver.co` **есть**
MX (`mx01/mx02.mail.icloud.com` + `route1-3.mx.cloudflare.net`) и корректный SPF
(`v=spf1 include:_spf.mx.cloudflare.net include:icloud.com ~all`). То есть почта
на домене в принципе настроена; доходит ли конкретно `support@itbeaver.co` —
проверяется одним письмом (H4).

---

## 6. Сборка DMG и нотаризация — путь рабочий

Предпосылки на этой машине проверены по факту:

| Проверка | Результат |
|---|---|
| `security find-identity -v -p codesigning` | ✅ `Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)` — совпадает с `docs/RELEASING.md` |
| `xcode-select -p` | ✅ полный Xcode 26.5 (не CommandLineTools) |
| Metal Toolchain | ✅ установлен (скрипт падает, если нет) |
| Модель GigaAM для бандла | ✅ `Resources/gigaam-v3-rnnt-mlx/` — 423 МБ, `config.json` + `model.safetensors` |
| `bash scripts/release-pro-ru.sh` (без `APPLE_ID`/`APP_PASSWORD`) | см. §6.1 |

### 6.1. Результат прогона `release-pro-ru.sh`

**Прогон выполнен, exit code 0.** Полный путь отработал без вмешательства:

```
==> Checking signing identity...
Found: Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)
==> Building with xcodebuild (Pro RU flavor, Release + Metal shaders)...
** BUILD SUCCEEDED **
==> Bundling GigaAM RNNT model ...            423M
App bundle: .../dist-pro-ru/Dikto Pro.app     475M
==> Signing with Developer ID...
Verifying signature...                        Signature OK ✓
.../Dikto Pro.app: accepted                   source=Developer ID
==> Creating DMG...
DMG: .../dist-pro-ru/Dikto-Pro-1.0.0.dmg      425M
⚠  Skipping notarization (APPLE_ID and APP_PASSWORD not set)
```

Проверки поверх результата:

| Проверка | Результат |
|---|---|
| `codesign -dv` по DMG | `Authority=Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)` → `Developer ID Certification Authority` → `Apple Root CA` |
| `spctl --assess --type execute` по `.app` | `accepted`, `source=Developer ID` |
| `Info.plist` собранного бандла | `CFBundleIdentifier = ru.diktopro`, `CFBundleShortVersionString = 1.0.0`, `DIKTOLicenseServer = https://api.dikto.itbeaver.co`, `DIKTOBuyURL = https://dikto.itbeaver.co/buy` |

Два следствия из последней строки:

- В собранный сегодня Pro RU DMG **уже вшит адрес сервера, которого не
  существует** (см. B2). Приложение соберётся и запустится, триал пойдёт, но
  первая же попытка активации уйдёт в DNS-ошибку. Переопределяется без
  пересборки Swift — через `DIKTO_LICENSE_SERVER` при вызове скрипта.
- **Размер DMG — 425 МБ** (из них 423 МБ — веса GigaAM). Для GitHub Releases это
  нормально (лимит 2 ГБ), но для landing-конверсии заметно: стоит заранее
  написать на странице скачивания, сколько весит файл и почему (модель внутри,
  ничего не докачивается).

Нотаризацию я **не** запускал: это отправка бинарника на серверы Apple, то есть
внешнее действие, которое в этой задаче запрещено. Путь в скрипте выглядит
корректно (`xcrun notarytool submit --wait` → `xcrun stapler staple`), но он
требует `APPLE_ID` + app-specific password и подтверждается только реальным
прогоном человеком.

### 6.2. Замечания по релизным скриптам

- **`scripts/release.sh` (free) ставит себя в `/Applications`.** Строки 231-235:
  `rm -rf "/Applications/Dikto.app"` + `cp -R`. На этой машине
  `/Applications/Dikto.app` установлен, поэтому я этот скрипт **не запускал** —
  он затёр бы рабочую установку без спроса. Для CI/релиза это лишний
  побочный эффект: сборка релиза не должна трогать установленное приложение.
  `release-pro-ru.sh` этим не страдает.
- **Версии разъезжаются.** `Version.swift:2` → `1.0.0`, `release.sh:5` → `1.0.0`,
  `release-pro-ru.sh:15` → `1.0.0`, а последний git-тег — `v0.19.0`. Нужно решение
  человека: продолжаем `0.20.0` или объявляем `1.0.0` релизом. Внутри приложения
  и в имени DMG сейчас `1.0.0`, в `install-guide-ru.md` фигурирует
  `Dikto-Pro-1.0.0.dmg`.
- **`dist-pro-ru/` не в `.gitignore`.** Корневой `.gitignore` содержит `dist`,
  что не покрывает `dist-pro-ru/`. Прогон релиза оставляет в рабочем дереве
  ~450 МБ артефактов, которые легко случайно закоммитить.

---

## 7. Цена: единообразна

Проверено grep'ом по всем витринам: **1 990 ₽, пожизненно, 2 устройства,
триал 14 дней** — расхождений нет.

| Где | Значение |
|---|---|
| `apps/landing/index.html` (meta, hero, pricing, FAQ, сравнение) | 1 990 ₽ |
| `apps/landing/buy.html` (title, meta, блок оплаты) | 1 990 ₽ |
| `apps/macos/README_RU.md` (таблица free vs Pro) | 1 990 ₽ пожизненная |
| `docs/exec-plans/dikto-pro-ru-roadmap.md` → Open questions | 1 990 ₽, 2 устройства, триал 14 дней |
| `ProductFlavor.swift:53` | `trialDays = 14` |
| `db/schema.ts` | `deviceLimit … default(2)` |

Мелкий дрейф в документации (не в ценах): `docs/SERVER_API.md:32` говорит про
лимит «`1` / `3` устройств», а строка 194 — про услугу «Лицензия Dikto Pro,
**1 устройство**», тогда как схема БД, роадмап и лендинг единогласно говорят
**2**. Это документ-источник истины для клиента и сервера, так что расхождение
стоит убрать до того, как по нему начнут писать Sprint 1.

Отдельно, не про цену, а про обещания на витрине: FAQ на `index.html:662`
говорит «Скачиваете DMG, ставите, пользуетесь 14 дней», `install-guide-ru.md`
шаг 1 — «Откройте dikto.itbeaver.co и нажмите **Скачать**», но **кнопки
«Скачать» на лендинге нет вообще** — единственные ссылки ведут на `/buy.html`.
Триал, который является главным аргументом продажи, физически недостижим.

---

## 8. Два пути до первой продажи

### Вариант А — доделать онлайн-бэкенд (как написано в PRD)

Sprint 1 по `backend-prd.md` §15.1: генерация ключей, `/v1/activate`,
`/v1/validate`, обработка веб-хука, email, деплой (VDS + Docker + Caddy + Postgres),
DNS, TLS. **9–14 рабочих дней** соло-разработчика, плюс внешние задержки.

**За:** реальный device-limit, мгновенный отзыв ключа при возврате (а возврат за
14 дней обещан в оферте), видно число активных лицензий.
**Против:** сервер нужно держать живым 24/7 — иначе платящие пользователи через
7 дней упрутся в ревалидацию; для соло-разработчика это постоянное обязательство.

### Вариант Б — оффлайн-подписи Ed25519 для первых продаж

Ровно то, что рекомендует `licensing-research.md`: подписанный JSON + публичный
ключ в `ProductFlavor.swift` + CLI выдачи ключей. Ключи выдаются вручную из
письма Lava о платеже, пока продаж единицы.

**3–5 рабочих дней:** ~1–2 дня на Ed25519 (проверка подписи в клиенте, CLI выдачи,
тесты), 0.5 дня на деплой лендинга, 0.5 дня на GitHub Release + ссылки на
скачивание, 1 день на подключение Lava и вычитку витрины.

**За:** бэкенд не нужен вообще, сервер не может «упасть», активация работает
офлайн, деньги начинают ходить в разы раньше. Проверка подписи уже наполовину
готова — `LicenseManager` (Keychain, триал, защита от перевода часов) переиспользуется
целиком, меняется только источник истины в `LicenseClient`.
**Против:** device-limit не форсится, отзыв ключа требует позже добавить
revocation-list (это статический JSON на том же Cloudflare Pages, не бэкенд).

**Рекомендация:** Б для первых продаж, А — когда объём оправдает эксплуатацию
сервера. Это и есть вывод research-документа; его нужно либо принять и внести в
роадмап, либо явно отклонить. Написанный клиентский код при этом не выбрасывается:
`/v1/activate` остаётся в кодовой базе как путь Sprint 2.

---

## 9. Таблица блокеров

Приоритет: **P0** — без этого продажа физически невозможна; **P1** — продажа
возможна, но покупатель столкнётся с поломкой или обещание на витрине не будет
исполнено; **P2** — не мешает первой продаже.

Оценки — рабочие дни соло-разработчика. «Внешнее» = ожидание третьей стороны,
не ускоряется трудозатратами.

| # | Блокер | P | Доказательство | Оценка | Человек? |
|---|---|---|---|---|---|
| B1 | `/v1/activate` и `/v1/validate` возвращают `501` — ключ невозможно активировать | P0 | `curl` к локально поднятому серверу → `501 not_implemented`; `src/routes/activation.ts:38-42, 56-61` (`TODO Sprint 1`) | 4–6 д (вариант А) / 1–2 д (вариант Б, Ed25519) | Нужно решение А vs Б |
| B2 | Бэкенд нигде не развёрнут; `api.dikto.itbeaver.co` не резолвится | P0 | `dig +short api.dikto.itbeaver.co` → пусто | 1–2 д + внешнее | Cloudflare/VDS-доступ |
| B3 | Лендинг не развёрнут; `dikto.itbeaver.co` не резолвится | P0 | `dig +short dikto.itbeaver.co` → пусто; `itbeaver.co` → Cloudflare NS | 0.5 д | Cloudflare-доступ (H7) |
| B4 | Кнопка оплаты — плейсхолдер; продукт в Lava.top не создан | P0 | `buy.html:24` → `REPLACE_ME`; fallback на `buy.html:315` делает кнопку неактивной | 0.5 д после H2 | Регистрация (H1, H2) |
| B5 | Скачать приложение неоткуда: ни одного GitHub Release, все ссылки → 404 | P0 | `gh release list` → пусто; `curl -L .../misteral/dikto/releases/latest` → `404`; `gh repo view misteral/dikto` → не существует | 0.5 д (+ B12 на переименование/правку ссылок) | — |
| B6 | На лендинге нет кнопки «Скачать» — триал недостижим | P0 | Все `href` в `index.html` ведут на `/buy.html`; при этом FAQ (`index.html:662`) и `install-guide-ru.md` обещают скачивание | 0.5 д (вместе с B5) | — |
| B7 | Выдачи ключей нет: генератор, email и веб-хук не реализованы | P0 | `webhooks.ts:32-36` — `TODO Sprint 1`; `resend` отсутствует в `package.json`; формат ключа описан только в PRD FR-2 | 2–3 д (А) / 0.5 д ручная выдача (Б) | Аккаунт Resend (H4) |
| B8 | Чек НПД: `NPD_INN` / `NPD_REFRESH_TOKEN` объявлены и не используются | P0 (юр.) | `src/config.ts:9-10` — переменные есть, ни одного обращения в `src/` | 0 д, если чек даёт Lava; 2–3 д, если писать самим | **Да — H3, выяснить в Lava** |
| B9 | ИНН самозанятого не проставлен в оферте | P0 (юр.) | `legal/terms.html:61` → `ИНН: __________ (заполняется)` | 5 мин после H1 | **Да — H1** |
| B10 | Три legal-страницы — непроверенные черновики | P1 | Пометка «Черновик — требует юридической проверки» в `terms.html` | внешнее | **Да — H6** |
| B11 | Веб-хук Lava: `500` вместо `401` на кривой подписи + HMAC по пересобранному JSON | P1 | `curl` → `ERR_CRYPTO_TIMING_SAFE_EQUAL_LENGTH`, HTTP 500; `webhooks.ts:21-23` | 0.5 д | — |
| B12 | Ссылки на несуществующий `misteral/dikto` в README, лендинге и `ProductFlavor.swift` | P1 | `gh repo view misteral/dikto` → not found; `README.md:16`, `ProductFlavor.swift:68`, `en/index.html:621`, `docs/index.html:195` | 0.5 д (или переименовать репозиторий) | Решение: переименовать `ru-wispr` → `dikto` |
| B13 | `dikto.itbeaver.co/support` не существует, но зашит в приложение | P1 | `ProductFlavor.swift:66-70`; в `apps/landing/` нет `support.html` | 0.5 д | — |
| B14 | `deploy.yml` не сработает: фильтр путей указывает на корень, деплой из `.`; последний запуск — failure | P1 | `.github/workflows/deploy.yml:5-13, 24`; `gh run list` → `failure` для «Deploy to Cloudflare Pages» (2026-05-19) | 0.5 ч | — |
| B15 | Живой сайт `misteral.github.io/ru-wispr` отдаёт старый лендинг с битой кнопкой «Download DMG» | P1 | `gh api repos/misteral/ru-wispr/pages` → `"status":"built"`; кнопка → `github.com/misteral/dikto/releases/latest` → 404 | 0.5 ч (снести или сделать редирект) | — |
| B16 | `npm run dev` падает: `pino-pretty` не в зависимостях | P1 | `Error: unable to determine transport target for "pino-pretty"`; `server.ts:14` vs `package.json` | 5 мин | — |
| B17 | У бэкенда ноль тестов при явном требовании `AGENTS.md` | P1 | `npm test` → `No test files found, exiting with code 1` | 1 д (вместе с B1) | — |
| B18 | Лицензия модели GigaAM на перепродажу не зафиксирована | P1 (юр.) | В `Resources/gigaam-v3-rnnt-mlx/` только `config.json` + `model.safetensors`, файла лицензии нет; в `docs/` условия не описаны | 1 ч на проверку | **Да — H8** |
| B19 | Расхождение версий: код `1.0.0` vs тег `v0.19.0` | P1 | `Version.swift:2`, `release.sh:5`, `release-pro-ru.sh:15` vs `git tag` | 15 мин | Да, выбрать номер |
| B20 | Схема лицензирования решена дважды и по-разному (онлайн vs Ed25519) | P1 | `roadmap` + PRD + код → онлайн; `licensing-research.md` → «оффлайн — рекомендуемый вариант для первых продаж», «онлайн … но не сейчас» | 0.5 д на решение + правку роадмапа | **Да — это выбор владельца** |
| B21 | `docs/SERVER_API.md` противоречит сам себе по device limit (1/3 vs 2) | P2 | `SERVER_API.md:32, 194` vs `schema.ts` (`default(2)`), роадмап, лендинг | 15 мин | — |
| B22 | `release.sh` затирает `/Applications/Dikto.app` при каждом релизе | P2 | `scripts/release.sh:231-235` | 15 мин | — |
| B23 | `dist-pro-ru/` не в `.gitignore` (~450 МБ артефактов в рабочем дереве) | P2 | Корневой `.gitignore` содержит `dist`, чего недостаточно | 5 мин | — |
| B24 | `@dikto_support` в Telegram, судя по всему, не занят, но уже опубликован на витрине | P2 | Пустой `og:description` на `t.me/dikto_support`; ссылки в `index.html:736`, `buy.html:236`, `success.html:140` | 15 мин | **Да — H5** |
| B25 | MIT-копирайт репозитория оформлен на `human37`, а продавец по оферте — Бобров Александр | P2 (юр.) | `LICENSE:3` → `Copyright (c) 2026 human37`; `legal/terms.html` → «самозанятый Бобров Александр» | 15 мин | Да, сверить |
| B26 | Сброс Accessibility-разрешения в Pro RU бьёт мимо: bundle ID захардкожен | P2 | `Permissions.swift:32` → `tccutil reset Accessibility co.itbeaver.dikto`, тогда как в Pro RU `ProductFlavor.bundleId == "ru.diktopro"`. У платного пользователя кнопка починки разрешений молча ничего не делает | 15 мин | — |
| B27 | `ARCHITECTURE.md` обещает автоскачивание весов GigaAM, которого в коде нет | P2 | `docs/ARCHITECTURE.md` → «model weights downloaded on first use»; grep по `GigaAMTranscriber.swift` и `GigaAM/` не находит ни одного сетевого вызова — веса кладутся релизным скриптом или вручную. Для Pro RU это не проблема (модель в DMG), для free-редакции — сюрприз | 15 мин | — |

**Сумма по P0** (вариант Б, оффлайн-лицензии): **3–5 рабочих дней** разработки,
после того как закрыты H1 (ИНН), H2 (Lava) и H3 (чеки).
**Сумма по P0** (вариант А, онлайн-бэкенд): **9–14 рабочих дней** плюс те же
внешние зависимости.

---

## 10. Что уже работает — и работает хорошо

Чтобы картина не читалась как сплошной красный:

- **Приложение собирается и проходит 99 тестов в обеих редакциях**, включая
  тесты `LicenseManager` (триал, защита от перевода часов, парсинг лицензии).
- **GigaAM работает нативно** через MLX, модель на 423 МБ лежит в репозитории
  и вшивается в DMG — пользователю не нужно ничего доустанавливать (в отличие
  от Whisper, которому нужен внешний `whisper-cpp`).
- **14-дневный триал полностью локален** и не требует ни сервера, ни сети
  (`LicenseManager.computeStatusLocked()` работает от файла + Keychain). Триальный
  DMG можно было бы раздавать хоть завтра — не хватает только места, откуда его скачать.
- **Подпись Developer ID на месте**, скрипт релиза Pro RU собирает и подписывает
  без вмешательства, путь нотаризации в скрипте прописан.
- **Приватность — не маркетинг, а свойство кода.** Проверено grep'ом по всему
  `Sources/DiktoLib/`: `URLSession` / `URLRequest` / `dataTask` встречаются
  **только** в `LicenseClient.swift`. Единственный второй выход в сеть —
  `ModelDownloader.swift`, который вызывает `/usr/bin/curl` за моделями Whisper
  с HuggingFace. Все остальные подпроцессы локальные: `whisper-cpp`
  (`Transcriber.swift:22`), `ffmpeg` для декодирования локального файла
  (`GigaAMTranscriber.swift:358`), `tccutil` (`Permissions.swift:30`). Ни аудио,
  ни текст никуда не отправляются — это можно утверждать в пресс-релизе без риска.
- **Лендинг свёрстан целиком** — главная, покупка, success/cancel, три
  юридические страницы, английская версия, OG-картинка, `_headers` с CSP.
  Не хватает деплоя и одной ссылки на скачивание.
- **Схема БД и PRD проработаны** — когда дойдёт до Sprint 1, проектировать
  с нуля не придётся.
- **`tsc --noEmit` по бэкенду чист**, конфиг валидируется через zod с fail-fast
  (проверено: без `DATABASE_URL` процесс корректно умирает с внятным сообщением).

---

## 11. Как это проверялось

Все команды выполнялись 2026-08-27 на рабочей машине (Apple M4 Pro, macOS 26.x,
Xcode 26.5, Node 24.14.1, pnpm 10.33).

```bash
# macOS
cd apps/macos
swift build -c release                    # ✅ 153.71s
swift test                                # ✅ 99 tests, 7 skipped, 0 failures
DIKTO_FLAVOR=pro_ru swift test            # ✅ 99 tests, 1 skipped, 0 failures
./.build/release/dikto --help | status | get-hotkey
bash scripts/release-pro-ru.sh            # без APPLE_ID/APP_PASSWORD — см. §6.1
security find-identity -v -p codesigning
xcode-select -p && xcodebuild -version

# backend
cd apps/backend
npm install && npx tsc --noEmit           # ✅ 0 ошибок
npm test                                  # ✗ No test files found
NODE_ENV=production DATABASE_URL=… TOKEN_HASH_PEPPER=… npx tsx src/server.ts
curl /healthz /v1/activate /v1/validate /webhooks/lava

# проверка обещания приватности
grep -rn "URLSession|URLRequest|dataTask|downloadTask" apps/macos/Sources/DiktoLib/
grep -rn "Process()" apps/macos/Sources/DiktoLib/

# инфраструктура (только пассивное чтение — ничего не публиковалось)
dig +short dikto.itbeaver.co api.dikto.itbeaver.co itbeaver.co
dig +short MX itbeaver.co && dig +short TXT itbeaver.co
gh release list --repo misteral/ru-wispr
gh repo view misteral/dikto
gh api repos/misteral/ru-wispr/pages
gh run list --repo misteral/ru-wispr
git ls-remote --tags origin
curl -I https://misteral.github.io/ru-wispr/
```

Ничего не публиковалось, не отправлялось и не регистрировалось: нотаризация не
запускалась, аккаунты не создавались, письма не отправлялись, изменения не
пушились. `pnpm-lock.yaml`, созданный `npm install`, удалён, чтобы не попасть
в коммит.

---

## Связанные документы

- [press-release.md](press-release.md) — черновик пресс-релиза (RU + EN)
- [outreach.md](outreach.md) — куда его нести
- [../exec-plans/dikto-pro-ru-roadmap.md](../exec-plans/dikto-pro-ru-roadmap.md)
- [../exec-plans/licensing-research.md](../exec-plans/licensing-research.md) — решение по §4 ждёт здесь
- [../product-specs/backend-prd.md](../product-specs/backend-prd.md) — Sprint 1 §15.1
- [../SERVER_API.md](../SERVER_API.md), [../RELEASING.md](../RELEASING.md)
