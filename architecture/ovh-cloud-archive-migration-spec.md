# OVH Cloud Archive — Migration & Live Storage Master Plan

Wersja: 1.1 (initial, pre-prod) — **2026-05-26: dodano sekcje 0 Hard Requirements (Daniel ack: immutable storage, FTP-style upload+list only)**
Repo glowne: `properbackup-buffer/.../ovh/`
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P1** (przed flipnieciem pierwszego prawdziwego klienta na live)

---

## 0. Hard Requirements (Immutable Rules) — PRAWO PROJEKTU

> **Te zasady sa NIENARUSZALNE. Wymuszone przez Daniela jako twardy contract dla OVH integracji. Kazde naruszenie = automatic rejection PR-a w review.**
>
> Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint` (sekcja 2.2 Storage Strategy — "immutable, append-only, deletion is metadata-only")

**HR-1. Storage Filozofia: TYLKO upload + list (zero DELETE)**
OvhSwiftClient / OvhFtpClient w produkcji obsluguje WYLACZNIE:
- `put(objectName, data)` — upload nowej paczki
- `list(prefix)` — listowanie istniejacych obiektow
- `get(objectName)` — odczyt (dla restore)
- `headObject(objectName)` — metadata only (dla integrity check)

**NIE WOLNO** wolac `delete()` w produkcji. Implementacja: `DevSafetyGuard.delete()` MUSI rzucic `SafetyException("Storage is immutable; deletion is metadata-only")` gdy `env=production`. W env=dev/test mock storage moze pozwalac DELETE dla testow czystki.

**HR-2. Klient widzi "deleted" jako metadata operation**
Gdy klient kliknie "Usun plik" w panelu lub przeniesie do "Kosza":
- Insert do `archive_snapshot` z `deleted_at=now()` (lub UPDATE)
- Aktualizacja `file_state` z `state='DELETED'`
- **Fizyczny obiekt na OVH ZOSTAJE niezmieniony**
- UI pokazuje "Plik usunieto 2026-05-24" + przycisk "Przywroc"
- Restore z OVH zawsze mozliwy (klient placi tylko egress)

**HR-3. Pack window 900-950MB (z buffera, NIE OVH-side)**
OVH NIE WIE o "pack window" — to jest kontrakt buffera. Cross-ref `buffer-core-master-spec.md` HR-2. Ale OVH MUSI akceptowac obiekty 900MB-950MB stabilnie. Test: upload 950MB blob -> success bez timeout, weryfikacja przez headObject.

**HR-4. FTP-Style Simulation w MockSwiftClient**
Mock storage uzywany w testach i dev MUSI symulowac FTP semantyki OVH Cloud Archive:
- `put(objectName, data)` — pisze do `mockDir/<container>/<objectName>` z atomic rename .tmp -> .final
- `list(prefix)` — listuje pliki w `mockDir` z matching prefix
- `delete()` — disabled w MockSafetyGuard (rzuca exception)
- Symulowane opoznienie >2s na put (OVH WAN latency)
- Symulowane okresowe 5xx (5% rate) dla testow circuit breaker

Mock jest **production-equivalent semantycznie** — to nie tylko local fs wrapper, to **simulator** OVH zachowania.

**HR-5. Integrity Verification po upload**
Po `ovh.put(objectName, data)`:
- Sprawdz `ovh.headObject(objectName).contentLength == expectedSize`
- Sprawdz ETag lub MD5 jezeli dostepne (OVH Swift zwraca ETag = md5)
- Jezeli mismatch -> retry put (max 3), potem alert `pb_ovh_integrity_failure`
- Insert do `archive_snapshot.upload_verified_at = now()` PO success

**HR-6. Object Naming — pseudonimizacja + lifecycle prefix**
Format (immutable po pierwszym release, do v2.0):
```
<userHash-8>/<serverHash-8>/<yearMonth>/<pack-uuid>.bin
```
- `userHash-8`: sha256(userId).substring(0,8) — RODO pseudonimizacja
- `serverHash-8`: sha256(serverId).substring(0,8)
- `yearMonth`: `2026-05` (UTC)
- `pack-uuid`: UUID v4

Naruszenie schematu = automatic rejection (kompatybilnosc backward z istniejacymi blobami).

**HR-7. Cold Tier Lifecycle (NIE delete, tylko transition)**
- Hot tier: ~0.03 PLN/GB/miesiac, instant retrieval
- Cold tier: ~0.01 PLN/GB/miesiac, retrieval ~3-5h
- Po 90 dniach hot -> auto-transition do cold (OVH lifecycle policy)
- Po 365 dniach cold -> **NIE DELETE**, zostaje archived (klient placi minimum cold storage)
- Klient moze zazadac restore z cold (cost-aware UI)

**HR-8. Cost Monitoring (krytyczne dla rentownosci)**
- Codzienny job `OvhCostFetcher` -> pobiera billing data z OVH API
- Zapis do `ovh_cost_daily` tabela (date, total_pln, storage_gb, egress_gb)
- Alert Slack jezeli `daily_pln > X` (default X=50 PLN/dzien, configurable)
- Alert critical jezeli `daily_pln > 2*30day_avg` (rapid spike)

**HR-9. Disaster Recovery z OVH (jezeli PostgreSQL padl)**
Implementacja `OvhRecoveryWalker`:
- Skanuje OVH list() przez wszystkich userHash prefixes
- Rebuilduje `archive_snapshot` table na podstawie naglowkow (HeaderFirstReader)
- Cross-ref `observability-and-dr-spec.md` sekcja 7 (DR procedure)
- Test: zniszcz PG dump, odzyskaj z OVH only -> verify integrity

**HR-10. Migration Weekend (mock -> live OVH)**
Migracja z `MockSwiftClient` na `OvhSwiftClient` to **dual-write window**:
1. Tydzien -1: dodaj OvhSwiftClient z mock secondary write (read still from mock)
2. Migration weekend: copy wszystkie istniejace `mockDir/*` -> OVH (przez `OvhMigrationCopyJob`)
3. Tydzien +1: flip primary read OVH, mock = secondary
4. Tydzien +2: usun mock primary (mock zostaje w testach only)

Cross-ref `buffer-core-master-spec.md` HR-3 (immutable) — migration NIE WOLNO usunac danych z mocka.

---

## 1. Cel dokumentu

Plan migracji warstwy storage z lokalnego mocku (`MockSwiftClient`) na produkcyjny **OVH Cloud Archive** (S3-compatible, OpenStack Swift API).

Dokument obejmuje:
- Konfiguracja kont OVH (klucze, container, lifecycle)
- Cost monitoring (alerty na przekroczenie budzetu)
- Cold tier strategy (hot 90d -> cold)
- Disaster recovery (odtworzenie wszystkich danych z OVH)
- Backupowanie kluczy OVH (zero-trust)
- Procedura migracji dla istniejacych testowych danych (jezeli sa)

Brat dokumentu `master-tdd-plan.md`, `agent-vps-master-spec.md`, `observability-and-dr-spec.md`.

### Zakres

- Wlaczenie produkcyjnego OVH dla **subset usere** (feature flag per user)
- Cleanup mocku (zostaje dla testow, **nie usuwac**)
- Procedura "migration weekend" (jak przewiezc istniejace dane z lokalnego storage na OVH)
- Lifecycle policy (hot/cold/delete)
- Cost alerts (Slack/SMS na spike >X GB/dzien)
- DR: jak zrestore'owac uzytkownika **tylko z OVH** gdy baza padla

### Co NIE jest w zakresie

- MinIO self-hosted (post-MVP, dla B2B Enterprise)
- AWS S3 jako alternatywa (post-MVP)
- Replikacja multi-region (post-MVP, OVH ma single-DC)
- BackBlaze B2 jako backup-of-backups (osobny doc, jezeli kiedykolwiek)

---

## 2. Mapowanie kodu

### 2.1 Stan obecny

| Klasa | Plik | Cel | Stan |
|-------|------|-----|------|
| `CloudStorageClient` | `ovh/CloudStorageClient.kt` | Generic interface (put/get/list/delete/exists) | Stabilny |
| `SwiftClient` | `ovh/SwiftClient.kt` | Konkretny interface dla OpenStack Swift | Stabilny |
| `MockSwiftClient` | `ovh/MockSwiftClient.kt` | Lokalny mock, pisze do `mockDir` | **Aktualnie uzywany w produkcji testowej** |
| `OvhSwiftClient` | `ovh/OvhSwiftClient.kt` | Real OVH client (Keystone auth) | **NIE jest aktywny** (brak credentials) |
| `DevSafetyGuard` | `ovh/DevSafetyGuard.kt` | Wrapper blokujacy destructive ops w env=dev | Stabilny |
| `SafetyException` | `ovh/SafetyException.kt` | Exception type | Stabilny |

### 2.2 Wlaczanie OvhSwiftClient

W `OvhSwiftClient.tryCreateFromEnv()` — sprawdz wymagane zmienne srodowiskowe (TODO przyszly agent sprawdz nazwy):
- `OVH_SWIFT_AUTH_URL`
- `OVH_SWIFT_USERNAME` (lub OS_USERNAME)
- `OVH_SWIFT_PASSWORD`
- `OVH_SWIFT_TENANT` (project ID)
- `OVH_SWIFT_REGION`
- `OVH_SWIFT_CONTAINER`

Jezeli wszystkie sa zdefiniowane: `tryCreateFromEnv()` zwraca instance.
Jezeli ktorakolwiek brak: zwraca null → fallback to `MockSwiftClient`.

### 2.3 Mapping flush -> OVH

`properbackup-buffer/.../flush/ChunkSealer.kt`:
- Po zapakowaniu chunkow do paczki (PackBuffer)
- Po szyfrowaniu
- Wola `CloudStorageClient.put(objectName, data)`

Czyli **jedna zmiana feature flag** w wyborze klienta (mock vs OVH) → calosc flush dziala identycznie.

### 2.4 Object naming convention

**TODO przyszly agent sprawdz** aktualne `objectName` format w `ChunkSealer.kt`.

Zalecany format:
```
<userId-hash-8>/<serverId-hash-8>/<year>/<month>/<chunk-uuid>.bin
```

Dlaczego:
- `userId-hash-8` (sha256 truncated): pseudonimizacja (RODO)
- `year/month`: lifecycle policy mozna ustawic per-prefix
- `chunk-uuid`: jednoznaczne, nie kolizja

**Decyzja: w aktualnym kodzie sprawdz** jak naming wyglada, jezeli inny - zostaw, ale udokumentuj.

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `MockSwiftClient.kt` — zostaje dla testow (CI nie ma OVH dostepu)
- `SafetyException.kt`
- `CloudStorageClient.kt` interface — semantyka stabilna
- `DevSafetyGuard.kt` — guard logic
- `ChunkSealer.kt` — flush flow (cross-ref `buffer-core-master-spec.md`)

### DOTYKAJ

- `OvhSwiftClient.kt` — dodaj brakujace features (multipart upload, presigned URLs)
- `BufferMain.kt` — wybor klienta na podstawie env (mock/ovh)
- `MetricsHandler.kt` — dodaj `pb_ovh_*` metryki
- `properbackup-stack/docker-compose.yml` — dodaj env vars dla OVH

### MOZESZ TWORZYC

- `OvhMultipartUploader.kt` — dla chunkow >5GB (segmenty Swift)
- `OvhCostTracker.kt` — agregacja bytes/req per dzien
- `OvhHealthCheck.kt` — periodic ping
- `OvhFallbackClient.kt` — dual-write (mock + ovh) podczas migracji
- Nowe testy *Test.kt
- Nowa tabela `ovh_object_metadata` (jezeli decyduje sie na dwujkowanie metadata: w PG + w object headers)
- `properbackup-stack/scripts/ovh-bootstrap.sh` (one-time setup: stwórz container, ustaw lifecycle)

---

## 4. Domain Model

### 4.1 Tier strategy

| Tier | OVH Service | Cena (PLN/GB/mies) | Dostep | Retencja default |
|------|-------------|-------------------|--------|------------------|
| **Hot** | Public Cloud Object Storage (Standard) | ~0.03 PLN | Natychmiast | 90 dni |
| **Cold** | Cloud Archive | ~0.01 PLN | 4-12h (rehydration) | 1 rok |
| **Frozen** | (planowane) | < 0.005 PLN | 24-48h | indefinite |

**Ceny SA przyklady — sprawdz aktualne na ovh.com/pl/public-cloud/cloud-archive/**

> ### ⚠️ KOREKTA (2026-06-05, decyzja Daniela) — jedziemy PŁASKI single-tier
>
> W praktyce **rezygnujemy z tieringu hot/cold/frozen.** OVH typowo ma jedną cenę;
> tańszy cold (~20% taniej) **nie jest wart** dodatkowej złożoności (lifecycle policy,
> rehydratacja 4–12h, ryzyko awarii w cutoverze) względem oszczędności.
>
> **Stawka robocza:** `0,009636 PLN netto/GiB/mc` (≈ 12,1 zł brutto/TB/mc) — jedna,
> płaska, niezależnie od wieku obiektu. Zapis (ingest) `0,04 PLN netto/GiB` jednorazowo.
>
> Tabela hot/cold/frozen powyżej jest **teoretyczna / superseded** — zostaje jako
> kontekst, ale model kosztowy i `OvhCostFetcher` liczą płaską stawkę.
> Pełna analiza: `pricing-and-storage-economics.md`.

**Lifecycle policy:**
- Plik > 90 dni bez restore -> tier transition `hot -> cold`
- Plik > 1 rok bez restore -> `cold -> frozen` (lub planowany delete dla wygaslych userow)

### 4.2 Per-user storage cap

Z biznesplanu:
- Hobby: 100 GB
- Pro: 1 TB

**StorageQuotaGuard** (juz istnieje) blokuje upload jezeli `current_used_bytes + new_chunk_bytes > plan_cap`.

**Decyzja:** Cap jest **per user**, nie per server. Klient z planem Hobby ma 100 GB dla wszystkich swoich VPS razem.

### 4.3 Restore lifecycle

Z cold/frozen tier:
1. UI: klient klika "Restore"
2. Backend: GET object → 202 Accepted, body "rehydrating", X-Restore-Status: in-progress
3. Backend wystawia `restore_request` tabela: status=pending, eta_at=now+4h
4. UI pokazuje progress bar z eta
5. Co X min backend cron sprawdza status w OVH (`HEAD object`)
6. Gdy OVH potwierdza: status=ready, SSE notify klient
7. Klient downloaduje (3 dni okno przed retransition)

**Pliki:**
- NEW: `properbackup-buffer/.../ovh/RestoreOrchestrator.kt`
- NEW: tabela `restore_request`
- DOTYKAJ: `properbackup-web/.../recovery/RecoveryWizard.jsx`

### 4.4 Cost model

**Czynnnki kosztow:**
1. Storage (GB-month)
2. Operations: PUT, GET, LIST, DELETE (per 1000 ops)
3. Egress (downloads, GB)
4. Rehydration z cold (per GB)

**Worst-case scenariusz:** klient robi 1TB backup, ale nie restoruje. Wtedy:
- 1TB Hot = ~30 PLN/mies
- Po 90 dniach -> Cold = ~10 PLN/mies
- Po 1 roku -> Frozen = ~5 PLN/mies

Klient placi 19 PLN/mies Hobby (na 100 GB) → margin ujemny jezeli klient utrzymuje pelnie 100 GB. Dlatego:
- **Limit 100 GB Hobby** wymaga zeby sredni klient nie wykorzystywal pelni
- **W biznesplanie sredni klient ma 30-50 GB** → margin pozytywny

> ### ⚠️ KOREKTA (2026-06-05) — założenie „średni klient 30–50 GB" NIE trzyma się dla niszy MC
>
> Założenie powyżej jest **obalone** dla realnego segmentu (serwery Minecraft z mapami
> 700 GB+, codzienny churn regionów). Dla takiego klienta storage NIE jest groszowy —
> jest dominującym kosztem. Dodatkowo **immutability (HR-1) sprawia, że FIZYCZNIE
> zajęte miejsce rośnie wiecznie** (każda wersja zostaje), nawet gdy „bieżące" dane
> stoją w miejscu. Rentowność zależy od tego, **czy quota i cena liczą się od
> fizycznych bajtów z historią (Opcja A) czy od logicznego bieżącego rozmiaru (Opcja B)** —
> przy płaskiej stawce Opcja B to ścieżka straty. Pełna analiza + liczby:
> **`pricing-and-storage-economics.md`**. Decyzja: Dodatek F → **D-5** w `master-tdd-plan.md`.

**Implementacja monitoringu:** `[OVH-D1]` (sekcja 5).

---

## 5. Test Groups

Numerowanie `[OVH-Xn]`.

### Grupa A: Konfiguracja i bootstrap

#### `[OVH-A1]` Bootstrap container

**Cel:** Skrypt `ovh-bootstrap.sh` tworzy:
- Container `properbackup-prod`
- Lifecycle policy (90d hot → cold, 1y cold → delete)
- ACL: brak public read
- Versioning: OFF (chunki immutable)

**Plik:** `properbackup-stack/scripts/ovh-bootstrap.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

source /etc/pb/ovh.env  # OVH_SWIFT_*

swift -V 3 -A "$OVH_SWIFT_AUTH_URL/auth/tokens" \
      --os-username "$OVH_SWIFT_USERNAME" \
      --os-password "$OVH_SWIFT_PASSWORD" \
      --os-project-id "$OVH_SWIFT_TENANT" \
      post properbackup-prod \
      --read-acl '.r:-*' \
      --write-acl '*:*'
# ... etc
```

**DoD:**
- Skrypt idempotent (drugi run nie failuje)
- Po runu: `swift list` pokazuje container
- ACL: `curl -I https://...properbackup-prod/foo.bin` zwraca 401 (nie 200)

#### `[OVH-A2]` Feature flag per user

**Cel:** Dodaj kolumne `users.storage_backend` z wartoscia `mock` / `ovh-prod`.

**Implementacja:**
1. Dodaj kolumna w `schema.sql`: `storage_backend VARCHAR(20) DEFAULT 'mock'`
2. `BufferMain.kt`: route'y storage rozszerz o context — wybor klienta na podstawie `users.storage_backend`
3. Admin UI: panel admina ze switchem per-user (manual flip)

**Po co per-user:** Migration weekend → flipnij userow batch-by-batch (kontrola blast radius).

**DoD:**
- Test: user A na `mock`, user B na `ovh-prod`, kazdy idzie do swojego klienta
- Test: admin switch wykonany w trakcie aktywnego uploadu → nowy chunk idzie na nowy backend, stary chunk gdzie byl

#### `[OVH-A3]` Healthcheck OVH endpoint

Cel: `/health/detailed` (z `observability-and-dr-spec.md` `[OBS-A2]`) sprawdza OVH dostepnosc.

**Pliki:**
- NEW: `OvhHealthCheck.kt` — `HEAD /v1/AUTH_xxx/properbackup-prod`
- DOTYKAJ: `HealthHandler.kt` — wlocz check

**DoD:**
- Test: OVH up -> health ok
- Test: timeout 5s na ping (nie blokuje innych healthcheckow)

### Grupa B: Upload

#### `[OVH-B1]` Single PUT < 5 GB

**Cel:** Chunki <5 GB ladowane jednym PUT.

**Implementacja:** Juz w `OvhSwiftClient.put()`. **Sprawdz** czy retry z exp backoff jest tam.

**DoD:**
- Test integracyjny z prawdziwym OVH staging (separate container `properbackup-staging`)
- Test "OVH 503": retry 3x, sukces na 4-tej
- Test "OVH 500 trwale": po 5 retry → throw, alert metric `pb_ovh_api_errors_total`

#### `[OVH-B2]` Multipart upload >5 GB

**Cel:** Chunki >5 GB (raczej teoretyczne, bo pack limit = 950MB, ale dla bezpieczenstwa).

**Implementacja Swift:** Dynamic Large Object (DLO) lub Static Large Object (SLO):
1. Upload segments: `PUT /container/segments/{uuid}/000001`, `000002`, ...
2. Po wszystkich: `PUT /container/{name}` z manifestem `?multipart-manifest=put`

**Pliki:** NEW `OvhMultipartUploader.kt`

**DoD:**
- Test upload 6GB (mock data, zero contents) → success
- Test "fail w sredku segment 5/10": retry tego segmentu, kontynuacja
- Test "manifest failure": cleanup orphan segments

#### `[OVH-B3]` Idempotency w PUT

**Cel:** Powtorny PUT tego samego objectName z innym contentem → konflikt? Ostatni wygrywa?

**Decyzja:**
- OVH default: ostatni wygrywa (overwrite)
- **Nasze wymaganie:** chunki sa **immutable**. PUT tego samego objectName drugi raz → ignoruj (returning existing ETag)

**Implementacja:** Przed PUT `HEAD` → jezeli istnieje i sha matches → skip. Jezeli istnieje ale sha nie matches → log warning, ALERT (mozliwy korupcja).

**DoD:**
- Test: PUT chunk twice → 1 actual upload, 1 skip
- Test: PUT chunk z innym sha → odmowa + alert

### Grupa C: Download / Restore

#### `[OVH-C1]` GET object

**Cel:** Pobranie pojedynczego chunka.

**Pliki:** `OvhSwiftClient.get()` — istnieje, sprawdz semantyke.

**DoD:**
- Test "object exists" → 200, content matches what was put
- Test "object not exists" → throw `ObjectNotFound`
- Test "OVH 503": retry

#### `[OVH-C2]` Restore z cold tier

**Cel:** Klient zada plik ktory jest w cold/frozen.

**Implementacja:**
1. Try GET → OVH zwraca 503 "object archived"
2. POST temp-url restore request → OVH zaczyna rehydration
3. Insert `restore_request` w PG
4. Cron co 5min sprawdza HEAD object → gdy 200, mark ready, SSE notify
5. Klient downloaduje w okreslonym oknie (3 dni)
6. Po 3 dniach OVH automatycznie wraca do cold

**Pliki:** NEW `RestoreOrchestrator.kt`

**DoD:**
- Test "restore z cold": symulacja OVH cold odpowiedz → cron polluje → user dostaje notify
- Test "restore expiry": po 3d cron flaguje `restore_request` jako expired
- Test "double restore request": idempotent (drugi req na ten sam object → reuse pending)

#### `[OVH-C3]` Bulk restore

Klient chce 1-Click Restore całego folderu. Backend musi rehydrate `N` chunkow rownolegle.

**Wymagania:**
- Throttling: max 10 rownoleglych restore requests per user
- UI progress bar (SSE)
- Eta computed: `eta = max(per-chunk-eta)`

### Grupa D: Cost Monitoring

#### `[OVH-D1]` Spend alert daily

**Cel:** Codziennie 09:00 cron liczy:
- Total bytes uploaded yesterday
- Total bytes stored (snapshot)
- Estymowany koszt = (storage_gb * tier_price + ops * ops_price + egress * egress_price)

**Alerty:**
- Daily upload > 100 GB → Slack warning
- Daily upload > 500 GB → Slack alert
- Monthly est cost > 1000 PLN → SMS

**Pliki:**
- NEW: `properbackup-stack/scripts/ovh-cost-report.sh`
- NEW: `OvhCostTracker.kt` (agregacja w metrykach)

**DoD:**
- Test z mock metrykami → alert wysyla sie poprawnie
- Daily digest w `[OBS-D3]` zawiera linię "OVH spend: X PLN"

#### `[OVH-D2]` Per-user cost attribution

**Cel:** Wiemy ile zlotych kosztuje **konkretny user** w OVH.

**Implementacja:** `agent_metrics` extension lub nowa tabela `user_storage_daily`:
```sql
CREATE TABLE user_storage_daily (
  date DATE,
  user_id UUID,
  bytes_stored BIGINT,
  bytes_uploaded BIGINT,
  bytes_downloaded BIGINT,
  est_cost_pln NUMERIC(10,4),
  PRIMARY KEY (date, user_id)
);
```

Codzienny cron pisze rekord per-user.

**Po co:** B2B billing z metered storage (post-MVP), wykrywanie abuserow.

**DoD:**
- Test: po 7 dniach widzimy 7 rekordow per active user
- Test: koszt zgadza sie z fakturą OVH (manual reconciliation raz na mies)

#### `[OVH-D3]` Spike detection

**Cel:** Klient uploaduje 100 GB w 1h (atak / klop). Auto-block.

**Heurystyka:**
- Per-user `bytes_uploaded_last_1h > 50 GB` → soft block (StorageQuotaGuard returns 429)
- Per-user `bytes_uploaded_last_1d > 200 GB` → hard block, alert admin
- Whitelist (admin overridable per user, dla B2B Enterprise)

**Pliki:**
- DOTYKAJ: `StorageQuotaGuard.kt` (dodaj velocity check)

**DoD:**
- Test: user uploaduje 60 GB w 1h → 4. upload zwraca 429
- Test: admin whitelist → user moze uploadowac dalej

### Grupa E: Disaster Recovery

#### `[OVH-E1]` Restore wszystkich danych z OVH gdy baza padla

**Cel:** Jezeli `users` i `archive_snapshot` tables sa kompletnie utracone (PG dies, GPG key lost), MOZE-li klient odzyskac swoje pliki tylko z OVH?

**Aktualne ryzyko:** **NIE**. Nazwa objektu w OVH jest UUID — bez metadata w PG nie wiemy:
- Czyj jest chunk
- Co jest w srodku (jaki path)
- Jak go zdeszyfrowac (klucz w `users` table)

**Rozwiazanie:**
1. **Object metadata embedded:** kazdy PUT z X-Object-Meta headers:
   - `X-Object-Meta-User-Hash: sha256(userId)`
   - `X-Object-Meta-Server-Hash: sha256(serverId)`
   - `X-Object-Meta-Original-Path-Hash: sha256(pathId)`
   - `X-Object-Meta-Created-At: <iso>`
   - `X-Object-Meta-Pack-Manifest: <encrypted bytes of pack manifest, max 4KB>`
2. **Recovery procedure:**
   - Klient kontaktuje support
   - Identyfikuje sie email + hashlock (TOTP) → recovery token
   - Support uruchamia `OvhRecoveryWalker` ktory:
     - List wszystkich objektow w container
     - Filter po `X-Object-Meta-User-Hash = sha256(klient.userId)`
     - Pobierz manifesty, odszyfruj klient-side
     - User dostaje katalog `recovery-2026-05-26/` z metadanymi
3. **Klucz szyfrujacy:** Tu jest klop. Klucz jest w `users.encryption_password` (lub derived) — utracony razem z baza.
   - **Decyzja:** klucz musi byc tez **escrowed** (kopia szyfrowana master-key na OVH)
   - Master key trzymany w Daniela 1Password (NIGDY w bazie)
   - W recovery: user provides email -> support odszyfrowuje user encryption key z master key -> user przekazuje plaintext w secure channel

**Pliki:**
- NEW: `OvhRecoveryWalker.kt` (admin-only)
- DOTYKAJ: `ChunkSealer.kt` — embed metadata przy putcie
- NEW: tabela `recovery_token` (one-time, 24h ttl)

**DoD:**
- Drill: full DR scenario na staging — baza zdroped, restore z OVH dziala
- Test "user nie ma master-key escrow" → 404, manual support intervention
- Test "atak: ktos zna email innego usera" → recovery wymaga TOTP / email confirm

#### `[OVH-E2]` Periodic verify

**Cel:** Cron co tydzien wybiera losowy chunk z `archive_snapshot`, sprawdza:
- Object istnieje w OVH (`HEAD`)
- Object size matches
- Object sha256 matches (full download na sample 1% chunkow)

**Pliki:**
- DOTYKAJ: `verify/RestoreVerifier.kt` (juz istnieje, **sprawdz** semantyke)
- Cross-ref `buffer-core-master-spec.md`

**DoD:**
- Tygodniowy raport: "OVH integrity: 100% (sample 47/47 chunks verified)"
- Alert jezeli >0.01% fail rate

### Grupa F: Migration weekend

#### `[OVH-F1]` Pre-migration dry run

**Cel:** Wszystkie chunki w mocku sa **upload-walidowalne** na OVH (sumiarnie pisac nie kasujac).

**Procedura:**
1. Wlocz dual-write mode: `OvhFallbackClient.put()` pisze do **both** mock + OVH
2. Drain queue: wszystkie nowe chunki ladaja na OBA backendy
3. Backfill: skrypt iteruje przez `archive_snapshot`, dla kazdego brak-w-OVH wykonuje upload
4. Verify: dla kazdego chunka HEAD OVH + HEAD mock, porownaj size

**Pliki:**
- NEW: `OvhFallbackClient.kt`
- NEW: `properbackup-stack/scripts/ovh-backfill.sh`

**DoD:**
- Po backfill: 100% mocku jest na OVH
- Verify report: 0 missing, 0 mismatch

#### `[OVH-F2]` Cutover

**Cel:** Flipnij `users.storage_backend` z `mock` -> `ovh-prod` batchami.

**Procedura:**
1. Cohort 1: 10 testowych userow
2. Wait 24h, sprawdz brak errors
3. Cohort 2: 50 userow
4. Wait 24h
5. Cohort 3: wszyscy

**Po cutover:** mock zostaje **read-only** (kasujemy po 30 dniach jezeli zero issues).

#### `[OVH-F3]` Rollback plan

**Cel:** Jezeli OVH ma problem → flip back na mock.

**Procedura:**
1. UPDATE users SET storage_backend = 'mock' WHERE storage_backend = 'ovh-prod' AND ...
2. Nowe chunki ladaja na mock
3. Stare chunki nadal na OVH → reads do nich nadal dzialaja
4. Po stabilizacji: backfill nowych chunkow na OVH, repeat cutover

**DoD:**
- Procedura w `properbackup-docs/operations/runbook-ovh-rollback.md`
- Manual drill: flip → upload → flip back → restore (test ze cykl jest non-destructive)

---

## 6. Edge Cases (15+)

### 6.1 OVH credentials w gicie (oops)

Klucze OVH w `.env` przypadkiem wrzucone do gita.

**Wymagane:** 
- `.gitignore` ma `.env`, `**/*.env`, `secrets/`
- Pre-commit hook (`trufflehog`) skanuje na sekrety
- Jezeli zdarzy sie: rotacja w OVH dashboardzie + revoke starych

### 6.2 Container public przypadkiem

ACL ustawiony zle, ktos znalazl URL.

**Wymagane:**
- `[OVH-A1]` testem sprawdza `curl -I` zwraca 401
- Nightly cron sprawdza ACL ustawienia (regression test)
- Naciaganie URL (recon attack) → log alert

### 6.3 OVH region failure

OVH GRA datacenter ma problem.

**Wymagane:**
- Aktualne: single-DC (post-MVP multi-region)
- Status page komunikuje
- Klient czeka na OVH recovery

### 6.4 Chunk overwritten by attacker

Atakujacy z dostępem do buffera wysyla PUT z różnym contentem (mismatch sha).

**Wymagane:**
- `[OVH-B3]` blokuje overwrites z innym sha
- Alert: "Object overwrite blocked: {objectName}"

### 6.5 Lifecycle policy zafire'owany w trakcie active restore

Plik byl restore'owany z cold, ale policy juz spakowala go back. Race.

**Wymagane:**
- Lifecycle policy "minimum retention 7 days w hot" po rehydration (OVH może wspierać `restore-period` parameter)
- Alternatywnie: aplikacyjny lock w PG — `restore_request` zapobiega cron lifecycle

### 6.6 Egress charges spike

Klient masowo restore'uje 1TB → egress moze byc drogi.

**Wymagane:**
- Per-user egress limit (np. 500 GB/mies dla Hobby) 
- Spike alert `[OVH-D3]`
- Throttle na 100 Mbps download per user

### 6.7 Object name kolizja (UUID v4 jednak)

Praktycznie niemozliwe (2^122), ale...

**Wymagane:**
- `[OVH-B3]` HEAD before PUT — jezeli istnieje, regenerate UUID, retry
- Log alert (potwierdza ze cos sie dzieje)

### 6.8 OVH zmiana cen

OVH podnosi ceny x2.

**Wymagane:**
- Cost model w dokumentacji aktualizowany kwartalnie
- Plan B: MinIO self-hosted, BackBlaze B2 (post-MVP alternatywy)
- Klient SLA przewiduje "OVH price change → ProperBackup może zmienić plany ceny z 60d wyprzedzeniem"

### 6.9 GDPR data deletion request

User zada `art. 17 RODO` — "right to be forgotten".

**Wymagane:**
- Skrypt `gdpr-delete-user.sh`:
  - List wszystkie objects per `X-Object-Meta-User-Hash`
  - DELETE z OVH
  - DELETE z PG (cascade)
  - Audit log: who, when, why
- Cross-ref `crypto-and-compliance-spec.md`

### 6.10 Object 0 bytes (corruption)

PUT bez body zaakceptowany, plik 0 bytes w OVH.

**Wymagane:**
- Pre-PUT walidacja: `data.size > 0`
- Post-PUT walidacja: `HEAD object → Content-Length == data.size`

### 6.11 OVH downtime w trakcie webhooka

Stripe webhook trigger flush (wątpliwy), OVH down, flush failuje.

**Wymagane:**
- Webhook NIE blokuje na flush
- Flush jest **asynchronous** (queue)
- OVH down → flush retry queue rosnie, alert

### 6.12 SSL certyfikat OVH wygasl

Java client throws SSL exception.

**Wymagane:**
- Retry z exp backoff
- Alert "OVH SSL error" → manual investigation
- Procedura: wybierz alternatywny endpoint OVH (multi-endpoint config)

### 6.13 Disk pelny na bufferze przed flush

Chunk czeka w inbox, lokalny disk pelny.

**Wymagane:**
- Cross-ref `buffer-core-master-spec.md` `[BUF-C2]` disk full
- Flush bardziej agresywny (rozne strategy w `FlushTrigger`)

### 6.14 OVH API rate limit

429 z OVH.

**Wymagane:**
- Retry z exp backoff (juz w OvhSwiftClient.put?)
- Token bucket lokalny — limit our requests do np. 100 req/s

### 6.15 Migration backfill w trakcie dnia (heavy load)

Backfill iteruje przez 100K obiektow → spike na OVH, slow down dla normalnych userow.

**Wymagane:**
- Backfill priorytet `nice -n 19`, max 10 req/s
- Per-night execution (02:00-05:00 only)
- Pause flag w PG (admin może zatrzymac)

---

## 7. Definition of Done

10 kryteriow (identyczne):

1. Red test first
2. Test integracyjny z **prawdziwy OVH staging container** (separate od prod)
3. Brak credentials w kodzie/gicie/logach
4. Sekrety w env vars + 1Password backup
5. DOTYKAJ zone respected
6. Docs updated
7. Smoke test na test serverze
8. Idempotent
9. Cost impact assessment w PR description
10. Rollback plan w PR

---

## 8. Sequence of work

1. **`[OVH-A1]` Bootstrap container w staging OVH** — bez tego nic nie zrobimy
2. **`[OVH-A3]` Healthcheck** — minimum monitoring
3. **`[OVH-B1]` Single PUT poprawnie** — fundament
4. **`[OVH-B3]` Idempotency w PUT** — immutability
5. **`[OVH-C1]` GET object** — fundament restore
6. **`[OVH-A2]` Feature flag per-user** — kontrola blast radius migracji
7. **`[OVH-F1]` Pre-migration dry run mode** — sprawdzic czy daje rade
8. **`[OVH-D1]` Cost monitoring alerts** — bez tego ryzyko bankructwa
9. **`[OVH-E1]` DR recovery procedure** — bez tego prawdziwy live to nieodpowiedzialnosc
10. **`[OVH-C2]` Cold tier restore** — UX dla starszych backupow
11. **`[OVH-F2]` Cutover migration weekend** — flip prod users
12. **`[OVH-F3]` Rollback plan** — bezpiecznik
13. **`[OVH-D2]` Per-user cost attribution** — pre-launch business analytics
14. **`[OVH-D3]` Spike detection** — abuse prevention
15. **`[OVH-B2]` Multipart >5GB** — bezpiecznik (pack limit 950MB rzadko przekraczany)
16. **`[OVH-E2]` Periodic verify** — long-term integrity

---

## 9. Go/No-Go checklist

- [ ] OVH staging container utworzony, ACL OK
- [ ] OVH prod container utworzony, ACL OK
- [ ] `OvhSwiftClient.tryCreateFromEnv()` zwraca instance gdy env set
- [ ] Pierwszy upload na prod udany (test chunk)
- [ ] Restore tego test chunka udany
- [ ] Lifecycle policy 90d -> cold ustawione
- [ ] Cost alert configurowany (Slack)
- [ ] Daily cost report uruchomiony i wpada do Slack
- [ ] DR recovery walker zaimplementowany + manual drill udany
- [ ] Master key (escrow) w 1Password z aliasem
- [ ] Feature flag `users.storage_backend` zaimplementowany
- [ ] Cohort 1 (10 userow testowych) migrowani, brak errors po 24h
- [ ] Rollback procedura przetestowana (flip back działa)
- [ ] Object metadata (`X-Object-Meta-*`) jest embedowane na wszystkich nowych chunkach
- [ ] Per-user storage cap (StorageQuotaGuard) działa z OVH backend
- [ ] Spike detection (60 GB / 1h) odpowiednio blokuje
- [ ] OVH SLA przeczytany (jaka availability OVH gwarantuje) i wpisany w nasze SLA klientow

---

## Dodatek A — Wskazowki configuration

### .env.prod (przyklad)

```bash
# OVH Public Cloud Object Storage
OVH_SWIFT_AUTH_URL=https://auth.cloud.ovh.net/v3
OVH_SWIFT_USERNAME=user-xxx-yyy
OVH_SWIFT_PASSWORD=<...>
OVH_SWIFT_TENANT=<project-id-uuid>
OVH_SWIFT_REGION=GRA
OVH_SWIFT_CONTAINER=properbackup-prod

