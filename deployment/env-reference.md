# Referencja zmiennych srodowiskowych (.env)

Kompletna lista zmiennych srodowiskowych dla properbackup-buffer.

## Wymagane (bez nich aplikacja nie dziala)

| Zmienna | Przyklad | Opis |
|---------|---------|------|
| `PROPERBACKUP_DB_PASSWORD` | `silne-haslo-32-znaki` | Haslo do PostgreSQL |
| `PROPERBACKUP_JWT_SECRET` | `losowy-string-32-znaki` | Secret do podpisywania JWT tokenow (autentykacja panelu) |
| `PROPERBACKUP_UPLOAD_TOKEN` | `losowy-token-hex` | Token autoryzacji agent → buffer (upload + log ingestion) |

## Stripe — platnosci (6 kluczy)

### Skad brac klucze?

1. **Secret key + Public key:** https://dashboard.stripe.com/apikeys
2. **Webhook secret:** https://dashboard.stripe.com/webhooks → dodaj endpoint → skopiuj Signing secret

### Klucze testowe (wymagane)

| Zmienna | Format | Opis |
|---------|--------|------|
| `STRIPE_TEST_SECRET_KEY` | `sk_test_...` | Klucz prywatny (test) — do wywolan API z backendu |
| `STRIPE_TEST_PUBLIC_KEY` | `pk_test_...` | Klucz publiczny (test) — wysylany do frontendu/Checkout |
| `STRIPE_TEST_WEBHOOK_SECRET` | `whsec_...` | Signing secret (test) — weryfikacja podpisu webhookow |

### Klucze live (opcjonalne — domyslnie = test)

| Zmienna | Format | Opis |
|---------|--------|------|
| `STRIPE_LIVE_SECRET_KEY` | `sk_live_...` | Klucz prywatny (live) — prawdziwe platnosci |
| `STRIPE_LIVE_PUBLIC_KEY` | `pk_live_...` | Klucz publiczny (live) |
| `STRIPE_LIVE_WEBHOOK_SECRET` | `whsec_...` | Signing secret (live) — osobny webhook endpoint w Stripe |

### Legacy fallback (backwards compatible)

Jesli nie ustawisz wariantow `_TEST_`/`_LIVE_`, system szuka starych nazw:

| Zmienna | Opis |
|---------|------|
| `STRIPE_SECRET_KEY` | Fallback dla `STRIPE_TEST_SECRET_KEY` |
| `STRIPE_PUBLIC_KEY` | Fallback dla `STRIPE_TEST_PUBLIC_KEY` |
| `STRIPE_WEBHOOK_SECRET` | Fallback dla `STRIPE_TEST_WEBHOOK_SECRET` |

### Jak to dziala razem?

```
Uzytkownik z stripe_test_mode = TRUE (domyslny)
  → StripeKeyProvider uzywa STRIPE_TEST_SECRET_KEY
  → Platnosci ida do Stripe TEST dashboard
  → Karta testowa 4242 4242 4242 4242

Uzytkownik z stripe_test_mode = FALSE (przelaczony na live)
  → StripeKeyProvider uzywa STRIPE_LIVE_SECRET_KEY
  → Platnosci ida do Stripe LIVE dashboard
  → Prawdziwa karta, prawdziwe pieniadze
```

### Webhook — co musisz zrobic w panelu Stripe

Na **kazdym** koncie Stripe (test i live osobno):

1. Idz do **Developers → Webhooks**
2. Kliknij **Add endpoint**
3. URL: `https://twoja-domena.pl/api/payment/stripe/webhook`
4. Wybierz eventy:
   - `checkout.session.completed`
   - `invoice.paid`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
5. Skopiuj **Signing secret** (`whsec_...`)
6. Wklej do `.env`:
   - Z konta test → `STRIPE_TEST_WEBHOOK_SECRET`
   - Z konta live → `STRIPE_LIVE_WEBHOOK_SECRET`

## Panel URL

| Zmienna | Przyklad | Opis |
|---------|---------|------|
| `PROPERBACKUP_PANEL_URL` | `https://twoja-domena.pl` | URL frontendu — uzywany w Stripe Checkout (success/cancel redirect) |

## OVH Storage (opcjonalne)

Domyslnie aplikacja uzywa local mock storage. Dla produkcji:

| Zmienna | Opis |
|---------|------|
| `PROPERBACKUP_OVH_MOCK` | `false` — wylacz mock, uzyj prawdziwego OVH |
| `OS_AUTH_URL` | `https://auth.cloud.ovh.net/v3` |
| `OS_PROJECT_ID` | ID projektu OVH Cloud |
| `OS_USER_DOMAIN_NAME` | `Default` |
| `OS_USERNAME` | Uzytkownik OVH Object Storage |
| `OS_PASSWORD` | Haslo |
| `OS_REGION_NAME` | np. `GRA` |
| `OS_CONTAINER` | Nazwa kontenera (np. `properbackup-archive`) |

## Inne

| Zmienna | Domyslnie | Opis |
|---------|-----------|------|
| `PROPERBACKUP_LOG_RETENTION_DAYS` | `14` | Ile dni trzymac logi agentow |
| `PROPERBACKUP_SERVICE_ADMIN_SEED_CODE` | — | Kod startowy dla Serviceman login |
| `PROPERBACKUP_LOG_INGEST_TOKEN` | = `UPLOAD_TOKEN` | Osobny token dla log ingestion (opcjonalny) |

## Generowanie bezpiecznych wartosci

```bash
# JWT Secret (32+ znakow)
openssl rand -base64 32

# Upload token (48 hex znakow)
openssl rand -hex 24

# DB password
openssl rand -base64 24
```

## Przykladowy .env (produkcja)

```bash
# === WYMAGANE ===
PROPERBACKUP_DB_PASSWORD=wygenerowane-haslo
PROPERBACKUP_JWT_SECRET=wygenerowany-jwt-secret
PROPERBACKUP_UPLOAD_TOKEN=wygenerowany-token
PROPERBACKUP_PANEL_URL=https://twoja-domena.pl

# === STRIPE TEST ===
STRIPE_TEST_SECRET_KEY=sk_test_XXXXXXXXXXXXXXXX
STRIPE_TEST_PUBLIC_KEY=pk_test_XXXXXXXXXXXXXXXX
STRIPE_TEST_WEBHOOK_SECRET=whsec_XXXXXXXXXXXXXXXX

# === STRIPE LIVE ===
STRIPE_LIVE_SECRET_KEY=sk_live_XXXXXXXXXXXXXXXX
STRIPE_LIVE_PUBLIC_KEY=pk_live_XXXXXXXXXXXXXXXX
STRIPE_LIVE_WEBHOOK_SECRET=whsec_XXXXXXXXXXXXXXXX
```

## Permissions

```bash
# .env powinien byc czytelny tylko przez wlasciciela
chmod 600 /opt/properbackup-buffer/.env
```
