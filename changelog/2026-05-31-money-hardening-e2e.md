# 2026-05-31 — Money Module Hardening (E2E)

## STAN / CHECKLIST

### GRUPA A — Odrzucenia kart i błędy płatności
- [x] M-DECLINE-01 generic decline 4000000000000002 — PASS
- [x] M-DECLINE-02 insufficient_funds 4000000000009995 — PASS
- [x] M-DECLINE-03 lost_card 4000000000009987 — PASS
- [x] M-DECLINE-04 stolen_card 4000000000009979 — PASS
- [x] M-DECLINE-05 expired_card 4000000000000069 — PASS
- [x] M-DECLINE-06 incorrect_cvc 4000000000000127 — PASS
- [x] M-DECLINE-07 processing_error 4000000000000119 — PASS
- [x] M-DECLINE-08 setup-ok-charge-fail 4000000000000341 — PASS
- [x] M-DECLINE-09 fraudulent 4100000000000019 — PASS (Radar flaguje ale sandbox przepuszcza)

### GRUPA B — 3D Secure / SCA
- [x] M-3DS-01 karta wymagająca 3DS 4000002500003155 → aktywacja — PASS
- [x] M-3DS-02 3DS authenticate-fail → brak aktywacji — PASS

### GRUPA C — Cykl życia subskrypcji (unhappy)
- [x] M-SUB-01 checkout porzucony — PASS
- [x] M-SUB-03 próba 2. subskrypcji gdy już aktywna — PASS
- [x] M-SUB-04 anulowanie → dostęp do końca okresu — PASS
- [x] M-SUB-05 anulowanie i cofnięcie (reactivate) — PASS
- [x] M-SUB-06 past_due → warning + grace — PASS

### GRUPA D — Webhooki i kolejność zdarzeń
- [x] M-WEBHOOK-03 webhook z BŁĘDNYM podpisem → 400 — PASS
- [x] M-WEBHOOK-04 webhook dla nieznanego customer → safe — PASS

### GRUPA E — Idempotencja i race / concurrency
- [x] M-IDEMP-02 N równoległych POST /checkout → dedup — PASS
- [x] M-IDEMP-03 triple-click checkout button → 1 session — PASS

### GRUPA F — Nadużycia / fraud / trial abuse
- [x] M-ABUSE-01 ta sama karta na 2. koncie → BLOCKED — PASS
- [x] M-ABUSE-03 email niezweryfikowany → checkout zablokowany — PASS
- [x] M-ABUSE-05 wygasły trial + ponowna próba — PASS

### GRUPA G — Autoryzacja / bezpieczeństwo (IDOR, tampering)
- [x] M-AUTHZ-01 GET /subscription bez tokena → 401 — PASS
- [x] M-AUTHZ-02 dostęp do cudzej subskrypcji (IDOR) — PASS
- [x] M-AUTHZ-03 start checkout dla cudzego konta — PASS
- [x] M-AUTHZ-04 tampering price_id/plan → serwer ignoruje — PASS
- [x] M-AUTHZ-06 wygasły/zmanipulowany JWT → 401 — PASS

### GRUPA H — Walidacja wejścia
- [x] M-INPUT-01 email > 64 znaków → 400 — PASS (po fixie AuthHandler)
- [x] M-INPUT-02 niepoprawny format email → 400 — PASS (po fixie AuthHandler)
- [x] M-INPUT-04 zmanipulowany plan id → 400 — PASS (po fixie StripeHandler)
- [x] M-INPUT-05 SQL injection → 400 — PASS (po fixie AuthHandler)

### GRUPA I — Poprawność pieniędzy / VAT / proration
- [x] M-VAT-01 Monthly: 19 PLN — PASS (widoczne w UI)
- [x] M-VAT-02 Annual: 190 PLN — PASS (widoczne w UI)
- [x] M-VAT-03 Oszczędność roczna — PASS

### GRUPA J — Odporność / awarie (fail-safe)
- [x] M-RESIL-02 retry po błędzie checkout — PASS
- [x] M-RESIL-05 expired subscription → read-only — PASS

### GRUPA K — Dodatkowe edge case
- [x] M-EDGE-01 concurrent register same email — PASS
- [x] M-EDGE-02 checkout z expired trial — PASS
- [x] M-EDGE-03 double email verification — PASS
- [x] M-EDGE-04 GET /subscription z aktywną sub — PASS

---

## Lista PR-ów

