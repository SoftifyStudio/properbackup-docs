# Prompt #1 — Playwright E2E: Stripe & Money Edge Cases

> **Kopiuj calosc ponizej i wklej jako prompt do nowej sesji Devin.**
> Plan referencyjny: `properbackup-docs/architecture/playwright-tdd-plan.md`

---

```
═══════════════════════════════════════════════════════════════════════
ROLA: Playwright E2E Test Engineer — ProperBackup
═══════════════════════════════════════════════════════════════════════

Serwer testowy: http://properbackup-test-server.softify.com.pl
Repozytoria:
  - properbackup-web (tutaj piszesz testy): tests/e2e/edge-money-e2e.spec.js
  - properbackup-docs (tutaj kopiujesz wideo): e2e-videos/{dzisiejsza-data}/

Plan testowy: properbackup-docs/architecture/playwright-tdd-plan.md (sekcja 2, Grupa E1)

═══════════════════════════════════════════════════════════════════════
TWOJE ZADANIE:
Napisz i uruchom testy Playwright dla 6 scenariuszy "Stripe & Money Edge Cases".
═══════════════════════════════════════════════════════════════════════

SCENARIUSZE:

1. EDGE-MONEY-01: Karta "always decline" (4000000000000341)
   GIVEN: nowy user zarejestrowany, przechodzi Checkout z karta 4000000000000341
   WHEN:  Stripe przetwarza platnosc (checkout session completed ale subscription incomplete)
   THEN:  - UI NIE pokazuje "aktywna subskrypcja"
          - UI pokazuje komunikat o odrzuconej karcie lub "incomplete"
          - DB: subscription_plan IS NULL
          - subscription_audit_log: action = 'checkout_incomplete' lub brak wpisu aktywacji
   UWAGA: Karta 4000000000000341 przechodzi setup ale ODMAWIA przy przyszlych obciazeniach.
          W sandbox Stripe moze zachowac sie inaczej — opisz dokladnie co sie stalo.

2. EDGE-MONEY-02: Browser back button po Checkout
   GIVEN: user oplacil subskrypcje, jest na /panel (lub /account/subscription)
   WHEN:  klika "wstecz" w przegladarce
   THEN:  - NIE wraca na checkout.stripe.com
          - Wraca na /account/subscription z aktywna subskrypcja
          - Brak duplikatu sesji checkout
          - Przycisk "Zmien plan" dziala normalnie

3. EDGE-MONEY-03: Webhook PRZED redirect
   GIVEN: user oplacil w Checkout, webhook dotarl do backendu
   WHEN:  frontend laduje success_url (/panel?session_id=...)
   THEN:  - Frontend widzi aktywna subskrypcje OD RAZU (bez ProcessingScreen/spinnera)
          - Brak 403, brak "czekamy na potwierdzenie"
          - GET /account/subscription zwraca subscriptionStatus != "none"
   UWAGA: To jest happy path (webhook szybszy niz redirect). Upewnij sie ze nie ma race.

4. EDGE-MONEY-04: Double-click na "Rozpocznij trial" (ochrona przed duplikatem)
   GIVEN: user na stronie subskrypcji, checkbox art. 38 zaznaczony
   WHEN:  klika "Rozpocznij trial" 3 razy szybko w ciagu 500ms
   THEN:  - Tylko 1 request do backendu (przycisk disabled po pierwszym kliknieciu)
          - Tylko 1 sesja Checkout w Stripe
          - Brak duplikatow w subscription_audit_log
   TECHNIKA: page.click() + page.click() + page.click() z minimalnym opoznieniem

5. EDGE-MONEY-05: Zmiana planu (monthly → annual) w trakcie trwajacego checkout
   GIVEN: user kliknal "Rozpocznij trial" na planie monthly, Checkout sie otwiera
   WHEN:  user wraca (back button), klika annual
   THEN:  - Nowa sesja checkout dla annual (stara expiruje)
          - Po oplaceniu: subscription_plan = "annual" (nie "monthly")
          - Brak podwojnego obciazenia

6. EDGE-MONEY-06: Weryfikacja VAT w UI
   GIVEN: user na stronie subskrypcji
   WHEN:  sprawdza ceny planow
   THEN:  - Monthly: 19 PLN brutto, netto 15.45 PLN, VAT 3.55 PLN (23%)
          - Annual: 190 PLN brutto, netto 154.47 PLN, VAT 35.53 PLN (23%)
          - Oszczednosc: "Oszczedzasz X PLN rocznie" (190 vs 12*19=228 = 38 PLN)

═══════════════════════════════════════════════════════════════════════
ZASADY:
═══════════════════════════════════════════════════════════════════════

1. Playwright chodzi NA TWOIM SRODOWISKU (npx playwright test), testuje ZDALNY serwer.
2. Zainstaluj Playwright: cd properbackup-web && npm install && npx playwright install chromium
3. Kazdy test tworzy unikalne konto: e2e-money-{N}-{timestamp}@properbackup.dev
4. Karta testowa: 4242 4242 4242 4242, exp: 12/30, CVC: 123
5. Karta decline: 4000000000000341, exp: 12/30, CVC: 123
6. Video recording WLACZONE (video: 'on' w playwright.config.js)
7. Timeout per test: 120s (webhooks moga trwac)
8. ZERO retries — failure = bug
9. NIE modyfikuj kodu backendu/frontendu — TYLKO piszesz testy
10. Jesli scenariusz jest NIEMOZLIWY do przetestowania (np. backend nie obsluguje)
    — opisz dokladnie DLACZEGO i co trzeba zmienic w kodzie

═══════════════════════════════════════════════════════════════════════
STRIPE SANDBOX INFO:
═══════════════════════════════════════════════════════════════════════

- Checkout: redirect na checkout.stripe.com (prawdziwy sandbox)
- Webhooks: opoznienie 1-5s po platnosci
- Card fingerprint: dziala w sandbox (ta sama karta = ten sam fingerprint)
- Karty testowe Stripe:
  * 4242424242424242 — zawsze OK
  * 4000000000000341 — przechodzi setup, odmawia platnosci
  * 4000000000009995 — insufficient_funds
  * 4000000000000002 — declined (generic)

═══════════════════════════════════════════════════════════════════════
OCZEKIWANY OUTPUT:
═══════════════════════════════════════════════════════════════════════

1. Plik: properbackup-web/tests/e2e/edge-money-e2e.spec.js
2. Wyniki: X/6 PASSED (kazdy scenariusz osobno)
3. Nagrania: test-results/*.webm
4. PR do properbackup-web z nowymi testami
5. Kopia nagran wideo do properbackup-docs/e2e-videos/{data}/
6. Raport: tabela scenariusz | status | uwagi

Jesli jakis test FAILUJE — NIE oznacza to bledu w tescie.
Oznacza to BUG w kodzie backendowym/frontendowym.
Opisz DOKLADNIE co sie stalo, z jakim HTTP status, jakim body,
co bylo w DB, co pokazal Playwright trace.
═══════════════════════════════════════════════════════════════════════
```
