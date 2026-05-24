# Architektura: Stripe Key Isolation (test/live per user)

## Problem

Stripe uzywa oddzielnych kluczy API dla srodowisk testowych i produkcyjnych. Customer ID, subscription ID i inne obiekty sa unikalne per srodowisko — test customer_id nie zadziala z live kluczami.

Wymagania:
1. Operator moze przelaczac uzytkownikow miedzy test a live trybem zmiana flagi w bazie
2. Klucze produkcyjne NIGDY nie moga wyciec do logow ani srodowiska testowego
3. Logika przelaczania kluczy musi byc calkowicie odizolowana od kodu biznesowego

## Rozwiazanie

### Warstwy

```
┌─────────────────────────────────────────────────────────┐
│  StripeHandler (business logic)                         │
│  - createCheckoutSession()                              │
│  - handleWebhook()                                      │
│  - cancelSubscription()                                 │
│  - ... 20+ metod                                        │
│                                                         │
│  NIE WIDZI surowych kluczy                              │
│  Otrzymuje opaque RequestOptions                        │
└──────────────────────┬──────────────────────────────────┘
                       │ requestOptionsFor(userId)
                       │ isTestMode(userId)
                       │ publicKeyFor(userId)
┌──────────────────────▼──────────────────────────────────┐
│  StripeKeyProvider (key management — jedyne miejsce)    │
│                                                         │
│  - Laduje klucze z env vars (raz, w konstruktorze)      │
│  - Czyta stripe_test_mode z DB per user                 │
│  - Generuje RequestOptions z poprawnym kluczem          │
│  - Loguje TYLKO 8-znakowy prefix klucza                 │
│                                                         │
│  JEDYNE miejsce z dostepem do pelnych kluczy            │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  PostgreSQL: users table                                │
│                                                         │
│  stripe_test_mode BOOLEAN DEFAULT TRUE                  │
│  stripe_customer_id VARCHAR(64)      -- test customer   │
│  stripe_live_customer_id VARCHAR(64) -- live customer   │
└─────────────────────────────────────────────────────────┘
```

### Env vars

```
STRIPE_TEST_SECRET_KEY     — klucz testowy (wymagany)
STRIPE_TEST_PUBLIC_KEY     — klucz publiczny testowy
STRIPE_TEST_WEBHOOK_SECRET — webhook secret testowy

STRIPE_LIVE_SECRET_KEY     — klucz live (domyslnie = test)
STRIPE_LIVE_PUBLIC_KEY     — klucz publiczny live (domyslnie = test)
STRIPE_LIVE_WEBHOOK_SECRET — webhook secret live (domyslnie = test)

# Legacy fallback (backwards compatible)
STRIPE_SECRET_KEY          — uzywany gdy _TEST_ variant nie istnieje
STRIPE_PUBLIC_KEY          — uzywany gdy _TEST_ variant nie istnieje
STRIPE_WEBHOOK_SECRET      — uzywany gdy _TEST_ variant nie istnieje
```

### Customer ID izolacja

Stripe customer IDs sa unikalne per srodowisko. Dlatego:

- `stripe_customer_id` — customer ID w srodowisku TEST
- `stripe_live_customer_id` — customer ID w srodowisku LIVE

Gdy uzytkownik jest przelaczany na live:
1. `getStripeCustomerId()` sprawdza `stripe_live_customer_id`
2. Jesli NULL → `getOrCreateStripeCustomer()` tworzy nowego customera w LIVE Stripe
3. Nowy customer ID zapisywany w `stripe_live_customer_id`
4. Test customer ID (`stripe_customer_id`) pozostaje niezmieniony

### Webhook dual-secret

Jeden endpoint webhookowy obsluguje zdarzenia z obu srodowisk:

```
Incoming webhook → probuj test secret
                 → jesli nie pasuje, probuj live secret
                 → jesli zaden nie pasuje → 400
                 → jesli pasuje → przetwarzaj event
```

Priorytet: test secret jest probowany pierwszy (wiekszosc ruchu w development).

### Bezpieczenstwo

1. **Zero globalnego stanu**: Usuniety `Stripe.apiKey` — kazde wywolanie API otrzymuje per-request `RequestOptions`
2. **Brak logowania kluczy**: `StripeKeyProvider` loguje tylko prefix (8 znakow) przy inicjalizacji
3. **Fail-closed**: Brak webhook secret = 503 (odmowa przetwarzania)
4. **Izolacja od business code**: `StripeHandler` nigdy nie widzi surowych kluczy — operuje na `RequestOptions`

## Jak przelaczac uzytkownika

```sql
-- Na live
UPDATE users SET stripe_test_mode = FALSE WHERE email = 'user@example.com';

-- Powrot na test
UPDATE users SET stripe_test_mode = TRUE WHERE email = 'user@example.com';
```

Po przelaczeniu:
- UI automatycznie wyswietla "Live" zamiast "Test Mode"
- Nastepny checkout tworzy nowego customera w live Stripe
- Stary test customer pozostaje (mozna wrocic na test)
