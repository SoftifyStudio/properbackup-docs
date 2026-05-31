# 2026-05-26 — Trial Abuse Prevention v2 + Past Due Grace Period

**PRy:** buffer (branch `devin/1779812528-trial-abuse-pastdue`), web (E2E testy subskrypcji)
**Sesja:** b2b8ff8b784f428d8252b2b2fd6b57df
**Dokumentacja:** docs PR #14, #15, #16, #17, #18

## Co zostalo dodane/zmienione

### Trial Abuse Prevention v2 (backend)

Rozszerzenie warstwy 1 (atomowy `trial_expires_at` przy rejestracji) o zaawansowana ochrone:

- **Card fingerprint guard** — `stripe_card_fingerprint` w tabeli `users`. Przy `activateSubscription` (webhook `checkout.session.completed`) system sprawdza, czy ta sama karta nie byla juz uzywana do trialu na innym koncie. Jesli tak — blokada (`abuse_blocked` flag + 403).
- **`SELECT FOR UPDATE`** w `activateSubscription` — eliminacja race condition (N rownoleglych webhookow z ta sama karta).
- **`ever_subscribed` guard** — uzytkownik, ktory kiedykolwiek mial subskrypcje, nie dostaje ponownego trialu (nawet po wygasnieciu).

### Past Due Grace Period (backend + frontend)

- **`subscription_payment_status`** — nowe pole w `users`: `active` | `past_due` | `unpaid`.
- **Webhook `invoice.payment_failed`** — ustawia `past_due` + 7-dniowy grace period zamiast natychmiastowej blokady.
- **Stripe Smart Retries** — system nie blokuje dostemu dopoki Stripe nie wyczerpie retry'ow (zwykle 4 proby w 7 dni).
- **UI** — zolte ostrzezenie (yellow banner) w stanie `past_due`: "Platnosc nie powiodla sie — zaktualizuj metode platnosci".
- **`unpaid`** — po wyczerpaniu retry'ow Stripe (`customer.subscription.updated` z `status=unpaid`) — upload zablokowany, restore dozwolony.

### Master TDD & Resilience Plan (docs)

- **Nowy dokument** `architecture/master-tdd-plan.md` — 1900 linii:
  - Pelny kontrakt testowy (10 grup testow A-H + 30+ edge cases)
  - Mapa kodu "DOTYKAJ vs NIE RUSZAJ"
  - Model domenowy billingu (Access Boundary FSM)
  - 6 filarow odpornosci (idempotency, fail-closed, audit, SSE, network, time)
  - Specyfikacja nowych komponentow (DLQ, Agent JWT, ProcessingScreen, dunning)
  - Go/No-Go checklist przed przejsciem na live
  - Prompt szablon "Senior + QA Paranoid Mode"

### Dodatkowe dokumenty architektoniczne (docs)

- `architecture/user-facing-recovery-spec.md` — specyfikacja Recovery Session (10 stanow maszyny stanow, per-server lockdown, DRY RUN preview, agent restore protocol)
- `architecture/resilience-testing.md` — rozszerzenie o chaos engineering i fault injection
- `architecture/operational-risks.md` — uzupelnienie o ryzyka Stripe (fallback kluczy, DLQ, checklist live)

### E2E testy (10/10 PASSED)

Playwright E2E na `properbackup-test-server.softify.com.pl` — 10 scenariuszy:

| # | Test | Status |
|---|------|--------|
| 1 | Rejestracja + pending payment | PASS |
| 2 | Checkout + trial 30d | PASS |
| 3 | Aktywacja platnosci (webhook) | PASS |
| 4 | Anulowanie subskrypcji | PASS |
| 5 | Cofniecie anulowania (renew) | PASS |
| 6 | Zmiana planu monthly → annual | PASS |
| 7 | Trial abuse — ta sama karta, drugie konto ZABLOKOWANE | PASS |
| 8 | Race condition — redirect przed webhookiem | PASS |
| 9 | Wygasniecie subskrypcji | PASS |
| 10 | Odmowa platnosci → past_due z grace period | PASS |

Nagrania wideo w `e2e-videos/2026-05-26-fixes/` (10 plikow `.webm`).

## Baza danych — nowe kolumny

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_card_fingerprint VARCHAR(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_payment_status VARCHAR(16) DEFAULT 'active';
ALTER TABLE users ADD COLUMN IF NOT EXISTS abuse_blocked BOOLEAN DEFAULT FALSE;
```

## Pliki zmienione

### properbackup-buffer
- `StripeHandler.kt` — `handleInvoicePaymentFailed()`, `handleSubscriptionUpdated()` (past_due/unpaid), card fingerprint guard w `activateSubscription()`
- `UserStore.kt` — nowe pola: `stripeCardFingerprint`, `subscriptionPaymentStatus`, `abuseBlocked`
- `schema.sql` — nowe kolumny (jak wyzej)
- `SubscriptionIntegrationTest.kt` — nowe testy: trial abuse fingerprint, past_due grace, race condition activate

### properbackup-web
- `SubscriptionPage.jsx` — yellow banner dla `past_due`
- Playwright E2E: 10 scenariuszy subskrypcyjnych

### properbackup-docs
- 5 nowych/zaktualizowanych dokumentow architektonicznych (PR #14-#18)
