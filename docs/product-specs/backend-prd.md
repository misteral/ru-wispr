# Dikto Pro RU — Backend PRD

**Статус:** draft
**Версия:** 0.1
**Автор:** Aleksandr Bobrov
**Дата:** 2026-05-19
**Связанные документы:** [SERVER_API.md](../SERVER_API.md), [dikto-pro-ru-roadmap.md](../exec-plans/dikto-pro-ru-roadmap.md), [core-beliefs.md](../design-docs/core-beliefs.md)

---

## 1. Обзор

Бэкенд Dikto Pro RU — это HTTPS-сервис, обеспечивающий жизненный цикл
коммерческой лицензии: приём оплаты от российской аудитории, выдачу ключа,
активацию на конкретном Mac, периодическую проверку валидности и оформление
чеков самозанятого (НПД).

Это **не** сервис распознавания речи. Аудио и текст пользователя продолжают
жить только на клиенте — бэкенд знает лицензионный ключ, email и анонимный
fingerprint устройства, ничего больше.

### Один абзац

Пользователь покупает на `dikto.itbeaver.co` → PSP (Lava.top) шлёт нам
веб-хук → мы выдаём ключ + чек НПД → email + Telegram → пользователь
вводит ключ в приложении → клиент бьёт `POST /v1/activate` → сервер
выдаёт bearer-токен → клиент раз в 7 дней дёргает `GET /v1/validate`.

---

## 2. Цели и не-цели

### Цели (MVP)

1. **Принять платёж и выдать ключ за < 60 секунд** после успешной оплаты.
2. **Соответствие 422-ФЗ** — выдать чек НПД через «Мой налог» автоматически на каждую продажу.
3. **Активация на устройстве** работает offline-tolerant: один запрос при первом вводе ключа, дальше клиент живёт автономно 7 дней.
4. **Device limit = 2** соблюдается строго; третья активация одного ключа отклоняется с понятной ошибкой.
5. **Возврат за 14 дней** — кнопка/админка, инвалидирующая лицензию; клиент узнаёт об этом при следующей валидации.
6. **Никаких аудио или транскрипций** — даже теоретическая возможность их получения отсутствует в коде.

### Не-цели (вне MVP)

- **Многоязычная UI** на сайте — только русский.
- **Подписочная модель** — выбран one-time, в БД оставляем поле `plan` на будущее.
- **Mac App Store** — продаём прямой DMG.
- **Мобильные клиенты** — не планируются.
- **Кросс-устройственная синхронизация словарей через сервер** — словари остаются в iCloud Drive у клиента.

---

## 3. Пользователи и роли

| Роль | Кто | Через что взаимодействует |
|---|---|---|
| Покупатель | Физлицо, плательщик за лицензию | Лендинг + чекаут PSP |
| Владелец лицензии | Тот же человек, после оплаты | Email с ключом, приложение Dikto Pro |
| Клиент-приложение | macOS app | `POST /v1/activate`, `GET /v1/validate` |
| Администратор (мы) | Самозанятый-продавец | Admin UI, веб-хуки от PSP, ЛК «Мой налог» |
| Поддержка (мы) | Те же | Email support@itbeaver.co, Telegram |

---

## 4. Функциональные требования

### FR-1. Приём платежа

- Лендинг `dikto.itbeaver.co/buy` ведёт на чекаут Lava.top (primary) или ЮKassa (fallback).
- Покупатель указывает email; email — единственный обязательный контакт.
- После успешной оплаты PSP шлёт `payment.succeeded` веб-хук на наш бэкенд.
- Бэкенд **дедуплицирует** доставку по `provider_payment_id`.

### FR-2. Выдача лицензии

- На каждый успешный платёж создаётся ровно одна запись `licenses`.
- Ключ: 16 символов в формате `XXXX-XXXX-XXXX-XXXX`, base32-Crockford без `I O 0 1`. ~80 бит энтропии.
- Срок действия: `lifetime` (по умолчанию) → `expires_at = NULL`.
- Default `device_limit = 2`.