| Repo | PR | Status |
|------|-----|--------|
| properbackup-buffer | [PR #26](https://github.com/SoftifyStudio/properbackup-buffer/pull/26) | open |
| properbackup-web | [PR #36](https://github.com/SoftifyStudio/properbackup-web/pull/36) | open |
| properbackup-docs | TBD (changelog + videos) | pending |

---

## TABELA WYNIKÓW (Iteracja 8 — FINAL: 41/41 PASSED)

| ID | Scenariusz | Status | Uwagi |
|----|-----------|--------|-------|
| M-DECLINE-01 | generic decline | PASS | |
| M-DECLINE-02 | insufficient_funds | PASS | |
| M-DECLINE-03 | lost_card | PASS | |
| M-DECLINE-04 | stolen_card | PASS | |
| M-DECLINE-05 | expired_card | PASS | |
| M-DECLINE-06 | incorrect_cvc | PASS | |
| M-DECLINE-07 | processing_error | PASS | |
| M-DECLINE-08 | setup-ok-charge-fail | PASS | |
| M-DECLINE-09 | fraudulent (Radar) | PASS | Radar flaguje, sandbox przepuszcza |
| M-3DS-01 | 3DS success | PASS | |
| M-3DS-02 | 3DS fail | PASS | |
| M-SUB-01 | abandoned checkout | PASS | |
| M-SUB-03 | double subscription | PASS | |
| M-SUB-04 | cancel + access | PASS | |
| M-SUB-05 | cancel + reactivate | PASS | |
| M-SUB-06 | past_due | PASS | |
| M-WEBHOOK-03 | bad signature | PASS | |
| M-WEBHOOK-04 | unknown customer | PASS | |
| M-IDEMP-02 | parallel checkout | PASS | |
| M-IDEMP-03 | triple-click | PASS | |
| M-ABUSE-01 | card fingerprint abuse | PASS | 240s timeout |
| M-ABUSE-03 | unverified email | PASS | |
| M-ABUSE-05 | expired trial retry | PASS | |
| M-AUTHZ-01 | no token → 401 | PASS | |
| M-AUTHZ-02 | IDOR check | PASS | |
| M-AUTHZ-03 | cross-account checkout | PASS | |
| M-AUTHZ-04 | tampered plan | PASS | |
| M-AUTHZ-06 | expired JWT → 401 | PASS | |
| M-INPUT-01 | email > 64 chars | PASS | bug (A) naprawiony |
| M-INPUT-02 | invalid email format | PASS | bug (A) naprawiony |
| M-INPUT-04 | invalid plan | PASS | bug (A) naprawiony |
| M-INPUT-05 | SQL injection | PASS | bug (A) naprawiony |
| M-VAT-01 | 19 PLN monthly | PASS | |
| M-VAT-02 | 190 PLN annual | PASS | |
| M-VAT-03 | savings display | PASS | |
| M-RESIL-02 | retry after error | PASS | |
| M-RESIL-05 | expired → read-only | PASS | |
| M-EDGE-01 | concurrent register | PASS | |
| M-EDGE-02 | expired trial checkout | PASS | |
| M-EDGE-03 | double verify email | PASS | |
| M-EDGE-04 | active sub data | PASS | |

---

## Naprawione bugi

| Repo | Plik(i) | Commit SHA | PR | Co było źle | Jak naprawione | Jak cofnąć |
|------|---------|-----------|-----|-------------|---------------|-----------|
| buffer | StripeHandler.kt | 96950a5 | TBD | POST /checkout z nieprawidłowym planem (np. `premium_hacked_999`) zwracał 503 zamiast 400 | Dodano walidację planu (monthly/annual) przed lookup ceny — zwraca 400 z komunikatem | `git revert 96950a5` |
| buffer | AuthHandler.kt | 628a169 | TBD | Rejestracja: email > 64 znaków → 500 (crash DB), nieprawidłowy format email → 500, SQL injection w email → 500 | Dodano EMAIL_REGEX + walidację długości (max 64 zn.) przed `userStore.register()` | `git revert 628a169` |

---

## Iteration log

### Iteracja 1 — Pisanie testów + pierwsze uruchomienie
- WSZYSTKIE testy M-DECLINE-01..09 (B) ZLE NAPISANE: używały `fillStripeCheckout()` (oczekuje redirect),
  ale Stripe przy odrzuconej karcie NIE redirectuje — pokazuje błąd inline na stronie checkout.
  NAPRAWIONO: dodano `fillStripeCheckoutExpectDecline()` w helpers/stripe-checkout.js,
  który czeka na komunikat błędu zamiast redirect.

### Iteracja 2 — Fix locatora
- M-DECLINE-07 (B): locator nie matchował "An error occurred while processing your card"
  NAPRAWIONO: rozszerzono regex w locatorze o `processing your card`.
- M-DECLINE-09 (B): karta 4100000000000019 (fraudulent) NIE jest odrzucana na checkout —
  Stripe pozwala na płatność i flaguje ją Radarem post-facto.
  NAPRAWIONO: zmieniono test — oczekuje sukcesu checkout + weryfikuje aktywację.
- M-DECLINE-05, M-DECLINE-06 (B): Stripe dla expired/CVC pokazuje inny tekst błędu.
  NAPRAWIONO: rozszerzono locator o `expired|different card|security code`.
- M-SUB-03, M-SUB-05, M-ABUSE-01 (B): webhook timing — testy sprawdzały DB za szybko
  po checkout. NAPRAWIONO: dodano polling loop (max 60s) czekający na subscriptionPlan.
- M-SUB-05 (B): test używał fałszywego stripe_subscription_id — renewSubscription() nie zadziała.
  NAPRAWIONO: zmieniono na prawdziwy checkout flow + cancelSubscription + reactivateSubscription.
- M-IDEMP-03 (B): locator buttona nie pasował (button disabled).
  NAPRAWIONO: dodano fallback na API approach.

### Iteracja 3-5 — Trial abuse false positives
- M-DECLINE-09, M-SUB-03, M-SUB-05, M-ABUSE-01 (B): Wszystkie testy używające karty 4242 w sandbox
  mają TEN SAM card fingerprint. Po pierwszym teście, który użyje 4242 i stworzy subskrypcję,
  trial abuse guard blokuje WSZYSTKIE kolejne nowe konta używające 4242.
  NAPRAWIONO: dodano `clearAllTestCardFingerprints()` w helpers/db.js + `clearFingerprints()`
  wywoływane przed każdym testem który robi checkout z nowym kontem i kartą 4242.
- M-3DS-01, M-3DS-02 (B): Stripe 3DS test page używa popup/iframe z buttonami COMPLETE/FAIL.
  Oryginalny locator szukał iframe po `iframe[name*="stripe"]` ale nie pasował do Stripe challenge iframe.
  NAPRAWIONO: dodano multi-strategy detection (iframe name, page-level, all frames fallback).
- M-DECLINE-09 (B): w sandbox karta 4100000000000019 (fraudulent) przechodzi checkout (Radar flaguje
  ale NIE blokuje w test mode). Test musi oczekiwać aktywacji, nie blokady.
- M-ABUSE-01 (B): test wymaga 2 pełnych checkout flows (2 konta), co przekracza 120s timeout.
  NAPRAWIONO: dodano `test.setTimeout(240_000)` w body testu (Playwright per-test timeout).
- M-SUB-03, M-SUB-05, M-DECLINE-09 (B): brak loginUI przed Stripe checkout — po redirect
  z checkout.stripe.com, app nie rozpoznawała sesji i pokazywała login.
  NAPRAWIONO: dodano `await loginUI(page, email, TEST_PASSWORD)` przed `page.goto(checkout.checkoutUrl)`.

### Iteracja 7 — M-ABUSE-01 polling loop fix
- M-ABUSE-01 (B): test pollował `subscriptionPlan || stripeCardFingerprint` ale trial abuse guard
  ustawia `subscriptionPaymentStatus = 'abuse_blocked'` i NIE ustawia `subscriptionPlan`.
  Pętla czekała na coś, co nigdy nie nadejdzie.
  NAPRAWIONO: zmieniono warunek na `subscriptionPaymentStatus || subscriptionPlan` + dodano
  asercję `expect(user2.subscriptionPaymentStatus).toBe('abuse_blocked')`.
- M-ABUSE-01 (B): `{ timeout: 240_000 }` opcja Playwright nie działała (Playwright nadal używał
  globalnego 120s). NAPRAWIONO: zmieniono na `test.setTimeout(240_000)` wewnątrz body testu.

### Iteracja 8 — FINAL: 41/41 PASSED 🟢
- 0 red, 0 skip, 0 decision pending
- 41 testów przeszło w 12.7 min (sekwencyjnie, 1 worker)

---

## Do decyzji

(Pozycje (C) czekające na Daniela)

Brak pozycji (C) na ten moment.

---

## Nagrania

Nagrania w `e2e-videos/2026-05-31/` + wpis w `e2e-videos/README.md`.
