# Playwright E2E TDD — Master Plan

> **Status:** Aktywny plan testowy. Single source of truth dla sesji Playwright E2E.
> **Serwer testowy:** `properbackup-test-server.softify.com.pl`
> **Kod testow:** `properbackup-web/tests/e2e/`
> **Strategia:** planujemy w docs → piszemy prompty → delegujemy do sesji Devin (micro-tasking)

---

## 0. Architektura testowania

```
┌─────────────────────────────────────────────────────────┐
│  Srodowisko Devina (maszyna agenta)                      │
│                                                          │
│  ┌──────────────────────────┐                            │
│  │  Playwright (Chromium)    │                            │
│  │  npx playwright test      │                            │
│  │  - headless               │                            │
│  │  - video recording        │                            │
│  │  - trace on failure       │                            │
│  └────────────┬─────────────┘                            │
│               │                                          │
│               │ HTTP (port 80)                           │
└───────────────┼──────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  Test Server (properbackup-test-server.softify.com.pl)   │
│                                                          │
│  ┌─────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │  Nginx   │→│  Buffer :7100 │→│  PostgreSQL :5432  │    │
│  │  :80     │  │  (Javalin)   │  │  (Docker)          │    │
│  └─────────┘  └──────────────┘  └──────────────────┘    │
│                                                          │
│  Stripe: sandbox (sk_test_..., pk_test_...)              │
│  Karta testowa: 4242 4242 4242 4242                      │
│  Konta: *@properbackup.dev (unikalne per test)           │
└─────────────────────────────────────────────────────────┘
```

**Zasada:** Playwright NIGDY nie chodzi na serwerze testowym. Zawsze na maszynie Devina.
Serwer testowy to **srodowisko produkcyjno-podobne** z prawdziwym backendem, DB i Stripe sandbox.

### Dostep do DB (weryfikacja stanu)

Testy moga weryfikowac stan DB przez:
1. **API backendu** — `GET /account/subscription`, `GET /admin/...` (preferowane)
2. **SSH + docker exec** — `docker exec properbackup-db psql -U properbackup -c "SELECT ..."` (dla edge cases gdzie API nie eksponuje danych)

### Konta testowe

- Kazdy test tworzy konto z unikalnym emailem: `e2e-{testname}-{timestamp}@properbackup.dev`
- Po tescie konto zostaje (nie kasujemy — to dane testowe na sandboxie)
- Fingerprint karty czyszczony przed kazda grupa testow (zapewnia niezaleznosc)

---

## 1. Co JUZ jest przetestowane (baseline)

### Subscription flows (2026-05-26) — 10/10 PASSED

| # | ID | Test | Plik |
|---|------|------|------|
| 1 | `SUB-01` | Rejestracja → pending payment | `subscription-e2e.spec.js` |
| 2 | `SUB-02` | Checkout + trial 30d | `subscription-e2e.spec.js` |
| 3 | `SUB-03` | Platnosc 4242 → webhook → active | `subscription-e2e.spec.js` |
| 4 | `SUB-04` | Anulowanie subskrypcji | `subscription-e2e.spec.js` |
| 5 | `SUB-05` | Cofniecie anulowania (renew) | `subscription-e2e.spec.js` |
| 6 | `SUB-06` | Monthly → Annual w trialu | `subscription-e2e.spec.js` |
| 7 | `SUB-07` | Trial abuse — ta sama karta, 2 konta | `subscription-e2e.spec.js` |
| 8 | `SUB-08` | Race: redirect przed webhookiem | `subscription-e2e.spec.js` |
| 9 | `SUB-09` | Wygasniecie subskrypcji | `subscription-e2e.spec.js` |
| 10 | `SUB-10` | Odmowa platnosci → past_due grace | `subscription-e2e.spec.js` |

### Recovery (2026-05-30) — 2/2 PASSED

| # | ID | Test | Plik |
|---|------|------|------|
| 1 | `REC-01` | API restore + SHA-256 verify | `recovery-e2e.spec.js` |
| 2 | `REC-02` | UI restore → decrypt → SHA-256 = oryginal | `recovery-e2e.spec.js` |

---

## 2. Nowe testy do napisania — EDGE CASES (priorytet)

Ponizsze scenariusze to **najwazniejsza czesc** tego planu. Kazdy edge case to
potencjalna dziura bezpieczenstwa lub incydent finansowy. Testy pogrupowane
tematycznie, od najwyzszego priorytetu.

