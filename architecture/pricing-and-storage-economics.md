# Pricing & Storage Economics — analiza opłacalności (robocza)

Wersja: 0.1 (robocza) — **2026-06-05: utworzono na podstawie sesji z Danielem (eksploracja modelu cenowego).**
Status: **EKSPLORACJA / DECYZJE OTWARTE** — to NIE jest zatwierdzony cennik. To zapis analizy + rekomendacja, na podstawie której Daniel podejmuje decyzję.
Powiązane: `ovh-cloud-archive-migration-spec.md` (HR-1 immutability, koszty per GB), `master-tdd-plan.md` (Dodatek F — D-5/D-6), `buffer-core-master-spec.md` (dedup/ChunkSealer/DifferentialScanner), `minecraft-plugin-master-spec.md` (profil ciężkiego klienta MC).

> **Po co ten dokument:** w trakcie hardeningu płatności wyszło, że model cenowy
> nie jest domknięty i przy realnym profilu klienta (serwer MC z dużą mapą) może
> być **strukturalnie nierentowny**. Ten plik spina ekonomię jednostkową, tłumaczy
> kluczowe pojęcie „fizyczne vs logiczne bajty" i zostawia jawne decyzje do podjęcia.
> Liczby cenowe są **przykładowe (DRAFT)** — do dostrojenia przez Daniela.

---

## 0. TL;DR (dla zabieganych)