### FR-3. Выдача чека НПД

- Чек выпускается через `POST https://lknpd.nalog.ru/api/v1/income` в течение 10 минут после оплаты.
- Если PSP сам выдаёт чек (Lava.top — да) — мы только сохраняем `receipt_uuid` и `receipt_url` из их payload.
- Если PSP чек не выдаёт (прямая СБП через Точку) — выдаём сами, фоновой задачей.
- Ретраи: 5 попыток с экспоненциальной задержкой (1m, 5m, 30m, 2h, 24h). После — алерт админу.
- Чек прикладываем в email покупателю и в Telegram-канал поддержки.

### FR-4. Активация на устройстве

- Эндпоинт: `POST /v1/activate` (см. [SERVER_API.md](../SERVER_API.md)).
- Уникальный ключ ↔ fingerprint в таблице `activations`.
- При попытке активации с новым `fingerprint`, если `COUNT(DISTINCT fingerprint) >= device_limit` → `402 device_limit`.
- При успехе выдаётся `token`, валидный 30 дней.
- Активация одного и того же устройства повторно (тот же `fingerprint`) **не** считается новой — просто продлеваем токен.

### FR-5. Re-валидация

- Эндпоинт: `GET /v1/validate?deviceId=...` (см. [SERVER_API.md](../SERVER_API.md)).
- Клиент вызывает раз в 7 дней.
- Если лицензия `refunded_at IS NOT NULL` или `revoked_at IS NOT NULL` → `200 {valid: false, reason: ...}`.
- Если `token_expires_at < NOW()` → `401`, клиент просит пользователя ввести ключ заново.

### FR-6. Возврат и блокировка

- Admin UI: список лицензий, поиск по email/ключу, кнопка «Вернуть деньги» и «Заблокировать».
- При возврате: вызываем refund-API соответствующего PSP, ставим `refunded_at = NOW()`. Лицензия становится `valid: false`.
- При блокировке (например, ключ утёк в торрент): `revoked_at = NOW()`, причина в свободном поле.
- Срок реакции на возврат: 14 дней с момента покупки (ст. 26.1 ЗоЗПП).

### FR-7. Уведомления

- **Email покупателю** — сразу после `payment.succeeded` + успешной выдачи чека.
  - Тема: «Ваш ключ Dikto Pro»
  - Содержание: ключ, ссылка `dikto://activate?key=XXXX-XXXX-XXXX-XXXX`, ссылка на чек, инструкция, контакт поддержки.
  - Отправитель: `noreply@itbeaver.co` (SMTP через Resend / Yandex 360 / Mailgun).
- **Telegram в админ-канал** — на каждое событие: оплата, выдача ключа, ошибка чека, возврат.

### FR-8. Логи и аудит

- Хранить полные логи всех веб-хуков PSP (raw payload + headers) для разбора спорных платежей.
- Audit log изменений `licenses`: кто, когда, что (admin actions).
- Срок хранения: 3 года (НДС-документация требует, у нас её нет, но не помешает).

---

## 5. Нефункциональные требования

| Требование | Цель | Как мерим |
|---|---|---|
| Доступность `/v1/activate`, `/v1/validate` | 99.5%/мес | Uptime-чекер (UptimeRobot бесплатно) |
| Latency p95 `/v1/validate` | < 500 мс | Прометей-метрика |
| Время выдачи ключа после оплаты | < 60 с | timestamp в `licenses.created_at` минус webhook receipt time |
| Безопасность данных | Только TLS 1.2+, токены в БД хэшированы | Manual audit + ssllabs.com |
| Бэкап БД | Daily, retain 30 дней | Managed Postgres provider |
| Восстановление БД | < 4 часов RTO | Тестируем раз в квартал |
| Стоимость хостинга | < 1 500 ₽/мес | Reg.ru / Selectel / TimeWeb VDS |
| Защита от перебора ключей | 5 req/min на IP для `/v1/activate` | Nginx rate-limit |

---

## 6. Архитектура