### Grupa E1 — Stripe & Money Edge Cases

| # | ID | Scenariusz | Typ | Ref |
|---|------|-----------|-----|-----|
| 1 | `EDGE-MONEY-01` | Karta 4000000000000341 (always decline) → checkout OK ale subscription incomplete → UI "karta odrzucona" | Playwright | 8.13 |
| 2 | `EDGE-MONEY-02` | Browser back button po Stripe Checkout → brak duplikatu sesji | Playwright | 8.15 |
| 3 | `EDGE-MONEY-03` | Webhook przychodzi PRZED redirect → frontend widzi aktywna subskrypcje bez ProcessingScreen | Playwright | 8.14 |
| 4 | `EDGE-MONEY-04` | Double-click „Rozpocznij trial" (3× w 500ms) → 1 request, 1 sesja Checkout, brak duplikatu w audit_log | Playwright | 8.21 |
| 5 | `EDGE-MONEY-05` | Zmiana planu monthly → annual w trakcie checkout (back → annual) → nowa sesja, brak podwojnego obciazenia | Playwright | — |
| 6 | `EDGE-MONEY-06` | Weryfikacja VAT w UI (brutto/netto/VAT 23%, oszczednosc roczna 38 PLN) | Playwright | — |

> **Uwaga:** wczesniejsze warianty E1 — „brak live price config → clean error" (master-tdd-plan §8.18) oraz „10 rownoczesnych POST /checkout → idempotency" (§8.2) — przeniesione do backlogu. Idempotency webhooków pokrywa `EDGE-RACE-02` w Grupie E4.

### Grupa E2 — Trial Abuse & Auth Edge Cases

| # | ID | Scenariusz | Typ | Ref |
|---|------|-----------|-----|-----|
| 1 | `EDGE-AUTH-01` | Email nie zweryfikowany → Checkout zablokowany → "Potwierdz email" | Playwright | 8.16 |
| 2 | `EDGE-AUTH-02` | Dlugi email >64 znakow → 400 EMAIL_TOO_LONG | Playwright | 8.29 |
| 3 | `EDGE-AUTH-03` | Trial abuse: 3 konta, ta sama karta → konto 2 i 3 zablokowane | Playwright | 8.5 (ext) |
| 4 | `EDGE-AUTH-04` | Wygasly trial + proba Checkout → poprawny flow (nie "juz masz trial") | Playwright | — |
| 5 | `EDGE-AUTH-05` | Rejestracja z disposable email (tempmail.io) → odrzucenie lub warning | Playwright | AV-1 |

### Grupa E3 — UI/UX Edge Cases

| # | ID | Scenariusz | Typ | Ref |
|---|------|-----------|-----|-----|
| 1 | `EDGE-UI-01` | Countdown timer: trial_expires_at vs daysRemaining (brak driftu) | Playwright | 8.19 |
| 2 | `EDGE-UI-02` | Past_due → yellow banner → update payment method → banner znika | Playwright | — |
| 3 | `EDGE-UI-03` | Expired sub → read-only restore, brak uploadu, "Subskrypcja wygasla" | Playwright | — |
| 4 | `EDGE-UI-04` | Plan cards: aktywny plan ma badge, drugi ma "Zmien plan", ceny brutto/netto | Playwright | — |
| 5 | `EDGE-UI-05` | i18n PL ↔ EN → teksty subskrypcji, klauzula art. 38, daty w locale | Playwright | — |
| 6 | `EDGE-UI-06` | Responsive: mobile viewport (375px) → plan cards stack vertically | Playwright | — |

### Grupa E4 — Webhook & Race Condition Edge Cases

| # | ID | Scenariusz | Typ | Ref |
|---|------|-----------|-----|-----|
| 1 | `EDGE-RACE-01` | Cancel + invoice.paid w tym samym momencie → poprawny stan koncowy | API | 8.1 |
| 2 | `EDGE-RACE-02` | 2 identyczne webhooki (ten sam event.id) → przetworzony dokladnie raz | API | 8.22 |
| 3 | `EDGE-RACE-03` | Out-of-order webhook (subscription.deleted PRZED checkout.completed) | API | 8.30 |
| 4 | `EDGE-RACE-04` | Webhook z przyszlosci (clock skew >5min) → odrzucony | API | 7.3 |

