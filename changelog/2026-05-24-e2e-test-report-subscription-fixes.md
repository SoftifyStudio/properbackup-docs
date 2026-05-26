# E2E Test Report — Subscription Fixes (2026-05-24)

## Podsumowanie

Pełne testy End-to-End po wdrożeniu poprawek:
1. Trial abuse prevention (trial_expires_at przy rejestracji)
2. Expiration handling (UI + backend timestamp-based)
3. UI redesign plan cards (usunięcie Best Value, kontrast aktywnego planu)
4. Legal withdrawal waiver (art. 38 pkt 13)

**Wynik: 7/7 testów PASSED**

## Środowisko testowe

- Serwer: `properbackup-test-server.softify.com.pl`
- Backend: port 7100 (Javalin)
- DB: PostgreSQL 16 (Docker `properbackup-db`)
- Stripe: tryb testowy (sandbox) dla obu kluczy (test + live)
- Karta testowa: 4242 4242 4242 4242

## Wyniki testów

| # | Test | Opis | Wynik |
|---|------|------|-------|
| 1 | UI Redesign | AKTYWNY PLAN badge, brak Best Value, savings w annual | PASS |
| 2 | Trial Registration | Nowe konto → trial_expires_at = created_at + 30d w DB | PASS |
| 3 | Stripe Checkout | Opłacenie monthly → subscription_plan = "monthly" w DB | PASS |
| 4 | Post-checkout UI | Badge AKTYWNY PLAN na monthly, countdown, karta Visa | PASS |
| 5 | Cancel + Reactivate | Anuluj → "(Anulowana)", Reaktywuj → powrót do normy | PASS |
| 6 | Trial Abuse Check | 2 konta → niezależne trial_expires_at, guard ever_subscribed | PASS |
| 7 | Expiration Handling | Wygasły trial → "Trial wygasł", 0 dni, pełne ceny | PASS |

### Bonus: i18n

- PL → EN switching działa poprawnie
- Klauzula prawna widoczna w obu językach

## Konta testowe

| Email | Stan | subscription_plan |
|-------|------|-------------------|
| `e2e-trial-test-1779643859@properbackup.dev` | Subscribed (monthly) | monthly |
| `e2e-trial-abuse-1779644331@properbackup.dev` | Trial (30d) | NULL |

## Weryfikacja DB

```
 email                                       | subscription_plan | trial_expires_at              | trial_duration | ever_subscribed
---------------------------------------------+-------------------+-------------------------------+----------------+-----------------
 e2e-trial-test-1779643859@properbackup.dev  | monthly           | 2026-06-23 17:31:00.876651+00 | 30 days        | t
 e2e-trial-abuse-1779644331@properbackup.dev | NULL              | 2026-06-23 17:39:05.513481+00 | 30 days        | f
```

## Nagranie

Nagranie ekranowe z pełnym przebiegiem testów E2E dostępne w sesji Devin.
