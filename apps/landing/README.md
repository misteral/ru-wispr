# Dikto landing

Статический сайт `dikto.itbeaver.co` — лендинг и витрина продаж Dikto Pro RU.

## Структура

```
apps/landing/
├── index.html               # Главная (русская, Pro RU)
├── buy.html                 # Страница покупки → Lava.top
├── success.html             # Пост-платёж: успех (redirect URL)
├── cancel.html              # Пост-платёж: отмена (redirect URL)
├── demo.html                # Демо страница (от старого лендинга)
├── en/
│   └── index.html           # Английский лендинг free Dikto
├── legal/
│   ├── _styles.css          # Общие стили для legal страниц
│   ├── terms.html           # Договор-оферта
│   ├── privacy.html         # Политика конфиденциальности (152-ФЗ)
│   └── refund.html          # Возврат (ст. 26.1 ЗоЗПП)
├── _headers                 # Cloudflare Pages: CSP, кэш
├── robots.txt
└── sitemap.xml
```

## Локальный просмотр

```bash
python3 -m http.server 8000 --directory apps/landing
open http://localhost:8000
```

## Что нужно сделать перед запуском продаж

### 1. Подключить Lava.top

1. Зарегистрироваться на [app.lava.top](https://app.lava.top/business) как самозанятый.
2. Создать продукт «Dikto Pro — пожизненная лицензия», цена 1990 ₽.
3. Скопировать URL вида `https://app.lava.top/products/<uuid>`.
4. В `buy.html` найти `<meta name="lava-product-url" content="https://app.lava.top/products/REPLACE_ME">` и подставить реальный URL.
5. В кабинете Lava указать redirect URLs:
   - Success → `https://dikto.itbeaver.co/success.html`
   - Cancel → `https://dikto.itbeaver.co/cancel.html`
6. Webhook URL: `https://api.dikto.itbeaver.co/webhooks/lava` (когда поднят бэкенд).
7. Скопировать `LAVA_WEBHOOK_SECRET` и добавить в `.env` бэкенда.

### 2. Заполнить юридические страницы

В `legal/terms.html` есть плейсхолдер `ИНН: __________` — заменить на реальный
ИНН самозанятого после регистрации в «Мой налог».

Все три legal-страницы помечены как «черновик — требует юридической проверки».
Перед запуском рекомендуется заверить у юриста, специализирующегося на
дистанционной продаже ПО самозанятыми.

### 3. Подключить домен

Подключаем `dikto.itbeaver.co` в Cloudflare Pages:

```
Build command:    (пусто)
Output directory: apps/landing
Production branch: main
```

`_headers` подхватится автоматически Cloudflare Pages.

### 4. Email и Telegram

В footer на главной и в legal-страницах используются:
- `support@itbeaver.co` — настроить через Cloudflare Email Routing на ваш ящик
- `sales@itbeaver.co` — для командных тарифов
- `@dikto_support` в Telegram — создать бот или канал и зарегистрировать его

## Дизайн-система

Брутальный монохром с пурпурным акцентом (`#7C3AED` light, `#A78BFA` dark).
Шрифты: DM Sans (заголовки, ui), IBM Plex Mono (body). Карточки с жёсткой
тенью `3px 3px 0` и 2-пиксельной чёрной рамкой. Темы переключаются через
`data-theme` атрибут на `<html>`, сохраняются в `localStorage`.

Все стили инлайн в каждом HTML, кроме `legal/_styles.css` — там общий файл
для трёх юридических страниц.

## Что подключено

- ✅ **OG-картинка**: `og.svg` (1200×630), указана в `<meta property="og:image">` в `index.html` и `buy.html`. SVG работает в Twitter/X и большинстве платформ; для максимальной совместимости с Facebook можно конвертировать в PNG (`rsvg-convert og.svg -o og.png` или через любой SVG→PNG сервис).
- ✅ **Mobile-меню**: hamburger-кнопка на экранах < 760 px (только `index.html`; на других страницах меню не нужно).
- ✅ **Plausible-аналитика**: подключён на всех страницах с `data-domain="dikto.itbeaver.co"`. Дашборд автоматически создастся при первом заходе с правильным доменом, нужен только аккаунт на [plausible.io](https://plausible.io).
- ✅ **Email-захват**: блок «Уведомить меня» внизу `index.html`. По умолчанию работает через mailto на `support@itbeaver.co`. Чтобы переключить на сервис, замените `REPLACE_ME` в `<meta name="email-capture-url">` на URL формы Formspree/Buttondown.

## TODO

- [ ] Скриншоты приложения и/или GIF демо в hero-секцию (нужны реальные ассеты)
- [ ] Сконвертировать `og.svg` → `og.png` если planируется шерить в Facebook
- [ ] Подключить аккаунт Plausible (бесплатный триал 30 дней)
- [ ] (Опционально) Зарегистрироваться в Formspree и подставить URL формы в `email-capture-url`
