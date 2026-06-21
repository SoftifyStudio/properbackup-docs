# Pricing & Storage Economics — analiza opłacalności (robocza)

Wersja: 0.2 — **2026-06-05: utworzono (eksploracja).** **2026-06-21: dopisano §9 — model kosztu STAŁY SERWER (dedyk), NADRZĘDNY dla kosztu/marży.**
Status: **§9 ZATWIERDZONA (Daniel, 2026-06-21)** dla struktury kosztów i quoty. Sekcje 1–8 to wcześniejsza eksploracja pod cold storage — stawki OVH Cloud Archive zostają **już tylko jako benchmark/historia**, NIE są naszym kosztem. **Aktualny model kosztu = §9.**
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

> ⚠ **SUPERSEDED jako NASZ koszt (2026-06-21).** Poniższe stawki per-GB dotyczą
> OVH Cloud Archive (cold storage), z którego **zrezygnowaliśmy** na rzecz
> dedykowanego serwera (koszt **stały**, nie per-GB). Te liczby zostają **tylko
> jako benchmark rynkowy**. Nasza realna struktura kosztu i marży = **§9**.

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

> ### ⚠️ KOREKTA (2026-06-20, decyzja Daniela) — TIERY S/M/L/XL, unlimited devices, max 2 TB
>
> Rezygnujemy z tierow Starter/Personal/Pro/Power. Nowe tiery:
>
> | Tier | Start quota | Cena mc | Cena rok (~25% rabat) |
> |---|---|---|---|
> | **S** | 150 GB | **29 zl/mc** | **259 zl/rok** |
> | **M** | 300 GB | **39 zl/mc** | **349 zl/rok** |
> | **L** | 500 GB | **59 zl/mc** | **529 zl/rok** |
> | **XL** | 1 TB | **89 zl/mc** | **790 zl/rok** |
>
> - **Unlimited devices** w kazdym tierze — quota WSPOLNA
> - Quota rośnie **per tier z sufitem 2× startu** (wzrost lojalnościowy, Opcja 2) — **nie** wspólne 2 TB dla każdego (to była pułapka). Pełne liczby: **§9.4**
> - **Kompresja:** GZIPOutputStream PRZED szyfrowaniem (~40% oszczednosci)
> - **Retencja po rezygnacji:** 90 dni (canRestore=true, canUpload=false)
> - **Downgrade:** current usage > nowa quota → backup zatrzymany
> - Pelna analiza: `session-orchestration-plan.md` §5
>
> Poprzednia tabela tierow ponizej jest **SUPERSEDED** — zostaje jako kontekst.

| Plan (unlimited devices) | Fizyczna przestrzeń | Cena (DRAFT) | Uwaga |
|---|---|---|---|
| ~~Starter~~ | ~~250 GB~~ | ~~\~14 zł/mc~~ | ~~SUPERSEDED~~ |
| ~~Personal~~ | ~~500 GB~~ | ~~\~24 zł/mc~~ | ~~SUPERSEDED~~ |
| ~~Pro~~ | ~~1 TB~~ | ~~\~39 zł/mc~~ | ~~SUPERSEDED~~ |
| ~~Power~~ | ~~2 TB~~ | ~~\~69 zł/mc~~ | ~~SUPERSEDED~~ |

> Liczby cenowe **SUPERSEDED** — patrz korekta powyzej.

---

## 9. MODEL KOSZTU: STAŁY SERWER (DEDYK OVH) — 2026-06-21 (NADRZĘDNY dla kosztu/marży)

> Status: **ZATWIERDZONE (Daniel, 2026-06-21).** Ta sekcja ma **PIERWSZEŃSTWO** nad
> §1 i §4–§8 w zakresie **NASZEJ struktury kosztu i marży**. Ceny KLIENTA
> (S/M/L/XL) bez zmian. Storage = **wyłącznie dedyk OVH** (patrz
> `deployment-dedicated-server.md` i `session-orchestration-plan.md` §0a).

### 9.1 Zmiana modelu: koszt ZMIENNY → STAŁY
- **Stary model (cold storage):** płaciliśmy OVH per-GB (~11,86 zł brutto/TiB/mc + ingest). Koszt **rósł razem z danymi** (zmienny) — był dodatni od pierwszego klienta.
- **Nowy model (dedyk):** **stały ~109 zł netto/mc ≈ 135 zł brutto/mc** za cały serwer, na którym mamy **realnie ~10 TB** na dane klientów (RAID5 4×4 TB → ~11 TB minus narzut/headroom).
- **Koszt all-in: ~13,5 zł brutto/TB/mc** — ale **tylko przy pełnym boxie**. Płacisz 135 zł niezależnie od tego, czy masz 1 czy 60 klientów.
- **Offsite/DR:** backup całego serwera na **dysk domowy (łącze 800/100 Mbps) ≈ 0 zł** — patrz §9.5.
- **Wniosek:** marża jest świetna, ale **trzeba box zapełnić**, a przychód per box ma **twardy sufit** (skalowanie = dokładanie serwerów).

### 9.2 Próg rentowności (pokrycie 135 zł/mc)

| Tier | Cena mc | Klientów na pokrycie serwera | (rocznie, na mc) |
|---|---|---|---|
| S | 29 zł | **5** | 7 |
| M | 39 zł | 4 | 5 |
| L | 59 zł | 3 | 4 |
| XL | 89 zł | **2** | 3 |

→ Już **~5 klientów S (albo 2 XL)** = serwer na zero. Powyżej to niemal czysty zysk (koszt stały).

### 9.3 Sufit pojemności i przychodu per serwer (klienci na quocie STARTOWEJ)

10 TB = 10 240 GB. Jeśli każdy klient siedzi na quocie startowej swojego tieru:

