<p align="center">
  <img src="apps/macos/logo.svg" width="80" alt="Dikto logo">
</p>

<h1 align="center">Dikto · monorepo</h1>

<p align="center">
  Local, private voice dictation for macOS — and the commercial Russian edition (<b>Dikto Pro RU</b>) built from the same code.
</p>

## Repository layout

```
.
├── apps/
│   ├── macos/      # Swift app — Dikto (free) и Dikto Pro RU (платная)
│   ├── backend/    # Node + Fastify — лицензионный сервер для Pro RU
│   └── landing/    # Статический сайт dikto.itbeaver.co
├── docs/           # Кросс-проектная документация (архитектура, PRD, roadmap)
├── AGENTS.md       # Карта репозитория для агентов
├── LICENSE
└── README.md       # ← этот файл
```

## Apps

| App | Что это | Quick start |
|---|---|---|
| **macos** | macOS приложение, free + Pro RU flavors | `cd apps/macos && swift build -c release` |
| **backend** | Лицензионный сервер для Pro RU | `cd apps/backend && npm install && npm run dev` |
| **landing** | Маркетинговый сайт | `python3 -m http.server 8000 --directory apps/landing` |

Подробности — в `apps/*/README.md`.

## Documentation

| Файл | О чём |
|---|---|
| [AGENTS.md](AGENTS.md) | Карта репозитория и правила для агентов |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Архитектура macOS-приложения |
| [docs/SERVER_API.md](docs/SERVER_API.md) | HTTP-контракт между macOS-клиентом и бэкендом |
| [docs/product-specs/backend-prd.md](docs/product-specs/backend-prd.md) | PRD на бэкенд (платежи, чеки НПД, активация) |
| [docs/exec-plans/dikto-pro-ru-roadmap.md](docs/exec-plans/dikto-pro-ru-roadmap.md) | Roadmap русской коммерческой версии |
| [apps/macos/README.md](apps/macos/README.md) | Пользовательская README для Dikto |
| [apps/macos/README_RU.md](apps/macos/README_RU.md) | Пользовательская README для Dikto Pro |

## Лицензия

`apps/macos/` — MIT (бесплатная редакция Dikto распространяется как OSS).
`apps/backend/` и `apps/landing/` — proprietary, all rights reserved (закрытая
часть коммерческого продукта).

Подробности в [LICENSE](LICENSE).
