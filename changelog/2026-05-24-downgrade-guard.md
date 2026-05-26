# Downgrade Guard — blokada przejścia z planu rocznego na miesięczny

**Data:** 2026-05-24  
**PRy:** buffer#20, web#29  
**Severity:** CRITICAL bugfix

## Problem

Gdy użytkownik posiadał aktywny plan roczny (np. wygasa 2027-05-24) i kliknął "Wybierz i zapłać" na planie miesięcznym:

1. Prorated discount pokrywał pełną cenę → checkout za 0 PLN
2. Webhook `checkout.session.completed` kasował starą subskrypcję Stripe
3. DB nadpisywane: `subscription_plan = 'monthly'`, `subscription_expires_at = ~30 dni`
4. **Plan roczny utracony** — użytkownik tracił kilkanaście miesięcy pokrycia

## Rozwiązanie

### Backend (buffer#20)

Guard w `createCheckoutSession` — jeśli `currentPlan == annual` i `requestedPlan == monthly` i `daysRemaining > 31`:

```
HTTP 409 Conflict
{
  "error": "downgrade_blocked",
  "reason": "active_annual_plan",
  "daysRemaining": 364,
  "message": "Cannot switch to monthly while annual plan is active with 364 days remaining."
}
```

### Frontend (web#29)

- Karta miesięczna: amber warning + disabled button gdy plan roczny aktywny
- Karta roczna: zawsze aktywna (odnowienie / upgrade dozwolone)

## Co NIE jest blokowane

| Scenariusz | Dozwolone? |
|---|---|
| annual → monthly (>31 dni) | ❌ Zablokowane |
| annual → annual (odnowienie) | ✅ Tak |
| monthly → annual (upgrade) | ✅ Tak |
| monthly → monthly (odnowienie) | ✅ Tak |
| annual → monthly (≤31 dni) | ✅ Tak (plan prawie wygasa) |

## Testy E2E na żywym serwerze

Przetestowane na `properbackup-test-server.softify.com.pl`:

1. ✅ Frontend: disabled button + amber warning na karcie miesięcznej (annual aktywny, 364 dni)
2. ✅ Backend: `POST /payment/stripe/checkout {plan: "monthly"}` → HTTP 409 `downgrade_blocked`
3. ✅ Backend: `POST /payment/stripe/checkout {plan: "annual"}` → HTTP 200 (odnowienie dozwolone)
4. ✅ Frontend: monthly → annual upgrade button aktywny (bez blokady)