```
┌─────────────────────┐
│  Лендинг            │
│  dikto.itbeaver.co  │  (Cloudflare Pages — статика)
└──────────┬──────────┘
           │  «Купить»
           ▼
┌─────────────────────┐         ┌──────────────────────┐
│  PSP (Lava.top)     │ ─webhook─▶  Backend API        │
│  Чекаут             │         │  api.dikto.itbeaver  │
└──────────┬──────────┘         │  - Node.js + Fastify │
           │                    │  - Postgres          │
           │ оплата             │  - Redis (rate-limit │
           ▼                    │    + idempotency)    │
┌─────────────────────┐         │                      │
│ ЛК «Мой налог» API  │ ◀── чек ─┤                      │
│ lknpd.nalog.ru      │         │                      │
└─────────────────────┘         └──────────┬───────────┘
                                           │
                       ┌───────────────────┼───────────────────┐
                       │                   │                   │
                       ▼                   ▼                   ▼
              ┌──────────────┐    ┌────────────────┐   ┌─────────────┐
              │ Email (SMTP) │    │ Telegram Bot   │   │ macOS app   │
              │ Resend       │    │ admin channel  │   │ (activate/  │
              └──────────────┘    └────────────────┘   │  validate)  │
                                                       └─────────────┘
```

### Стек

| Слой | Выбор | Почему |
|---|---|---|
| Runtime | **Node.js 20 LTS** + TypeScript | Быстрый MVP, экосистема, легко нанять |
| HTTP framework | **Fastify** | В 2–3 раза быстрее Express, схемы валидации из коробки |
| ORM / SQL | **Drizzle** или **Prisma** | Типобезопасный SQL, миграции |
| База | **Postgres 16** | Транзакции для idempotency, рекомендуется managed (Yandex Cloud / Selectel) |
| Кэш / Rate-limit | **Redis** | Idempotency keys + sliding-window rate limit |
| Деплой | **Docker + docker-compose** на VDS / fly.io | Один маленький сервер, без k8s |
| Reverse proxy / TLS | **Caddy** или **Nginx + certbot** | Автообновление сертификатов |
| Мониторинг | **UptimeRobot** + Telegram bot для алертов | Бесплатно, достаточно для MVP |
| Логи | **pino** → файл → ротация logrotate | Простота. ELK/Loki — за горизонтом MVP |
| Секреты | `.env` + `chmod 600`. Для секретов PSP — переменные окружения systemd | Простота |

### Альтернатива стека: Go + sqlc + Postgres

Если хочется минимум зависимостей и однобинарное развёртывание — Go + sqlc + chi. Производительность та же, но скорость прототипирования у Node выше. Решение откладываем до выбора подрядчика.

---

## 7. Модель данных

