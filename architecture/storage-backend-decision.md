# Storage Backend — decyzja architektoniczna (PROPOZYCJA)

Wersja: 0.1 (propozycja) — **2026-06-05: utworzono po sesji z Danielem.**
Status: **PROPOZYCJA / DO AKCEPTACJI** — rekomenduje **odejście od OVH Cloud Archive (Swift)** jako live storage. To NIE jest jeszcze zatwierdzony backend; to zapis decyzji + rekomendacja.
Powiązane: `ovh-cloud-archive-migration-spec.md` (oznaczony *superseded / under review*), `pricing-and-storage-economics.md` (koszt/TB, Opcja A), `observability-and-dr-spec.md` (backup PostgreSQL, DR), `buffer-core-master-spec.md` (`CloudStorageClient`, packi, ChunkSealer), `crypto-and-compliance-spec.md` (szyfrowanie, RODO).

> **Po co ten dokument:** w trakcie realnej pracy z OVH Cloud Archive (Swift) wyszło,
> że ten konkretny backend jest operacyjnie zbyt złożony i zbyt kruchy dla produktu
> backupowego: segmenty Dynamic/Static Large Object (DLO/SLO), odmrażanie archiwum,
> osierocone segmenty po kasowaniu, fakturowanie „z dołu" i opłaty za gotowość.
> Daniel (2026-06-05): *„nie zaufam tej usłudze po tym wszystkim — wystarczy, że
> kod się rozjedzie i wszystko się wali"*. Ten plik rozdziela **realne ryzyko**
> (format danych + metadane) od **wyboru dostawcy** i daje uczciwe porównanie opcji.

---

## 0. TL;DR

1. **Odchodzimy od OVH Cloud Archive (Swift).** Powód NIE jest cenowy (jest najtańszy) — jest **operacyjny i zaufania**: segmenty + odmrażanie = de facto własny sterownik, kruche na edge case'ach, trudne do ręcznej naprawy.
2. **Prawdziwe ryzyko „kod się rozjedzie → tracę dane" leży w FORMACIE i METADANYCH, nie w dostawcy.** Dane to zaszyfrowane packi 950 MB indeksowane w PostgreSQL. Utrata bazy = sterta nieczytelnych packów — niezależnie, czy leżą na OVH, czy na własnym dysku. Własne dyski **same tego nie naprawiają**.
3. **Zmiana backendu na zwykłe S3 / pliki USUWA najbardziej kruchy kod**, nie dokłada — `CloudStorageClient` jest generyczny, multipart i kasowanie-z-częściami robi biblioteka klienta transparentnie.
4. **Jedyna NIEAKCEPTOWALNA opcja: jeden dysk w jednej lokalizacji.** Wszystko inne (managed object storage, Hetzner Storage Box, dedyk+MinIO, kolokacja) jest na stole — pod warunkiem **3-2-1** (offsite druga kopia).
5. **Rekomendacja:** prosty backend S3/plikowy + **druga kopia u innego dostawcy** (3-2-1). To jednocześnie znosi „nie ufam jednemu dostawcy" — nie jesteś zakładnikiem żadnego.

---

## 1. Co realnie poszło nie tak z OVH Cloud Archive (Swift)

| Problem | Co to znaczy w praktyce |
|---|---|
| **Segmenty DLO/SLO** | duży obiekt = manifest w głównym kontenerze + segmenty w **osobnym kontenerze** (`*_segments`). Skasowanie manifestu w panelu **zostawia osierocone segmenty**, które dalej zajmują miejsce i są fakturowane (to się Danielowi zdarzyło na żywo). |
| **Odmrażanie archiwum (unfreeze)** | dane „zamrożone", odczyt wymaga żądania rehydratacji z opóźnieniem — komplikuje restore i tooling. |
| **Własny sterownik** | poprawna obsługa (multipart, retry, manifesty, sprzątanie segmentów, freeze/unfreeze) = sporo bespoke kodu na styku Swift. Każdy z tych elementów to potencjalny edge-case-bug w ścieżce, która MUSI być niezawodna. |
| **rclone „wysypywało się"** | standardowe narzędzia nie działają out-of-the-box bez znajomości segmentów/auth v3 — sygnał, że to nisko-poziomowy, niewdzięczny backend. |
| **Fakturowanie „z dołu" + gotowość** | spadek zużycia widać dopiero w kolejnym cyklu; opłaty za „gotowość do świadczenia usług" / minima budują nieufność. |

**Wniosek:** to nie jest „zły dostawca", to **zła klasa usługi** dla naszego zastosowania.
Cloud Archive (Swift) jest projektowany pod rzadko ruszane, zimne archiwum — nie pod
żywy, często zapisywany/odtwarzany backup z panelem self-service.

