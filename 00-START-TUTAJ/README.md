# 00 — START TUTAJ 👋

To jest **punkt wejścia do całego ProperBackup**, napisany po ludzku. Jeśli gubisz
się w dziesiątkach plików `architecture/` — czytaj stąd, nie stamtąd.

## Co czytać i w jakiej kolejności

| Plik | Co znajdziesz | Dla kogo |
|---|---|---|
| [`1-CO-TO-JEST.md`](1-CO-TO-JEST.md) | Produkt w jednej stronie, bez żargonu | każdy |
| [`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md) | ⭐ **KANON** — ceny, storage, quota, DR, koszt (co obowiązuje DZIŚ) | każdy / AI |
| [`3-CO-JEST-ZROBIONE.md`](3-CO-JEST-ZROBIONE.md) | Stan prac: gotowe / w toku / do zrobienia | Daniel / AI |
| [`4-JAK-TO-URUCHOMIC.md`](4-JAK-TO-URUCHOMIC.md) | Gdzie co stoi, dedyk OVH, deploy | Daniel / AI |
| [`5-DLA-AGENTA-AI.md`](5-DLA-AGENTA-AI.md) | Jak zlecać zadania Devinowi, żeby nie błądził | Daniel |
| [`6-ZADANIE-TESTY-E2E.md`](6-ZADANIE-TESTY-E2E.md) | ⭐ **AKTYWNE ZADANIE** — budowa prawdziwych testów E2E (Playwright + nagrania) | AI |

## Jedna zasada, żeby się znów nie rozjechało

**`2-DECYZJE-AKTUALNE.md` to jedyne źródło prawdy o cenach / storage / quocie / DR.**
Każdy inny dokument (biznesplan, specy `architecture/`) **linkuje** tu, a nie powtarza
liczb. Zmieniasz decyzję → edytujesz ten jeden plik + dopisujesz linijkę w changelogu.
Koniec z dopiskami „SUPERSEDED" rozsianymi po 24 plikach.
