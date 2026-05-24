# Logika zmiany planow (Downgrade Logic)

## Zasada nadrzedna

**NIGDY nie zabierac klientowi czasu, za ktory juz zaplacil.**

Kazda zmiana planu respektuje `subscription_expires_at` — jesli klient zaplacil do 2027-05-24, to do 2027-05-24 ma aktywny dostep, niezaleznie od tego jaki plan wybierze nastepny.

## Kluczowa zmiana: `max(currentExpiresAt, stripePeriodEnd)`

Jedna linia robi cala roznice:

```kotlin
val newExpiresAt = if (currentExpiresAt != null && currentExpiresAt.isAfter(stripePeriodEnd)) {
    currentExpiresAt  // zachowujemy dluzsza date
} else {
    stripePeriodEnd
}
```

## 6 scenariuszy

| Scenariusz | Plan w DB | ExpiresAt w DB | Stripe subscription |
|---|---|---|---|
| Brak -> monthly | monthly | +31 dni | Nowa monthly |
| Brak -> annual | annual | +365 dni | Nowa annual |
| Monthly (30d left) -> annual | annual | max(+30d, +365d) = +365d | Nowa annual (stara skasowana) |
| Annual (300d left) -> monthly | monthly | max(+300d, +31d) = **+300d** | Nowa monthly (stara skasowana) |
| Annual (300d left) -> annual | annual | max(+300d, +365d) = +365d | Nowa annual (stara skasowana) |
| Monthly (5d left) -> monthly | monthly | max(+5d, +31d) = +31d | Nowa monthly (stara skasowana) |

## 3 zmiany w kodzie

### 1. `activateSubscription` (StripeHandler.kt)

- Dodano `max(currentExpiresAt, stripePeriodEnd)` — nigdy nie skraca daty wygasniecia
- Loguje `prevExpiresAt` dla audytu

### 2. `handleSubscriptionDeleted` (StripeHandler.kt) — CRITICAL

**Stara logika:** Zawsze `deactivateSubscription()` — kasowala plan + date z DB. Klient tracil oplacony czas.

**Nowa logika:**

| Warunek | Stara logika | Nowa logika |
|---|---|---|
| `expiresAt > now` (oplacony czas) | Kasuje plan + date | Czysci tylko `stripe_subscription_id`, plan + data zostaja |
| `expiresAt <= now` (wygaslo) | Kasuje plan | Kasuje plan (bez zmian) |
| Brak `expiresAt` | Kasuje plan | Kasuje plan (bez zmian) |

Dodatkowo ustawia `cancel_at_period_end = true` i loguje audit `subscription_deleted_but_time_preserved`.

### 3. Frontend (SubscriptionPage.jsx)

- Usuniety amber warning "Plan roczny jest aktywny — zmiana zablokowana"
- Usuniety disabled button
- Wszystkie plany zawsze dostepne do wyboru

## Edge cases

### Stripe billing vs DB expiry desync
Stripe monthly odnawia co 31 dni. Klient z annual (300d left) kupil monthly — Stripe mowi `period_end = +31 dni`, DB ma `+300 dni`. Stripe odnowi za 31 dni, ale DB daje dostep do 300 dni. To jest OK — `max()` w `activateSubscription` gwarantuje ze date nigdy nie cofniemy.

### Anulowanie subskrypcji po downgrade
Klient ma annual +300d, kupil monthly, po 2 dniach anuluje. Nowa logika `handleSubscriptionDeleted` czysci tylko `stripe_subscription_id` — plan + data zostaja. Klient ma dostep do konca oplaconego okresu.

### Po wygasnieciu zachowanego czasu
Brak crona/jobu — system sprawdza `expiresAt > now` przy kazdym request. Gdy minie, klient naturalnie traci dostep i moze kupic nowy plan od zera.

### Double-cancel
Stripe nie wysle drugiego `subscription.deleted` dla tej samej subskrypcji. Jesli klient kupi nowy monthly i znow anuluje — `max()` + zachowanie czasu gwarantuja ze data nigdy nie cofa sie.

## Paranoid QA — defensywna architektura (2026-05-24)

### Race Conditions: SELECT FOR UPDATE
`activateSubscription` i `handleSubscriptionDeleted` uzywaja transakcji z `SELECT FOR UPDATE` na wierszu usera. Zapobiega to scenariuszowi, w ktorym dwa rownoczesne webhooki (np. `invoice.paid` + `checkout.completed`) nadpisza sie nawzajem. Nowe metody w `UserStore`: `findByIdForUpdate(conn, id)` + connection-aware overloady `updateSubscription`, `deactivateSubscription` itd.

### Double-Click Protection
- **Frontend:** `checkoutLoading` state blokuje przycisk + pokazuje "Przekierowuje..."
- **Backend:** Deterministic idempotency key (SHA-256 z userId+plan+promo+30s bucket). Stripe gwarantuje jedna sesje per klucz.
- **bfcache fix:** `pageshow` event listener resetuje `checkoutLoading` gdy uzytkownik wraca przyciskiem "Back" z checkout Stripe. Bez tego przycisk zostawalby zablokowany na stale.

### Stripe Retry z Exponential Backoff
`StripeHandler.withRetry()` — 3 proby z opoznieniami 200ms, 800ms, 2000ms. Obsluguje:
- `RateLimitException` (429)
- `ApiConnectionException` (siec)
- `ApiException` z statusCode >= 500

4xx (np. `InvalidRequestException`) NIE sa ponawiane.

### Edge Case: klient z >365 dniami
Mechanizm `capped + overflow` w `calculateProratedDiscount` poprawnie obsluguje kazdy przypadek:
- Kupon = `min(cena_nowego_planu, wartosc_pozostala)` — nigdy nie przekracza ceny planu
- Overflow = roznica idzie na `customer.balance` w Stripe (kredyt na przyszle faktury)
- Przetestowane scenariuszami: 500 dni annual→monthly, 500 dni annual→annual, 60 dni monthly→monthly

### Testy (122 integracyjne, 39 frontend)
- TestContainers z prawdziwym PostgreSQL 16 (NIE H2)
- Testy negatywne: 8-watkowy concurrent `activateSubscription`, row-lock blocking, withRetry positive/negative/4xx
- E2E na zywo: nowe konto `qa-paranoid-test@properbackup.dev` na serwerze testowym

## PRy implementujace

- `properbackup-buffer#21` — backend (activateSubscription max() + handleSubscriptionDeleted + SELECT FOR UPDATE + retry)
- `properbackup-web#30` — frontend (usuniety downgrade guard + bfcache fix)
