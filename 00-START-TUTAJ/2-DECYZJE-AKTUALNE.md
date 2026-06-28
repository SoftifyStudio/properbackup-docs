# 2. DECYZJE AKTUALNE — KANON ⭐

> **To jest jedyne źródło prawdy o cenach, storage, quocie, koszcie i DR.**
> Jeśli jakikolwiek inny plik (biznesplan, `architecture/*`, README) mówi inaczej —
> **obowiązuje ten plik.** Zmiana decyzji = edycja TUTAJ + linijka w `../changelog`.

Ostatnia aktualizacja: **2026-06-28**

---

## A. Cennik klienta (ZATWIERDZONY)

Unlimited devices w każdym tierze. Quota wspólna dla wszystkich urządzeń.
Płatność roczna ≈ 25% taniej **i** od razu pełny sufit tieru.

| Tier | Quota start | Sufit (2× start) | Cena mc | Cena rok |
|------|-------------|------------------|---------|----------|
| **S** | 150 GB | 300 GB | 29 zł | 259 zł |
| **M** | 300 GB | 600 GB | 39 zł | 349 zł |
| **L** | 500 GB | 1 TB | 59 zł | 529 zł |
| **XL** | 1 TB | 2 TB | 89 zł | 790 zł |

- Trial: **30 dni** (45 dni dla agencji WP/IT — segment B2B). Anti-abuse: soft limit **500 GB** w trialu, rate limit flushy, weryfikacja email.
- **Quota „Opcja 2":** start rośnie **+10% startu/mc** aż do **2× startu** (sufit per tier). To NIE jest „wspólne 2 TB dla każdego" (stara, błędna reguła — odrzucona).
- **Po rezygnacji:** 90 dni dostępu do restore (canRestore=true, canUpload=false), potem mail 7 dni przed → fizyczne usunięcie.
- **Downgrade:** jeśli zużycie > nowa quota → backup zatrzymany, dane zachowane, klient czyści lub wraca wyżej.
- ⚠ **Walutowo:** panel `properbackup-web` pokazuje dziś ceny w **USD** — do uspójnienia z PLN (zadanie w kodzie).

---

## B. Storage — gdzie leżą dane (ZATWIERDZONY 2026-06-20)

- **Primary = WYŁĄCZNIE dedykowany serwer OVH** (Kimsufi KS-STOR, RAID5 4×4 TB ≈ **~10–11 TB** użytecznego, `/mnt/storage`).
- **Restore = INSTANT** — pliki czytane wprost z lokalnego dysku. Brak „odmrażania"/unsealing.
- **NIE** ma już OVH Cloud Archive / Swift / unsealing w krytycznej ścieżce (relikt, za interfejsem `StorageClient` ale nieużywany).
- Quota liczona na **fizycznych bajtach po kompresji** (`StorageQuotaGuard`).
- **Immutability (HR-1):** dla **aktywnego konta** nigdy nie kasujemy danych — usunięcie pliku przez klienta to tylko flaga `DELETED` (historia zostaje). Fizyczne bajty aktywnego konta **tylko rosną**. Dlatego dedup (DifferentialScanner, 4 MB chunki) + kompresja (~40% GZIP) są krytyczne dla opłacalności.
- **Wyjątek — sprzątanie po rezygnacji (osobny cykl, NIE łamie HR-1):** dane konta **anulowanego** są fizycznie usuwane dopiero **po 90-dniowym oknie retencji** (patrz §A) — to czyszczenie porzuconych kont, nie kasowanie historii aktywnego klienta.

---

## C. DR / kopia zapasowa (kierunek 2026-06-28)

- **Kopia #1 (primary):** dedyk OVH (hot RAID, instant restore).
- **Kopia #2 (offsite) — DOCELOWO: drugi serwer dedykowany jako Proxmox Backup Server (PBS).** Identyczny box jak primary, ale wyłącznie na backupy. PBS robi **inkrementalne, deduplikowane** kopie → koszt **stały** (~135 zł/mc za box), nie rosnący per-GB. *Status: plan / pomysł, NIE teraz.*
- **Na teraz (interim):** „byle gdzie zgrane" — **wystarczy jakakolwiek tania kopia offsite**, żeby kopia #2 w ogóle istniała (np. dysk domowy / inny dostępny zasób). Cel: nie zostać z jedną kopią.
- ❌ **OVH cold/backup — odrzucone jako za drogie** (koszt rośnie per-GB razem z danymi; sprzeczne z modelem kosztu stałego). Zostaje co najwyżej jako ostateczność.
- **Wymóg (każdy wariant):** kopia inkrementalna + automatyczna + **okresowy testowy restore** (backup nieprzetestowany = brak backupu).
- ⚠ **Otwarte ryzyko (świadome, faza bootstrap):** dopóki nie ma drugiego serwera/PBS, offsite jest prowizoryczne. **RODO:** przed sprzedażą obcym klientom offsite musi mieć umowę powierzenia (drugi serwer w DC / zasób EU) — prowizorka domowa nie jest zgodna dla cudzych danych.
- **Trigger postawienia PBS / drugiego serwera:** zapełnienie primary > ~50% **lub** rosnąca liczba płacących obcych klientów.

---

## D. Koszt i opłacalność (ZATWIERDZONY 2026-06-21)

- **Nasz koszt = STAŁY ~135 zł brutto/mc** (≈109 zł netto) za cały serwer (~10 TB). **Nie per-GB.** Płacimy tyle samo przy 1 i przy 60 klientach.
- **Próg rentowności:** **~5 klientów S** (albo 2 XL) = serwer na zero.
- **Sufit per box (start quota):** ~68×S / 34×M / 20×L / 10×XL. Skalowanie = dokładanie serwerów (+135 zł / +~10 TB każdy).
- **Marża:** świeży klient 85–93%; worst case (wszyscy na suficie 2×) 70–86%; realnie **~75–90%**.
- Pełne tabele i wyprowadzenie: [`../architecture/pricing-and-storage-economics.md`](../architecture/pricing-and-storage-economics.md) §9.

---

## E. Co jest „prawem projektu" (Hard Requirements — nie ruszać bez decyzji Daniela)

- Jeden JAR KMP (agent serwis + wrapper JAR dla hostingu MC).
- Zero-knowledge: Argon2id → AES-256-GCM, klucz po stronie klienta.
- Buffer persistent-first, paczki **900–950 MB** strict.
- `BudgetGuard` + `StorageQuotaGuard` = **fail-safe** (blokują przy awarii DB, nie przepuszczają).
- HR-1 immutability (patrz B).
- Auto-test restore + Audit PDF.

---

## Czego ten plik świadomie NIE rozstrzyga
- Ujednolicenie waluty w panelu (USD→PLN) — zadanie w kodzie `properbackup-web`.
- Dokładny moment zamówienia drugiego serwera — wg triggera w C.
- Strategia dystrybucji (GTM) — patrz biznesplan, rozdz. B2B.
