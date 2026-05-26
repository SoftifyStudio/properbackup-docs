# E2E Test Videos — ProperBackup Subscription Flows

Automated Playwright E2E tests run against live test server (`properbackup-test-server.softify.com.pl`) with real Stripe test mode.

**Last run:** 2026-05-26  
**Result:** 10/10 PASSED (9 minutes total)  
**Test code:** [`properbackup-web/tests/e2e/`](https://github.com/SoftifyStudio/properbackup-web/tree/main/tests/e2e)

## Videos

| # | File | Test | Time |
|---|------|------|------|
| 1 | `test01-registration-pending-payment.webm` | Rejestracja → pending payment, `trial_expires_at=NULL`, blue banner | 16s |
| 2 | `test02-checkout-session-trial.webm` | Checkout z `trial_period_days=30`, Stripe redirect | 15s |
| 3 | `test03-payment-activation.webm` | Płatność kartą 4242 → webhook → subscription active | 51s |
| 4 | `test04-cancel-subscription.webm` | Anulowanie subskrypcji → `cancel_at_period_end=true` | 21s |
| 5 | `test05-renew-subscription.webm` | Cofnięcie anulowania → `cancel_at_period_end=false` | 21s |
| 6 | `test06-plan-change-monthly-to-annual.webm` | Monthly → Annual w trakcie trialu | 1.6m |
| 7 | `test07-trial-abuse-same-card.webm` | Ta sama karta 4242 na dwóch kontach | 1.9m |
| 8 | `test08-race-condition.webm` | Redirect przed webhookiem → brak 403 | 16s |
| 9 | `test09-expiry-access-block.webm` | Wygaśnięcie → API `active:false`, UI expired | 1.1m |
| 10 | `test10-payment-failure.webm` | Karta 4000000000000341 + symulacja expiry | 1.1m |

## Screenshots

Folder `screenshots/` zawiera zrzuty ekranu z kluczowych momentów każdego testu.

## Jak odpalić testy

```bash
cd properbackup-web
npx playwright install chromium
npx playwright test
```

Filmiki zapisywane w `test-results/`, raport HTML w `playwright-report/`.

## Uwagi

- **Test 7 (abuse):** W Stripe test mode ta sama karta testowa (4242) jest dozwolona na wielu kontach. W trybie live Stripe Radar blokuje to przez fingerprinting karty.
- **Test 10 (payment failure):** Karta `4000000000000341` przechodzi setup ale odmawia przy przyszłych obciążeniach. Symulujemy expiry przez DB.
- Wszystkie testy tworzą unikalne konta `*@properbackup.dev` — nie wpływają na dane produkcyjne.
