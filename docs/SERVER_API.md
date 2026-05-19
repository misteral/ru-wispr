# Dikto Pro RU — License Server API

Минимальный контракт сервера активации, к которому идёт клиент
(`Sources/DiktoLib/LicenseClient.swift`). Все эндпоинты — JSON over HTTPS,
TLS обязательно. Базовый URL по умолчанию: `https://api.dikto.itbeaver.co`, переопределяется
через `Info.plist` ключ `DIKTOLicenseServer` (см. `scripts/release-pro-ru.sh`).

## Содержание

- [Авторизация](#авторизация)
- [Машинный отпечаток](#машинный-отпечаток)
- [POST /v1/activate](#post-v1activate)
- [GET /v1/validate](#get-v1validate)
- [Коды ошибок](#коды-ошибок)
- [Веб-хук ЮKassa](#вебхук-юkassa)
- [Схема БД (рекомендуемая)](#схема-бд-рекомендуемая)
- [Безопасность](#безопасность)

## Авторизация

- `POST /v1/activate` — без авторизации, только `licenseKey` в теле.
- `GET /v1/validate` — `Authorization: Bearer <token>`, где `token` — это
  ответ от `/v1/activate`. Срок жизни токена — 30 дней, после чего клиент
  должен повторно активироваться (для пожизненных лицензий это происходит
  прозрачно: сервер выдаёт новый токен по тому же `licenseKey`).

## Машинный отпечаток

Клиент шлёт `fingerprint` — это SHA-256 от `IOPlatformUUID` хост-машины
(см. `LicenseClient.machineFingerprint()`). Сырой UUID никогда не покидает
устройство. Сервер хранит только хэш и использует его для:
- идентификации устройства внутри лицензии (для лимита `1` / `3` устройств);
- защиты от массового шеринга ключа (одинаковый ключ + разные fingerprints).

Не используйте отпечаток для идентификации пользователя — он анонимен и
непрозрачен.

## POST /v1/activate

Активация лицензии на конкретном устройстве.

### Запрос

```http
POST /v1/activate
Content-Type: application/json
User-Agent: Dikto/1.0.0

{
  "licenseKey": "ABCD-EFGH-IJKL-MNOP",
  "fingerprint": "a1b2c3...",
  "deviceId": "DEVICE-UUID-FROM-CLIENT",
  "appVersion": "1.0.0",
  "os": "macOS 14.5.0"
}
```

| Поле | Тип | Описание |
|---|---|---|
| `licenseKey` | string | Ключ, который пользователь получил после покупки |
| `fingerprint` | string (hex, 64) | SHA-256 от `IOPlatformUUID` |
| `deviceId` | string (uuid) | Локальный device ID, генерируется клиентом при первом запуске |
| `appVersion` | string | Версия Dikto Pro |
| `os` | string | Версия macOS |

### Успешный ответ (200)

```json
{
  "token": "tok_xxxxxxxxxxxx",
  "plan": "lifetime",
  "expiresAt": null,
  "deviceId": "DEVICE-UUID-FROM-CLIENT"
}
```

| Поле | Тип | Описание |
|---|---|---|
| `token` | string | Bearer-токен для `/v1/validate`. Хранится в Keychain |
| `plan` | string | `lifetime`, `yearly`, `monthly` |
| `expiresAt` | string (ISO8601) или `null` | Дата конца действия лицензии. `null` для пожизненной |
| `deviceId` | string | Эхо запроса; сервер может выдать свой ID, если хочет переименовать |

### Ошибки

- `402 invalid_key` — ключа нет в БД либо он отозван (возврат).
- `402 device_limit` — на этом ключе уже зарегистрировано N устройств с другими
  отпечатками, и попытка активации с новым отпечатком отклоняется.

```json
{
  "error": "device_limit",
  "message": "На этом ключе уже активировано 2 устройства"
}
```

## GET /v1/validate

Периодическая (раз в 7 дней) тихая проверка. Клиент использует токен из
активации; если сервер вернул `valid: false` — клиент стирает лицензию из
Keychain и просит активироваться заново.

### Запрос

```http
GET /v1/validate?deviceId=DEVICE-UUID-FROM-CLIENT
Authorization: Bearer tok_xxxxxxxxxxxx
User-Agent: Dikto/1.0.0
```

### Успешный ответ (200)

```json
{
  "valid": true,
  "expiresAt": null,
  "reason": null
}
```

### Невалидная лицензия (200 с `valid: false`)

```json
{
  "valid": false,
  "expiresAt": null,
  "reason": "refunded"
}
```

`reason` — справочное поле, может быть `"refunded"`, `"revoked"`,
`"expired"`. Клиент только логирует это в Console; пользователю показывается
общая фраза «Лицензия не подтверждена», без деталей.

### 401 — токен протух

Клиент должен снова показать окно активации, чтобы пользователь ввёл ключ.
Не делать это автоматически — пользователь должен явно увидеть, что что-то
изменилось.

## Коды ошибок

| HTTP | `error` | Реакция клиента |
|---|---|---|
| 200 | — | Парсим JSON по схеме выше |
| 401 | — | Стираем токен из Keychain, форсируем окно активации |
| 402 | `invalid_key` | Показываем «Неверный ключ лицензии» |
| 402 | `device_limit` | Показываем «Лимит устройств для этого ключа исчерпан» |
| 5xx | любое | Не трогаем локальное состояние, retry on next launch |

## Платёжная архитектура: самозанятый + СБП

Юрлица нет: продавец — самозанятый (режим НПД). Это диктует два жёстких
требования:

1. **Чек НПД на каждый платёж.** По 422-ФЗ самозанятый обязан выдать чек
   через «Мой налог» (мобильное приложение или API `lknpd.nalog.ru`) в
   момент расчёта или не позднее 9-го числа следующего месяца. Для
   автоматизации продаж используем API ЛК НПД.
2. **PSP должен принимать самозанятого.** Не все платёжные сервисы дают
   договор самозанятому — нужны те, что прямо его поддерживают и в идеале
   сами выдают чеки НПД.

### Рекомендуемый стек

| Слой | Сервис | Зачем |
|---|---|---|
| Приём оплаты (primary) | **Lava.top** | Поддерживает самозанятых, принимает СБП + карты МИР/Visa/MC + UnionPay, авточеки НПД встроены |
| Приём оплаты (backup) | **ЮKassa для самозанятых** | План «Самозанятые» в ЮKassa, тоже автоматизирует чеки, шире покрытие банков |
| Альтернатива «минимум комиссии» | **Точка / Тинькофф СБП-приём для самозанятых** | Прямая интеграция СБП через банк, ~0.4–0.7% комиссии (Lava ~5%), но чеки оформляем сами через ЛК НПД API |
| Чеки НПД (manual fallback) | `lknpd.nalog.ru/api/v1/income` | Если PSP не выдаёт чек автоматически — выдаём через эндпоинт ЛК НПД |

Бэкенд проектируем так, чтобы PSP был интерфейсом (`PaymentGateway`), а не
вшит — в MVP реализуем Lava.top, остальное добавляем по мере роста.

### Веб-хук PSP

Каждый PSP шлёт `payment.succeeded` (или эквивалент) в свой эндпоинт:

| PSP | Эндпоинт | Проверка подлинности |
|---|---|---|
| Lava.top | `POST /webhooks/lava` | HMAC-SHA256 по `secret`, заголовок `X-Api-Signature` |
| ЮKassa | `POST /webhooks/yookassa` | IP-whitelist + `Idempotence-Key` |
| Tinkoff СБП | `POST /webhooks/tinkoff` | `Token` поле в JSON, SHA-256 от отсортированных параметров |

После проверки подписи сервер выполняет одинаковый поток:

1. Дедупликация: проверяем, не обработан ли уже `provider_payment_id`. Если
   обработан — отвечаем 200 без побочных эффектов (idempotency).
2. Создаёт запись в `licenses` с уникальным `licenseKey` (формат
   `XXXX-XXXX-XXXX-XXXX`, base32 без I/O/0/1).
3. Если PSP не выдал чек автоматически — фоновая задача делает
   `POST lknpd.nalog.ru/api/v1/income` с суммой, ИНН покупателя (если есть)
   и наименованием услуги «Лицензия Dikto Pro, 1 устройство».
4. Шлёт письмо покупателю с ключом и ссылкой `dikto://activate?key=...`
   (deep-link для one-click активации; deep-link wiring — задача Stage 2).
5. Отправляет дубль ключа в Telegram-канал поддержки.

Любой `*-succeeded` веб-хук **обязан** быть идемпотентным — PSP могут слать
один и тот же платёж несколько раз при ретраях.

### Чеки НПД через ЛК НПД API

Подробности — отдельный документ `docs/product-specs/backend-prd.md`,
раздел «Интеграция с „Мой налог“». Кратко:

- Авторизация: одноразовый код из приложения «Мой налог» → постоянный
  `refresh_token` (живёт пока самозанятый не отзовёт).
- Эндпоинт: `POST https://lknpd.nalog.ru/api/v1/income` с телом
  `{operationTime, requestTime, services, totalAmount, client, ...}`.
- Ответ: `{approvedReceiptUuid}` → ссылка на чек
  `https://lknpd.nalog.ru/api/v1/receipt/<inn>/<uuid>/print` — сохраняем
  в `payments.receipt_url` и отправляем покупателю в письме.
- При ошибке сохраняем платёж со статусом `receipt_pending`, ретраим
  каждые 30 минут до 24 часов, потом уведомляем админа.

## Схема БД (рекомендуемая)

```sql
CREATE TABLE licenses (
  license_key      TEXT PRIMARY KEY,
  email            TEXT NOT NULL,
  plan             TEXT NOT NULL,  -- 'lifetime' | 'yearly' | 'monthly'
  device_limit     INTEGER NOT NULL DEFAULT 2,
  expires_at       TIMESTAMPTZ,    -- NULL для lifetime
  refunded_at      TIMESTAMPTZ,
  revoked_at       TIMESTAMPTZ,
  payment_id       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE activations (
  id               BIGSERIAL PRIMARY KEY,
  license_key      TEXT NOT NULL REFERENCES licenses(license_key),
  fingerprint      TEXT NOT NULL,        -- SHA-256 hex
  device_id        UUID NOT NULL,        -- client-supplied
  token            TEXT NOT NULL UNIQUE, -- bearer token issued to client
  token_expires_at TIMESTAMPTZ NOT NULL,
  last_validated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  app_version      TEXT,
  os               TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (license_key, fingerprint)
);

CREATE TABLE payments (
  id               BIGSERIAL PRIMARY KEY,
  provider         TEXT NOT NULL,        -- 'lava' | 'yookassa' | 'tinkoff_sbp'
  provider_payment_id TEXT NOT NULL,
  license_key      TEXT REFERENCES licenses(license_key),
  receipt_uuid     TEXT,                 -- approvedReceiptUuid from ЛК НПД
  receipt_url      TEXT,
  receipt_status   TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'issued' | 'failed'
  amount_kopecks   BIGINT NOT NULL,
  currency         TEXT NOT NULL DEFAULT 'RUB',
  status           TEXT NOT NULL,        -- 'succeeded' | 'refunded'
  email            TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_payment_id)
);

CREATE INDEX idx_activations_fp ON activations(license_key, fingerprint);
```

`device_limit` сравнивается с `COUNT(DISTINCT fingerprint)` для данной
лицензии. Повторная активация с тем же отпечатком (например, переустановка
macOS не меняет `IOPlatformUUID`) не увеличивает счётчик.

## Безопасность

- TLS 1.2+ обязателен, иначе клиент откажет в соединении (системный URLSession).
- Хранить только хэши отпечатков, никогда сырые `IOPlatformUUID`.
- Логи не должны содержать `licenseKey` целиком — маскировать как
  `ABCD-****-****-MNOP`.
- Rate-limit `/v1/activate`: не больше 5 запросов в минуту с одного IP, иначе
  можно подбирать ключи.
- Лицензионные ключи генерировать с криптостойким RNG; в формате
  base32-Crockford 16 символов даёт ~80 бит энтропии — достаточно.
- На клиенте дополнительно проверяем подпись токена (зарезервировано на
  Stage 2, пока хватает HTTPS + Keychain).
