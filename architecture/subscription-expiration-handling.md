# Subscription & Trial Expiration Handling

## Architektura

System obsługuje dwa typy wygasania:
1. **Trial** — `trial_expires_at` (30 dni od rejestracji)
2. **Subskrypcja** — `subscription_expires_at` (ustawiane przez Stripe webhook)

### Backend (StripeHandler / UserStore)

Porównanie timestamp-based w Kotlin:

```kotlin
val now = Instant.now()
val isTrialExpired = user.trialExpiresAt != null && Instant.parse(user.trialExpiresAt).isBefore(now)
val isSubExpired = user.subscriptionExpiresAt != null && Instant.parse(user.subscriptionExpiresAt).isBefore(now)
```

Kolumny w PostgreSQL (TIMESTAMPTZ):
- `trial_expires_at` — ustawiany przy rejestracji (`NOW() + 30 days`)
- `subscription_expires_at` — ustawiany przez webhook Stripe (`checkout.session.completed`)
- `subscription_plan` — `monthly` | `annual` | `NULL`

### Frontend (SubscriptionPage.jsx)

UI reaguje na stan subskrypcji:

| Stan | Badge | Pozostałe dni | Ceny |
|------|-------|---------------|------|
| Trial aktywny | `Wersja próbna` (zielony) | Countdown do `trial_expires_at` | Z proracją (credit za trial) |
| Trial wygasły | `Trial wygasł` (czerwony) | 0 | Pełne ceny |
| Subskrypcja aktywna | `Aktywna` + `AKTYWNY PLAN` | Countdown do `subscription_expires_at` | Z proracją |
| Subskrypcja anulowana | `Aktywna` + `(Anulowana — nie zostanie odnowiona)` | Countdown | Z proracją |

### Proration

Gdy użytkownik ma aktywny trial lub subskrypcję, system oblicza rabat proporcjonalny:

```
rabat = (cena_planu / 30) * dni_pozostałe
cena_do_zapłaty = cena_planu - rabat
```

Przy wygasłym trialu/subskrypcji proration = 0, więc użytkownik płaci pełną cenę.

## Flow wygasania

```
Trial aktywny (30 dni)
  ↓ czas mija
Trial wygasł (0 dni)
  ↓ użytkownik płaci
Subskrypcja aktywna (30 dni)
  ↓ użytkownik anuluje
Subskrypcja anulowana (countdown do końca)
  ↓ czas mija
Subskrypcja wygasła → powrót do stanu "brak planu"
  ↓ użytkownik może reaktywować
Subskrypcja aktywna (nowy okres)
```

## Weryfikacja E2E

| Test | Wynik |
|------|-------|
| Trial 30d → countdown poprawny | PASS |
| Trial wygasły → badge "Trial wygasł", 0 dni | PASS |
| Subskrypcja aktywna → badge "Aktywna", countdown | PASS |
| Anulowanie → "(Anulowana — nie zostanie odnowiona)" | PASS |
| Reaktywacja → powrót do normalnego stanu | PASS |
