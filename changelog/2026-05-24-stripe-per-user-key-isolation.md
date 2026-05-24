# 2026-05-24 — Per-user Stripe key isolation (test/live mode)

**PRy:** buffer#19, web#28
**Branche:** `devin/1779612187-stripe-per-user-key-isolation` (buffer), `devin/1779612188-stripe-per-user-key-isolation` (web)
**Bazuje na:** `devin/1779463462-promo-subscription-v2` (implementacja Stripe z poprzedniej sesji)

## Co zostalo zmienione

### Backend (properbackup-buffer)

#### Nowe pliki
- `StripeKeyProvider.kt` — wyizolowana klasa do zarzadzania kluczami Stripe
  - Laduje klucze test/live z env vars (`STRIPE_TEST_SECRET_KEY`, `STRIPE_LIVE_SECRET_KEY`, itd.)
  - Per-user tryb (test/live) na podstawie flagi `stripe_test_mode` w bazie
  - Generuje `RequestOptions` per-request zamiast globalnego `Stripe.apiKey`
  - Nigdy nie loguje pelnych kluczy (tylko 8-znakowy prefix)
  - Live klucze domyslnie = test klucze (fallback)

#### Zmodyfikowane pliki
- `schema.sql` — dodane kolumny:
  - `stripe_test_mode BOOLEAN NOT NULL DEFAULT TRUE` — flaga per-user
  - `stripe_live_customer_id VARCHAR(64)` — osobny customer ID dla srodowiska live
- `UserStore.kt` — nowe pola w data class `User`: `stripeTestMode`, `stripeLiveCustomerId`
- `StripeHandler.kt` — pelny refactor:
  - Wszystkie 20+ wywolan Stripe API uzywaja per-user `RequestOptions`
  - Usuniete globalne `Stripe.apiKey` i `stripeSecretKey`
  - Webhook handler probuje oba sekrety (test + live) — dual-secret verification
  - `getStripeCustomerId`/`saveStripeCustomerId` wybieraja kolumne na podstawie trybu
  - `getCardInfo()` zwraca `isTestCard` per user
  - `getStripeModeForUser(userId)` zamiast globalnego `getStripeMode()`
- `SubscriptionHandler.kt` — endpoint `/account/subscription` zwraca `stripeTestMode` i per-user `stripeMode`
- `BufferMain.kt` — wiring `StripeKeyProvider` do `StripeHandler`
- `.env.example` — dodane nowe env vars z opisem

#### Testy
- 11 nowych testow w `SubscriptionIntegrationTest.kt`:
  - Key isolation: test vs live klucze per user
  - Mode switching: flip flagi i weryfikacja kluczy
  - RequestOptions: poprawny klucz w RequestOptions
  - Dual-secret webhook: oba sekrety akceptowane
  - Fallback: live klucze defaultuja do test gdy nieskonfigurowane
  - Webhook deduplication: identyczne sekrety nie duplikowane
  - UserStore: flaga persystowana w bazie
- Istniejace testy zaktualizowane do nowego konstruktora (StripeKeyProvider)
- Wszystkie 114 testow przechodzacych

### Frontend (properbackup-web)

- `SubscriptionPage.jsx`:
  - Nowy komponent `CardModeBadge` — badge "Test Mode" (amber) lub "Live" (zielony)
  - Badge wyswietlany zawsze (nie tylko w trybie test)
  - `isTestMode` teraz uzywa per-user `stripeTestMode` z backendu
  - Backwards-compatible fallback na `stripeMode === 'test'`

## Jak uzywac

### Przylaczanie na live (per-user)
```sql
-- Przelacz uzytkownika na live billing
UPDATE users SET stripe_test_mode = FALSE WHERE id = 'USER_ID';

-- Wroc do test mode
UPDATE users SET stripe_test_mode = TRUE WHERE id = 'USER_ID';
```

### Env vars (produkcja)
```bash
# Test (domyslne)
STRIPE_TEST_SECRET_KEY=sk_test_...
STRIPE_TEST_PUBLIC_KEY=pk_test_...
STRIPE_TEST_WEBHOOK_SECRET=whsec_test_...

# Live (opcjonalne — domyslnie = test)
STRIPE_LIVE_SECRET_KEY=sk_live_...
STRIPE_LIVE_PUBLIC_KEY=pk_live_...
STRIPE_LIVE_WEBHOOK_SECRET=whsec_live_...
```

## Wazne uwagi

1. **Customer ID izolacja**: Stripe customer IDs sa unikalne per srodowisko. Kolumna `stripe_customer_id` = test, `stripe_live_customer_id` = live. Przy pierwszym checkout w trybie live, system automatycznie tworzy nowego customera.
2. **Klucze nigdy w logach**: `StripeKeyProvider` loguje tylko prefix klucza (8 znakow). Business code nie ma dostepu do surowych kluczy.
3. **Backwards compatible**: Jesli ustawisz tylko `STRIPE_SECRET_KEY` (stary env var), system dziala jak wczesniej.