| Tier | Quota | Max klientów / 10 TB | Przychód mc | Zysk mc (−135 zł) | Marża |
|---|---|---|---|---|---|
| same S | 150 GB | 68 | 1 972 zł | **1 837 zł** | 93% |
| same M | 300 GB | 34 | 1 326 zł | 1 191 zł | 90% |
| same L | 500 GB | 20 | 1 180 zł | 1 045 zł | 89% |
| same XL | 1 TB | 10 | 890 zł | 755 zł | 85% |

Małe tiery (S/M) monetyzują stały box **najlepiej** (najwyższa cena za GB), kosztem większego wolumenu supportu/churnu.

### 9.4 Quota: Opcja 2 — wzrost lojalnościowy z SUFITEM PER TIER (ZATWIERDZONE)

> **Zastępuje** regułę „+150 GB/mc → wspólne 2 TB dla każdego" — była pułapką:
> tani tier (29 zł) mógł z czasem zająć 2 TB = 1/5 całego serwera.

Reguła: quota startowa rośnie **+10% startu/mc**, aż do **2× startu** (twardy sufit per tier). Cena stała. Quota liczona na fizycznych bajtach po kompresji.

| Tier | Start | Wzrost/mc | Sufit (2× start) | Cena mc | Cena/TB przy suficie | Narzut nad koszt |
|---|---|---|---|---|---|---|
| S | 150 GB | +15 GB | 300 GB | 29 zł | 97 zł | ×7,2 |
| M | 300 GB | +30 GB | 600 GB | 39 zł | 65 zł | ×4,8 |
| L | 500 GB | +50 GB | 1 TB | 59 zł | 59 zł | ×4,4 |
| XL | 1 TB | +100 GB | 2 TB | 89 zł | 44 zł | ×3,3 |

**Bezpieczeństwo marży — worst case (WSZYSCY dorośli do sufitu):**

| Tier | Sufit | Max klientów / 10 TB | Przychód mc | Zysk mc | Marża |
|---|---|---|---|---|---|
| same S | 300 GB | 34 | 986 zł | 851 zł | 86% |
| same M | 600 GB | 17 | 663 zł | 528 zł | 80% |
| same L | 1 TB | 10 | 590 zł | 455 zł | 77% |
| same XL | 2 TB | 5 | 445 zł | 310 zł | 70% |

→ Nawet w najgorszym przypadku **marża 70–86%**. Świeży klient (start quota) = 85–93%. Realnie operacyjnie **~75–90%**. „Darmowy" wzrost świadomie zjada część marży — to **koszt retencji**, ograniczony sufitem 2×.

> **Dwa pokrętła** (do dostrojenia): tempo wzrostu (domyślnie +10%/mc) i mnożnik sufitu (domyślnie 2×).

### 9.5 DR / offsite: dysk domowy jako kopia v1

- **3-2-1 startowo:** kopia #1 = dedyk OVH, kopia #2 = dysk domowy (inna lokalizacja).
- **Tworzenie kopii (OVH → dom):** szybkie — limit = download domu **800 Mbps ≈ 100 MB/s ≈ ~300+ GB/h**. Codzienny inkrement i pierwszy duży zrzut OK.
- **Restore po awarii (dom → OVH):** wolniejszy kierunek — limit = upload domu **100 Mbps ≈ ~40 GB/h realnie**: 500 GB ≈ ~13 h, 1 TB ≈ ~1 dzień, pełne 10 TB ≈ ~10 dni.
- **Wymóg:** inkrementalnie (`restic`/`borg`/`rsync` na `/mnt/storage`), automatycznie, + **okresowy testowy restore** (backup nieprzetestowany = brak backupu).
- **RPO vs RTO:** dysk domowy chroni przed **utratą danych** (RPO dobre); **tempo odtworzenia** (RTO) ogranicza 100 Mbps up — komunikować klientowi uczciwie.
- **Trigger graduacji** do twardszego offsite (drugi serwer / object storage offsite): gdy płacących obcych > próg LUB zapełnienie boxa > ~50%.

### 9.6 Skalowanie i RODO
- **Sufit przychodu per box** (§9.3/§9.4). Skalowanie = **dokładanie serwerów** — każdy kolejny to +135 zł/mc i +~10 TB (kolejny stały skok), nie nieskończony wzrost na jednym.
- **RODO:** faza bootstrap / własni klienci na dysku domowym jako offsite = OK. Przed szerszą sprzedażą obcym (pozycjonowanie „EU/RODO") offsite przenieść na rozwiązanie z umową powierzenia (drugi serwer w DC / object storage EU).

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

> **AKTUALIZACJA 2026-06-21 — świadomy pivot.** Powyżej odrzucono „self-host na
> RAID" i „dyski w domu" jako **primary** storage (jedna lokalizacja = utrata
> wszystkiego, RODO, zostajesz operatorem storage). Decyzja z 2026-06-21
> **świadomie przyjmuje dedyk OVH jako primary**, a obiekcję „jedna lokalizacja"
> rozwiązuje **offsite na dysk domowy (§9.5) + plan graduacji**. To nie unieważnia
> ostrzeżeń z tej tabeli — to ich **kontrolowane przyjęcie na fazę bootstrap**.
> Pełna ekonomia tej decyzji: **§9**.

---

## Dodatek B — co zasila testy płatności (constraint dla Devina)

Po decyzji A/B/C (Dodatek F: D-5) wynika twardy constraint dla pierwszego testu
`StorageQuotaGuard`:
- **baza pomiaru `used_bytes`** (fizyczne z historią vs logiczne) — to ustawia, co test asertuje,
- **wartości `storage_limit` per plan** (półki pojemności),
- **zachowanie przy downgrade pojemności** (D-6),
- **fail-safe przy DB-down** (już pokryte: TDD-G1c).
