# 5. Dla agenta AI (jak zlecać zadania, żeby Devin nie błądził)

> Ten plik jest dla Ciebie (Daniela) — jak formułować zlecenia — oraz dla agenta,
> jako pierwszy punkt wejścia przed dotknięciem kodu.

## Dla agenta: zanim cokolwiek zrobisz, przeczytaj w tej kolejności
1. [`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md) — **kanon** (ceny, storage, quota, DR, koszt, Hard Requirements). Wygrywa z każdym innym plikiem.
2. Konkretny master-spec z [`../architecture/`](../architecture/) dla Twojego obszaru (indeks: [`../architecture/README.md`](../architecture/README.md)).
3. Sekcję `0. Hard Requirements` i `DOTYKAJ vs NIE RUSZAJ` w tym specu.

**Nie analizuj całego repo.** Kanon + jeden spec do zadania wystarczą. Jeśli kanon
i spec są sprzeczne — obowiązuje kanon, a rozjazd zgłoś Danielowi.

## Dla Daniela: jak pisać dobre zlecenie (przeciw „prompt fatigue")
- **Jedno zadanie na sesję** (micro-tasking). Długie, wielozadaniowe prompty = Devin gubi się „w środku".
- Wskaż **konkretny spec + sekcję + numery niezmienników/LLD** („krótka smycz"), zamiast „ogarnij temat".
- Wymagaj **step-by-step audytu** przed merge: punkt po punkcie kod + log/test, nie „zrobione".
- Pamiętaj: **brak CI** (testy lokalne), **Devin nie merguje** do `main` (robisz to sam).

## Czy da się zbudować/utrzymać cały system samym AI?
Tak — duża część już jest zbudowana (patrz [`3-CO-JEST-ZROBIONE.md`](3-CO-JEST-ZROBIONE.md)).
AI dowiezie inżynierię i testy. AI **nie** weźmie za Ciebie ryzyka biznesowego ani
nie sprzeda — to zostaje po stronie człowieka (decyzje DR/RODO, legal, dystrybucja).

## Złota zasada utrzymania docs
Zmieniasz cenę / storage / quotę / DR → edytujesz **tylko** [`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md)
+ dopisujesz linijkę w [`../changelog`](../changelog). Nie rozsiewaj liczb po wielu plikach
i nie dopisuj „SUPERSEDED" — to jest dokładnie to, co doprowadziło do chaosu.
