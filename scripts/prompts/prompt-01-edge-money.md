# Prompt #1 — Money Module Hardening (Playwright E2E, pętla aż „nie do zajechania")

> **Kopiuj calosc ponizej i wklej jako prompt do nowej sesji Devin.**
> To jest prompt DLUGODYSTANSOWY — agent ma pracowac w petli przez dlugi czas,
> az caly modul platnosci/subskrypcji bedzie odporny na wszystkie edge case.
> Plan referencyjny: `properbackup-docs/architecture/playwright-tdd-plan.md`

---

```
═══════════════════════════════════════════════════════════════════════
ROLA: Senior QA / Security Engineer — hardening modulu platnosci ProperBackup
═══════════════════════════════════════════════════════════════════════

Serwer testowy: http://properbackup-test-server.softify.com.pl
Repozytoria:
  - properbackup-web    (panel + testy Playwright): tests/e2e/edge-money-e2e.spec.js
  - properbackup-buffer (backend Kotlin/Javalin: checkout, webhooki, subskrypcje)
  - properbackup-shared (wspolne biblioteki)
  - properbackup-docs   (changelog + nagrania): changelog/, e2e-videos/{data}/

Plan testowy: properbackup-docs/architecture/playwright-tdd-plan.md

WZORZEC (WAZNE): NIE pisz rejestracji/logowania/checkoutu od zera.
  Reuzyj helperow z istniejacego tests/e2e/subscription-e2e.spec.js (SUB-01..SUB-10,
  10/10 PASSED) — rejestracja, weryfikacja emaila i flow Checkout sa tam juz rozwiazane.

═══════════════════════════════════════════════════════════════════════
CEL NADRZEDNY (GWIAZDA POLARNA — wracaj do tego przy KAZDEJ iteracji):
Uczynic CALY modul platnosci/subskrypcji NIE DO ZAJECHANIA.
Masz napisac JAK NAJWIECEJ testow unhappy path / edge case (mysl jak atakujacy
i jak pechowy uzytkownik), uruchamiac je na zywym serwerze i pracowac w PETLI
tak dlugo, az KAZDY scenariusz jest zielony — a system zachowuje sie bezpiecznie
(fail-safe) w kazdej awarii. To zadanie dlugodystansowe: iteruj w kolko.

ZAKRES = CALY modul platnosci w TEJ JEDNEJ PETLI (nie dziel na osobne sesje):
checkout, cykl subskrypcji, webhooki, race/idempotencja, trial abuse, autoryzacja,
VAT/proration, odpornosc/awarie. Wszystko ponizej to jedno zadanie.
═══════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────
PAMIEC PETLI (anti-"lost in the middle" — KRYTYCZNE przy dlugim przebiegu):
───────────────────────────────────────────────────────────────────────
NIE polegaj na pamieci kontekstu — polegaj na PLIKU. Prowadz zywy plik-pamiec:
  properbackup-docs/changelog/{data}-money-hardening-e2e.md
Na GORZE tego pliku trzymaj sekcje "STAN / CHECKLIST" — liste WSZYSTKICH ID
scenariuszy (M-DECLINE-01 ... M-RESIL-05) z checkboxem i statusem
[ ] TODO / [~] in-progress / [x] PASS / [!] FAIL / [?] DECYZJA + 1-zdaniowa notatka.
Aktualizuj ten plik po KAZDYM scenariuszu i po KAZDYM fixie.
To jest Twoja pamiec — z niej wiesz co juz zrobione i co zostalo.

───────────────────────────────────────────────────────────────────────
PRZED STARTEM (preflight — fail fast, zanim zaczniesz pisac testy):
───────────────────────────────────────────────────────────────────────
Sprawdz, ze masz wymagane sekrety w env:
  - ${PROPERBACKUP_TEST_ACCOUNT_PASSWORD} (haslo kont testowych)
  - ${TEST_SERVER_SECRET_KEY} (klucz SSH ed25519, user root)

UWAGA o kluczu SSH: sekret moze byc zapisany jako sam base64 (jedna linia, ze
spacjami, BEZ naglowkow PEM). Zbuduj plik klucza odpornie na oba formaty:
  KEY=~/.ssh/tskey; mkdir -p ~/.ssh
  if printf '%s' "${TEST_SERVER_SECRET_KEY}" | grep -q "BEGIN OPENSSH"; then
    printf '%s\n' "${TEST_SERVER_SECRET_KEY}" > "$KEY"
  else
    { echo "-----BEGIN OPENSSH PRIVATE KEY-----"; \
      printf '%s' "${TEST_SERVER_SECRET_KEY}" | tr -d ' \t\r\n' | fold -w 70; echo; \
      echo "-----END OPENSSH PRIVATE KEY-----"; } > "$KEY"
  fi
  chmod 600 "$KEY"; ssh-keygen -y -f "$KEY"   # musi wypisac klucz publiczny

Zweryfikowane parametry serwera (dzialaja):
  - host: root@properbackup-test-server.softify.com.pl
  - kontener bazy: properbackup-db, psql user: properbackup
  - SSH test: ssh -i "$KEY" -o StrictHostKeyChecking=no root@properbackup-test-server.softify.com.pl 'echo ok'
  - DB test: ssh ... 'docker exec properbackup-db psql -U properbackup -c "\dt"'
  - tabele istotne: users, payment_order, subscription_config, subscription_audit_log,
    stripe_event, stripe_event_idempotency, stripe_price_config

Jesli ktoregos sekretu brakuje, klucz jest niepoprawny (ssh-keygen -y pada) albo
SSH/psql nie wchodzi — ZATRZYMAJ sie OD RAZU i napisz do Daniela dokladnie co.
NIE pisz testow, ktore i tak padna w KROKU 0.

───────────────────────────────────────────────────────────────────────
PETLA HARDENINGU (rdzen tego zadania — wykonuj w kolko):
───────────────────────────────────────────────────────────────────────
KROK 0 (na poczatku KAZDEJ iteracji — re-anchor celu):
        Zanim cokolwiek zrobisz, PRZECZYTAJ ponownie: (a) sekcje CEL NADRZEDNY
        powyzej, (b) sekcje "STAN / CHECKLIST" w pliku-pamieci. Dopiero potem
        wybierz nastepny scenariusz. To chroni przed zgubieniem celu w dlugiej petli.
KROK 1. Napisz/dopisz testy z baterii ponizej (zacznij od grupy, dokladaj kolejne).
        Po napisaniu/zmianie ZAKTUALIZUJ "STAN / CHECKLIST" w pliku-pamieci.
KROK 2. Uruchom CALY zestaw: `npx playwright test` (video on, zero retries).
KROK 3. Dla KAZDEGO czerwonego testu zreprodukuj i zdiagnozuj (trace, HTTP status,
        body, stan DB przez SSH+psql). Potem ZAKLASYFIKUJ przyczyne:

   (A) PRAWDZIWY BUG W KODZIE — system zachowuje sie niezgodnie z bezpiecznym,
       poprawnym zachowaniem (np. aktywuje subskrypcje mimo odrzuconej karty,
       podwojnie obciaza, przepuszcza cudza subskrypcje, fail-open przy DB down).
       → NAPRAW w odpowiednim repo (web/buffer/shared). Osobny PR per repo.
       → Zasada FAIL-SAFE: w razie awarii (DB down, Stripe timeout) system MA
         BLOKOWAC dostep/aktywacje, nigdy przepuszczac.
       → Opisz fix w changelogu (co bylo zle, jak naprawione).

   (B) ZLE NAPISANY TEST — to test jest bledny (zly selektor, zla karta testowa,
       zle zalozenie o oczekiwanym zachowaniu, race w samym tescie, brak
       czekania na webhook). Kod jest OK.
       → PRZEPISZ test na prawidlowy.
       → WYRAZNIE zaznacz to w docs (sekcja "Iteration log" w changelogu):
         co bylo zle w tescie, dlaczego, jak poprawione. To jest wymagane.

   (C) NIEJASNE / RYZYKOWNE — fix wymagalby duzej zmiany architektury, spec jest
       niejednoznaczna, albo to decyzja produktowa (np. czy downgrade dziala od
       razu czy na koniec okresu).
       → NIE ZGADUJ. Zostaw test jako FAIL z dokladnym opisem, ZAPISZ pytanie
         do Daniela w sekcji "Do decyzji" changelogu i kontynuuj reszte.

KROK 4. Uruchom CALY zestaw ponownie. Powtarzaj KROK 3-4 az 0 czerwonych
        (poza ewentualnymi pozycjami (C) czekajacymi na decyzje).
        CIRCUIT BREAKER (anti-utkniecie): jesli dany test failuje z TEGO SAMEGO
        powodu 3 razy z rzedu mimo Twoich prob naprawy — NIE probuj 4. raz.
        Oznacz go OD RAZU jako (C) DECYZJA, opisz problem w changelogu i idz dalej.
        Nie blokuj calej petli jednym opornym bledem.
KROK 5. Gdy CALA bateria bazowa (A-J) jest zielona — wroc do CELU NADRZEDNEGO i
        wymysl MAKSYMALNIE 5 nowych, unikalnych scenariuszy edge case (nie warianty
        tego samego: NIE rob email 64/65/66 znakow — szukaj jakosciowo innych dziur:
        nowy decline code, nowa kolejnosc webhookow, nowy atak na autoryzacje).
        Dopisz je do CHECKLIST, przetestuj, napraw wg KROK 3-4.
        Jesli te 5 tez wyjdzie zielone — ZATRZYMAJ sie i POPROS Daniela o autoryzacje
        dalszego wymyslania. NIE wpadaj w nieskonczona petle wariacji.

───────────────────────────────────────────────────────────────────────
BATERIA SCENARIUSZY (pisz JAK NAJWIECEJ — to jest minimum, dokladaj wlasne):
───────────────────────────────────────────────────────────────────────

# GRUPA A — Odrzucenia kart i bledy platnosci (Stripe test cards)
M-DECLINE-01  generic decline 4000000000000002 → brak aktywacji, czytelny blad
M-DECLINE-02  insufficient_funds 4000000000009995 → brak aktywacji, komunikat
M-DECLINE-03  lost_card 4000000000009987 → brak aktywacji
M-DECLINE-04  stolen_card 4000000000009979 → brak aktywacji
M-DECLINE-05  expired_card 4000000000000069 → blad, brak aktywacji
M-DECLINE-06  incorrect_cvc 4000000000000127 → blad walidacji, brak aktywacji
M-DECLINE-07  processing_error 4000000000000119 → blad, brak aktywacji, retry mozliwy
M-DECLINE-08  always-decline-on-charge 4000000000000341 → setup OK, charge fail,
              subscription_plan IS NULL, audit_log brak aktywacji
M-DECLINE-09  fraudulent 4100000000000019 → zablokowane, brak aktywacji

# GRUPA B — 3D Secure / SCA
M-3DS-01  karta wymagajaca 3DS 4000002500003155 → modal 3DS, po sukcesie aktywacja
M-3DS-02  3DS authenticate-fail (uzytkownik nie przechodzi auth) → brak aktywacji
M-3DS-03  3DS porzucone (zamkniecie modala) → brak aktywacji, czysty stan, retry

# GRUPA C — Cykl zycia subskrypcji (unhappy)
M-SUB-01  checkout porzucony (zamkniecie karty/taba) → brak subskrypcji, mozna ponowic
M-SUB-02  sesja checkout wygasla (po terminie) → expired, czysty stan
M-SUB-03  proba 2. subskrypcji gdy juz aktywna → brak duplikatu, blokada
M-SUB-04  anulowanie → dostep do konca okresu → po okresie expired (read-only)
M-SUB-05  anulowanie i cofniecie (renew) przed koncem okresu → znow active
M-SUB-06  past_due (nieudana platnosc cykliczna) → yellow banner + grace
M-SUB-07  past_due + update karty (4242) → banner znika, subskrypcja recovers
M-SUB-08  past_due grace wygasa → subskrypcja suspended, upload zablokowany
M-SUB-09  upgrade monthly→annual w trialu → poprawny plan, proration, brak 2x charge
M-SUB-10  downgrade annual→monthly → zaznacz oczekiwane zachowanie (od razu vs koniec
          okresu); jesli spec niejasna → pozycja (C) do decyzji

# GRUPA D — Webhooki i kolejnosc zdarzen
M-WEBHOOK-01  webhook PRZED redirectem → panel od razu aktywny, bez ProcessingScreen
M-WEBHOOK-02  redirect PRZED webhookiem → ProcessingScreen → po webhooku aktywny
M-WEBHOOK-03  webhook z BLEDNYM podpisem (zly Stripe-Signature) → 400, brak zmian
M-WEBHOOK-04  webhook dla nieznanego customer/subscription → bezpieczna obsluga, brak crasha
M-WEBHOOK-05  out-of-order: customer.subscription.deleted PRZED checkout.completed
              → stan koncowy poprawny (nie "aktywny duch")
M-WEBHOOK-06  webhook z przyszlosci / clock skew > tolerancja → odrzucony

# GRUPA E — Idempotencja i race / concurrency
M-IDEMP-01  ten sam event.id wyslany 2x → przetworzony DOKLADNIE raz
M-IDEMP-02  N rownoleglych POST /checkout (np. 10) → 1 sesja Stripe (idempotency key)
M-IDEMP-03  double-click "Rozpocznij trial" 3x w 500ms → 1 request, 1 sesja, przycisk disabled
M-IDEMP-04  Slow 3G + szybki re-klik → brak podwojnego submitu
M-RACE-01   cancel + invoice.paid w tym samym momencie → deterministyczny stan koncowy
M-RACE-02   zmiana planu w trakcie otwartego checkoutu (back→annual) → 1 poprawny plan

# GRUPA F — Naduzycia / fraud / trial abuse
M-ABUSE-01  ta sama karta (fingerprint) na 2. koncie → 2. konto BLOCKED
M-ABUSE-02  ta sama karta na 3 kontach → konto 2 i 3 BLOCKED
M-ABUSE-03  email niezweryfikowany → checkout zablokowany → "Potwierdz email"
M-ABUSE-04  disposable email (np. tempmail) → odrzucenie lub warning
M-ABUSE-05  wygasly trial + ponowna proba → poprawny flow (nie "juz masz trial")

# GRUPA G — Autoryzacja / bezpieczenstwo (IDOR, tampering)
M-AUTHZ-01  GET /account/subscription bez tokena → 401
M-AUTHZ-02  dostep do cudzej subskrypcji (podmiana id, IDOR) → 403/404, zero wycieku
M-AUTHZ-03  start checkout dla cudzego konta → zablokowane
M-AUTHZ-04  tampering price_id/plan w request → serwer IGNORUJE, uzywa ceny server-side
M-AUTHZ-05  tampering kwoty/waluty → wymuszone server-side, brak wplywu klienta
M-AUTHZ-06  wygasly/zmanipulowany JWT → 401

# GRUPA H — Walidacja wejscia
M-INPUT-01  email > 64 znakow → 400 EMAIL_TOO_LONG
M-INPUT-02  niepoprawny format email → 400
M-INPUT-03  brak zgody art. 38 (checkbox) → checkout zablokowany
M-INPUT-04  zmanipulowany/nieistniejacy plan id → 400, brak crasha
M-INPUT-05  SQL injection / XSS w polach (email, nazwa) → bezpiecznie obsluzone/escaped

# GRUPA I — Poprawnosc pieniedzy / VAT / proration
M-VAT-01  Monthly: 19 PLN brutto = netto 15.45 + VAT 3.55 (23%)
M-VAT-02  Annual: 190 PLN brutto = netto 154.47 + VAT 35.53 (23%)
M-VAT-03  Oszczednosc roczna: 12*19=228 vs 190 = 38 PLN, pokazane w UI
M-VAT-04  Proration przy zmianie planu policzona poprawnie (brak naddatku/ubytku)
M-VAT-05  Brak podwojnego obciazenia przy retry/refresh

# GRUPA J — Odpornosc / awarie (fail-safe)
M-RESIL-01  drop sieci w trakcie checkoutu → po wznowieniu spojny stan, brak duplikatu
M-RESIL-02  backend 500 przy tworzeniu checkout → czytelny blad, retry mozliwy
M-RESIL-03  Stripe API timeout → graceful, brak "wisielca", brak aktywacji bez platnosci
M-RESIL-04  DB down w trakcie webhooka → FAIL-SAFE: nie przyznawaj dostepu, retry pozniej
M-RESIL-05  expired subscription → restore READ-ONLY dozwolony, upload ZABLOKOWANY

═══════════════════════════════════════════════════════════════════════
ZASADY (twarde):
═══════════════════════════════════════════════════════════════════════
1. Playwright chodzi NA TWOIM SRODOWISKU (npx playwright test), testuje ZDALNY serwer.
2. Instalacja: cd properbackup-web && npm install && npx playwright install chromium
3. Kazdy test tworzy unikalne konto: e2e-money-{scenariusz}-{timestamp}@properbackup.dev
   Haslo nowych kont: sekret ${PROPERBACKUP_TEST_ACCOUNT_PASSWORD} (w env sesji).
   Weryfikacja emaila: obsluz tak samo jak w subscription-e2e.spec.js.
4. Karty testowe: patrz sekcja STRIPE SANDBOX ponizej.
5. Video recording WLACZONE (video: 'on'), trace: 'on', screenshot: 'only-on-failure'.
6. Timeout per test: 120s (webhooki 1-5s). ZERO retries — flaky maskuje bugi.
7. Weryfikacja stanu DB: SSH na serwer testowy (klucz w sekrecie TEST_SERVER_SECRET_KEY,
   user root) → docker exec properbackup-db psql -U properbackup -c "SELECT ...".
8. NAPRAWY KODU sa DOZWOLONE i OCZEKIWANE gdy test ujawnia prawdziwy bug — osobny
   PR w odpowiednim repo (web/buffer/shared), z opisem w changelogu.
9. PRZEPISANIE TESTU jest dozwolone TYLKO gdy test byl faktycznie zle napisany —
   musisz to WYRAZNIE udokumentowac w "Iteration log" (co i dlaczego).
10. ODWRACALNOSC (WAZNE dla Daniela): kazda naprawa kodu MUSI byc do cofniecia.
    - JEDEN bug = JEDEN maly, atomowy commit (nie mieszaj kilku fixow w jednym).
    - Commit message: "fix(money): <bug> [M-XXX-NN]" — z ID scenariusza.
    - W changelogu zapisz dla kazdego fixu: repo, plik(i), commit SHA, PR,
      1 zdanie "jak to cofnac" (np. `git revert <SHA>`).
    - NIE rob duzych refaktorow przy okazji. Zmiana ma byc minimalna i punktowa,
      zeby Daniel mogl przywrocic dowolny pojedynczy fix bez ruszania reszty.

ANTY-OSZUSTWO (krytyczne — zielony przez oszustwo jest GORSZY niz czerwony):
  - NIGDY nie oslabiaj asercji, zeby test przeszedl.
  - NIGDY nie mockuj Stripe / nie podmieniaj webhookow na sztuczne.
  - ZERO skip / @disabled / try-catch ukrywajacego blad / sleep zamiast czekania na stan.
  - Jesli kusi Cie oslabienie testu — to znak, ze masz prawdziwy bug (A) albo
    niejasnosc (C). Nie obchodzic — diagnozuj.

ESKALACJA: jesli fix bylby duza/ryzykowna zmiana architektury albo wymaga decyzji
produktowej — NIE rob jej na wlasna reke. Zapisz w "Do decyzji" i pytaj Daniela.

═══════════════════════════════════════════════════════════════════════
STRIPE SANDBOX INFO:
═══════════════════════════════════════════════════════════════════════
- Checkout: redirect na checkout.stripe.com (prawdziwy sandbox).
- Webhooki: opoznienie 1-5s po platnosci (czekaj na stan, nie polluj agresywnie).
- Card fingerprint dziala (ta sama karta = ten sam fingerprint = trial abuse guard).
- Karty:
  * 4242424242424242 — zawsze OK
  * 4000000000000002 — generic decline
  * 4000000000009995 — insufficient_funds
  * 4000000000009987 — lost_card
  * 4000000000009979 — stolen_card
  * 4000000000000069 — expired_card
  * 4000000000000127 — incorrect_cvc
  * 4000000000000119 — processing_error
  * 4000000000000341 — setup OK, odmawia przy obciazeniu
  * 4000002500003155 — wymaga 3D Secure (authentication)
  * 4100000000000019 — fraudulent (blocked)
  (exp: dowolna przyszla np. 12/30, CVC: dowolne np. 123)

═══════════════════════════════════════════════════════════════════════
DOKUMENTACJA (po kazdej iteracji aktualizuj):
═══════════════════════════════════════════════════════════════════════
Plik: properbackup-docs/changelog/{data}-money-hardening-e2e.md (= zywy plik-pamiec)
  - naglowek "# {data} — Money Module Hardening (E2E)"
  - sekcja "STAN / CHECKLIST" NA GORZE: wszystkie ID scenariuszy z checkboxem i
    statusem [ ]/[~]/[x]/[!]/[?] (Twoja pamiec petli — czytaj ja w KROKU 0)
  - lista PR-ow (web / buffer / shared / docs)
  - TABELA WYNIKOW: ID | scenariusz | status (PASS/FAIL/DECYZJA) | uwagi
  - sekcja "Naprawione bugi": TABELA repo | plik | commit SHA | PR | co bylo zle |
    jak naprawione | jak cofnac (git revert <SHA>) — kazdy fix osobny wiersz
  - sekcja "Iteration log": ktore testy byly ZLE NAPISANE i jak je poprawiono (wymagane)
  - sekcja "Do decyzji": pozycje (C) czekajace na Daniela
  - linki do nagran w e2e-videos/{data}/ + wpis w e2e-videos/README.md
Nagrania: skopiuj .webm wszystkich testow do properbackup-docs/e2e-videos/{data}/.

═══════════════════════════════════════════════════════════════════════
OCZEKIWANY OUTPUT (stan koncowy):
═══════════════════════════════════════════════════════════════════════
1. properbackup-web/tests/e2e/edge-money-e2e.spec.js — pelna bateria (>40 testow)
2. Wynik: WSZYSTKO PASSED (poza pozycjami "Do decyzji", jasno oznaczonymi)
3. PR(y): testy do properbackup-web + ewentualne fixy w buffer/shared (osobno)
4. Nagrania .webm w properbackup-docs/e2e-videos/{data}/
5. Changelog money-hardening z tabela + naprawione bugi + iteration log + do decyzji
6. Krotkie podsumowanie: ile bugow znaleziono i naprawiono, ile testow poprawiono,
   co czeka na decyzje.

PAMIETAJ: to jest praca w PETLI. Nie konczysz po pierwszym przebiegu — iterujesz,
dokladasz nowe edge case i naprawiasz az modulu NIE DA SIE zajechac.
═══════════════════════════════════════════════════════════════════════
```
