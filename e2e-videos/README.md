# E2E Test Videos — ProperBackup Subscription Flows

Automated Playwright E2E tests run against live test server (`properbackup-test-server.softify.com.pl`) with real Stripe test mode.

**Last run:** 2026-05-26 (after trial abuse + past_due fixes)  
**Result:** 10/10 PASSED (9.6 minutes total)  
**Test code:** [`properbackup-web/tests/e2e/`](https://github.com/SoftifyStudio/properbackup-web/tree/main/tests/e2e)

## Videos (2026-05-26 — with fixes)

Directory: `2026-05-26-fixes/`

| # | File | Test | Time | Status |
|---|------|------|------|--------|
| 1 | `test01-registration.webm` | Rejestracja → pending payment, `trial_expires_at=NULL`, blue banner | 16s | PASS |
| 2 | `test02-checkout-trial.webm` | Checkout z `trial_period_days=30`, Stripe redirect | 17s | PASS |
| 3 | `test03-payment-activation.webm` | Płatność kartą 4242 → webhook → subscription active | 53s | PASS |
| 4 | `test04-cancel.webm` | Anulowanie subskrypcji → `cancel_at_period_end=true` | 20s | PASS |
| 5 | `test05-renew.webm` | Cofnięcie anulowania → `cancel_at_period_end=false` | 21s | PASS |
| 6 | `test06-plan-change.webm` | Monthly → Annual w trakcie trialu | 1.6m | PASS |
| 7 | `test07-trial-abuse.webm` | Ta sama karta 4242 na dwóch kontach → **Account B BLOCKED** | 2.2m | PASS |
| 8 | `test08-race-condition.webm` | Redirect przed webhookiem → brak 403 | 16s | PASS |
| 9 | `test09-expiry.webm` | Wygaśnięcie → API `active:false`, UI expired | 1.1m | PASS |
| 10 | `test10-payment-failure.webm` | Odmowa płatności → **past_due z grace period** (yellow banner) | 1.3m | PASS |

### Key fixes in this run vs previous:
- **Test 7:** Backend now blocks Account B via card fingerprint validation in PostgreSQL + `abuse_blocked` flag in `activateSubscription` transaction
- **Test 10:** Backend sets `past_due` status + 7-day grace period instead of immediate lockout. Frontend shows yellow warning banner.

## Jak odpalić testy

```bash
cd properbackup-web
npx playwright install chromium
npx playwright test
```

Filmiki zapisywane w `test-results/`, raport HTML w `playwright-report/`.

## Uwagi

- **Test 7 (abuse):** Backend waliduje fingerprint karty w PostgreSQL — nawet jeśli Stripe test mode nie blokuje duplikatów, nasza logika serwerowa to robi. Guard w `activateSubscription` (SELECT FOR UPDATE) uniemożliwia race condition z `invoice.paid`.
- **Test 10 (payment failure):** Karta `4000000000000341` przechodzi setup ale odmawia przy przyszłych obciążeniach. Backend ustawia `past_due` + 7-dniowy grace period. UI pokazuje żółte ostrzeżenie.
- Wszystkie testy tworzą unikalne konta `*@properbackup.dev` — nie wpływają na dane produkcyjne.
- Każda grupa testów czyści `stripe_card_fingerprint` w DB przed startem, zapewniając niezależność testów.