Базовая схема описана в [SERVER_API.md](../SERVER_API.md#схема-бд-рекомендуемая). Здесь — дополнения и инварианты.

### Инварианты

- `licenses.license_key` — уникальный, генерируется CSRNG, проверка коллизии при `INSERT`.
- `activations.fingerprint` — `LOWER(HEX(...))`, длина 64.
- `(license_key, fingerprint)` — `UNIQUE`: повторная активация того же устройства не плодит записи.
- `payments.provider + provider_payment_id` — `UNIQUE`: защита от двойной обработки веб-хука.
- `payments.receipt_status` ∈ {`pending`, `issued`, `failed`} — для отслеживания статуса чека НПД.

### Дополнительные таблицы

```sql
CREATE TABLE webhook_events (
  id                    BIGSERIAL PRIMARY KEY,
  provider              TEXT NOT NULL,
  provider_event_id     TEXT,
  raw_headers           JSONB NOT NULL,
  raw_body              JSONB NOT NULL,
  processed_at          TIMESTAMPTZ,
  status                TEXT NOT NULL DEFAULT 'received', -- received | processed | error
  error_message         TEXT,
  received_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_webhook_provider_event ON webhook_events(provider, provider_event_id);

CREATE TABLE audit_log (
  id            BIGSERIAL PRIMARY KEY,
  actor         TEXT NOT NULL,           -- 'system' | admin email
  action        TEXT NOT NULL,           -- 'refund' | 'revoke' | 'license.issue' | ...
  target_type   TEXT NOT NULL,           -- 'license' | 'activation' | ...
  target_id     TEXT NOT NULL,
  diff          JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE npd_tokens (
  id              BIGSERIAL PRIMARY KEY,
  inn             TEXT NOT NULL,         -- ИНН самозанятого
  refresh_token   TEXT NOT NULL,         -- из лк нпд
  access_token    TEXT,
  access_expires_at TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Хранение токена клиента

`activations.token` хранится **в виде SHA-256 хэша**, не в открытом виде. Клиент сравнивается так:

```sql
SELECT * FROM activations WHERE token_hash = $1 AND token_expires_at > NOW();
```

Если БД утечёт — токены не будут пригодны для запросов от чужого имени.

---

## 8. Эндпоинты

См. [SERVER_API.md](../SERVER_API.md) — это первоисточник контракта с клиентом. В PRD только обзор:

| Метод | Путь | Назначение |
|---|---|---|
| `POST` | `/v1/activate` | Активация лицензии на устройстве (без auth) |
| `GET` | `/v1/validate` | Проверка лицензии (Bearer token) |
| `POST` | `/webhooks/lava` | Веб-хук Lava.top |
| `POST` | `/webhooks/yookassa` | Веб-хук ЮKassa |
| `POST` | `/webhooks/tinkoff` | Веб-хук Тинькофф СБП (если включен) |
| `GET` | `/healthz` | Liveness probe для UptimeRobot |
| `GET` | `/admin/*` | Admin UI (Basic Auth + IP-allowlist) |

---

## 9. Платёжные потоки

### 9.1 Lava.top (primary)

1. Покупатель жмёт «Купить» → редирект на `https://lava.top/...?...`.
2. Lava проводит платёж, посылает на `POST /webhooks/lava` JSON с `order_id`, `amount`, `email`, подписью `X-Api-Signature`.
3. Бэкенд:
   - Проверяет HMAC-SHA256 от тела по секрету.
   - INSERT в `webhook_events`.
   - INSERT в `payments` с `ON CONFLICT (provider, provider_payment_id) DO NOTHING`.
   - Если это первый раз — генерит `licenseKey`, INSERT в `licenses`.
   - Триггерит async job: выпустить чек + отправить email + telegram.
4. Lava сам выдаёт чек НПД (в их аккаунте самозанятого) — мы сохраняем `receipt_url` из payload.

### 9.2 ЮKassa для самозанятых (fallback)

Аналогично, но:
- IP-whitelist 185.71.76.0/27, 185.71.77.0/27.
- Идемпотентность по `Idempotence-Key` header.
- Чек выдаём сами через ЛК НПД API.

### 9.3 Прямой СБП через Точку (опционально, low-fee)

- Аккаунт самозанятого в Точка-банке → API «Прием СБП».
- При покупке: сервер создаёт QR-код через `POST https://enter.tochka.com/...`, отдаёт пользователю.
- Веб-хук от Точки приходит на `/webhooks/tinkoff` (или отдельный `/webhooks/tochka`).
- Чек выдаём сами через ЛК НПД API.
- Комиссия: 0.4–0.7% vs Lava ~5%. Решение: включаем в Stage 2, если SBP-доля платежей оправдает дополнительный код.

### 9.4 Refund flow

1. Админ нажимает «Вернуть» в админке.
2. Бэкенд вызывает API возврата у соответствующего PSP.
3. После подтверждения от PSP: `licenses.refunded_at = NOW()`.
4. Следующий вызов `/v1/validate` от клиента вернёт `{valid: false, reason: "refunded"}`.
5. Клиент стирает токен из Keychain, показывает окно активации.

---

## 10. Интеграция с «Мой налог» (НПД)

API: `https://lknpd.nalog.ru/api/v1` (документация — неофициальная, реверс-инжиниринг приложения; стабильный, но без SLA).

### 10.1 Авторизация

Один раз, вручную:

1. Самозанятый в приложении «Мой налог» → «Партнёры» → «ЛК налогоплательщика» → получить временный код.
2. Сервер обменивает код на `refresh_token` и `access_token` через
   `POST /v1/auth/token`.
3. `refresh_token` сохраняем в `npd_tokens` (зашифрованно). Живёт пока самозанятый не отзовёт.
4. `access_token` живёт 15 минут — обновляем по мере необходимости.

### 10.2 Выпуск чека

```http
POST https://lknpd.nalog.ru/api/v1/income
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "operationTime": "2026-05-19T12:34:56+03:00",
  "requestTime":   "2026-05-19T12:34:56+03:00",
  "services": [{
    "name":     "Лицензия Dikto Pro, пожизненная, 2 устройства",
    "amount":   1990,
    "quantity": 1
  }],
  "totalAmount": "1990.00",
  "client": {
    "contactPhone": null,
    "displayName":  null,
    "inn":          null,
    "incomeType":   "FROM_INDIVIDUAL"
  },
  "paymentType":   "CASH",
  "ignoreMaxTotalIncomeRestriction": false
}
```

Ответ:
```json
{"approvedReceiptUuid": "20abcdef..."}
```

Ссылка на чек:
```
https://lknpd.nalog.ru/api/v1/receipt/<inn>/<uuid>/print
```

### 10.3 Edge cases

- **Лимит дохода превышен** (2.4M ₽/год) → API вернёт ошибку → переключаемся на ИП, оповещаем админа алертом.
- **«Мой налог» лежит** → ставим `payments.receipt_status = pending`, ретраим. Покупателю шлём ключ сразу (он его ждёт), но письмо «чек придёт отдельно».
- **Отзыв чека** (если возврат) → `POST /v1/cancel` с `approvedReceiptUuid`.

---

## 11. Уведомления

### 11.1 Email

- Транспорт: **Resend** (3 000 писем/мес бесплатно, есть SMTP API) или Yandex 360.
- Шаблоны: HTML + plain-text. Размещаем в `templates/email/*.mjml`.
- Письма:
  - `purchase.success` — ключ, ссылка `dikto://activate?key=...`, ссылка на чек.
  - `receipt.delayed` — если чек выпустился позже основного письма.
  - `refund.confirmed` — после успешного возврата.
- Подпись DKIM + SPF + DMARC обязательно — иначе попадаем в спам.

### 11.2 Telegram (админ-канал)

Бот шлёт в приватный канал `@dikto_ops`:

- ✅ Новый платёж: сумма, email, маскированный ключ.
- ⚠️ Ошибка веб-хука / чека / email.
- 💸 Возврат.
- 🚨 Алерт: лимит самозанятого близок (>2.0M ₽).

---

## 12. Мониторинг и наблюдаемость

| Что | Где | Алерт |
|---|---|---|
| Liveness `/healthz` | UptimeRobot, раз в минуту | Telegram если 2 пропуска подряд |
| TLS истекает | UptimeRobot SSL monitor | Email за 14 дней |
| Latency p95 `/v1/validate` | pino-logs → grep / Loki (опционально) | > 1 сек 5 минут подряд |
| Размер БД | cron + Telegram | > 80% диска |
| Failed receipts | таблица `payments` где `receipt_status = failed` | Telegram сразу |
| Расхождение баланса PSP ↔ `payments.amount` | nightly reconciliation job | Telegram |

В MVP не делаем Prometheus/Grafana — достаточно структурированных логов pino + Telegram-алертов.

---

## 13. Безопасность

- **TLS обязателен**. HSTS, `max-age=31536000`.
- **CORS**: разрешён только для `dikto.itbeaver.co`.
- **Rate limit**:
  - `/v1/activate`: 5 req/min/IP, 30 req/min/licenseKey.
  - `/webhooks/*`: 60 req/min/IP, плюс проверка подписи.
- **Секреты**: PSP-ключи и токен НПД — переменные окружения systemd, в БД храним только хэши.
- **Логи без PII**: маскируем `licenseKey` (`ABCD-****-****-MNOP`), не логируем тело webhook'а в обычные логи (только в `webhook_events` таблицу с доступом только админу).
- **Admin UI**: Basic Auth + IP-allowlist (мой домашний и офисный IP). Никаких сессионных кук, никакой регистрации пользователей.
- **БД**: только private-network доступ; нет публичного 5432.
- **Регулярные обновления**: `apt unattended-upgrades` для system, `npm audit` в CI.

---

## 14. Деплой

### 14.1 Окружения

| Окружение | Хост | Назначение |
|---|---|---|
| `prod` | `api.dikto.itbeaver.co` | Боевой |
| `staging` | `staging.api.dikto.itbeaver.co` | Тестовые платежи, тест клиента перед релизом |
| `local` | `localhost:3000` | Разработка |

В клиенте URL переключается через `Info.plist` ключ `DIKTOLicenseServer` (см. `scripts/release-pro-ru.sh`).

### 14.2 CI/CD

- GitHub Actions: на каждый push в `main` бэкенд-репозитория — `docker build` + `docker push` + `ssh && docker compose pull && docker compose up -d`.
- Миграции применяются перед стартом приложения (`drizzle-kit migrate` или эквивалент Prisma).
- Rollback: `docker compose up -d --rollback` (хранить 3 последних тега).

### 14.3 Бэкапы

- Postgres: managed-сервис с автобэкапами (Selectel / Yandex Cloud). Daily, retain 30 дней.
- В коде: nightly `pg_dump` в S3-совместимое хранилище как страховка.

---

## 15. MVP scope и итерации

### 15.1 MVP (Sprint 1, ~2 недели)

Покрывает минимальный сценарий: пользователь купил → получил ключ → активировал.

- [ ] Проект на Node + Fastify + Drizzle + Postgres.
- [ ] Миграции для `licenses`, `activations`, `payments`, `webhook_events`.
- [ ] `POST /v1/activate` + `GET /v1/validate` по контракту.
- [ ] Веб-хук Lava.top: подпись, дедупликация, генерация ключа.
- [ ] Email через Resend, один шаблон `purchase.success`.
- [ ] Telegram-бот для админ-канала.
- [ ] Чеки НПД — **ручной** выпуск пока (через приложение «Мой налог»), API оставляем заглушкой.
- [ ] Деплой на одну VDS, домены, Caddy + Let's Encrypt.
- [ ] Smoke-тест: купить за реальные деньги → активация в Pro RU билде клиента.

**Definition of done MVP**: первый платный пользователь оплачивает, получает ключ, активирует, видит «Лицензия активна» в строке меню.

### 15.2 Итерация 2 (Sprint 2, ~1 неделя)

- [ ] Автовыпуск чеков НПД через ЛК НПД API.
- [ ] Admin UI (минимальный): список лицензий, поиск, кнопки refund/revoke.
- [ ] Rate limiting через Redis.
- [ ] Reconciliation: nightly job сверки `payments` ↔ PSP API.

### 15.3 Итерация 3 (Sprint 3, ~1 неделя)

- [ ] ЮKassa как backup PSP.
- [ ] Шаблоны email на MJML.
- [ ] Deep-link `dikto://activate?key=...` — обработка в клиенте + одноразовая ссылка из письма.
- [ ] Метрики: суточные продажи, конверсия trial→buy, refund rate.

### 15.4 Итерация 4+

- [ ] Прямой СБП через Точку для снижения комиссии.
- [ ] Реферальные ссылки.
- [ ] Промокоды.

---

## 16. Риски и митигации

| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| ЛК НПД API не имеет официального SLA, может ломаться | Средняя | Высокое | Ретраи + manual fallback через приложение «Мой налог» |
| Лимит самозанятого 2.4M ₽/год | Низкая в MVP | Высокое (если случится) | Алерт при 2.0M; план перехода на ИП заранее |
| Утечка PSP-ключей / токена НПД | Низкая | Очень высокое | Секреты в env + chmod 600 + Vault-as-a-Service позже |
| Lava.top сменит условия для самозанятых | Низкая | Среднее | Иметь готовый интерфейс PSP, чтобы быстро добавить альтернативу |
| Пиратство — кто-то выложил ключ | Средняя | Низкое | Device limit + revoke по жалобе. Не пытаемся бороться технически за пределами разумного. |
| Возвраты выше 10% от продаж | Низкая | Среднее | Анализ причин, улучшение онбординга |
| Регуляторные изменения (требование российского хостинга для ПДн) | Низкая | Высокое | Изначально хостимся в РФ (Selectel/Yandex), email storage в Resend EU/US — email не относится к ПДн по 152-ФЗ в нашем сценарии |

---

## 17. Открытые вопросы

1. **Стек: Node vs Go?** Node быстрее для MVP, Go проще для одного бинаря на VDS. Решение — после оценки времени Node-имплементации.
2. **Email-провайдер**: Resend (US) vs Yandex 360 (РФ). Resend проще API, Yandex — резидент РФ. Для MVP — Resend, перейдём при первых жалобах на доставляемость.
3. **БД-хостинг**: managed (Selectel Postgres) vs self-hosted в Docker рядом. Managed безопаснее, но +1000 ₽/мес.
4. **Лицензионные ключи — формат**: `XXXX-XXXX-XXXX-XXXX` (16 base32) vs UUID. Текущий выбор — base32, читается с экрана.
5. **Deep-link `dikto://activate?key=...`** — нужно зарегистрировать URL scheme в `Info.plist` Pro RU билда. Тривиально, но в MVP оставляем ручной ввод ключа.

---

## 18. Acceptance criteria

MVP считается готовым, когда выполнены **все** пункты:

- [ ] Покупка тестовой лицензии за 1 ₽ через Lava.top проходит end-to-end.
- [ ] Письмо с ключом приходит в течение 60 секунд после оплаты.
- [ ] Чек НПД (ручной) выпущен в течение часа, ссылка приложена.
- [ ] Pro RU билд клиента успешно активируется купленным ключом.
- [ ] `GET /v1/validate` возвращает `valid: true` через 7 дней без сброса.
- [ ] Refund через админку инвалидирует лицензию в течение следующей валидации (макс. 7 дней).
- [ ] UptimeRobot пингует `/healthz` без ошибок 72 часа подряд.
- [ ] README.md в бэкенд-репозитории описывает локальный запуск в три команды.

---

## 19. Метрики успеха

После 1 месяца с момента публичного запуска:

- ≥ 30 успешных платежей.
- Refund rate ≤ 5%.
- Никаких ручных вмешательств в выдачу ключей (всё через автоматизацию).
- Среднее время «оплата → ключ в почте» < 60 секунд (P95).
- Zero инцидентов утечки PSP-ключей или токенов НПД.

После 3 месяцев:

- ≥ 200 платежей, что подтверждает product-market fit на русском Mac-сообществе.
- < 2.4M ₽ годового дохода (т.е. остаёмся на НПД), либо переходим на ИП с заранее подготовленным планом.

---

## 20. Связанные ссылки

- [SERVER_API.md](../SERVER_API.md) — контракт HTTP API.
- [dikto-pro-ru-roadmap.md](../exec-plans/dikto-pro-ru-roadmap.md) — продуктовый roadmap.
- [core-beliefs.md](../design-docs/core-beliefs.md) — принципы on-device приватности.
- 422-ФЗ о НПД: http://www.consultant.ru/document/cons_doc_LAW_311977/
- ЛК НПД API (неофициальное описание): https://github.com/aLkRicha/lknpd-api
- Lava.top API: https://dev.lava.ru/
- ЮKassa для самозанятых: https://yookassa.ru/developers/payments/payment-methods/self-employed