1. **Koszt storage NIE jest wrogiem** — OVH jest tani i blisko dna cenowego. Wrogiem jest **niedopasowanie ceny do realnego zużycia** ciężkiego klienta.
2. **Prawo HR-1 (immutable, „nigdy nie kasujemy")** sprawia, że **fizycznie zajęte miejsce rośnie wiecznie**, nawet gdy „bieżące" dane klienta stoją w miejscu.
3. Dlatego **quota i cena MUSZĄ liczyć się od FIZYCZNYCH bajtów (z historią)**, inaczej „nielimitowana historia / time-travel" finansowo bankrutuje (Opcja B).
4. **Deduplikacja to fundament opłacalności**, nie detal — decyduje, czy „fizyczne" trzyma się blisko „logicznego".
5. Pozycjonowanie: **nie konkurujemy ceną-za-TB z iDrive** — wygrywamy zdolnością (MC plugin, zweryfikowany restore, IoThrottle, time-travel, EU/RODO).

---

## 1. Koszt jednostkowy (stawki OVH)

> **DECYZJA Daniela (2026-06-05):** liczymy **jedną płaską stawkę** storage.
> OVH typowo ma jedną cenę; tańszy „cold" (~20% taniej) **nie jest wart** dodatkowej
> złożoności i ryzyka rehydratacji. To **koryguje** opis hot/cold/frozen w
> `ovh-cloud-archive-migration-spec.md` §4.1 / HR-7 (patrz §7 niżej — rozjazd docs↔rzeczywistość).

| Składnik | Stawka netto | Stawka brutto (×1,23) | Uwaga |
|---|---|---|---|
| Storage | 0,009636 PLN/GiB/mc | ~0,01185 PLN/GiB/mc | ≈ **12,1 zł brutto/TB/mc** ≈ **145,6 zł brutto/TB/rok** |
| Zapis (ingest) | 0,04 PLN/GiB | ~0,049 PLN/GiB | jednorazowo per wgrany GiB ≈ **50 zł brutto/TB wgrane** |
| Egress / restore | (płaci klient / pomijalny) | — | przy płaskim single-tier brak rehydratacji |

**Przychód planu (dziś):** 190 zł brutto/rok (annual) lub 19 zł brutto/mc (monthly).
Patrz `promo-codes.md`: `MONTHLY_PRICE_PLN=1900`, `ANNUAL_PRICE_PLN=19000` (grosze).

---

## 2. Pojęcie kluczowe: „fizyczne" vs „logiczne" bajty

**Analogia segregatora:** wpinasz kartki, ale **nigdy nie wolno Ci żadnej wyjąć**
(prawo HR-1: „usunięcie to tylko metadana, fizyczny obiekt zostaje").

- **Logiczny rozmiar** = ile danych klient „ma teraz" (jego aktualny świat MC = 700 GB). Stoi w miejscu.
- **Fizyczny rozmiar** = ile leży **w sumie** na OVH: każda wersja z każdego dnia + każdy „skasowany" plik. **Tylko rośnie.**

Każdy codzienny backup dokłada nowe (niekasowalne) chunki. Świat „na biurku" dalej
~700 GB, ale „segregator" puchnie. **OVH liczy kasę od segregatora (fizyczne),
nie od biurka (logiczne).**

`StorageQuotaGuard` liczy `used_bytes` jako sumę wgranych chunków (`archive_snapshot`).
Skoro chunki są niekasowalne (HR-1), **to już jest pomiar fizyczny z historią** —
kod jest po stronie Opcji A; trzeba to świadomie potwierdzić i tak wycenić.

---

## 3. Scenariusz referencyjny (ciężki klient MC)

Serwer MC, świat **700 GB**, codzienny backup, ~**10 GB/dzień** nowych/zmienionych
regionów (przed dedup). Immutable = każde 10 GB zostaje na zawsze.

| Czas | Logicznie (bieżące pliki) | FIZYCZNIE na OVH (z historią) |
|---|---|---|
| start | 700 GB | 700 GB |
| 1 mc | ~700 GB | ~1,0 TB |
| 6 mc | ~700 GB | ~2,5 TB |
| 12 mc | ~700 GB | **~4,35 TB** |
| 24 mc | ~700 GB | **~8 TB** |

Logicznie klient „ma 700 GB" w nieskończoność. Fizycznie po roku ~4,35 TB i rośnie.

---

## 4. Trzy modele rozliczania (na liczbach, płaska stawka)

### Opcja A — quota/cena od FIZYCZNYCH bajtów (z historią) — **REKOMENDACJA**
- Klient płaci za to, co realnie leży. W 12. mc ~4,35 TB → ~**527 zł brutto/rok** kosztu storage; przy uczciwej cenie (np. ~250–300 zł/TB/rok) rachunek rośnie wraz z historią, **marża dodatnia**.
- Plan „1 TB" → limit wbity po ~30 dniach (700 GB + miesiąc historii). Dalej: większy plan. Miejsca nie zwolni (HR-1).
- **Marża: bezpieczna. UX: trudny** („mam 700 GB, a brak miejsca po miesiącu") — ratuje dedup (§5).

### Opcja B — quota/cena od LOGICZNEGO bieżącego rozmiaru — **BANKRUCTWO**
- Licznik pokazuje ~700 GB zawsze; klient ma „nielimitowaną historię w cenie planu 1 TB" — produkt marzeń, sam się sprzedaje.
- Twój koszt (płaska stawka):
  - **Rok 1:** storage (śr. ~2,5 TB) ~368 zł + zapis 4,35 TB ~219 zł = **~587 zł brutto**; przychód 190 zł → **strata ~−400 zł**.
  - **Rok 2:** fizycznie 4,35→8 TB (śr. ~6,2 TB) ~900 zł + zapis ~184 zł = **~1 080 zł brutto**; przychód 190 zł → **strata ~−890 zł i rośnie**.
- → Płaska stawka nic nie ratuje; problem to rosnąca wiecznie historia, nie tier.

### Opcja C — HYBRYDA (limit bieżące + osobno historia)
- Ładny licznik („bieżące 700 GB / 1 TB" + „historia X GB") z dopłatą powyżej okna.
- ALE „historia ograniczona kosztowo" wymaga **kasowania starych wersji = złamania HR-1**. Działa tylko jeśli świadomie zrelaksujesz albo immutability (retencja), albo obietnicę „na zawsze".

**Wniosek:** „niekasowalna historia na zawsze" (HR-1) finansuje **tylko Opcja A**.
B = bankructwo. C = trzeba złamać „keep forever".

---

## 5. Dedup — dźwignia, która decyduje o opłacalności Opcji A

Te „10 GB/dzień" w MC to głównie **niezmienione bloki regionów**. Jeśli
`ChunkSealer`/`DifferentialScanner` realnie wgrywa np. **2 GB/dzień zamiast 10**:
- po 12 mc fizycznie ~1,43 TB zamiast 4,35 TB,
- „fizyczne ≈ logiczne + cienka historia" → ból Opcji A znika,
- koszt zapisu (0,04/GiB) też leci ~5× w dół.

**Dlatego przed zabetonowaniem liczb trzeba zmierzyć realny współczynnik dedup
na prawdziwej mapie MC.** To on decyduje, czy Opcja A boli, czy jest niewidzialna.

---

## 6. Pozycjonowanie i benchmark rynku

Nie konkurujemy ceną-za-TB (iDrive 5 TB ≈ 320 zł/rok < nasz koszt 5 TB ≈ 728 zł/rok netto).
Wygrywamy **zdolnością**, której iDrive nie daje:

| USP | iDrive | ProperBackup |
|---|---|---|
| Plugin Minecraft (świadomy świata) | ✗ | ✓ |
| IoThrottle pod tani VPS/ARM | ✗ | ✓ |
| Zweryfikowany restore + Audit PDF | ✗ | ✓ |
| Time-travel / pełna historia (HR-1) | ograniczona | ✓ (immutable) |
| EU / RODO, PL | częściowo | ✓ |

Benchmark (kurs ~4 zł/$, retail): iDrive 5 TB ~80 $/rok; Backblaze B2 ~72 $/TB/rok;
Wasabi ~84 $/TB/rok (min. 90 dni). Nasz **koszt** ~24 $/TB/rok — tańszy niż object
storage, ale droższy niż konsumencki backup na skali. Sprzedajemy premium-zdolność,
nie najtańszy GB.

---

## 7. Rozjazdy docs ↔ rzeczywistość wykryte przy cross-checku (2026-06-05)

1. **Hot/cold/frozen lifecycle** (`ovh...spec.md` §4.1, HR-7) — w praktyce jedziemy **płaski single-tier**. Do skorygowania w tamtym specu (zrobione: dopisek korygujący).
2. **Założenie „średni klient 30–50 GB"** (`ovh...spec.md` §4.4) — obalone dla niszy MC (mapy 700 GB+). Ekonomia w docs stała na tym założeniu.
3. **Billing nie ma planów per-pojemność** — `stripe_price_config` keyowane `(plan_key∈{monthly,annual}, mode)`; pojemność (Hobby 100 GB / Pro 1 TB) istnieje tylko jako `storage_limit`, odpięta od ceny. Wprowadzenie półek pojemności = realny feature (enum `Plan`, schemat price config, karty planów, downgrade-logic).
4. **Downgrade pojemności niezdefiniowany** — `downgrade-logic.md` obsługuje tylko zmianę okresu (monthly↔annual), nie „1 TB→500 GB gdy zużyte 800 GB".
5. **Restore z cold nie jest darmowy/instant** — przy single-tier flat ten problem znika (brak rehydratacji), ale HR-2 mówi „klient płaci egress".
6. **Wewnętrzna sprzeczność w specu OVH:** HR-7 „po 365 dniach NIE DELETE" vs §4.1/§5 „1y cold → delete dla wygasłych userów". Do ujednolicenia.

---

## 8. Rekomendacja

1. **Quota/cena od fizycznych bajtów (Opcja A)** — jedyny model spójny z HR-1 i „keep forever".
2. **Mocny dedup jako warunek** (zmierzyć współczynnik na realnej mapie MC).
3. **Przejrzysty licznik „bieżące vs historia"** w panelu — żeby klient rozumiał, za co płaci.
4. **Unlimited devices** jako USP (urządzenia nic nie kosztują — kosztują dane).
5. **Time-travel / pełna historia** jako sztandarowy wyróżnik premium.
6. Cennik per-pojemność (DRAFT, do dostrojenia po pomiarze dedup):

| Plan (unlimited devices) | Fizyczna przestrzeń | Cena (DRAFT) | Uwaga |
|---|---|---|---|
| Starter | 250 GB | ~14 zł/mc | lekkie configy, małe serwery |
| Personal | 500 GB | ~24 zł/mc | multi-device (PC+telefon+rodzina) |
| Pro | 1 TB | ~39 zł/mc | duże mapy MC, ciężkie VPS |
| Power | 2 TB | ~69 zł/mc | bardzo duże / metered overage |

> Liczby cenowe **DRAFT** — zależą od zmierzonego dedup i decyzji A/B/C (Dodatek F: D-5).

---

## Dodatek A — luźne przemyślenia: modele cenowe przeanalizowane i ODRZUCONE

Zapis ścieżki myślowej z sesji (żeby nie przepadła i żeby nie wracać do ślepych uliczek):

| Model | Pomysł | Dlaczego odrzucony |
|---|---|---|
| **Flat per-konto, „2 TB za 190 zł"** | jedna cena, dużo miejsca | przy pełnym zapełnieniu koszt > przychód; ciężki klient pod kreską |
| **Per-server (190 zł/serwer)** | rozliczać per chroniona maszyna | Daniel chce **unlimited devices**; per-server kłóci się z USP |
| **Pay-per-write (chomikuj.pl, płatność za zapis)** | klient płaci raz za wgranie, trzyma wiecznie | zapis = koszt jednorazowy, storage = koszt **wieczny i rosnący**; jednorazowy przychód << wieloletni koszt; dodatkowo perwersyjna zachęta (klient backupuje RZADZIEJ, by nie płacić) |
| **Self-host na RAID (dedyk Hetzner)** | własne dyski taniej | po doliczeniu redundancji (RAID6/3-2-1) ~15–40 zł/TB/mc — **drożej** niż OVH; stajesz się operatorem storage |
| **Dyski w domu** | najtaniej per-TB | łącze domowe, brak 24/7, jedna lokalizacja (pożar/kradzież = utrata backupów WSZYSTKICH klientów), RODO, on-call — dyskwalifikujące dla płatnego produktu |
| **Hetzner Storage Box + restic** | ~9–10 zł/TB, bez paczek, „gorący" | kuszące (mógłby usunąć custom chunking), ale to **pivot architektury**; storage/krypto są FROZEN — poza zakresem |
| **Migracja na inny tani backend** | szukanie taniej niż OVH | OVH ~9,9 zł/TB/mc to praktycznie dno; „restrykcyjne paczki" to CENA tej taniości |

**Wniosek z całej rundy:** każda droga zbiega się do tego samego — **cena musi być
CYKLICZNA i proporcjonalna do ZAJĘTEJ (fizycznej) PRZESTRZENI.** Reszta to wariacje
na temat progów i overage.

> **AKTUALIZACJA 2026-06-05 (rozjazd z tym Dodatkiem):** wiersze „Hetzner Storage Box"
> i „Migracja na inny tani backend" były tu oznaczone jako *pivot / FROZEN / poza
> zakresem*. **To założenie zostało świadomie reotwarte** — po realnej pracy z OVH
> Cloud Archive (Swift) backend jest reewaluowany z powodów **operacyjnych i zaufania**
> (a nie cenowych). Aktualny kierunek: **[`storage-backend-decision.md`](storage-backend-decision.md)**
> (rekomendacja: odejść od Cloud Archive na rzecz prostego S3/plikowego backendu + 3-2-1).
> Opcja A (cena od fizycznych bajtów) pozostaje słuszna **niezależnie od dostawcy** —
> zmienia się tylko stawka kosztu/TB do podstawienia.

---

## Dodatek B — co zasila testy płatności (constraint dla Devina)

Po decyzji A/B/C (Dodatek F: D-5) wynika twardy constraint dla pierwszego testu
`StorageQuotaGuard`:
- **baza pomiaru `used_bytes`** (fizyczne z historią vs logiczne) — to ustawia, co test asertuje,
- **wartości `storage_limit` per plan** (półki pojemności),
- **zachowanie przy downgrade pojemności** (D-6),
- **fail-safe przy DB-down** (już pokryte: TDD-G1c).
