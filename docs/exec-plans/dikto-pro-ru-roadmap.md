# Dikto Pro RU — Product Roadmap

Russian commercial edition of Dikto distributed as a separate notarized DMG. Built from the same code base via a compile-time flavor flag; shipped under a separate bundle ID, app name, and marketing site. Free Dikto stays MIT, untouched.

## Positioning

- **Free Dikto** (current): English-first OSS, MIT license, no telemetry, no license check.
- **Dikto Pro RU** (this plan): Russian-first paid product. 14-day full-feature trial, then requires an online-activated license. Same on-device transcription, same privacy guarantee for audio/text — only the license check uses network.

The free edition keeps its place as the open-source community version; Pro RU funds further development and offers a polished out-of-the-box Russian experience.

## Privacy promise (unchanged for audio)

`core-beliefs.md` says: *"No audio or text ever leaves the machine."* Pro RU keeps this. The network is used **only** for:
- license activation (one HTTPS POST with a license key + machine fingerprint),
- periodic license re-validation (one HTTPS GET every 7 days),
- model download on first run (already in free edition).

Audio buffers, transcription text, recordings, and dictionaries never leave the machine. This must be stated explicitly in marketing copy and in the activation window.

## Stages

### Stage 1 — Foundation (this iteration)

Buildable Pro RU DMG with working trial, license storage, and online-activation skeleton.

- [x] **Roadmap** — this document.
- [ ] **Build flavor** — compile-time flag `DIKTO_FLAVOR=pro_ru` toggles `ProductFlavor.swift` constants (display name, bundle ID, force language, license-required flag).
- [ ] **LicenseManager.swift** — first-launch trial seed (Application Support, monotonic-time-aware), license persistence in Keychain, status enum (`trial(daysLeft)`, `active`, `expired`, `invalid`).
- [ ] **LicenseClient.swift** — HTTP client for `POST /v1/activate` and `GET /v1/validate`, machine fingerprint, retries, timeouts.
- [ ] **ActivationWindowController.swift** — minimal AppKit window with license-key field, status banner, "Buy" link.
- [ ] **Wire-up** — `AppDelegate.gateStartup()` in Pro RU flavor blocks the hotkey when license is expired; `StatusBarController` shows trial countdown and "Activate" / "Buy" items.
- [ ] **L10n** — complete Russian coverage of all UI surfaces including license states.
- [ ] **release-pro-ru.sh** — separate DMG with `ru.diktopro` bundle ID, Russian `CFBundleDisplayName`, signed and ready for notarization.
- [ ] **LicenseManager tests** — trial computation, clock-skew defense, license parsing.
- [ ] **SERVER_API.md** — endpoint contract so server can be built in next stage.
- [ ] **README_RU.md + install-guide-ru.md** — minimal Russian-facing docs.

### Stage 2 — Server + Payments

Activation server, PSP integration, и автоматические чеки НПД.

Продавец — самозанятый (НПД), поэтому платёжный слой обязан:
(1) приниматься PSP, который работает с самозанятыми;
(2) выдавать чек через «Мой налог» (либо PSP, либо наш сервер через
`lknpd.nalog.ru` API).

- [ ] Node/Go HTTP service implementing `SERVER_API.md`.
- [ ] Postgres schema: `licenses`, `activations`, `payments`.
- [ ] **Lava.top** webhook (primary): payment success → issue license key → email + Telegram delivery.
- [ ] Backup PSP: ЮKassa для самозанятых.
- [ ] Интеграция с «Мой налог» API для авточеков (если PSP не выдаёт сам).
- [ ] СБП-приём через Точку / Тинькофф как low-fee альтернатива.
- [ ] Admin UI for refunds / device-limit resets.
- [ ] Детальный PRD — [`docs/product-specs/backend-prd.md`](../product-specs/backend-prd.md).

### Stage 3 — Landing page

Russian marketing site at `dikto.itbeaver.co` (or chosen domain) with download, pricing, FAQ.

- [ ] Reuse `index.html` styling, translate copy.
- [ ] Pricing block, FAQ ("чем отличается от бесплатного", "что с данными").
- [ ] Buy button → ЮKassa checkout.
- [ ] Email capture for trial users → drip sequence.

### Stage 4 — Onboarding & first-run

Russian first-run experience that walks new users through permissions, hotkey choice, and dictation test.

- [ ] First-launch onboarding window (микрофон, accessibility, выбор hotkey).
- [ ] Tutorial dictation with verification overlay.
- [ ] Pre-trained Russian dictionary preset (имена технологий, бренды).

### Stage 5 — Pro-only features

Differentiate Pro RU beyond brand and audience.

- [ ] Расширенный custom dictionary с правилами замены и регулярками.
- [ ] AI-форматирование текста (опционально, локальная Llama).
- [ ] История записей > 5.
- [ ] Сценарии (предустановленные prompts для деловой переписки, кода, заметок).

## Server contract summary

See `docs/SERVER_API.md` for full details.

```
POST /v1/activate
  body: { licenseKey, fingerprint, appVersion, os }
  200:  { token, expiresAt, plan, deviceId }
  402:  { error: "invalid_key" | "device_limit" }

GET /v1/validate?deviceId=...
  header: Authorization: Bearer <token>
  200:  { valid: true, expiresAt }
  401:  { valid: false, reason }
```

## Open questions

- **Цена**: 1 990 ₽ за пожизненную лицензию (2 устройства). Финал — после первого этапа продаж.
- **Триал длина**: 14 дней. Можно ужать до 7, если конверсия покажет, что 14 «жгут жир».
- **Device limit**: по умолчанию 2 (рабочий + домашний Mac).
- **Возвраты**: 14 дней без вопросов, как требует ст. 26.1 ЗоЗПП для дистанционной продажи.
- **Юр.форма**: самозанятый (НПД, 4% с физлиц). Лимит дохода 2,4 млн ₽/год — достаточно для MVP, перейдём на ИП при пересечении.

## What this plan deliberately does NOT do (yet)

- Не делаем мобильную версию.
- Не делаем cloud-режим транскрипции — это противоречит core belief #1.
- Не делаем подписку — выбран one-time + триал.
- Не делаем In-App Purchase через Mac App Store — продаём прямой DMG.

## Cross-references

- [Core beliefs](../design-docs/core-beliefs.md)
- [Architecture](../ARCHITECTURE.md)
- [Releasing](../RELEASING.md)
- [Server API contract](../SERVER_API.md)