# Cost monitoring
PB_OVH_DAILY_UPLOAD_WARN_GB=100
PB_OVH_DAILY_UPLOAD_ALERT_GB=500
PB_OVH_MONTHLY_COST_ALERT_PLN=1000

# Lifecycle
PB_OVH_HOT_RETENTION_DAYS=90
PB_OVH_COLD_RETENTION_DAYS=365
```

## Dodatek B — Stripe & OVH cost reconciliation

Per-user revenue/cost calculation:
```
Klient Hobby: 19 PLN / mies
Stripe fee: ~0.30 PLN (1.4% + 0.25 EUR)
VAT 23%: -3.55 PLN
Net rev: ~15.15 PLN

OVH cost (avg 40 GB Hobby user):
  Hot (90d): 40 GB * 0.03 PLN = 1.20 PLN/mies
  Cold (>90d): 40 GB * 0.01 PLN = 0.40 PLN/mies
  Ops + egress: ~0.10 PLN

Server / VPS cost: ~0.50 PLN per user (shared 100 users on 1 VPS)
Email / Slack / Better Stack: ~0.10 PLN per user

Net margin Hobby: ~13 PLN/user/mies (~85%)
```

(Detal: `Biznesplan_ProperBackup_v6.2_NAJLEPSZY.docx`)

## Dodatek C — Linki

- `master-tdd-plan.md` — billing
- `agent-vps-master-spec.md` — agent (klient OVH)
- `observability-and-dr-spec.md` — monitoring + DR
- `buffer-core-master-spec.md` — flush flow do OVH
- `crypto-and-compliance-spec.md` — RODO data deletion
- OVH docs: https://docs.ovh.com/pl/storage/

## Dodatek D — Glosariusz

- **Hot tier** — Standard Object Storage, instant access
- **Cold tier** — Cloud Archive, 4-12h rehydration
- **Frozen** — Glacier-tier, 24-48h rehydration (post-MVP planowany)
- **Rehydration** — proces przywrocenia obiektu z cold do hot
- **DLO/SLO** — Dynamic/Static Large Object (Swift terminology for multipart)
- **Keystone** — OpenStack identity service (OVH uses for auth)
- **Egress** — outbound traffic, OVH liczy oddzielnie od storage
- **Backfill** — historic data migration to new backend
- **Cutover** — moment flipnięcia feature flag z mock na ovh

---

## Dodatek E — LLD: asynchroniczny restore (odpowiedź na audyt ryzyka #2)

> **Kontekst audytu:** „AI pisząc logikę restore może potraktować Cold Archive jak
> szybki dysk (S3 Standard) i kod wywali timeout przy natychmiastowym pobraniu."
> Ta sekcja czyni asynchroniczność **wymuszoną przez typy i kontrakt API** — nie
> da się napisać synchronicznego restore z cold, bo `get()` zwraca stan, nie bajty.

### E.1 Typowany kontrakt storage (asynchroniczność wbudowana w API)

```kotlin
sealed interface RestoreState {
    data class Ready(val bytes: ByteArray) : RestoreState        // hot tier — natychmiast
    data class Rehydrating(val etaAt: Instant) : RestoreState    // cold/frozen — czekaj
    data object NotFound : RestoreState
}