---

## 2. Prawdziwe ryzyko: format danych + metadane (provider-independent)

Daniel boi się słusznie: *„kod się rozjedzie → rozkładam ręce"*. Ale popatrz, co realnie trzyma dane:

- Dane = **zaszyfrowane packi po ~950 MB** (`PackBuffer`, `ChunkSealer`).
- Mapa „który plik = który pack + offset" siedzi w **PostgreSQL** (`archive_snapshot`, `buffer_pack`, `file_state`).

Jeśli zgubisz/uszkodzisz bazę metadanych albo logika packowania się rozjedzie, to **na każdym backendzie** masz nieczytelną stertę `pack_0007.bin`. **Własny dysk pokazuje `pack_0007.bin`, nie Twoje pliki.** Czyli posiadanie dysków NIE jest tym, co chroni.

Co realnie chroni (do zrobienia niezależnie od wyboru dostawcy — **te trzy punkty są ważniejsze niż sam backend**):

1. **Backup bazy metadanych** — regularny dump PostgreSQL z własnym retencyjnym oknem (patrz `observability-and-dr-spec.md`). To jest „mapa skarbów"; jej utrata = prawdziwy „rozkładam ręce".
2. **Samoopisujący się manifest obok packów** — minimalny indeks (jakie pliki, jakie chunki, ref do klucza) zapisany razem z danymi, tak by dało się odtworzyć **bez aplikacji**, samodzielnym skryptem. To jest realne „nie jestem zakładnikiem własnego kodu".
3. **Zweryfikowany restore (Auto-Test Restore + Audit PDF)** — już istnieje; to mechanizm zaufania. Powinien chodzić cyklicznie i alarmować przy rozjeździe.

---

## 3. Reframe: zmiana na S3/pliki to MNIEJ kodu

Wasza warstwa storage jest już abstrakcyjna:

```
CloudStorageClient (put / get / list / delete / exists)   <- interfejs (stabilny)
  └─ OvhSwiftClient   (Swift: multipart-segmenty, freeze, sprzątanie *_segments)  <- KRUCHY
  └─ S3Client         (AWS SDK / dowolne S3-compatible)                            <- prosty
  └─ FsClient         (SFTP/lokalny FS dla Hetzner Storage Box / restic-style)     <- prosty
```

Przejście z Swift na S3-compatible **usuwa** ręczne segmenty, manifesty multipart, freeze/unfreeze
i sprzątanie osieroconych części — bo robi to biblioteka klienta (np. AWS SDK `TransferManager`)
transparentnie, a `delete` kasuje obiekt **razem z częściami**. Czyli dokładnie ta klasa
błędów, której Daniel się boi, **znika z kodu**.

---

## 4. Porównanie opcji

> Ceny są **orientacyjne (retail)** i wymagają potwierdzenia aktualnego cennika
> przed decyzją. Kurs przyjęty ~4 zł/$. Koszt OVH Cloud Archive jest **zweryfikowany**
> (cennik Daniela): 0,009636 zł netto/GiB/mc ≈ ~10 zł netto/TB/mc.

### 4a. Managed object storage (dostawca trzyma sprzęt + redundancję)

| Backend | API | Złożoność | Koszt ~/TB/mc | Egress | Min. retencja | Uwagi |
|---|---|---|---|---|---|---|
| OVH Cloud Archive (Swift) | Swift | **wysoka** (segmenty, freeze) | **~10 zł** (najtaniej) | w cenie | brak | obecny; **rekomendacja: odejść** |
| OVH Object Storage (S3, Standard/IA) | **S3** | niska | ~15–40 zł (zweryfikować) | zależne | zależne od klasy | ten sam dostawca, ale prawdziwe S3 → zero segment-hell |
| **Backblaze B2** | **S3** | niska | ~24 zł ($6) | free do 3× storage/mc | **brak** | proste, popularne, dobre tooling |
| **Wasabi** | **S3** | niska | ~28 zł ($7) | w cenie | **90 dni** + min ~1 TB | flat, ale uważać na min. retencję (jak na koncie testowym!) |
| Cloudflare R2 | S3 | niska | ~60 zł ($15) | **$0 egress** | brak | drogi storage, ale zerowy egress (dobre przy częstym restore) |

### 4b. „Własne dyski" zrobione dobrze (kontrola + niezawodność)

