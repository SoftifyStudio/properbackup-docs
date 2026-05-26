# Trial Abuse Prevention

## Problem

Użytkownik mógł zakładać kolejne konta na nowe adresy e-mail i za każdym razem otrzymywać 30 dni darmowego trialu.

Pierwotnie `trial_expires_at` było ustawiane **retroaktywnie** przez migrację w `schema.sql`, która uruchamiała się przy każdym starcie aplikacji:

```sql
UPDATE users SET trial_expires_at = created_at + INTERVAL '30 days'
  WHERE trial_expires_at IS NULL;
```

To powodowało, że:
1. Każdy nowy użytkownik startował z `trial_expires_at = NULL`
2. Dopiero po restarcie serwera migracja ustawiała datę wygaśnięcia
3. W oknie między rejestracją a restartem trial nie był egzekwowany

## Rozwiązanie

### 1. Trial ustawiany przy rejestracji (UserStore.kt)

```kotlin
companion object {
    const val TRIAL_DAYS = 30
}

fun register(email: String, plainPassword: String): User {
    val now = Instant.now()
    val trialExpires = now.plus(Duration.ofDays(TRIAL_DAYS.toLong()))
    // INSERT INTO users (..., trial_expires_at) VALUES (..., ?)
    ps.setTimestamp(7, Timestamp.from(trialExpires))
}
```

`trial_expires_at` jest teraz ustawiany atomowo razem z `INSERT` — brak okna bez ochrony.

### 2. Migracja z guardem (schema.sql)

```sql
UPDATE users SET trial_expires_at = created_at + INTERVAL '30 days'
  WHERE trial_expires_at IS NULL
    AND subscription_plan IS NULL
    AND ever_subscribed = FALSE;
```

Guard `ever_subscribed = FALSE` zapobiega sytuacji, w której użytkownik, który już kiedyś płacił, dostaje ponownie darmowy trial.

### 3. Stripe jako dodatkowa warstwa

Sam Stripe jest najskuteczniejszą blokadą — ta sama karta kredytowa = ten sam customer, nawet jeśli e-mail jest inny. Konfiguracja w panelu Stripe:
- Ustawienie limitu jednego trialu na kartę
- Rozpoznawanie powtarzających się kart

## Weryfikacja

| Test | Wynik |
|------|-------|
| Nowe konto → `trial_expires_at` = `created_at + 30 dni` | PASS |
| Drugie konto → niezależny `trial_expires_at` | PASS |
| `ever_subscribed = TRUE` → migracja nie nadpisze | PASS |

## Pliki zmienione

- `properbackup-buffer/src/main/kotlin/.../auth/UserStore.kt` — dodano `TRIAL_DAYS`, ustawianie `trial_expires_at` przy INSERT
- `properbackup-buffer/src/main/resources/schema.sql` — guard `ever_subscribed = FALSE` w migracji
