# 2026-06-28 — Uspójnienie docs: kanon decyzji + odzyskanie ekonomii stałego serwera

## Kontekst
Decyzje z czerwca 2026 (dedyk OVH jako primary storage, cennik S/M/L/XL, model kosztu
stałego serwera) były rozsiane po `architecture/`, częściowo wzajemnie sprzeczne, a
część (PR #27: §9 — koszt 135 zł/~10 TB, quota Opcja 2, DR) **nigdy nie trafiła do `main`**
(merge na już-zmergowany branch). README i biznesplan v6.2 zostały na starych liczbach.

## Co zmienione
- **NOWE: `00-START-TUTAJ/`** — „po ludzku" punkt wejścia (5 plików), w tym
  `2-DECYZJE-AKTUALNE.md` = **jedyny kanon** cen/storage/quoty/kosztu/DR.
- **NOWE: `biznesplan/Biznesplan_v6.3.md`** — v6.2 docx przepisany na markdown + pivot
  (dedyk OVH + S/M/L/XL + koszt stały + DR OVH cold).
- **`architecture/pricing-and-storage-economics.md`**: odtworzono **§9** (model kosztu
  STAŁY SERWER 135 zł/~10 TB, próg rentowności, sufit per box, **quota Opcja 2 — sufit
  2× per tier**). §1 oznaczone jako benchmark/koszt offsite, nie koszt primary. DR §9.5
  zmienione na **OVH cold** (zamiast dysku domowego — decyzja 2026-06-28).
- **`architecture/session-orchestration-plan.md`**: §5 — usunięto „+150 GB/mc → 2 TB dla
  każdego" (pułapka) na rzecz Opcja 2; „Fakty OVH" oznaczone jako offsite/benchmark;
  roczny = pełny sufit od razu; §0a offsite/DR = OVH cold.
- **`README.md`**: usunięto „19 zł/mc, 190 zł/rok, OVH Cloud Archive"; dodano S/M/L/XL,
  dedyk, DR OVH cold, link do `00-START-TUTAJ/`, repo `softify-website`.

## Decyzje utrwalone w kanonie
- Storage primary = dedyk OVH RAID5 ~10–11 TB, restore instant.
- DR/offsite = OVH cold/backup (kopia #2), EU/RODO.
- Koszt = stały ~135 zł brutto/mc; próg ~5 klientów S; marża ~75–90%.
- Quota = Opcja 2 (+10%/mc, sufit 2× startu per tier).

## Otwarte (świadome) ryzyko
Single-server + RAID5; RTO przy pełnym odtworzeniu z cold długie. Trigger graduacji:
zapełnienie boxa > ~50% lub rosnąca liczba płacących obcych klientów.

## Do zrobienia osobno
- Ujednolicenie waluty w panelu `properbackup-web` (USD → PLN).
- Wdrożenie najnowszego kodu na dedyk + pełny E2E + konfiguracja DR na OVH cold.