| Opcja | Co to | Kontrola | Redundancja | Ops na Tobie | Koszt ~/TB/mc |
|---|---|---|---|---|---|
| **Hetzner Storage Box** | dyski w DC Hetznera, dostęp **SFTP/restic/borg/rclone** | widzisz pliki, standardowe narzędzia | RAID po stronie Hetznera | minimalny | **~10–15 zł** (€2,3–3,8) |
| **Hetzner/OVH dedyk + MinIO** | własny serwer z dyskami, **MinIO = S3 na Twoim sprzęcie**, erasure coding | pełna | erasure coding (przeżywa N awarii dysków) | średni | amortyzacja sprzętu, zwykle tanio/TB przy większej skali |
| **Kolokacja** | Twój sprzęt w profesjonalnym DC (prąd/chłodzenie/sieć/ochrona) | pełna | Ty robisz RAID + offsite | wysoki | capex + opłata za U/prąd |
| ~~Jeden dysk w domu/biurze~~ | — | pełna | **ZERO** | **niedopuszczalne** dla płatnego backupu | — |

### 4c. Osie oceny (nie tylko cena)

- **Zaufanie / kontrola** — czy widzisz i odtworzysz dane standardowym narzędziem.
- **Niezawodność / durability** — RAID/erasure + brak pojedynczego punktu awarii.
- **Złożoność API** — czy potrzeba bespoke sterownika (Swift) czy „just works" (S3/SFTP).
- **Ops burden** — ile sprzętu/serwisu babysittingu po Twojej stronie.
- **Odtwarzalność bez aplikacji** — czy da się odzyskać dane bez Waszego kodu (manifest!).
- **RODO / EU** — lokalizacja danych, DPA.
- **Skalowalność** — czy rośnie liniowo do TB wielu klientów bez przebudowy.

---

## 5. Rekomendacja

**5.1. Odejść od OVH Cloud Archive (Swift) jako live storage.** Powód operacyjny + zaufania (sekcja 1), nie cenowy.

**5.2. Wybrać prosty backend (S3-compatible LUB plikowy):**
- jeśli priorytetem jest **model object-storage + skala SaaS** → **Backblaze B2** (proste S3, brak min. retencji, tani egress).
- jeśli priorytetem jest **„własne dyski, którym ufam, widzę pliki"** → **Hetzner Storage Box** (zwykłe pliki, restic/borg, EU/RODO), z opcją późniejszego **dedyk + MinIO** przy wzroście.

**5.3. Zrobić 3-2-1 na DWÓCH niezależnych dostawcach.** To znosi „nie ufam jednemu dostawcy": np. **primary Hetzner Storage Box + offsite replikacja do Backblaze B2** (albo odwrotnie). Awaria/utrata zaufania do jednego ≠ utrata danych. To jest najmocniejsza odpowiedź na lęk Daniela.

**5.4. Niezależnie od backendu — domknąć „prawdziwą niezawodność" (sekcja 2):** backup metadanych PG + samoopisujący się manifest + cykliczny zweryfikowany restore.

> **Decyzja do podjęcia przez Daniela:** (a) primary backend: B2 czy Hetzner Storage Box?
> (b) offsite: drugi z tej dwójki? (c) czy MinIO-na-dedyku to cel docelowy przy skali?

---

## 6. Wpływ na resztę dokumentacji (jeśli propozycja przyjęta)

- `ovh-cloud-archive-migration-spec.md` → **superseded / under review** (banner dodany). HR-1/HR-2 (immutability, deletion=metadata-only) jako koncepcja zostają do rozstrzygnięcia razem z modelem retencji (patrz niżej); część Swift-specyficzna (segmenty, freeze, cutover OVH) staje się nieaktualna.
- `pricing-and-storage-economics.md` → koszt/TB do przeliczenia na wybrany backend (Opcja A — fizyczne bajty — pozostaje słuszna niezależnie od dostawcy). Dodatek A („Hetzner = pivot, FROZEN") **zdezaktualizowany** — backend jest teraz świadomie reotwierany.
- `master-tdd-plan.md` → `CloudStorageClient` zyskuje drugą realną implementację (S3/Fs); testy storage powinny iść przeciw interfejsowi, nie Swiftowi.
- **Decyzja modelu retencji (próg min, kasowanie sterowane retencją, HR-1/HR-7)** — wciąż otwarta; na prostym S3/plikowym backendzie realny `delete` jest trywialny (brak segment-hell), co dodatkowo ułatwia wprowadzenie retencji.

---

## 7. Status / następne kroki

1. Daniel wybiera primary + offsite (sekcja 5).
2. Po wyborze: zaktualizować `pricing-and-storage-economics.md` (koszt na nowym backendzie) i oznaczyć kierunek w `ovh-...-spec.md`.
3. Implementacja (osobne repo `buffer`): `S3Client`/`FsClient` jako `CloudStorageClient`, replikacja offsite, manifest + backup metadanych. **Poza zakresem tego repo (docs).**
