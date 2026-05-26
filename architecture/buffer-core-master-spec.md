# Buffer Core (non-billing) — Master Plan

Wersja: 1.1 (initial, pre-prod) — **2026-05-26: dodano sekcje 0 Hard Requirements (Daniel ack)**
Repo: `properbackup-buffer` (poza modulami billing/subscription/payment, ktore są w `master-tdd-plan.md`)
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P1**

---

## 0. Hard Requirements (Immutable Rules) — PRAWO PROJEKTU

> **Te zasady sa NIENARUSZALNE. Wymuszone przez Daniela jako twardy contract dla buffera. Kazde naruszenie = automatic rejection PR-a w review.**
>
> Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint` (sekcja 2.1 Master Blueprint — buffer jako write-ahead persistent + immutable storage)

**HR-1. Persistent-First (zero RAM-only)**
Kazdy bajt klienta wpadajacy do buffera MUSI byc natychmiast utrwalony na dysku (write-ahead persistence). Nie wolno trzymac danych klienta wylacznie w RAM-ie nawet na chwilowy bufor. Powod: crash JVM = utrata danych klienta. Implementacja: `InboxReceiver` zapisuje do `.tmp` -> `fsync` -> `rename` (atomic). Audit log INSERT po commit, nie przed.

**HR-2. Strict pack window 900-950MB (twardy minimum + twardy maksimum)**
Pack assembler w `flush/PackBuffer.kt` musi przestrzegac:
- **Minimum strict:** czekaj az nazbiera sie **≥900MB** danych zaszyfrowanych przed flush (zapobiega kosztownym malym packom na OVH).
- **Maksimum strict:** **≤950MB** po szyfrowaniu (powyzej tego = error, force-flush wczesniej).
- **Buffer min/max nigdy nie odwracane** — nie pakuj 850MB "bo siedzi za dlugo" bez force-flush logic (HR-7).
PACK_MIN_BYTES = 900L * 1024 * 1024, PACK_MAX_BYTES = 950L * 1024 * 1024.

**HR-3. Immutable Storage Strategy (OVH = upload + list TYLKO)**
Buffer NIE WOLNO wolac OVH `.delete(...)` w zadnej scieczce kodu produkcyjnego. CloudStorageClient.delete() w `DevSafetyGuard` MUSI rzucic `SafetyException` w env=production. Klient widzi "deleted" na osi czasu (UI) — to jest **tylko zmiana statusu w bazie**, fizyczny blob na OVH **nie znika nigdy** (do future restore). Cross-ref: `ovh-cloud-archive-migration-spec.md` HR-3.

**HR-4. Test-Driven Development obowiazkowe**
Kazda zmiana w `inbox/`, `flush/`, `verify/` MUSI byc poprzedzona **red testem** (Testcontainers PostgreSQL — nie H2). Bez red testu = automatic rejection. Cel: 100% coverage critical paths (write-ahead, pack assembly, sealing, restore verify).

**HR-5. Restart Resilience (crash w trakcie pisania do bufora)**
Kazdy upload chunka musi byc atomic: `.tmp` -> rename -> commit. Po `kill -9` w polowie pisania:
- Plik `.tmp` zostaje, plik `.final` nie istnieje
- Restart bufora znajduje `.tmp` i albo: (a) wznawia jezeli ma full body (sprawdz sha256), albo (b) deletes (incomplete).
- Test integracyjny: `BufferCrashRecoveryTest` z kill -9 mid-write.

**HR-6. Integrity Verification (sha256 przed kazdym przejsciem stanu)**
- Inbox chunk: sha256 sprawdzany przy odbiorze (Content-SHA256 header) i ponownie przy seal (przed encryption).
- Pack: sha256 calego pack-pliku zapisany w `buffer_pack.pack_sha256`, sprawdzany przed OVH put.
- Po OVH put: weryfikacja przez `OvhSwiftClient.headObject().etag` (lub equivalent) — jezeli rozni sie od oczekiwanego sha256, retry + alert.

**HR-7. Force-Flush ("zastoj bufora" guard)**
Jezeli pack nie osiagnie 900MB w **24 godziny** od pierwszego chunka, system MUSI:
- Force-flush taka jaka jest (np. 350MB pack)
- Log warning `pb_pack_force_flush_total{reason="age_24h"}`
- Alert Slack jezeli force-flush > 3 dziennie (sugestia: czy klient padl)
Implementacja: cron `flush/ForceFlushCron.kt` co 1h, czytaj `buffer_pack` z `WHERE first_chunk_at < now() - interval '24 hours' AND sealed_at IS NULL`.

**HR-8. Idempotency-Key per upload**
Kazdy POST do `/inbox/...` MUSI zawierac `Idempotency-Key` header (UUID v4 generowany przez agenta). Buffer trzyma `inbox_idempotency` tabela (idempotency_key, response_status, response_body, created_at, server_id). Powtorzenie tego samego klucza = zwroc cached response. TTL 24h.

**HR-9. At-Rest Encryption (buffer disk = zaszyfrowane przez OS / LUKS)**
Pliki na dysku w `/storage/inbox/...` i `/storage/sealed/...` to **juz zaszyfrowane przez agenta** AES-256-GCM. Buffer NIE WOLNO operowac na plaintext klienta NIGDY. Jezeli decyzja ma byc inna (np. server-side encryption), zaktualizuj ten dokument PRZED implementacja.

**HR-10. Disk-Full Soft Block + Alert**
Jezeli buffer storage zaplenia sie powyzej 80% i pack < 900MB:
- Soft block uploadow od agentow z 503 + `Retry-After: 3600`
- Alert Slack `pb_disk_full_soft_block`
- Admin endpoint `/admin/buffer/force-flush-now` (manual override)
- Cron prubuje force-flush co 30 minut

---

## 1. Cel dokumentu

Single source of truth dla agenta wykonujacego prace nad **rdzeniem buffera** (poza billingiem). Obejmuje: ingestion (inbox), packing (PackBuffer), sealing (ChunkSealer), flush triggers (FlushTrigger), storage quotas (StorageQuotaGuard), budget (BudgetGuard), verification (RestoreVerifier), audit reports (AuditReportGenerator), agent registration (ActivationTokenStore, ServerStore).

Brat dokumentu `master-tdd-plan.md` (billing), `agent-vps-master-spec.md`, `ovh-cloud-archive-migration-spec.md`.

### Co JEST w zakresie

- Chunk ingestion: HTTP API od agenta, walidacja, encryption boundary
- Pack assembly: 950MB chunking algorithm
- Sealing: idempotency, encryption layer, archive_snapshot insertion
- Flush triggers: time/size/manual
- Verify: integrity checks, Restore Verifier
- Audit PDF: backup history reports
- Server lifecycle: activation, deactivation, rename
- Path/file index: pathId mapping, file_state history
- DiskGuard, PayloadGuard: defensive validators

### Co NIE jest w zakresie

- Stripe/billing flow (juz w `master-tdd-plan.md`)
- LemonSqueezy (legacy, deprecated by Stripe)
- Web UI (osobny `web-panel-master-spec.md`)
- Agent (osobny `agent-vps-master-spec.md`)
- OVH transport (osobny `ovh-cloud-archive-migration-spec.md`)
- Observability/DR (osobny `observability-and-dr-spec.md`)

---

## 2. Mapowanie kodu

### 2.1 Kluczowe komponenty (na main, 51 plików Kotlin)

| Komponent | Plik | Linii | Rola |
|-----------|------|-------|------|
| Main entry | `BufferMain.kt` | (sprawdz) | HTTP routes, lifecycle |
| HTTP framework | (Javalin) | - | - |
| DB layer | `db/Database.kt` | ? | Hikari pool, schema apply |
| Inbox receive | `inbox/InboxReceiver.kt` | ? | POST /inbox/... |
| Chunk storage | `inbox/ChunkStorage.kt` | ? | Disk write |
| Disk guard | `inbox/DiskGuard.kt` | ? | Fail-safe disk-full |
| Payload guard | `inbox/PayloadGuard.kt` | ? | Header validation |
| Flush trigger | `flush/FlushTrigger.kt` | ? | Cron-like polling |
| Pack buffer | `flush/PackBuffer.kt` | ? | 950MB aggregation |
| Chunk sealer | `flush/ChunkSealer.kt` | ? | Encryption + ovh.put() |
| Budget guard | `flush/BudgetGuard.kt` | ? | Max flushes/day |
| Storage quota | `flush/StorageQuotaGuard.kt` | ? | Plan cap check |
| Server store | `server/ServerStore.kt` | ? | servers table |
| Activation tokens | `server/ActivationTokenStore.kt` | ? | Single-use tokens |
| Server handler | `server/ServerHandler.kt` | ? | HTTP routes |
| Restore verifier | `verify/RestoreVerifier.kt` | ? | Integrity check |
| Audit report | `report/AuditReportGenerator.kt` | ? | OpenPDF generation |
| Audit handler | `report/AuditReportHandler.kt` | ? | GET /reports/audit |
| Logs ingest | `logs/LogApiHandler.kt` | ? | POST /logs |
| File state | `logs/FileStateStore.kt` | ? | file_state table |
| Stack log | `logs/StackLogStore.kt` | ? | Agent crash trace |
| Machine events | `logs/MachineFileEventStore.kt` | ? | Append-only event log |
| Token bucket | `logs/TokenBucketLimiter.kt` | ? | Rate limit per agent |
| Agent metrics | `monitoring/AgentMetricsStore.kt` | ? | agent_metrics table |
| Paths index | `pathsidx/PathsIdxStore.kt` | ? | pathId mapping |
| Backup config | `pathsidx/BackupConfigStore.kt` | ? | Per-server config |
| Backup roots | `pathsidx/BackupRootStore.kt` | ? | Which dirs to backup |
| Archive snapshot | `pathsidx/ArchiveSnapshotStore.kt` | ? | Sealed chunks index |
| SSE bus | `sse/SseEventBus.kt` | ? | Real-time push to web |
| Cleanup | `cleanup/PostUploadCleanup.kt` | ? | Inbox/state cleanup |
| Object store | `store/ObjectStore.kt`, `LocalObjectStore.kt`, `ObjectReadFacade.kt` | ? | Storage abstraction |

### 2.2 Schema istotne (z `schema.sql`)

| Tabela | Rola |
|--------|------|
| `users` | Userzy + flagi (zobacz `master-tdd-plan.md`) |
| `servers` | Logiczne servery per user |
| `activation_tokens` | Single-use tokens dla agent activation |
| `paths_index` | pathId (8 chars) -> originalPath mapping |
| `file_state` | Per-file metadata current snapshot |
| `machine_file_event` | Append-only event log |
| `archive_snapshot` | Sealed chunk index |
| `agent_metrics` | CPU/RAM/disk samples |
| `stack_log` | Agent crash dumps |
| `buffer_pack` | 950MB pack files index |
| `archive_chunk` | Pojedyncze chunki w packach |
| `inbox_*` (jezeli istnieje) | Tymczasowe chunki przed sealing |
| `audit_log` | (od master-tdd-plan.md) Append-only billing audit |

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `flush/BudgetGuard.kt` — fail-safe contract: blokuje przy DB unavailability
- `flush/StorageQuotaGuard.kt` — fail-safe: blokuje przy DB unavailability
- `inbox/DiskGuard.kt`, `inbox/PayloadGuard.kt`
- `db/Database.kt` Hikari pool config (tuning OK, semantics nie)
- Wszystkie istniejace migrations w `schema.sql` — **TYLKO dodawaj** nowe (CREATE TABLE / ALTER TABLE w nowych blokach)
- Istniejace public method signatures w `ChunkSealer`, `PackBuffer`, `InboxReceiver`
- `payment/LemonSqueezyHandler.kt` — DEPRECATED, zostaw, agenci billingowi go ignoruja
- `auth/JwtFilter.kt`, `auth/JwtService.kt`, `auth/PasswordPolicy.kt`

### DOTYKAJ (mozna modyfikowac)

- `BufferMain.kt` — dodawanie nowych route handlers
- `inbox/InboxReceiver.kt` — wsparcie Content-Range (cross-ref `agent-vps-master-spec.md` `[AGT-B3]`)
- `verify/RestoreVerifier.kt` — rozszerz o periodic sample verification
- `report/AuditReportGenerator.kt` — dodaj nowe sekcje raportu
- `pathsidx/*` — dodawanie nowych query metod (nie usuwac istniejacych)
- `cleanup/PostUploadCleanup.kt` — dodaj cleanup dla `stripe_event_idempotency` (cross-ref `master-tdd-plan.md` 9.7)

### MOZESZ TWORZYC

- `inbox/IdempotencyStore.kt` — table `inbox_idempotency` dla `Idempotency-Key`
- `verify/PeriodicVerifier.kt` — cron sample 1% chunkow
- `monitoring/MetricsRegistry.kt` (cross-ref `observability-and-dr-spec.md`)
- Nowe handlers HTTP (np. `/admin/...`)
- Nowe tabele jako CREATE TABLE w nowym bloku schema.sql

---

## 4. Domain Model — przelew danych

### 4.1 End-to-end flow (agent → archive_snapshot → OVH)

```
1. AGENT (Kotlin)
   - DifferentialScanner detects changed file
   - TarGzPacker pakuje plik
   - ProperCrypto szyfruje (AES-256-GCM)
   - BufferUploader.upload(encryptedBytes, pathId, originalPath, flag)
   
2. BUFFER inbox layer
   POST /inbox/{userId}/{pathId} (Authorization: Bearer JWT)
   Body: encrypted chunk
   
   InboxReceiver:
   - JwtFilter walidacja JWT
   - PayloadGuard waliduje header (magic bytes, version)
   - DiskGuard sprawdza disk space
   - StorageQuotaGuard sprawdza per-user cap
   - ChunkStorage.write(userId, pathId, data) → /inbox/{userId}/{pathId}/{chunk-uuid}
   - INSERT inbox_chunk (user_id, path_id, chunk_uuid, size, sha256, created_at)
   - Response: 200 + {chunkId}

3. FLUSH cycle (FlushTrigger co N min)
   - Iterate users with pending chunks
   - For each user:
     - BudgetGuard.tryConsume(userId): jezeli rate limit exceeded, skip
     - PackBuffer.addToPack(chunk): aggregate do 950MB
     - Gdy pack full lub timeout: sealOpenPack()

4. SEALING
   ChunkSealer.seal(userId, pathId, originalPath, serverId):
   - Pakuj chunki do paczki (PackBuffer manages)
   - Encrypt pack (pakiet sealed shape)
   - CloudStorageClient.put(packName, packData) → OVH (lub mock)
   - INSERT archive_snapshot (chunk_id, pack_name, ovh_key, sealed_at, ...)
   - INSERT archive_chunk (chunk_id, pack_name, offset_in_pack, size, sha256, ...)
   - SSE event "chunk_sealed" to web

5. POST-CLEANUP (PostUploadCleanup)
   - DELETE inbox_chunk po N hours (raz pack jest sealed)
   - Optymalnie: DELETE plik z /inbox/ na dysku
```

### 4.2 Path identifier model

```
originalPath: "/home/user/Documents/important.txt"
hash(originalPath, serverId) -> pathId: "x7a3b2c9" (8 chars Base62)
INSERT paths_index (path_id, server_id, original_path, registered_at)
```

`pathId` jest **pseudonymized** identifier — nie ujawnia plain path w logach/storage.

### 4.3 Pack format

```
.pack file (950MB max):
┌──────────────────────────────────────────────────────────┐
│ Header: magic bytes "PBPACK01" + version + entry count   │
├──────────────────────────────────────────────────────────┤
│ Entry 1: objectName (40B) + size (8B) + data (variable) │
├──────────────────────────────────────────────────────────┤
│ Entry 2: ...                                             │
├──────────────────────────────────────────────────────────┤
│ ...                                                      │
├──────────────────────────────────────────────────────────┤
│ Footer: sha256 of all data (32B)                         │
└──────────────────────────────────────────────────────────┘
```

`readPack(path) -> List<PackEntry>` używany przez RestoreVerifier i restore.

### 4.4 Storage tiers (jezeli implementujemy w bufferze)

```
Disk tier:                     OVH tier:
/storage/                      properbackup-prod/
  /sealed/<user>/<pack-uuid>   (transferred after seal, kept on disk for N days)
  /inbox/<user>/<chunk-uuid>   (temporary, before flush)

Po N (default 7) dniach od seal: pack moze byc usuniety z disku (juz na OVH).
Klient restore: pobiera z OVH bezposrednio (lub backend pre-fetches do cache).
```

---

## 5. Test Groups

Numerowanie `[BUF-Xn]`.

### Grupa A: Inbox ingestion

#### `[BUF-A1]` POST /inbox happy path

**Given:** Agent ma valid JWT, payload encrypted chunk, user ma quota

**When:** POST /inbox/{userId}/{pathId} z encrypted body

**Then:**
- 200 OK
- INSERT do `inbox_chunk` z chunk_uuid, size, sha256
- Plik na disku w `/storage/inbox/{userId}/{pathId}/{chunk-uuid}`
- SSE event "chunk_received" emitted

**Pliki:**
- DOTYKAJ: `InboxReceiver.kt`
- DOTYKAJ: `ChunkStorage.kt`

**DoD:**
- Test integracyjny z Testcontainers PG
- Test sha256 matches body content
- Test idempotency (drugi POST tego samego pathId+sha256 → 200, 1 row in DB)

#### `[BUF-A2]` PayloadGuard rejects malformed

**Given:** Agent wysyla body bez magic bytes (lub złe magic bytes)

**When:** POST /inbox/...

**Then:**
- 400 Bad Request z `{"code": "INVALID_PAYLOAD"}`
- Nic w DB, nic na disku

**DoD:**
- Test "magic bytes wrong"
- Test "header version unsupported"
- Test "header truncated"

#### `[BUF-A3]` DiskGuard fail-safe

**Given:** Disk pelny (>95% used)

**When:** POST /inbox/...

**Then:**
- 507 Insufficient Storage
- Alert metric `pb_chunks_failed_total{reason="disk_full"}`
- Nic na disku

**DoD:**
- Test z mock NIO `getFileStore().getUsableSpace() = 0`
- Test ze DiskGuard reagency takze gdy DB jest DOWN (fail-safe, blokuje a nie przepuszcza)

#### `[BUF-A4]` StorageQuotaGuard fail-safe

**Given:** User ma Hobby (100 GB), uzywa 99 GB. Nowy chunk 2 GB.

**When:** POST /inbox

**Then:**
- 413 Payload Too Large `{"code": "QUOTA_EXCEEDED", "used_gb": 99, "cap_gb": 100}`
- Alert metric `pb_chunks_failed_total{reason="quota"}`

**Given (sad path 2):** DB down

**When:** POST /inbox

**Then:**
- **507** (nie 200!) — fail-safe blokuje, nie przepuszcza

**DoD:**
- Test z near-quota user (99.5 GB) → block przy 600MB chunk
- Test ze DB down → block (fail-safe)
- Test ze velocity check (cross-ref `ovh-cloud-archive-migration-spec.md` `[OVH-D3]`): >50 GB / 1h → 429

#### `[BUF-A5]` Resumable upload Content-Range

(Cross-ref `agent-vps-master-spec.md` `[AGT-B3]`)

**Given:** Klient zaczyna upload 500MB chunka, traci 200MB w polowie

**When:** Drugi PUT z `Content-Range: bytes 200000000-499999999/500000000` (resume)

**Then:**
- Buffer appendsuje do existing inbox file
- Po seal: weryfikacja sha256 całego pliku
- Niezgodnosc sha256 → 400 Bad Request, plik kasowany

**DoD:**
- Test z PUT 0-200MB, potem PUT 200-500MB → 1 chunk
- Test "ranges nie kontynuują się" (gap) → 416 Range Not Satisfiable
- Test "Idempotency-Key replay" → 200 z poprzednim response (nie podwojny zapis)

### Grupa B: Pack & flush

#### `[BUF-B1]` PackBuffer 950MB max

**Given:** PackBuffer ma 940MB w open pack. Klient wysyla 20MB chunk.

**When:** PackBuffer.addToPack(chunk)

**Then:**
- Open pack sealed (940MB final size)
- Nowy open pack utworzony z tym chunkiem (20MB)
- INSERT `buffer_pack` row dla sealed pack

**DoD:**
- Test z chunkiem dokladnie 950MB → 1 pack, sealed natychmiast
- Test z 100 chunkow po 10MB → 1 pack (1000MB total → split into pack 1 (950MB, 95 chunks) + pack 2 (50MB))
- Race test: 10 watkow rownolegle addToPack → spojnosc, brak corruption

#### `[BUF-B2]` FlushTrigger time-based

**Given:** `PROPERBACKUP_FLUSH_AGE_SECONDS=120` (2 min)

**When:** Pack ma 100MB i jest otwarty 130s

**Then:**
- FlushTrigger wykrywa age > threshold
- Pack sealed (mimo ze <950MB)
- OVH put wykonany

**DoD:**
- Test z `MAX_FLUSHES_PER_DAY=3` (BudgetGuard) — 4. trigger w tym samym dniu → skip
- Test "manual flush" — admin endpoint `POST /admin/flush?userId=...` → flush + audit log

#### `[BUF-B3]` BudgetGuard rate limit

**Given:** User wykonal juz 3 flushes today (limit z `PROPERBACKUP_MAX_FLUSHES_PER_DAY`)

**When:** Czwarty flush trigger

**Then:**
- BudgetGuard.tryConsume() → false
- Flush skipped (chunk zostaje w inbox, kolejny dzien)
- Metric `pb_flushes_rate_limited_total` incrementuje

**Sad path:** DB down

**Then:** tryConsume() returns false (fail-safe), skip flush

**DoD:**
- Test 24h cykl: 3 flushes ok, 4. blocked
- Test "midnight rollover": flush count reset o 00:00 UTC
- Test ze `remaining()` zwraca current count

### Grupa C: Sealing & encryption

#### `[BUF-C1]` ChunkSealer happy path

**Given:** PackBuffer ma full pack 950MB

**When:** ChunkSealer.seal(userId, pathId, ...)

**Then:**
- Pack content encrypted (lub juz encrypted at chunk level — sprawdz)
- CloudStorageClient.put(packName, ...) wykonany
- INSERT `archive_snapshot` per chunk
- INSERT `archive_chunk` z offset_in_pack
- INSERT `buffer_pack` row z size i ovh_key
- SSE event "pack_sealed" do web

**DoD:**
- Test integracyjny z mock CloudStorageClient
- Test "OVH put fails": retry 3x, jezeli ciagle fail → pack zostaje na disku, retry w nastepnym flush cycle
- Test "DB INSERT fails mid-batch": rollback transakcji, brak częsciowych writes

#### `[BUF-C2]` Disk full during seal

(Cross-ref `[BUF-A3]` ale na inny etap)

**Given:** /storage/sealed/ disk pelny

**When:** ChunkSealer.seal proba zapisu sealed pack

**Then:**
- Skip seal, log alert
- Pack zostaje w open state (kolejna proba w nastepnym cycle)
- Metryka `pb_seals_failed_total{reason="disk_full"}`

**DoD:**
- Test z mock low disk, sprawdz że pack zostaje otwarty

#### `[BUF-C3]` Encryption integrity

(Cross-ref `crypto-and-compliance-spec.md`)

**Given:** Pack sealed z encrypted content

**When:** RestoreVerifier weryfikuje (sample 1% packs)

**Then:**
- Pobiera pack z OVH
- Dekoduje header (HeaderCodec)
- Decrypts (ProperCrypto z user encryption key)
- Compares sha256 vs `archive_chunk.sha256`
- Match → ok
- Mismatch → ALERT (potential corruption)

**DoD:**
- Test happy path: random sample passes
- Test "bit flip w pack": detection, alert

### Grupa D: Server lifecycle

#### `[BUF-D1]` Activation token (single-use)

**Given:** User w UI generuje token aktywacyjny → INSERT `activation_tokens` (user_id, token, expires_at)

**When:** Agent wykonuje POST /agents/activate {token: "ABC123"}

**Then:**
- ActivationTokenStore.consume(token) → 1 row updated (used_at = now)
- ServerStore.insert(server_id, user_id, machine_name, ...)
- Response: 200 + refreshToken

**Sad path:** Drugi POST z tym samym tokenem

**Then:** 400 TOKEN_ALREADY_USED

**Sad path 2:** Token expired (>7 dni)

**Then:** 400 TOKEN_EXPIRED

**DoD:**
- Test concurrent activation race (10 watkow z tym samym token) → 1 sukces, 9 fail
- Test token z `expires_at > now()` → ok
- Test token przez SQL injection (`'; DROP TABLE...`) → bezpieczne (prepared statements)

#### `[BUF-D2]` Server rename / lifecycle

**Cel:** User moze zmienic `server_name` w UI.

**When:** PUT /servers/{serverId} {name: "Nowy serwer"}

**Then:**
- ServerStore.update(server_id, name)
- Wymaganie: user owns server (Authorization check)
- Audit log entry

**Edge cases:**
- 2 servery z tą samą nazwą (allowed, name nie jest unique)
- Server name z emoji / RTL chars → UTF-8

**DoD:**
- Test 403 jezeli user nie owns server
- Test rename do pustego stringa → 400

#### `[BUF-D3]` Server delete (soft delete)

**Cel:** Klient usuwa server. Co sie dzieje z jego danymi?

**Decyzja:**
- Soft delete: `servers.deleted_at = now()`, no hard delete
- Backupy zostaja (retencja 30 dni)
- Klient moze "undelete" w okresie grace
- Po 30 dniach: hard delete z `archive_snapshot` + OVH delete

**Implementacja:**
- `DELETE /servers/{serverId}` → UPDATE deleted_at
- Cron `properbackup-stack/scripts/server-cleanup.sh` daily
- Audit log entry

**DoD:**
- Test soft delete: server widoczny w admin, ukryty w user UI
- Test undelete w 25 dni → ok
- Test undelete w 35 dni → 404 (juz hard deleted)
- Test cascade: file_state, paths_index, archive_snapshot kasowane razem

### Grupa E: Paths & file state

#### `[BUF-E1]` Paths index registration

**Cel:** Agent wysyla mapping pathId -> originalPath, buffer zapisuje.

**When:** POST /agents/paths {serverId, paths: [(pathId, originalPath), ...]}

**Then:**
- UPSERT paths_index dla kazdego (pathId, server_id)
- Idempotent (drugi POST nie failuje)
- Audit "paths_registered" event

**Edge cases:**
- pathId hash kolizja (8 chars Base62 = 218 trillion combinations, niemozliwe ale...) → INSERT z PG `ON CONFLICT` strategia
- Path z null bytes (`\0`) → reject 400
- Path > 4096 chars (Linux PATH_MAX) → reject 400

**DoD:**
- Test 10K paths in single request
- Test concurrent registration (2 agents same serverId) → no race

#### `[BUF-E2]` File state versioning

**Cel:** Per-file metadata w `file_state` table updated on each scan.

**When:** Agent wysyla differential scan results

**Then:**
- For each changed file:
  - UPSERT file_state (path_id, mtime, size, sha256, change_flag)
  - INSERT machine_file_event (append-only) — historic record

**Edge cases:**
- Plik usuniety → change_flag='D' (tombstone)
- Plik renamed → change_flag='R' z `previous_path_id`

**DoD:**
- Test 1M file_state rows in one batch
- Test machine_file_event partycjonowane (rozne lata)
- Test ze stary event nie nadpisuje nowszego (timestamp-based)

#### `[BUF-E3]` Archive snapshot query

**Cel:** GET /archives/{serverId}/{pathId}/history → lista wszystkich versions plika.

**Response:**
```json
{
  "pathId": "x7a3b2c9",
  "originalPath": "/home/user/file.txt",
  "history": [
    {"sealed_at": "...", "size": 1024, "sha256": "...", "available": true},
    {"sealed_at": "...", "size": 512, "sha256": "...", "available": true, "tombstone": true},
    {"sealed_at": "...", "size": 256, "sha256": "...", "available": false, "in_cold_tier": true}
  ]
}
```

**DoD:**
- Test history (3 versions chronologicznie)
- Test pagination (jezeli >100 versions)
- Test 403 jezeli user nie owns path

### Grupa F: Verify

#### `[BUF-F1]` On-demand verify

**Cel:** Admin/user triggeruje verify `POST /admin/verify/{serverId}` lub `POST /verify/{archiveSnapshotId}`.

**When:** Verify request

**Then:**
- RestoreVerifier pobiera chunki z OVH
- Decrypts (server-side, klucz dostarczony przez user lub admin master-key)
- Compares sha256
- Generates raport
- Audit log entry

**DoD:**
- Test single-chunk verify w <30s
- Test full-server verify (100GB) w background z progress (SSE)
- Test "chunk missing in OVH" → flagged red, alert

#### `[BUF-F2]` Periodic background verify

**Cel:** Cron tygodniowy weryfikuje sample 1% chunkow z OVH.

(Cross-ref `ovh-cloud-archive-migration-spec.md` `[OVH-E2]`)

**Implementacja:**
- NEW: `verify/PeriodicVerifier.kt`
- Cron 1x/tydzien (sobota 04:00)
- Sample: 1% archives losowo wybranych
- Report do admin Slack

**DoD:**
- Test sample size (sprawdza ze losuje ~1%, nie 0%)
- Test ze chunks NOT sealed (still in pack buffer) nie sa w sampling
- Test alert >0.01% fail rate

### Grupa G: Audit report (PDF)

#### `[BUF-G1]` PDF generation happy path

**Cel:** User klika "Pobierz raport za maj 2026" w UI → PDF download.

**When:** GET /reports/audit?from=2026-05-01&to=2026-05-31&serverId=...

**Then:**
- AuditReportGenerator pobiera z DB:
  - Total bytes backed up
  - Number of backups
  - Restore events
  - Verify events (if any)
  - File state changes summary
- OpenPDF buduje dokument
- Response: `Content-Type: application/pdf`

**DoD:**
- Test generated PDF parses validly (PDFBox)
- Test polskie znaki w PDF (kodowanie UTF-8)
- Test 12-mies raport renders <30s
- Test 403 jezeli user nie owns server
- Test "no data in period" → PDF z "brak danych"

#### `[BUF-G2]` PDF audit trail integrity

**Cel:** PDF zawiera sha256 swojej zawartosci (footer) + signed digest.

**Po co:** Niezaprzeczalnosc dla kontroli skarbowej.

**DoD:**
- Test ze PDF ma footer "sha256: ..."
- Test re-generation tego samego okresu daje **identyczny** PDF (deterministic)
- Test PDF nie zawiera userId / encryption keys / IP

### Grupa H: Cleanup

#### `[BUF-H1]` Post-upload cleanup

**Cel:** PostUploadCleanup cron usuwa stale dane.

**Co czysci:**
- `inbox_chunk` rekord starszy niz 24h (raz pack jest sealed) → DELETE
- Plik na disku `/storage/inbox/...` powiazany z usunietym rekordem → fs DELETE
- `archive_chunk` orphan (nie ma archive_snapshot) → DELETE + log warning
- `agent_metrics` starsze niz 30 dni → DELETE (kompresja do roczne aggregat)
- `stack_log` starsze niz 90 dni → DELETE

**Pliki:**
- DOTYKAJ: `PostUploadCleanup.kt` (juz istnieje, sprawdz semantyke)
- DOTYKAJ: cron config w `properbackup-stack/docker-compose.yml`

**DoD:**
- Test "stale rows are deleted" (mock time)
- Test "fresh rows untouched"
- Test "concurrent cleanup runs" (2 cron jobs jednoczesnie) → idempotent
- Test "cleanup doesn't delete sealed packs from disk" (sealed/ retencja 7 dni)

#### `[BUF-H2]` Pending users cleanup

(Cross-ref `master-tdd-plan.md` 9.7)

**Cel:** Userzy w stanie `pending_payment` (zarejestrowani, ale nie aktywowali subskrypcji) usuwani po 30 dniach.

**Implementacja:**
- Cron daily
- SELECT users WHERE subscription_status='none' AND created_at < now() - INTERVAL '30 days'
- DELETE (cascade: paths_index, file_state, archive_snapshot)
- Audit log
- Alert summary count

**DoD:**
- Test happy path
- Test "user activated last day" → not deleted
- Test cascade integrity

#### `[BUF-H3]` Stripe idempotency cleanup

(Cross-ref `master-tdd-plan.md` 9.7)

**Cel:** `stripe_event_idempotency` starsze 90d → DELETE.

**DoD:** Standard cron test.

### Grupa I: SSE (Server-Sent Events)

#### `[BUF-I1]` Connection lifecycle

**Cel:** Web client otwiera SSE connection `GET /sse/events?token=jwt`, otrzymuje events.

**Events emitted:**
- `chunk_received` (po POST /inbox)
- `pack_sealed` (po ChunkSealer.seal)
- `subscription_updated` (z master-tdd-plan.md, po Stripe webhook)
- `agent_offline` (po N min braku heartbeat)
- `verify_progress` (background verify)
- `restore_ready` (cross-ref `ovh-cloud-archive-migration-spec.md` `[OVH-C2]`)

**Pliki:**
- DOTYKAJ: `sse/SseEventBus.kt`
- DOTYKAJ: BufferMain.kt route

**DoD:**
- Test connection survives 30 min idle
- Test reconnect po network drop
- Test heartbeat ping co 30s (keeps proxy connections alive)
- Test 401 bez JWT
- Test izolacja: user A nie dostaje events user B

#### `[BUF-I2]` Backpressure

**Cel:** Klient slow consumer (3G) — events sie nie kolejkuja w nieskonczonosc.

**Wymagane:**
- Buffer per-connection max 100 queued events
- Po 100: drop oldest, log warning
- Klient widzi `event: backpressure` notify

**DoD:**
- Test slow consumer: 1000 events sent, najwyzej 100 in queue
- Test buffer freed po consumer reconnect

### Grupa J: Admin endpoints

#### `[BUF-J1]` Admin authentication

**Cel:** `/admin/*` routes wymaga `SERVICE_ADMIN` role.

**Implementacja:**
- `users.is_service_admin BOOLEAN` (lub `users.role TEXT`)
- ServiceAdminCodeStore — one-time seed code z env `PROPERBACKUP_SERVICE_ADMIN_SEED_CODE`
- Bootstrap: pierwszy `/auth/elevate` z seed code → user staje sie admin

**DoD:**
- Test ze seed code single-use
- Test ze non-admin → 403 na /admin/*
- Test seed code w env → audit log entry

#### `[BUF-J2]` Admin endpoints catalog

| Endpoint | Co robi |
|----------|---------|
| `GET /admin/users` | List wszystkich (paginated) |
| `GET /admin/users/{id}/usage` | Storage usage per user |
| `POST /admin/users/{id}/upgrade` | Manual plan change (audit log) |
| `POST /admin/users/{id}/grant-grace` | Custom grace period after dunning |
| `POST /admin/flush?userId=...` | Manual flush trigger |
| `POST /admin/verify?serverId=...` | Manual verify run |
| `POST /admin/cleanup` | Manual cleanup run |
| `GET /admin/audit?from=...&to=...` | Audit log query |
| `GET /admin/system/status` | Health-detailed (cross-ref `[OBS-A2]`) |

**DoD:**
- Każdy endpoint audit log
- Rate limit (admin nie ma unlimited dostepu, no accident bulk operations)

---

## 6. Edge Cases (20+)

### 6.1 Concurrent flush triggers (race)

Dwa watki FlushTrigger uruchamiaja sie jednoczesnie.

**Wymagane:**
- `flushAll()` ma `synchronized` lub PG `LOCK TABLE buffer_pack IN EXCLUSIVE MODE` na granicy
- Drugi watek widzi "nothing to flush" (pierwszy juz wykonal)

### 6.2 Pack sealed mid-upload chunk

Klient uploaduje chunk D, w tym samym czasie FlushTrigger seals pack A,B,C. Co z D?

**Wymagane:**
- PackBuffer.addToPack tworzy NOWY open pack
- D ladaje w nowym packu, nie w sealed

### 6.3 Restore chunk po delete server

User usunal server, ale Restore wciaz w toku.

**Wymagane:**
- Server soft-delete: Restore in-progress widzi `deleted_at` ale dokancza
- Po 30 dniach grace: Restore odmowa "server permanently deleted"

### 6.4 Pack name kolizja

UUID kolizja (teoretycznie niemozliwa).

**Wymagane:**
- INSERT `buffer_pack` z UNIQUE constraint na (server_id, pack_name)
- Konflikt → regenerate UUID, retry max 3x

### 6.5 Multi-server concurrent backup tego samego pliku

User ma 2 servery, oba widza ten sam plik (NFS share). Oba wysylaja chunk dla tego samego `originalPath`.

**Wymagane:**
- pathId jest hash(originalPath + **serverId**) → rozne pathId dla rozne servery
- 2 oddzielne archive_snapshot
- Klient widzi 2 entry w UI (oznaczone per-server)

### 6.6 Chunk overwrite atak

Atakujacy uzyskal JWT, probuje PUT chunk z innym contentem na istniejacy pathId.

**Wymagane:**
- POST /inbox jest **append-only** semantic — nowa version, nie overwrite
- Idempotency-Key: drugi POST z tym samym key → no-op
- Bez Idempotency-Key + identyczne body → no-op (sha matches)
- Bez Idempotency-Key + rozne body → INSERT (nowy version, nie overwrite)

### 6.7 Brak miejsca na OVH (rare)

OVH zwraca 507.

**Wymagane:**
- Retry 3x z backoff
- Po 3 failach: pack zostaje na disku, alert
- Admin manual interwencja (cleanup OVH lub zmiana planu)

### 6.8 Race przy activation token

10 maszyn uzywa tego samego tokenu jednoczesnie (atak / wycieczek).

**Wymagane:**
- `[BUF-D1]` SQL: `UPDATE activation_tokens SET used_at=now() WHERE token=? AND used_at IS NULL RETURNING ...`
- Tylko 1 maszyna dostaje serverId, pozostale → 400

### 6.9 Duza paczka audit PDF (year of data)

Klient zada raport roczny — generation 30+ sekund.

**Wymagane:**
- Async generation: POST /reports/audit?async=true → 202 + jobId
- Klient pollouje GET /reports/jobs/{jobId} → 200 + URL gdy ready
- PDF generated do `/storage/reports/{jobId}.pdf` retencja 7 dni

### 6.10 Pack file korumpowany na disku

Disk failure mid-write, pack file partial.

**Wymagane:**
- Footer sha256 weryfikuje calego packu po write
- Niezgodny sha256 → pack flagowany `corrupted`, alert
- Cleanup: corrupted pack DELETE z disku, re-flush nastepuje (ChunkSealer zauwaza brak `buffer_pack` row)

### 6.11 Long-running TX (deadlock risk)

Cron wykonuje pelne archiwum query z UPDATE → blokuje webhooki.

**Wymagane:**
- Long-running queries `SET LOCAL statement_timeout = 30000`
- PG `LOCK TABLE ... NOWAIT` zamiast blocking
- Webhook handler ma osobna connection pool (mniej szansy konfliktu)

### 6.12 Disk fill po cleanup

Cleanup probuje DELETE z disku, ale disk readonly (sata fault).

**Wymagane:**
- Alert "disk read-only" — system staje (nie probuje nic pisac, fail-safe)
- Manual intervention

### 6.13 SSE clients flood

1000 polaczen SSE z jednego usera.

**Wymagane:**
- Per-user limit max 5 active SSE connections
- 6 → close oldest

### 6.14 Audit log overflow

`audit_log` rosnie do milionow rekordow.

**Wymagane:**
- Partitioning per month
- Archiwizacja: starsze niz 3 lata → wyeksportowane do JSON na B2, DELETE z PG
- Wymagaczne dla ksiegowosci

### 6.15 Logback pisze sekrety

InboxReceiver loguje `Failed to validate: {token}` z full JWT.

**Wymagane:**
- Filter w logback masks `(token|key|password)=[^\s]+`
- Test "log secret leak"

### 6.16 Server name SQL injection

User nazywa server `'); DROP TABLE users; --`.

**Wymagane:**
- Prepared statements wszedzie (ScalarPreparedStatement)
- Test "evil server name" → serwer utworzony z literalna nazwa, DB intact

### 6.17 RestoreVerifier OOM przy duzym packu

950MB pack ladowany w pamiec na raz → OOM.

**Wymagane:**
- Streaming verify (zapis i czytanie chunk by chunk)
- `-Xmx512m` w produkcji wystarcza

### 6.18 Pack sealed z 0 chunkow

Edge case: PackBuffer.sealOpenPack() bez przygotowanych chunkow.

**Wymagane:**
- Skip seal, log warning
- Brak insertu do `buffer_pack`

### 6.19 Multi-user shared file

Klient A backup'uje `secret.txt`, klient B ma podobny plik (deduplicated).

**Decyzja:**
- NIE robimy cross-user dedup (privacy)
- A i B sa zupelnie oddzielni

### 6.20 Daylight saving time (DST)

Cleanup cron uruchamia sie codziennie 04:00. DST → 2x w jeden dzien lub 0x.

**Wymagane:**
- Wszystkie crony w UTC (nie local time)
- `flock` zapobiega 2x runom

---

## 7. Definition of Done

10 kryteriow (identyczne):

1. Red test first
2. Test integracyjny z Testcontainers PG
3. Brak nowych deps bez approval
4. Brak sekretow w logach/stack tracach
5. DOTYKAJ zone respected
6. Audit log entry per kazda inwazyjna operacje
7. Smoke test na test serverze
8. Idempotent operations
9. Metryka per feature (`pb_*` Prometheus)
10. Rollback plan w PR

---

## 8. Sequence of work

1. **`[BUF-A5]` Resumable upload Content-Range** — UI feature & agent UX
2. **`[BUF-B3]` BudgetGuard fail-safe verification** — sprawdz semantyke na DB down
3. **`[BUF-A4]` StorageQuotaGuard fail-safe verification** — to samo
4. **`[BUF-H1]` PostUploadCleanup expansion** — pending users, stripe idempotency
5. **`[BUF-D3]` Server soft-delete + 30d grace** — biznes-krytyczne
6. **`[BUF-F2]` PeriodicVerifier (sample 1%)** — integrity assurance
7. **`[BUF-G2]` Audit PDF integrity (sha256 footer)** — ksiegowosc
8. **`[BUF-I2]` SSE backpressure** — slow consumer protection
9. **`[BUF-J2]` Admin endpoints** — operations
10. **`[BUF-E3]` Archive snapshot history endpoint** — UI restore wizard

---

## 9. Go/No-Go checklist

- [ ] Inbox: resumable upload dziala (test 500MB z 200MB interrupt)
- [ ] Quota guards: DB-down → fail-closed (test mock)
- [ ] BudgetGuard: rate limit per day enforced
- [ ] Pack: 950MB rozdzielany prawidlowo, multi-thread safe
- [ ] Sealing: encryption + OVH put + DB transaction atomic
- [ ] Activation: token single-use enforced (concurrent race test)
- [ ] Server soft-delete: 30d grace + hard delete cascade
- [ ] PostUploadCleanup: stale inbox kasowany po 24h
- [ ] PeriodicVerifier: tygodniowy raport email
- [ ] Audit PDF: parses validly, ma sha256 footer, deterministic
- [ ] SSE: per-user limit, backpressure
- [ ] Admin endpoints: SERVICE_ADMIN role enforced + audit log
- [ ] Manual chaos: kill -9 buffer w polowie flush → po restart pack zostaje w open, ponowny flush sealed
- [ ] Manual chaos: PG down → no chunk written (fail-safe)
- [ ] Manual chaos: OVH down → flush queue rosnie, alert (cross-ref `[OVH-D1]`)

---

## Dodatek A — Linki

- `master-tdd-plan.md` — billing tests touching audit_log, stripe_event_idempotency
- `agent-vps-master-spec.md` — server-side counterpart resumable upload, JWT
- `ovh-cloud-archive-migration-spec.md` — flush layer destination
- `observability-and-dr-spec.md` — metryki, alerty
- `crypto-and-compliance-spec.md` — encryption layer
- `web-panel-master-spec.md` — UI consumer SSE i admin

## Dodatek B — Glosariusz

- **Chunk** — atomic encrypted unit od agenta (pre-pack)
- **Pack** — agregat do 950MB chunkow w jednym pliku
- **Inbox** — tymczasowy disk storage przed flush
- **Sealing** — proces zaszyfrowania pakietu i przekazania do OVH
- **Flush trigger** — cron polling, czas/rozmiar
- **BudgetGuard** — rate limit na flushe per user per day
- **StorageQuotaGuard** — per-user storage cap
- **DiskGuard** — fail-safe na full disk
- **PayloadGuard** — header validator (anti-malformed)
- **PostUploadCleanup** — cron kasujacy stale data
- **PathId** — Base62 8-char hash of (originalPath + serverId)
- **MachineFileEvent** — append-only event log of file changes
- **ActivationToken** — single-use credential dla agent registration
- **Tombstone** — soft-delete marker dla pliku (retencja 30d)
