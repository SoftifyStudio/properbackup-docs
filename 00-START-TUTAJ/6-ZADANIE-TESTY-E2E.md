# 6. ZADANIE: zestaw prawdziwych testów E2E (Playwright) ⭐ AKTYWNE

> Ten plik to **konkretne zlecenie** dla agenta AI, który właśnie wszedł w `00-START-TUTAJ/`.
> Najpierw przeczytaj [`5-DLA-AGENTA-AI.md`](5-DLA-AGENTA-AI.md) (jak nie błądzić) i
> [`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md) (KANON). Potem wróć tutaj.

---

## Po co to robimy (cel, nie litera)

Sprzedajemy **„gwarancję, że backup da się odtworzyć"**. Żeby móc to mówić ze spokojną
głową, potrzebujemy **zestawu prawdziwych testów E2E**, które:

- **faktycznie łapią błędy** (regresje w realnym przepływie agent→buffer→storage→restore),
- **nie tworzą nowych błędów** ani nie maskują istniejących,
- **nie są testami „pod zielony pasek"** — żadnego asercjowania trywialności, mockowania
  rzeczy, które właśnie mają być sprawdzone, ani podkręcania testu, aż przejdzie.

To NIE jest „dopisz parę testów". To jest **budowa wiarygodnej siatki regresji** wokół
najważniejszej obietnicy produktu.

## Twarde zasady wykonania (NIENEGOCJOWALNE)

1. **Tylko pierwszy kontener na dedyku.** Cała praca na serwerze dzieje się w
   **LXC 100 „properbackup"** (`pct exec 100 -- ...` / `pct enter 100`).
   **NIE DOTYKAJ kontenera Minecraft** (osobny LXC) — ani konfiguracji, ani danych,
   ani procesów. Jeśli coś wymaga ruszenia MC — STOP i pytaj Daniela.
2. **E2E = Playwright z WBUDOWANYM nagrywaniem** (`video: 'on'` w configu Playwright).
   **NIE** używaj nagrywania ekranu Devina — natywne wideo Playwright jest deterministyczne,
   małe i powtarzalne. Jeden `.webm` na test.
3. **Nagrania trafiają do właściwego folderu w docs** wg istniejącej konwencji:
   `properbackup-docs/e2e-videos/<YYYY-MM-DD>-<temat>/testNN-krotki-opis.webm`
   (append-only, nie nadpisuj starych zestawów). Pełny protokół: `e2e-videos/README.md`
   + `architecture/master-tdd-plan.md` §11.1.
4. **Każdy zielony test 2× pod rząd** (anty-flake), `workers=1`. Brak zielonego nagrania
   = test NIE jest „Done".
5. **Red-first (TDD).** Najpierw test, który pada na realnym błędzie/luce; dopiero potem
   naprawa w kodzie. Test ma opisywać **zachowanie wymagane przez spec/Hard Requirement**,
   nie bieżącą implementację.
6. **NIE zmieniaj testów, żeby przeszły.** Jeśli test pada, bo kod jest zły — popraw kod.
   Jeśli test pada, bo wymaganie się zmieniło — potwierdź z kanonem/Danielem, nie „napraw"
   po cichu test.
7. **Asercje DB-first + pliki-na-dysku**, nie tylko UI. Sprawdzaj stan w PostgreSQL
   (przez `pct exec 100 -- docker exec ... psql`) i SHA-256 plików na `/mnt/storage`.
   UI jest asercją wtórną.

## Co już istnieje (NIE pisz od zera — rozbuduj)

- **Playwright skonfigurowany**: `properbackup-web/playwright.config.js` (`video:'on'`,
  `workers:1`, baseURL z env).
- **Istniejące specy E2E**: `properbackup-web/tests/e2e/recovery-e2e.spec.js`
  (restore + SHA-256) oraz suite billing/recovery-QA.
- **Skill QA**: `properbackup-docs/.agents/skills/recovery-e2e-testing.md` — jak odpalać,
  etykiety triażu (`[TRIAGE:BUFFER|AGENT|WEB|INFRA]`), pułapki.
- **Indeks nagrań + konwencja**: `e2e-videos/README.md`.

## Priorytet #1 (pierwszy kamień milowy)

**Pełny, zielony E2E na NAJNOWSZYM kodzie, na dedyku (LXC 100):**

```
agent → buffer → seal → pack → zapis na /mnt/storage → restore → weryfikacja SHA-256
```

To jest dziś dziura nr 1 (patrz [`3-CO-JEST-ZROBIONE.md`](3-CO-JEST-ZROBIONE.md)): na
dedyku stoi stary build, a pełny E2E na najnowszym kodzie nie był przepuszczony. Bez tego
„gwarancja odzyskania" to obietnica, nie fakt. Zacznij od tego, z nagraniem.

## Definition of Done (per test)

- [ ] Test opisuje realne zachowanie (powiązane z konkretnym Hard Requirement / spec).
- [ ] Czerwony przed naprawą, zielony po (jeśli dotyczy bugfixa).
- [ ] Zielony **2× pod rząd**, `workers=1`.
- [ ] Asercja DB i/lub plik-na-dysku (nie tylko UI).
- [ ] Nagranie `.webm` (natywne Playwright) w `e2e-videos/<data>-<temat>/`.
- [ ] Wiersz dopisany do tabeli w `e2e-videos/README.md` (+ `master-tdd-plan.md` §11.2).
- [ ] Praca na serwerze wyłącznie w LXC 100; kontener MC nietknięty.

## Workflow (micro-tasking — jedno na raz)

1. Wejdź na dedyk **tylko do LXC 100**, sprawdź zdrowie stacku (buffer `:8080`, web `:80`,
   postgres w dockerze, `/mnt/storage`).
2. Wdróż najnowszy kod do LXC 100 (jeśli trzeba) — opis w
   [`4-JAK-TO-URUCHOMIC.md`](4-JAK-TO-URUCHOMIC.md) / `deployment/`.
3. Napisz/rozbuduj jeden test E2E (red-first), odpal, dopnij zielony 2×.
4. Skopiuj nagranie do `e2e-videos/`, dopisz wiersz w indeksie, zrób commit.
5. Otwórz/zaktualizuj PR. **Nie mergujesz** — Daniel merguje ręcznie.
6. Następny test. Gdy coś wymaga decyzji produktowej / ruszenia MC / wyjścia poza LXC 100
   → STOP, pytaj Daniela.

## Czego NIE robić

- Nie ruszaj kontenera Minecraft (osobny LXC).
- Nie zmieniaj cen/quoty/DR/kosztu — to KANON, nie zadanie testowe.
- Nie mockuj rzeczy, które test ma realnie zweryfikować (szyfrowanie, seal, restore, SHA).
- Nie używaj nagrywania ekranu Devina — tylko natywne wideo Playwright.
- Nie merguj PR-ów.
