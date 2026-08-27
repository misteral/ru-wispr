# AGENTS.md

Dikto — monorepo: macOS-приложение (free + Pro RU), лицензионный backend и маркетинговый landing. Privacy-focused voice dictation — push-to-talk запись, on-device транскрипция (Whisper / GigaAM), вставка текста по курсору. Без облака, только Apple Silicon.

Этот файл — карта. Полная документация в `docs/`. Прочитайте релевантный документ перед началом задачи.

## Repository layout

```
.
├── apps/
│   ├── macos/      # Swift — Dikto free + Dikto Pro RU
│   ├── backend/    # Node + Fastify — license server for Pro RU
│   └── landing/    # Static site (dikto.itbeaver.co)
├── docs/           # Cross-project documentation
└── AGENTS.md
```

## Documentation Index

| File | Contents |
|---|---|
| [README.md](README.md) | Monorepo overview |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | macOS package map, components, transcription engines, CLI |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Dev setup, PR workflow, branch strategy, git rules |
| [docs/CODING_STANDARDS.md](docs/CODING_STANDARDS.md) | Swift style, forbidden patterns, config handling |
| [docs/TESTING.md](docs/TESTING.md) | Unit tests, integration tests, CI |
| [docs/RELEASING.md](docs/RELEASING.md) | Signing, notarization, DMG build, versioning |
| [docs/SECURITY.md](docs/SECURITY.md) | Privacy model, permissions, secrets |
| [docs/RELIABILITY.md](docs/RELIABILITY.md) | Performance, error handling, resource management |
| [docs/QUALITY_SCORE.md](docs/QUALITY_SCORE.md) | Per-component quality grades and gaps |
| [docs/SERVER_API.md](docs/SERVER_API.md) | HTTP contract: macOS client ↔ backend |
| [docs/design-docs/core-beliefs.md](docs/design-docs/core-beliefs.md) | Agent-first operating principles |
| [docs/design-docs/index.md](docs/design-docs/index.md) | All design decisions |
| [docs/product-specs/index.md](docs/product-specs/index.md) | Product specifications |
| [docs/product-specs/backend-prd.md](docs/product-specs/backend-prd.md) | Backend PRD (платежи, чеки НПД, активация) |
| [docs/exec-plans/tech-debt-tracker.md](docs/exec-plans/tech-debt-tracker.md) | Known tech debt |
| [docs/exec-plans/dikto-pro-ru-roadmap.md](docs/exec-plans/dikto-pro-ru-roadmap.md) | Dikto Pro RU roadmap |
| [docs/go-to-market/readiness.md](docs/go-to-market/readiness.md) | Что блокирует первые продажи (проверено прогоном) |
| [docs/go-to-market/press-release.md](docs/go-to-market/press-release.md) | Пресс-релиз, черновик RU + EN |
| [docs/go-to-market/outreach.md](docs/go-to-market/outreach.md) | Куда нести релиз: площадки и маршруты |
| [docs/install-guide-ru.md](docs/install-guide-ru.md) | Russian install guide for Pro RU |
| [apps/macos/README.md](apps/macos/README.md) | End-user readme (free) |
| [apps/macos/README_RU.md](apps/macos/README_RU.md) | End-user readme (Pro RU) |
| [apps/backend/README.md](apps/backend/README.md) | Backend dev README |
| [apps/landing/README.md](apps/landing/README.md) | Landing dev README |

## Quick Commands

```bash
# macOS app
cd apps/macos
swift build -c release                         # Free flavor
DIKTO_FLAVOR=pro_ru swift build -c release     # Pro RU flavor
swift test                                     # Tests (free)
DIKTO_FLAVOR=pro_ru swift test                 # Tests (Pro RU)
bash scripts/dev.sh                            # Full dev cycle
bash scripts/test-install.sh                   # Integration tests + shellcheck
bash scripts/release.sh                        # Sign + free DMG
bash scripts/release-pro-ru.sh                 # Sign + Pro RU DMG

# Backend
cd apps/backend
npm install
npm run dev                                    # tsx watch
npm run test
npm run db:generate && npm run db:migrate      # Drizzle migrations

# Landing
cd apps/landing
python3 -m http.server 8000                    # Local preview
```

## First Message

Если пользователь не дал конкретную задачу: прочитать `README.md` и `docs/ARCHITECTURE.md`, потом спросить, в какой части (`apps/macos`, `apps/backend`, `apps/landing`, `docs`) работаем. После ответа — открыть соответствующий `apps/*/README.md` или `docs/`-файл.

## Critical Rules

- **No cloud dependencies for audio/text** — транскрипция всегда on-device. Network в Pro RU только для лицензии (activate/validate) и опционально для загрузки моделей.
- **Apple Silicon only** для macOS — никаких Intel fallback.
- **Test before committing** — `swift test` в `apps/macos`, `npm test` в `apps/backend`. Для CLI/scripts — `bash scripts/test-install.sh`.
- **No secrets in code** — signing identity, notarization credentials, PSP-ключи, токены НПД — только через env vars или `.env` (не коммитим).
- **New pure logic → unit test**: macOS → `apps/macos/Tests/DiktoTests/`, backend → `apps/backend/src/**/*.test.ts`. Новые CLI команды → проверки в `apps/macos/scripts/test-install.sh`. Новые скрипты → в shellcheck-список.
- **Cross-app contracts** документируем в `docs/` (например, `SERVER_API.md`) — это источник истины для клиента и сервера одновременно.