interface ArchiveRetriever {
    /** NIGDY nie blokuje na godziny. Cold tier => Rehydrating(eta), nie wyjątek/timeout. */
    fun requestObject(objectName: String): RestoreState
    fun pollObject(objectName: String): RestoreState             // wołane przez cron
}
```

> **Niezmiennik O-1:** Warstwa biznesowa NIE woła „pobierz bajty teraz". Woła
> `requestObject` → jeśli `Rehydrating`, zapisuje `restore_request` i zwraca
> `202`. Bajty pobiera dopiero gdy `pollObject` → `Ready`. Brak ścieżki kodu,
> która zakłada synchroniczny odczyt z cold.

### E.2 `RestoreOrchestrator` — sygnatury

```kotlin
class RestoreOrchestrator(private val retriever: ArchiveRetriever, private val sse: SseBroadcaster) {
    /** Idempotentny po (userId, objectName): drugi request reużywa pending. */
    fun requestRestore(userId: String, objectName: String): RestoreRequest
    /** Cron co ~5 min: HEAD object, aktualizuje status, SSE notify gdy ready. */
    fun pollPending()
    /** Bulk (1-Click folder): max 10 równoległych rehydracji per user (throttle). */
    fun requestBulk(userId: String, objectNames: List<String>): List<RestoreRequest>
}
```

### E.3 DDL `restore_request`

```sql
CREATE TABLE IF NOT EXISTS restore_request (
    id            BIGSERIAL PRIMARY KEY,
    user_id       VARCHAR(36) NOT NULL,
    object_name   VARCHAR(256) NOT NULL,
    status        VARCHAR(16) NOT NULL DEFAULT 'pending',  -- pending | ready | expired | failed
    eta_at        TIMESTAMPTZ,                              -- now() + ~4h (cold)
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    ready_at      TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ                               -- ready_at + 3 dni (okno downloadu)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_restore_pending
    ON restore_request(user_id, object_name) WHERE status = 'pending';  -- idempotencja
```

### E.4 Kontrakt HTTP restore

| Endpoint | Sukces (hot) | Sukces (cold) | Polling |
|----------|--------------|---------------|---------|
| `POST /restore` `{objectName}` | `200 {url}` (presigned) | `202 {restoreId, etaAt, status:"rehydrating"}` | klient/UI poll `GET /restore/{id}` |
| `GET /restore/{id}` | `200 {status:"ready", url}` | `200 {status:"pending", etaAt}` | po `ready` → download |

### E.5 Edge cases (uzupełnienie LLD)

| Sytuacja | Reguła |
|----------|--------|
| Podwójny request tego samego obiektu | idempotencja: reużyj `pending` (uq index) |
| Lifecycle re-pakuje obiekt w trakcie restore | aplikacyjny lock przez `restore_request` blokuje retransition (patrz §6.5); ew. OVH `restore-period` |
| Rehydracja nie kończy się w 7 dni | cron flaguje `expired`, SSE notify „retry"; patrz `user-facing-recovery-spec.md` §6.5 |
| Bulk > 10 obiektów | kolejka, max 10 równoległych per user (egress/throttle) |

### E.6 Cross-references

- `buffer-core-master-spec.md` C.2/B-5 — `CloudStorageClient.get()` może być async.
- `user-facing-recovery-spec.md` — stan `THAWING`, ThawProgress UI, timeouty 8h/7d.
- `observability-and-dr-spec.md` — alert na zaległe `restore_request`.
