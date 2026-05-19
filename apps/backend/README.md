# Dikto Pro RU — Backend

License-activation service. Spec: [docs/product-specs/backend-prd.md](../../docs/product-specs/backend-prd.md). HTTP contract: [docs/SERVER_API.md](../../docs/SERVER_API.md).

**Status:** scaffold (Sprint 0). Эндпоинты `/v1/activate` и `/v1/validate` отвечают 501. Веб-хук Lava — каркас с проверкой подписи, без эффектов. Полноценная реализация — Sprint 1 по PRD.

## Стек

- Node.js 20 LTS + TypeScript
- Fastify 5 (HTTP), Drizzle ORM (Postgres), Zod (валидация)
- Pino (логи), Vitest (тесты)
- Production target: VDS + Docker + Caddy

## Локальный запуск

```bash
cd apps/backend
cp .env.example .env          # заполнить минимум DATABASE_URL и TOKEN_HASH_PEPPER
npm install
npm run db:generate           # сгенерировать миграции из src/db/schema.ts
npm run db:migrate            # применить
npm run dev                   # tsx watch
```

Healthcheck:

```bash
curl http://localhost:3000/healthz
```

## Структура

```
src/
├── server.ts           # bootstrap Fastify
├── config.ts           # парсинг env через zod, fail-fast
├── routes/
│   ├── activation.ts   # POST /v1/activate, GET /v1/validate
│   └── webhooks.ts     # POST /webhooks/lava, /webhooks/yookassa
└── db/
    └── schema.ts       # Drizzle pgTable определения
drizzle.config.ts       # конфиг для drizzle-kit
.env.example            # шаблон переменных окружения
```

## Следующие шаги (Sprint 1)

См. `docs/product-specs/backend-prd.md` секция 15.1. Кратко:

- [ ] Подключить Postgres (Selectel managed или Docker compose локально)
- [ ] Реализовать `/v1/activate` end-to-end (поиск лицензии, проверка device limit, выдача токена)
- [ ] Реализовать `/v1/validate` end-to-end (refresh `last_validated_at`)
- [ ] Lava.top webhook: генерация ключа, INSERT в `licenses`, очередь email-задачи
- [ ] Email через Resend (шаблон `purchase.success`)
- [ ] Telegram-бот для админ-канала
- [ ] Deploy: Docker + Caddy + GitHub Actions

## Замечания по безопасности

- `tokenHash` в БД — никогда не сырой токен. Хэшируем SHA-256 с `TOKEN_HASH_PEPPER`.
- Веб-хук подпись проверяем `crypto.timingSafeEqual` — без shortcut'ов на `===`.
- Rate-limit на `/v1/activate`: 5/min на IP (см. `routes/activation.ts`).
- Admin UI (Sprint 2) — Basic Auth + IP allowlist через `@fastify/middie` или nginx.
