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

- Trial: **30 dni**.
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
- **Immutability (HR-1):** nigdy nie kasujemy — usunięcie to tylko flaga `DELETED`. Fizyczne bajty **tylko rosną**. Dlatego dedup (DifferentialScanner, 4 MB chunki) + kompresja (~40% GZIP) są krytyczne dla opłacalności.

---

## C. DR / kopia zapasowa (ZATWIERDZONY 2026-06-28)

- **3-2-1:** kopia #1 = dedyk OVH (hot RAID, instant restore); **kopia #2 = OVH cold/backup** (offsite, write-once, „wrzuć raz, leży tanio na taśmach").
- **Restore z cold = tylko ścieżka DR** (gdy padnie cały dedyk). Odmrażanie (godziny) jest tu akceptowalne — zwykły restore klienta zawsze idzie z hot RAID.
- **Wymóg:** kopia inkrementalna + automatyczna + **okresowy testowy restore** (backup nieprzetestowany = brak backupu).
- **RODO:** OVH cold zostaje w EU, z umową powierzenia → rozwiązuje „jedna lokalizacja" i zgodność dla danych obcych klientów (dysk domowy tego nie dawał — odrzucony jako jedyny offsite).
- ⚠ **Otwarte ryzyko (świadome, faza bootstrap):** jeden serwer + RAID5 (przeżyje 1 dysk). Pełne odtworzenie 10 TB z cold trwa długo (RTO). Trigger graduacji (drugi serwer / object storage EU): zapełnienie boxa > ~50% **lub** rosnąca liczba płacących obcych.

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