### Grupa E5 — Recovery & Storage Edge Cases

| # | ID | Scenariusz | Typ | Ref |
|---|------|-----------|-----|-----|
| 1 | `EDGE-STORE-01` | Restore pliku ktory zostal sealed do packa (unpack-on-read) | Playwright | — |
| 2 | `EDGE-STORE-02` | Restore z expired sub → dozwolony (read-only) | Playwright | — |
| 3 | `EDGE-STORE-03` | Download duzego pliku (>100MB) → timeout handling | Playwright | — |

---

## 3. Konwencje testow Playwright

### Naming

```
tests/e2e/
├── subscription-e2e.spec.js          # SUB-01..SUB-10 (istniejace)
├── recovery-e2e.spec.js              # REC-01..REC-02 (istniejace)
├── edge-money-e2e.spec.js            # EDGE-MONEY-01..06 (NOWE)
├── edge-auth-e2e.spec.js             # EDGE-AUTH-01..05 (NOWE)
├── edge-ui-e2e.spec.js               # EDGE-UI-01..06 (NOWE)
├── edge-race-e2e.spec.js             # EDGE-RACE-01..04 (NOWE)
└── edge-storage-e2e.spec.js          # EDGE-STORE-01..03 (NOWE)
```

### Struktura testu

```javascript
import { test, expect } from '@playwright/test';

const BASE_URL = 'http://properbackup-test-server.softify.com.pl';

test.describe('EDGE-MONEY: Stripe & Money Edge Cases', () => {
  test.beforeEach(async ({ page }) => {
    // Cleanup: wyczysc fingerprint karty w DB (jesli potrzebne)
    // await cleanupCardFingerprints();
  });

  test('EDGE-MONEY-01: declined card shows error, not active subscription', async ({ page }) => {
    // 1. Zarejestruj nowe konto
    const email = `e2e-decline-${Date.now()}@properbackup.dev`;
    await page.goto(`${BASE_URL}/register`);
    // ... rejestracja ...

    // 2. Przejdz do Checkout z karta 4000000000000341
    // ... checkout flow ...

    // 3. Asercja: UI pokazuje blad, NIE aktywna subskrypcje
    await expect(page.locator('[data-testid="subscription-status"]'))
      .toContainText('incomplete');
  });
});
```

### Playwright config

```javascript
// playwright.config.js
export default {
  testDir: './tests/e2e',
  timeout: 120_000,        // 2 min per test (Stripe webhooks moga trwac)
  retries: 0,              // ZERO retries — chcemy widziec prawdziwe failures
  use: {
    baseURL: 'http://properbackup-test-server.softify.com.pl',
    video: 'on',           // nagrywaj KAZDY test
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  reporter: [['html', { outputFolder: 'playwright-report' }]],
};
```

### Video evidence

Kazdy test musi produkowac wideo (`.webm`). Wideo sa dowodem ze test przeszedl
na zywym serwerze z prawdziwym Stripe sandbox. Wideo przechowywane w:
- `properbackup-web/test-results/` (lokalne, .gitignore)
- `properbackup-docs/e2e-videos/{data}/` (commit do docs repo — dowody)

---

## 4. Workflow: jak delegowac testy do sesji Devin

### Zasada micro-taskingu

> **Wnioski z sesji f90660be:** Przy dlugim kontekscie Devin traci uwage
> (prompt fatigue / lost in the middle). Najlepiej dawac mu zadania POJEDYNCZO.
> Jeden prompt = jedna grupa testow (3-5 scenariuszy). Nie wiecej.

### Szablon prompta sesji

