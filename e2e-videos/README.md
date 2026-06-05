# E2E Test Videos — ProperBackup Subscription Flows

Automated Playwright E2E tests run against live test server (`properbackup-test-server.softify.com.pl`) with real Stripe test mode.

**Last run:** 2026-05-26 (after trial abuse + past_due fixes)  
**Result:** 10/10 PASSED (9.6 minutes total)  
**Test code:** [`properbackup-web/tests/e2e/`](https://github.com/SoftifyStudio/properbackup-web/tree/main/tests/e2e)

## Konwencja nagrań (protokół RECORD & WRITE-BACK)

Pełny protokół: [`architecture/master-tdd-plan.md` §11.1](../architecture/master-tdd-plan.md). W skrócie:

- **Natywne wideo Playwright** (`video:'on'`), NIE nagrywanie ekranu Devina — deterministyczne i małe.
- **Katalog per data + temat:** `e2e-videos/<YYYY-MM-DD>-<temat>/` (np. `2026-06-05-billing-hardening/`). Append-only — nie nadpisuj starych zestawów.
- **Nazewnictwo:** `testNN-krotki-opis.webm`.
- **Każdy zielony test 2× pod rząd** (anty-flake), `workers=1`.
- Po zielonym teście agent dopisuje wiersz do tabeli poniżej **oraz** do tabeli statusów w `master-tdd-plan.md` §11.2 (link do `.webm` + commita implementacji). Brak wideo zielonego testu = test nie jest „Done" (DoD §10 pkt 11).

> **Legacy / do konsolidacji:** pliki `testNN-*.webm` leżące płasko w katalogu głównym to starszy zestaw zduplikowany z `2026-05-26-fixes/`. Aktualny indeks to tabele poniżej; płaskie pliki traktuj jako archiwum (kandydat do usunięcia w osobnym PR porządkowym).

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

## Videos (2026-05-30 — recovery restore)

Directory: `2026-05-30-recovery/`

| # | File | Test | Time | Status |
|---|------|------|------|--------|
| 1 | `test01-recovery-restore.webm` | UI download → AES-256-GCM decrypt → tar xzf → SHA-256 = oryginał (`c985a725…dbe32`) | 11s | PASS |

Test 1 (API restore) + Test 2 (UI restore) oba zielone 2× pod rząd. Natywne wideo Playwright (nie nagrywanie ekranu Devina).
Test code: [`properbackup-web/tests/e2e/recovery-e2e.spec.js`](https://github.com/SoftifyStudio/properbackup-web/tree/main/tests/e2e/recovery-e2e.spec.js)

### Key fixes in this run vs previous:
- **Test 7:** Backend now blocks Account B via card fingerprint validation in PostgreSQL + `abuse_blocked` flag in `activateSubscription` transaction
- **Test 10:** Backend sets `past_due` status + 7-day grace period instead of immediate lockout. Frontend shows yellow warning banner.

## Videos (2026-05-31 — money module hardening)

Directory: `2026-05-31/`

**41/41 PASSED** (12.7 min, 1 worker, zero retries). Full payment module hardening.

20 .webm recordings from browser-based tests (API-only tests have no video):

| Group | Tests | Coverage |
|-------|-------|----------|
| A (9) | M-DECLINE-01..09 | Card declines: generic, insufficient_funds, lost, stolen, expired, CVC, processing_error, charge-fail, Radar |
| B (2) | M-3DS-01..02 | 3D Secure: auth success/fail |
| C (5) | M-SUB-01..06 | Subscription lifecycle: abandoned, double-sub, cancel, reactivate, past_due |
| F (2) | M-ABUSE-01,05 | Trial abuse: card fingerprint, expired trial retry |

API-only tests (no video): WEBHOOK-03/04, IDEMP-02/03, ABUSE-03, AUTHZ-01..06, INPUT-01..05, VAT-01..03, RESIL-02/05, EDGE-01..04

### Bugs found and fixed (2 × A-type):
1. `StripeHandler.kt` — invalid `plan` → 503 NPE. Fixed: `plan in listOf("monthly", "annual")` guard → 400.
2. `AuthHandler.kt` — email >64 chars / invalid format / SQL injection → 500. Fixed: regex + length validation → 400.

Test code: [`properbackup-web/tests/e2e/edge-money-e2e.spec.js`](https://github.com/SoftifyStudio/properbackup-web/tree/main/tests/e2e/edge-money-e2e.spec.js)

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
