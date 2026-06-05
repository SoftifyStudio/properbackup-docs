# Subscription & Trial Expiration Handling

## Architektura

System obsługuje dwa typy wygasania:
1. **Trial** — `trial_expires_at` (30 dni od rejestracji)
2. **Subskrypcja** — `subscription_expires_at` (ustawiane przez Stripe webhook)

> ⚠️ **OPEN DECISION D-3 (model trialu).** Powyższy opis „30 dni od rejestracji"
> jest niezgodny z `master-tdd-plan.md` §5.1, który deklaruje model **card-first**
> (trial startuje dopiero po udanym Stripe Checkout). Do czasu rozstrzygnięcia (patrz
> `master-tdd-plan.md` Dodatek F, D-3) traktuj card-first jako kanon. Rekomendacja:
> card-first — bez karty `subscription_status='none'`, brak `trial_expires_at`.

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

---

# LLD — Access Boundary i kontrakt decyzyjny

> Sekcja referencyjna dla agenta. Definiuje **jedną** funkcję prawdy o dostępie,
> tak aby UI, agent i buffer nie liczyły wygaśnięcia każdy po swojemu (rozjazd =
> bug). Cała logika jest **lazy** (brak crona) i liczona per request w UTC.

## 1. Maszyna stanów dostępu (Access Boundary)

```
                 trial_expires_at > now
       ┌──────────────────────────────────────┐
       │                                       ▼
   [TRIAL] ──expired──► [LOCKED_TRIAL] ──pay──► [ACTIVE_SUB]
                                                  │   ▲
                                          cancel  │   │ pay/renew
                                                  ▼   │
                                          [CANCELLED_GRACE]  (expiresAt > now)
                                                  │
                                          expired ▼
                                          [LOCKED_EXPIRED]
```

| Stan | Warunek | Dostęp do backupów | UI badge |
|------|---------|--------------------|----------|
| `TRIAL` | `trial_expires_at > now` ∧ brak sub | full | „Wersja próbna" |
| `LOCKED_TRIAL` | `trial_expires_at <= now` ∧ brak sub | read-only restore, brak nowych uploadów | „Trial wygasł" |
| `ACTIVE_SUB` | `subscription_expires_at > now` ∧ `stripe_subscription_id != NULL` | full | „Aktywna" |
| `CANCELLED_GRACE` | `subscription_expires_at > now` ∧ `stripe_subscription_id = NULL` | full | „Aktywna (anulowana)" |
| `LOCKED_EXPIRED` | `subscription_expires_at <= now` ∧ brak trialu | read-only restore | „Subskrypcja wygasła" |

> **Decyzja produktowa (do potwierdzenia z Danielem):** stan zablokowany daje
> **read-only restore** (klient odzyskuje dane), ale blokuje nowe uploady.
> Dane NIE są kasowane przy wygaśnięciu — patrz `ovh-cloud-archive-migration-spec.md`
> (HR-7: cold tier, NIE delete).

> ⚠️ **OPEN DECISION D-1 / D-2.** Ta FSM (`canRestore` zawsze true, patrz §2)
> jest **sprzeczna** z `master-tdd-plan.md` §5.3 (`expired`/`none` => `canRestore=false`)
> i **nie zawiera stanów `past_due_grace`/`past_due_suspended`** wymaganych przez
> dunning (Test 10, §9.4). Kanon billingu to FSM z `master-tdd-plan.md` §5.2/§5.3.
> Rozstrzygnięcie: `master-tdd-plan.md` Dodatek F (D-1 = anti-hostage rekomendowane,
> D-2 = jedna maszyna stanów). NIE koduj testu, póki D-1 nie jest rozstrzygnięte.

## 2. Jedna funkcja prawdy

```kotlin
enum class AccessState { TRIAL, LOCKED_TRIAL, ACTIVE_SUB, CANCELLED_GRACE, LOCKED_EXPIRED }

object AccessBoundary {
    fun evaluate(u: User, now: Instant = Instant.now()): AccessState {
        val subActive = u.subscriptionExpiresAt?.isAfter(now) == true
        val trialActive = u.trialExpiresAt?.isAfter(now) == true
        return when {
            subActive && u.stripeSubscriptionId != null -> AccessState.ACTIVE_SUB
            subActive                                    -> AccessState.CANCELLED_GRACE
            trialActive                                  -> AccessState.TRIAL
            u.everSubscribed || u.subscriptionExpiresAt != null -> AccessState.LOCKED_EXPIRED
            else                                         -> AccessState.LOCKED_TRIAL
        }
    }

    fun canUpload(s: AccessState) = s == AccessState.TRIAL || s == AccessState.ACTIVE_SUB || s == AccessState.CANCELLED_GRACE
    fun canRestore(s: AccessState) = true   // restore zawsze dozwolony (anti-hostage)
}
```

- **canRestore zawsze true** — nigdy nie bierzemy danych klienta „na zakładnika".
- `AccessBoundary.evaluate` to jedyne miejsce decyzji; UI dostaje `accessState` z API
  (`GET /api/account/status`), agent dostaje `canUpload` w heartbeacie.

> ⚠️ Wartość `canRestore` powyżej (zawsze `true`) podlega **OPEN DECISION D-1**
> (`master-tdd-plan.md` Dodatek F). Jeśli Daniel potwierdzi anti-hostage — ten kod
> jest poprawny i `master-tdd-plan.md` §5.3 wymaga aktualizacji. Jeśli nie —
> `canRestore` musi zależeć od stanu. Do tego czasu: **nie implementować**.

## 3. Proration — edge cases (uzupełnienie)

Wzór bazowy `rabat = (cena_planu / 30) * dni_pozostałe` ma pułapki:

| Edge case | Reguła |
|-----------|--------|
| `dni_pozostałe > 30` (annual w trakcie) | rabat = `min(cena_planu, wartość_pozostała)`; nadwyżka → `customer.balance` (kredyt). Patrz `downgrade-logic.md` §„capped + overflow" |
| plan annual: dzielnik 30 vs 365 | dla annual proration liczona wg realnej ceny dziennej planu źródłowego, nie sztywne `/30` |
| rabat ujemny (zegar przeskoczył) | clamp do `0` (`coerceAtLeast(0)`) |
| promo + proration jednocześnie | promo aplikowane PO proracji; suma rabatów ≤ cena planu (patrz `promo-codes.md`) |

## 4. `GET /api/account/status` — payload

```json
{
  "accessState": "CANCELLED_GRACE",
  "trialExpiresAt": null,
  "subscriptionExpiresAt": "2027-05-24T00:00:00Z",
  "subscriptionPlan": "annual",
  "daysRemaining": 312,
  "canUpload": true,
  "canRestore": true
}
```

## 5. Cross-references

- `downgrade-logic.md` — `max()`, `handleSubscriptionDeleted`, niezmienniki I-1..I-5.
- `trial-abuse-prevention.md` — `ever_trialed` / `ever_subscribed`.
- `ovh-cloud-archive-migration-spec.md` — co się dzieje z danymi po wygaśnięciu (cold tier).