```
═══════════════════════════════════════════════════════════════════════
ROLA: Playwright E2E Test Engineer — ProperBackup
═══════════════════════════════════════════════════════════════════════

Serwer testowy: http://properbackup-test-server.softify.com.pl
Kod testow:     properbackup-web/tests/e2e/
Plan testow:    properbackup-docs/architecture/playwright-tdd-plan.md

WZORZEC: reuzyj helperow rejestracji/weryfikacji-emaila/checkoutu z
         tests/e2e/subscription-e2e.spec.js (SUB-01..SUB-10). Nie pisz ich od zera.

TWOJE ZADANIE:
Napisz i uruchom testy Playwright dla grupy [GRUPA_ID] z planu testowego.
Plik docelowy: tests/e2e/[PLIK].spec.js

SCENARIUSZE DO POKRYCIA:
[LISTA SCENARIUSZY Z SEKCJI 2]

ZASADY:
1. Playwright chodzi NA TWOIM SRODOWISKU, testuje ZDALNY serwer (URL powyzej).
2. Kazdy test tworzy unikalne konto e2e-{name}-{timestamp}@properbackup.dev.
   Haslo nowych kont: sekret ${PROPERBACKUP_TEST_ACCOUNT_PASSWORD} (w env sesji).
3. Karta testowa Stripe: 4242 4242 4242 4242 (exp: dowolna przyszla, CVC: dowolne).
4. Karta decline: 4000000000000341 (przechodzi setup, odmawia platnosci).
5. Video recording WLACZONE dla kazdego testu.
6. ZERO @Disabled, ZERO skipow, ZERO mockow — wszystko na zywym serwerze.
7. Jesli test FAILUJE — to jest BUG w kodzie, nie w tescie. Opisz dokladnie co sie stalo.
8. Nie modyfikuj kodu backendu/frontendu — TYLKO testy.
9. Po ukonczeniu: PR do properbackup-web z nowymi testami.
10. Skopiuj nagrania wideo do properbackup-docs/e2e-videos/{dzisiejsza-data}/.

STRIPE SANDBOX:
- Checkout przenosi na checkout.stripe.com (prawdziwy sandbox).
- Webhooks przychodza z opoznieniem 1-5s (czekaj, nie polluj agresywnie).
- Card fingerprint guard dziala — ta sama karta na 2 kontach = 2. konto BLOCKED.

DB WERYFIKACJA (jesli potrzebna):
SSH na serwer testowy → docker exec properbackup-db psql -U properbackup -c "..."

OCZEKIWANY OUTPUT:
1. Plik testowy: tests/e2e/[PLIK].spec.js
2. Wyniki: X/Y PASSED (kazdy scenariusz)
3. Nagrania: test-results/*.webm
4. PR do properbackup-web
5. Kopia wideo do properbackup-docs
═══════════════════════════════════════════════════════════════════════
```

### Kolejnosc wykonywania (roadmap)

| Priorytet | Grupa | Prompt | Scenariuszy | Estymacja |
|-----------|-------|--------|-------------|-----------|
| **P0** | E1: Stripe & Money | Prompt #1 | 6 | ~30 min |
| **P0** | E4: Webhook & Race | Prompt #2 | 4 | ~20 min |
| **P1** | E2: Trial Abuse & Auth | Prompt #3 | 5 | ~25 min |
| **P1** | E3: UI/UX | Prompt #4 | 6 | ~20 min |
| **P2** | E5: Recovery & Storage | Prompt #5 | 3 | ~15 min |

**Lacznie:** 24 nowe scenariusze edge case w 5 sesjach.

### Po kazdej sesji

1. Zmerguj PR z nowymi testami do `properbackup-web`
2. Zaktualizuj tabele w sekcji 1 tego dokumentu (dodaj nowe testy do baseline)
3. Jesli test FAILOWAL = BUG → stworz osobna sesje na fix
4. Skopiuj nagrania wideo do `properbackup-docs/e2e-videos/`

---

## 5. Definition of Done

Caly plan jest "Done" gdy:

- [ ] Wszystkie 24 scenariusze z sekcji 2 maja zielone testy Playwright
- [ ] Kazdy test ma nagranie wideo w `properbackup-docs/e2e-videos/`
- [ ] Zero KNOWN FAILURES — kazdy failure zostal naprawiony w osobnej sesji
- [ ] Testy sa IDEMPOTENTNE — mozna je uruchomic N razy bez czyszczenia
- [ ] `npx playwright test` przechodzi w <10 minut na czystym srodowisku

---

## 6. Powiazane dokumenty

- [Master TDD & Resilience Plan](master-tdd-plan.md) — pelna specyfikacja testow backend (sekcje 7-8)
- [E2E Videos](../e2e-videos/README.md) — archiwum nagran
- [Stripe Key Isolation](stripe-key-isolation.md) — dual-key architektura
- [Trial Abuse Prevention](trial-abuse-prevention.md) — threat model AV-1..AV-7
- [Subscription Expiration](subscription-expiration-handling.md) — Access Boundary FSM
