# Agent VPS — Master Plan (Resilience & Distribution)

Wersja: 1.0 (initial, pre-prod)
Repo: `properbackup-agent` + `properbackup-shared` (transport layer)
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P1**

---

## 1. Cel dokumentu

Single source of truth dla wszystkich prac nad **agentem ProperBackup w wariancie VPS / Dedicated Server / ARM64 / desktop** (standalone proces JVM/jlink, nie plugin Minecraft).

Zakres: distribution (jlinkDist), aktywacja, transport (resumable upload, circuit breaker, retry), I/O throttling, JWT 5min, auto-update channel, telemetria.

Brat dokumentu `master-tdd-plan.md` (billing) i `observability-and-dr-spec.md` (DR). Filozofia identyczna: minimal invasiveness, DOTYKAJ vs NIE RUSZAJ, TDD red-first.

### Co NIE jest w zakresie

- Plugin Minecraft `properbackup-mc` (osobny doc: `minecraft-plugin-master-spec.md`)
- Aplikacja iOS/Android (post-MVP)
- Synchronizacja desktop-only Windows installer (post-MVP, na razie tylko Windows portable jlink)
- Reverse VPN / NAT traversal (na razie agent ma access do public buffer URL)

---

## 2. Mapowanie kodu

### 2.1 Stan obecny — gdzie co siedzi

| Funkcja | Repo | Plik | Linii (zgrubnie) |
|---------|------|------|------------------|
| Entry point (CLI args, lifecycle) | `properbackup-agent` | `AgentMain.kt` | ~750 |
| Pakowanie tar.gz | `properbackup-shared` | `packer/TarGzPacker.kt` | ? |
| Szyfrowanie AES-256-GCM | `properbackup-shared` | `core/crypto/ProperCrypto.kt` | ? |
| Key derivation Argon2id | `properbackup-shared` | `core/crypto/KeyDerivation.kt` | ? |
| Header codec | `properbackup-shared` | `core/crypto/HeaderCodec.kt` | ? |
| Differential scanner | `properbackup-shared` | `scanner/DifferentialScanner.kt` | ? |
| Metadata cache | `properbackup-shared` | `scanner/MetadataCache.kt` | ? |
| Upload klient HTTP | `properbackup-shared` | `transport/BufferUploader.kt` | 175 |
| Retry policy | `properbackup-shared` | `transport/RetryPolicy.kt` | 39 |
| Activation client | `properbackup-shared` | `activation/ActivationClient.kt` | ? |
| Global config writer | `properbackup-shared` | `activation/GlobalConfigWriter.kt` | ? |
| Service installer (systemd/Windows service) | branch `devin/1778954012-service-installer` | ? | ? |
| IoThrottle | branch `devin/1779032082-5-feature-production` | (TODO sprawdz `AgentMain.kt`) | ? |
| Telemetria zdalna | `properbackup-shared` | `logging/RemoteTelemetry.kt` | ? |

### 2.2 Branches istotne

- `main` — stabilna baseline
- `origin/devin/1779032082-5-feature-production` — najbardziej rozbudowany (IoThrottle, real-time progress)
- `origin/devin/1778954012-service-installer` — install jako systemd / Windows service

Przyszly agent **musi sprawdzic ktore branche zmergowane** przed startem prac.

### 2.3 Tabele w bufferze ktore agent dotyka

| Tabela | Uzycie |
|--------|--------|
| `users` | login (przez `AuthHandler`) |
| `servers` | rejestracja przez `ActivationTokenStore` |
| `agent_metrics` | upload metryk co N sekund |
| `file_state` | upload differential scan results |
| `machine_file_event` | append-only event log |
| `archive_snapshot` | po sealing chunka |
| `inbox_chunk` (jezeli istnieje) | partial upload |
| `paths_index` | mapping pathId -> originalPath |

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `properbackup-shared/.../core/crypto/ProperCrypto.kt` — bezpieczenstwo
- `properbackup-shared/.../core/crypto/KeyDerivation.kt`
- `properbackup-shared/.../core/crypto/HeaderCodec.kt`
- `properbackup-shared/.../core/filename/FilenameGrammar.kt` — grammar parser dla nazw
- `properbackup-shared/.../core/codec/Base62.kt`, `ProperCodec.kt`
- Istniejacy semantyk `BufferUploader.upload()` (mozna **dodawac** nowe metody jak `uploadChunked`, ale stara musi dalej dzialac dla MC plugin)

### DOTYKAJ (mozna modyfikowac, ostroznie)

- `properbackup-shared/.../transport/RetryPolicy.kt` — rozszerz o circuit breaker
- `properbackup-shared/.../transport/BufferUploader.kt` — dodaj resumable upload (nowy konstruktor / new method)
- `properbackup-agent/.../AgentMain.kt` — JWT bootstrap, periodic revalidation
- `properbackup-shared/.../activation/*.kt` — JWT minted on activation
- `properbackup-shared/.../scanner/*.kt` — performance tuning ok, semantyki nie zmieniac

### MOZESZ TWORZYC

- `properbackup-shared/.../transport/CircuitBreaker.kt`
- `properbackup-shared/.../transport/ResumableUpload.kt`
- `properbackup-shared/.../transport/JwtClient.kt` — refresh tokenu co 4 min
- `properbackup-agent/.../updater/AutoUpdater.kt`
- `properbackup-shared/.../iothrottle/IoThrottle.kt` (jezeli jeszcze nie istnieje)
- Test: `*Test.kt` w `src/jvmTest/`

---

## 4. Domain Model

### 4.1 Lifecycle agenta

```
1. Install (download jlinkDist + extract)
   → ~/.local/share/properbackup-agent/ (Linux)
   → C:\ProgramData\ProperBackup\Agent\ (Windows)

2. Activate (one-time, via web/CLI)
   $ ./properbackup-agent --activate TOKEN
   → ActivationClient -> POST /agents/activate
   → Buffer returns: serverId, ownerEmail, encryptionPassword, JWT refresh token
   → GlobalConfigWriter saves to ~/.config/properbackup/global.json

3. Start (systemd / Windows service / standalone)
   → Read config
   → Authenticate (JWT bootstrap from refresh token)
   → Scan once (full scan -> differential cache)
   → Loop:
     - Differential scan
     - Pack changed files (TarGzPacker)
     - Encrypt (ProperCrypto)
     - Upload to buffer (BufferUploader with retry + CB)
     - Report metrics (RemoteTelemetry)
     - Sleep POLL_INTERVAL (default 5 min)

4. Update (auto, post-MVP)
   → Compare local version vs buffer's latest_agent_version
   → If newer: download, extract, restart self

5. Stop / Uninstall
   → Systemd: systemctl stop properbackup-agent
   → Cleanup state (optional)
```

### 4.2 Auth flow

```
Activation (jednorazowo):
  Agent CLI: --activate TOKEN
  Agent --> POST /agents/activate {token, machineId, machineName}
  Buffer: validate token (single-use)
  Buffer: insert into `servers` table
  Buffer --> 200 OK {
    serverId,
    ownerEmail,
    refreshToken,     // long-lived, signed, scoped to (userId, serverId)
    bufferUrl,
    storageUrl
  }
  Agent: store refreshToken in global config (encrypted disk-side)
       store machineId in global config (UUID v4, generated on first start)

Normal operation:
  Agent (every 4 min):
    POST /agents/refresh {refreshToken, machineId}
    --> 200 {accessToken: jwt-5min, expiresAt}
  Agent uses accessToken in Authorization: Bearer for all subsequent calls
  If accessToken expires (subscription canceled, server revoked):
    Agent gets 403 SUBSCRIPTION_EXPIRED -> stops + alerts owner email
```

### 4.3 Resumable upload protocol

```
Chunk upload protocol (large files, >100MB):

1. Agent computes sha256(plaintext) BEFORE encryption (for resume identity)
2. Agent issues:
   HEAD /inbox/{userId}/{pathId}/{sha256} HTTP/1.1
   Authorization: Bearer <jwt>
3. Buffer responds:
   200 OK
   Content-Length: <bytes-already-received>   ← resume point
   ETag: "<chunk-id>"
   (or 404 if not started)
4. Agent uploads with Content-Range:
   PUT /inbox/{userId}/{pathId}/{sha256} HTTP/1.1
   Content-Range: bytes <start>-<end>/<total>
   Authorization: Bearer <jwt>
   Idempotency-Key: <sha256>
   <encrypted bytes from offset>
5. Buffer appends to inbox file (write-only mode)
6. After full upload, agent signals:
   POST /inbox/{userId}/{pathId}/{sha256}/seal
7. Buffer:
   - Verifies size + sha256 (decrypts header to read plaintext sha)
   - Promotes from inbox to permanent storage
   - Inserts into archive_snapshot
8. Cleanup: jeżeli klient porzuci upload, cron czysci inbox po 24h (PostUploadCleanup)

NIE wysylamy plain sha256 w URLu (privacy). Sha256 jest *po enkrypcji* — nazwa pliku to UUID.
```

---

## 5. Test Groups

### Grupa A: Activation & Authentication

#### `[AGT-A1]` Activation z prawidlowym tokenem

**Given:** Buffer dziala, ma waznego usera, token aktywacyjny "T123" w `activation_tokens` (single-use)

**When:** `./properbackup-agent --activate T123` na maszynie agenta

**Then:**
- Buffer returns 200 z `{serverId, refreshToken, ...}`
- `~/.config/properbackup/global.json` zawiera te dane
- `activation_tokens.used_at` ustawione
- Druga proba uzycia tego samego tokenu: **400 TOKEN_ALREADY_USED**

**Pliki:**
- DOTYKAJ: `ActivationClient.kt`, `GlobalConfigWriter.kt`
- NIE RUSZAJ: `ActivationTokenStore.kt` server-side (juz istnieje, sprawdz semantyke)

**DoD:**
- Test integracyjny z Testcontainers + agent JVM-runner
- Test "token expired" (token starszy niz 7 dni)
- Test "user inactive" (user usuniety) — token tracenie aktywności

#### `[AGT-A2]` JWT bootstrap z refresh tokenu

**Given:** Agent ma valid `refreshToken` w global config

**When:** Agent startuje

**Then:**
- POST /agents/refresh wykonany
- Otrzymany JWT 5min ze claimami `{userId, serverId, ownerEmail, exp}`
- JWT trzymany **tylko w pamieci** (nie na dysku)
- Auto-refresh 60s przed expiry

**Tabele uzywane:** `users`, `servers`

**DoD:**
- Test "refresh token invalid" (zmieniony klucz JWT na bufferze) -> agent oddaje 401, exits
- Test "refresh token revoked" (admin usunal server) -> agent oddaje 403, exits
- JWT na dysku **nigdy**, weryfikacja przez `strings ~/.config/properbackup/` (test)

#### `[AGT-A3]` Subskrypcja wygasla mid-session

**Given:** Agent dziala, ma JWT 5min, subscription_status w bazie zmienia sie na `expired`

**When:** Agent probuje upload chunk

**Then:**
- Buffer odpowiada **403 SUBSCRIPTION_EXPIRED**
- Agent loguje, próbuje refresh
- Refresh oddaje **403 SUBSCRIPTION_EXPIRED**
- Agent zatrzymuje upload, wysyla email do `ownerEmail` (RemoteTelemetry)
- Agent NIE pisze nic do storage (cross-ref `master-tdd-plan.md` `[TDD-G1]`)

**DoD:**
- Test z chaos: zmien `subscription_status` w trakcie testu, sprawdz ze agent stoi
- Test ze JVM nie crashuje, tylko zglasza error i wraca do oczekiwania

### Grupa B: Transport — Retry & Circuit Breaker

#### `[AGT-B1]` Retry policy z exponential backoff

**Status obecny:** `RetryPolicy.kt` (39 linii) ma `maxAttempts=5, initialDelayMs=2000`. Backoff exponential?

**TODO sprawdz:** `RetryPolicy.execute()` — czy delay rosnie 2x kazda iteracja?

**Cel:** Standardowy retry z jitter:
- Attempts: 5
- Backoff: 1s, 2s, 4s, 8s, 16s (with ±20% jitter)
- Max total delay: 30s

**When:** Buffer zwraca 503 / network timeout

**Then:**
- Agent retry zgodnie z policy
- Po 5 nieudanych: raisem `TransportException`
- CircuitBreaker dostaje sygnal (zlicza fail)

**Pliki:**
- DOTYKAJ: `RetryPolicy.kt`
- NEW: `CircuitBreaker.kt`

**DoD:**
- Test z mock HTTP server zwracajacym kolejno: 503, 503, 503, 200 → agent przezwycieza po 4 probie
- Test "all fails" → exception properly typed
- Jitter test: w 100 iteracjach delay rozsypany ±20% (stat test)

#### `[AGT-B2]` Circuit breaker 3-strikes

**Cel:** Po 3 kolejnych failach z tej samej kategorii (5xx, timeout, DNS fail), CB przechodzi w stan **OPEN** na 60s. W stanie OPEN agent **nie probuje** uploadu, tylko czeka.

**Stany:**
- `CLOSED` (normal): pozwala
- `OPEN`: blokuje wszystkie uploady, czeka 60s
- `HALF_OPEN`: po 60s probuje jeden chunk. Jezeli OK → CLOSED. Jezeli fail → OPEN reset 60s.

**Pliki:**
- NEW: `properbackup-shared/.../transport/CircuitBreaker.kt`
- DOTYKAJ: `BufferUploader.kt` — wraps `doUpload` w CB

**DoD:**
- Test 4 kolejne 503: CB przechodzi w OPEN po 3-cim
- W OPEN: kolejne `upload()` rzucaja `CircuitOpenException` natychmiast (bez network call)
- Po 60s: kolejna proba half-open
- Sukces w half-open → CLOSED
- Metryki `pb_agent_circuit_breaker_state` 0/1/2

#### `[AGT-B3]` Resumable upload Content-Range

**Status obecny:** Brak. `BufferUploader.upload()` robi naive `POST /upload` z full ciałem.

**Cel:** Dla chunkow >100MB wspierac upload z resume po pakiet-loss / network drop.

**Implementacja:**
1. Agent przed wyslaniem robi `HEAD /inbox/{...}/{sha256}`
2. Buffer odpowiada `Content-Length: N` z dotychczasowym progress
3. Agent wysyla `PUT /inbox/{...}/{sha256}` z `Content-Range: bytes N-total/total`
4. Buffer appendsuje do tymczasowego pliku
5. Po sukcesie: `POST /inbox/{...}/seal`

**Pliki:**
- NEW: `properbackup-shared/.../transport/ResumableUpload.kt`
- DOTYKAJ: `BufferUploader.kt` — dla chunkow >100MB uzyj ResumableUpload zamiast classic POST
- DOTYKAJ: `properbackup-buffer/.../inbox/InboxReceiver.kt` — wsparcie HEAD i PUT z Content-Range

**DoD:**
- Test: upload 500MB chunk, przerwij po 200MB (kill HTTP client), restart agent, sprawdz że upload kontynuuje od 200MB (nie zaczyna od 0)
- Test: Content-Range walidacja w bufferze (zlosliwy `bytes 50-200/300` gdy file size = 100 → 400)
- Test: nieprawidlowy sha256 hash → po seal buffer **odrzuca** chunk, kasuje inbox file
- Test: chunk >>950MB (przekroczony pack limit) → 413 Payload Too Large

#### `[AGT-B4]` Idempotency-Key na upload

Każde `PUT /inbox/...` z naglowkiem `Idempotency-Key: <sha256>`. Buffer:
- Jezeli ten sam Idempotency-Key + ten sam URL w ciagu 24h → odsyła poprzedni response (replay)
- Zapobiega podwojnemu zapisowi gdy agent timeout'uje ale buffer zdążył przyjąć

**Pliki:** DOTYKAJ `InboxReceiver.kt` — dodaj idempotency cache (w PG lub Redis, na MVP w PG `inbox_idempotency` tabela)

### Grupa C: I/O Throttling

#### `[AGT-C1]` IoThrottle 50 MB/s read

**Status obecny:** Branch `devin/1779032082-5-feature-production` ma IoThrottle. **TODO sprawdz** strukture w `AgentMain.kt`.

**Cel:** Agent **nigdy** nie czyta szybciej niz **50 MB/s** (limit konfigurowalny w `global.json` jako `ioReadMbps`).

**Po co:** ARM64 / tanie VPS / współdzielone hostingi z innymi serwisami. Ma nie zabic IO ofiar.

**Implementacja:**
- TokenBucket lub LeakyBucket (1 token = 1 MB)
- 50 tokens/s refill rate
- Sleep gdy bucket pusty

**Pliki:**
- DOTYKAJ: `IoThrottle.kt` (jezeli juz istnieje na branchu) lub NEW
- DOTYKAJ: `AgentMain.kt` ROUTE czytania plikow przez throttle

**DoD:**
- Test: czytaj 200 MB pliku, sprawdz że całkowity czas >= 4s (200 MB / 50 MB/s)
- Test konfiguracji: ustaw `ioReadMbps=10`, sprawdz że jest 10x wolniej
- Test bez throttle (config disabled): czyta bez ograniczen

#### `[AGT-C2]` CPU throttle (post-MVP)

**Cel:** Maksimum 25% CPU w trakcie scan/encrypt na ARM64.

**Implementacja sugerowana:** `nice -n 19` przy starcie procesu, lub `taskset` (przypisanie do 1 core'a), lub aktywny sleep w petli (`Thread.sleep(75ms)` per 25ms work).

**Decyzja:** **post-MVP**, na razie tylko I/O throttle (CPU mniej dotkliwy dla ofiar). Dodaj jako `[AGT-C2]` w nastepnej iteracji.

#### `[AGT-C3]` Bandwidth throttle (network)

**Cel:** Limit szybkosci uploadu (np. 20 Mbps) aby nie zalac uplinku klienta.

**Implementacja:** Podobnie jak IoThrottle, ale na network buffer.

**Decyzja:** **opcjonalnie**, config flag `uploadMbps`. Default = unlimited.

### Grupa D: Differential Scanner & Telemetry

#### `[AGT-D1]` Scanner nie tonie pamieci

**Cel:** Skanowanie 1M+ plików nie powoduje OOM.

**Implementacja:**
- `MetadataCache` chunked write to disk (SQLite? plain file? — sprawdz aktualny)
- Streaming traversal (NIO `Files.walk()` lazy)
- Memory cap w `AgentMain.kt`: `-Xmx256m` (default w jlinkDist)

**DoD:**
- Test: utworz 1M plikow w `/tmp/test-corpus`, uruchom scanner, RAM <500MB (heap)
- Test: w trakcie scan kill scanner, restart, sprawdz że odzyskuje cache (no full rescan)

#### `[AGT-D2]` File deduplication (heuristic)

**Cel:** Plik nie zmieniony (cherry-picked po mtime + sha256) nie jest ponownie wysylany.

**Status obecny:** `DifferentialScanner.kt` powinien to robic. **Sprawdz** semantykę.

**DoD:**
- Test: zmodyfikuj 1 plik w 1000-pliku katalogu, sprawdz że tylko 1 chunk wysylany
- Test: zmiana mtime ale plik bit-identical (touch) → mimo wszystko nie wysylane (sha256 match)

#### `[AGT-D3]` Telemetria (RemoteTelemetry)

**Status obecny:** `RemoteTelemetry.kt` w shared. Sprawdz co wysyla.

**Cel:** Agent wysyla do buffera co N sekund:
- CPU/RAM/disk usage
- Backup progress (files scanned, bytes uploaded today)
- Last error
- Agent version

**Wszystko trafia do `agent_metrics` table.**

**DoD:**
- Test: agent dziala 10 min, w bazie >0 wpisow w `agent_metrics`
- Test "buffer down": agent kolejkuje telemetrie lokalnie, po przywróceniu wysyla

### Grupa E: Distribution

#### `[AGT-E1]` jlinkDist build

**Cel:** Gradle task `jlinkDist` generuje samodzielny artefakt z JRE.

**Stan obecny:** Sprawdz `build.gradle.kts` agenta.

**Wymagania:**
- Linux: tar.gz ~61MB
- Windows: zip ~70MB
- macOS: tar.gz ~65MB
- ARM64 Linux: tar.gz ~60MB (cross-compile, **TODO** sprawdz)

**DoD:**
- Build w CI dla 4 platform
- Smoke test: `./properbackup-agent --version` zwraca version z gita
- Brak external deps (`ldd` na Linux → only libc/pthread)

#### `[AGT-E2]` Aktywacja CLI

**Cel:** `./properbackup-agent --activate TOKEN` — jedno polecenie aktywuje agenta.

**Procedura:**
1. Sprawdz czy juz aktywowany (`~/.config/properbackup/global.json` istnieje) → jezeli tak, error "already activated"
2. POST /agents/activate
3. Zapisz config
4. Sukces komunikat ze instrukcja jak start (`systemd enable --now` lub `service install`)

**Pliki:**
- DOTYKAJ: `AgentMain.kt` `--activate` handler
- DOTYKAJ: `ActivationClient.kt`

**DoD:**
- Test: bad token → user-friendly error message
- Test: brak network → retry 3x z jasnym komunikatem
- Test: server already exists (re-activation z innego maszyny tego samego user'a) → unique server entry

#### `[AGT-E3]` Service installation

**Status obecny:** Branch `devin/1778954012-service-installer`. **TODO sprawdz**.

**Cel:** Jedno polecenie instaluje agenta jako:
- Linux systemd unit: `~/.config/systemd/user/properbackup-agent.service` lub `/etc/systemd/system/`
- Windows Service: NSSM lub `sc create`
- macOS launchd: `~/Library/LaunchAgents/com.properbackup.agent.plist`

**Polecenie:** `./properbackup-agent --install-service`

**DoD:**
- Per-OS test (3 separate VM-like tests)
- Po `--install-service` proces sam sie restartuje + uruchamia jako service
- `--uninstall-service` cleanly removes

#### `[AGT-E4]` Auto-update channel

**Cel:** Agent sam sciaga nowsza wersje gdy dostepna.

**Mechanizm:**
1. Co 24h agent pyta buffer: GET /agents/latest-version (zwraca `2026.05.26`)
2. Jezeli newer: download artefakt z `https://app.properbackup.pl/downloads/agent-{platform}-{version}.tar.gz`
3. Weryfikuj sha256 (publikowany pod URL `+.sha256`)
4. Wypakuj do `~/.local/share/properbackup-agent.new/`
5. Atomic rename: stop service → mv old new → start service
6. Telemetria: nowa wersja zglasza sie do buffera

**Edge cases:**
- Rollback: jezeli nowa wersja crashuje 3x w 5 min → mv stara back, alert
- Skip update flag w `global.json` (`autoUpdate: false`)
- Update tylko w "okno" 02:00-05:00 (nie w trakcie aktywnego uploadu)

**Pliki:**
- NEW: `properbackup-agent/.../updater/AutoUpdater.kt`
- NEW: route w bufferze `/agents/latest-version`

**DoD:**
- Test: mock buffer odpowiada z newer version, agent self-updatuje (na osobnym staging)
- Test "bad sha256": agent odrzuca artefakt, zostaje na starej
- Test "version downgrade attempt" (atak): agent odmawia downgrade'u (`version <= current`)

### Grupa F: Privacy / Safety

#### `[AGT-F1]` Exclude patterns

**Status obecny:** `ExcludePatterns.kt`, `ExcludeFilter.kt` w shared.

**Cel:** Agent **nigdy** nie wysyla pliku ktory zawiera:
- `.ssh/id_rsa`, `id_ed25519` itd. (private SSH keys) — **PrivacyAlertException**
- `.aws/credentials`
- `.gnupg/private-keys-v1.d/`
- `*.pem`, `*.key` (heurystyka)
- `wallet.dat` (crypto wallets)

**Po wykryciu:**
- Plik **omijany**
- Alert w UI: "Wykryto wrazliwy plik. Czy chcesz go uwzglednic? (recommended: NO)"
- Audit log w bufferze

**DoD:**
- Test: utworz `.ssh/id_rsa` w corpus, sprawdz że NIE jest w uploadowanym tar
- Test: `--include-sensitive` flag (jezeli istnieje) override'uje exclude i loguje warning

#### `[AGT-F2]` Tombstone — bezpieczne kasowanie

**Status obecny:** `TombstoneDetector.kt` w shared.

**Cel:** Gdy plik jest skasowany na maszynie, agent zaznacza go jako "tombstoned" w bazie buffera. Plik na storage NIE jest natychmiast kasowany (retencja 30 dni).

**Po 30 dniach:** PostUploadCleanup kasuje go z storage.

**DoD:**
- Test: usun plik, agent rejestruje tombstone, plik nadal w archive_snapshot z `tombstone_at = now`
- Test: po 31 dniach (mock time) cleanup task usuwa
- Test: restore tombstoned within 30d dziala (plik wciaz na storage)

#### `[AGT-F3]` GUI singleton lock

**Status obecny:** `GuiSingletonLock.kt` w shared.

**Cel:** Tylko jeden GUI process per machine (czy ma w ogole GUI? Sprawdz `AgentMain.kt` — wyglada na headless).

**Decyzja:** Jezeli MVP nie ma GUI w agencie (tylko CLI + service), to ten test **SKIP**.

### Grupa G: Error Handling

#### `[AGT-G1]` Network total outage

**Given:** Agent zaczyna upload, traci network mid-chunk

**When:** Po 5 minutach probuje znow

**Then:**
- Circuit breaker w stanie OPEN → wait 60s
- Po 60s half-open → 1 retry → fail (sieci nadal nie ma) → OPEN
- Telemetria nie wysylana, ale **lokalnie kolejkowana** w `~/.local/share/properbackup-agent/queue/`
- Po przywroceniu sieci: queue jest opozniany, telemetria flushed

**DoD:**
- Test: 2h disconnect, sprawdz że agent nie crashuje
- Test: po reconnect telemetria nadrabia (sprawdz `agent_metrics` po fakcie)

#### `[AGT-G2]` Encryption error

**Given:** ProperCrypto raise exception (klucz wadliwy)

**When:** Trafia na to przy szyfrowaniu chunka

**Then:**
- Chunk **NIE** wysylany
- Alert w telemetrii: "Encryption failed for {pathId}"
- Agent kontynuuje z nastepnym plikiem
- Wsztkie failed pliki sa zlistowane w UI: "1 file failed to backup"

**DoD:**
- Test z mock ProperCrypto rzucajacym → agent nie crashuje

#### `[AGT-G3]` Disk full lokalnie

**Given:** Agent probuje zapisac tymczasowy chunk do `/tmp`, disk full

**When:** Pack próbuje flush

**Then:**
- Alert w telemetrii
- Agent **wstrzymuje** upload (nie crashuje)
- Czeka 60s i probuje znow
- Po godzinie alarmu: email do `ownerEmail`

#### `[AGT-G4]` Klucz szyfrujacy utracony

**Cel:** Klucz szyfrowania `encryptionPassword` jest w `~/.config/properbackup/global.json`. Co jezeli plik skasowany?

**Wymagane zachowanie:**
- Agent NIE moze sie aktywowac bez klucza
- **NIE MA odzyskiwania** klucza ze strony serwera (zero-knowledge model)
- User must re-activate z nowym kluczem (stare backupy beda nieodszyfrowywalne!)
- W UI: ostrzezenie "klucz to ostatnia linia obrony, zachowaj!"

**Decyzja architekt:** Czy klucz JEST faktycznie znany tylko klientowi? Sprawdz `KeyDerivation.kt`. Jezeli buffer zna password → zero-knowledge model jest złamany. Rozwiaz to przed launchem.

**TODO przyszly agent:** sprawdz current crypto flow, zaproponuj rekomendacje w `crypto-and-compliance-spec.md`.

### Grupa H: Platforma-specyficzne

#### `[AGT-H1]` ARM64 (Raspberry Pi 4, ARM VPS)

**Cel:** Agent dziala na ARM64 bez problemow.

**Wymagania:**
- jlinkDist cross-compile dla ARM64
- IoThrottle ON by default (slabe SSD na RPi)
- Memory cap 256MB heap
- Test: faktyczny upload 1GB na RPi (manual drill)

**DoD:**
- Branch CI buildy dla `linux-arm64`
- Smoke test w docker-compose z `platform: linux/arm64` (qemu)

#### `[AGT-H2]` Windows (firewall, paths z spacjami, antywirus)

**Edge cases:**
- Defender flagi jar/exe jako "virus" — code signing certificate wymagany (kosztuje, post-MVP)
- Paths z polskimi znakami (`C:\Users\Daniel\Dokumenty`) — UTF-8 handling
- Backslash separators
- Long paths >260 chars (`\\?\` prefix)

**DoD:**
- Test "polish characters in path"
- Test "long path"
- Manual: zainstaluj na Win10/11, sprawdz ze Defender nie flaguje (jeszcze bez signing)

#### `[AGT-H3]` macOS (gatekeeper, sandbox)

- Gatekeeper: trzeba signed + notarized binary (post-MVP, kosztuje 99 USD/rok)
- Alternatywa MVP: instrukcja "right-click -> Open" na pierwszym uruchomieniu (gdy unsigned)
- Sandbox: brak. Agent musi miec full disk access (manual w System Preferences)

**DoD:** Manual test na Macu, ze instrukcje dzialaja.

---

## 6. Edge Cases (15+)

### 6.1 Agent restartowany 100x w ciagu min

**Cel:** Zaden race condition w `global.json` (np. dwa procesy pisza w tym samym czasie).

**Wymagane:** File lock (`AgentInstanceLock.kt` — sprawdz semantyke). Drugi agent exit cleanly.

### 6.2 Agent dziala z replikowanego image (cloud snapshot)

User snapshotuje VPS, restoruje na drugiej maszynie. Dwie machineId beda kolidowac.

**Wymagane:**
- machineId regenerated jezeli detect "new MAC" + "new hostname" + "new disk UUID" combo
- Lub: prompt user przy starcie ("Wykryto przeniesione installation, czy chcesz utworzyc nowy server entry?")

### 6.3 Agent ma godzine drift

**Cel:** Zegar systemu klienta drift'uje. Agent uzywa `Instant.now()` do timestampow.

**Wymagane:**
- JWT validation tolerates ±5min skew (juz w buffer side, `master-tdd-plan.md` `[TDD-B3]`)
- Telemetria timestamp z buffer side, nie agent side

### 6.4 Race: scanner enkapsulując vs Stop signal

User kill -TERM agent w trakcie scan. Agent przerywa cleanly:
- Flush MetadataCache
- Cancel pending uploads
- Send "shutdown" telemetry

### 6.5 Plik zmienia sie w trakcie upload

User edytuje plik X w trakcie agent reading X. Agent dostaje partial old + partial new content. **Wynik:** sha256 inconsistent z metadata.

**Wymagane:**
- Po pakowaniu, agent re-checks sha256
- Jezeli zmiana → tar pack rebuild
- Jezeli zmiana 3x z rzedu → skip plik, alert "file constantly changing"

### 6.6 Symlink loop

Plik wskazuje na siebie. Scanner wpada w petle.

**Wymagane:** `Files.walk()` z `FileVisitOption.FOLLOW_LINKS=false` (default w Java).

### 6.7 Permission denied

Agent nie ma uprawnien do czytania pliku.

**Wymagane:** Loguj warning, kontynuuj scan. Nie crashuj.

### 6.8 Agent process killed by OOM (Linux)

systemd restart automatycznie. Sprawdz `Restart=on-failure` w unit file.

### 6.9 Klient zmienia plan w trakcie aktywnego uploadu (downgrade)

Klient byl na Pro 1TB, jest 800GB. Downgrade na Hobby 100GB. **Co sie dzieje?**

**Wymagane:**
- StorageQuotaGuard sprawdza przy KAZDYM upload (`[TDD-G1]`)
- Pierwszy upload nad 100GB → 403 QUOTA_EXCEEDED
- UI: "Zmniejszyles plan ale masz 800GB danych. Albo upgraduj, albo skasuj stare backupy."
- Storage NIE jest auto-kasowany (klient moze restore w okresie grace)

### 6.10 Stack trace z agenta zawiera password / klucz

Agent loguje `Failed to encrypt with key ABC123`. Klucz w stack trace.

**Wymagane:**
- RemoteTelemetry maskuje pole `encryptionPassword` przed wyslaniem
- StackLogStore w bufferze ma drugi filter (regex masking)

### 6.11 Server name z emoji / RTL

Klient nazywa server `🚀 Production`. Trzeba zachowac UTF-8.

**Wymagane:** UTF-8 wszedzie. Test z RTL/emoji/CJK.

### 6.12 Path z newline w nazwie

Linux pozwala. `printf "a\nb" > 'evil\nfile'`.

**Wymagane:** Filename grammar (`FilenameGrammar.kt`) odrzuca takie pliki (security).

### 6.13 Bind mount / overlay filesystem

Agent skanuje `/var/lib/docker` zawierajace overlay layers. Petle, duplicate inode.

**Wymagane:** Exclude default `/var/lib/docker`, `/proc`, `/sys`, `/dev`, `/run`.

### 6.14 NFS / network filesystem

Backup z NFS — stale handles, EIO errors. Network drop → wszystkie pliki "znikaja".

**Wymagane:**
- Detekcja NFS (sprawdzanie mount type) → warning
- Tolerancja EIO (skip plik, kontynuuj)

### 6.15 Pelny dysk lokalny w trakcie TarGzPacker

Pack budowany w `/tmp`, /tmp pelny.

**Wymagane:**
- Pack pisany do storage path (konfigurowalne, default `~/.local/share/properbackup-agent/cache/`)
- Pre-check: `Files.getFileStore(...).getUsableSpace() > 2 * estimatedPackSize`
- Jezeli za malo: skip flush, retry za 5min, alert po 1h

---

## 7. Definition of Done

10 kryteriow per task (identyczne jak `master-tdd-plan.md`):

1. Red test first (failing test commit)
2. Test integracyjny z **prawdziwy buffer** (Testcontainers spinning up buffer service)
3. Brak nowych top-level deps bez approval
4. Brak sekretow w logach / stack tracach
5. DOTYKAJ zone respected
6. Update odpowiednich docs (np. README agenta)
7. Smoke test na test serverze
8. Idempotent operations (gdzie dotyczy)
9. Telemetria z metryka per feature
10. Rollback plan w PR

---

## 8. TDD Workflow Protocol

(podobnie jak `master-tdd-plan.md` sekcja 11)

1. **Scope:** Wybierz jeden test `[AGT-Xn]` z grup A-H
2. **Red test:** Napisz failing test w `src/jvmTest/`
3. **Green impl:** Najmniejsza zmiana zeby test przeszedl
4. **Refactor:** Jezeli kod jest brzydki, refactor (tylko w obrebie DOTYKAJ)
5. **Audit trail:** Update audit log (`[AGT-Xn] DONE`)
6. **PR:** Tytul `feat(agent): [AGT-Xn] <description>`, link do tego docu

### Czerwone linie

- **Nie** modyfikuj `ProperCrypto.kt`, `KeyDerivation.kt`, `HeaderCodec.kt`
- **Nie** dodawaj globalne deps bez approval
- **Nie** breaking change w `BufferUploader` public API (MC plugin zalezy)
- **Nie** pisz logi z sekretami

---

## 9. Sequence of work

1. **`[AGT-A2]` JWT bootstrap** — bez tego cala reszta nie ma sensu
2. **`[AGT-A3]` Subscription expiry mid-session** — billing enforcement
3. **`[AGT-B1]` Retry policy review** — fundament
4. **`[AGT-B2]` Circuit breaker** — odpornosc na network problems
5. **`[AGT-B3]` Resumable upload** — bez tego duze backupy slabo
6. **`[AGT-B4]` Idempotency-Key** — zapobiega doublecharge w PG
7. **`[AGT-C1]` IoThrottle integration** — UX dla niskich VPS
8. **`[AGT-E3]` Service installer** — production deployment
9. **`[AGT-E4]` Auto-update channel** — operational must-have
10. **`[AGT-H1]` ARM64 cross-compile** — szerszy market
11. **`[AGT-H2]` + `[AGT-H3]` Windows + macOS edge** — gdy budget pozwala na signing
12. **`[AGT-C2]` CPU throttle** — post-MVP
13. **`[AGT-C3]` Bandwidth throttle** — post-MVP

---

## 10. Go/No-Go checklist przed live

- [ ] JWT 5-min flow dziala
- [ ] Subscription enforcement: agent zatrzymuje sie po wygasnieciu
- [ ] Resumable upload: chunk 500MB z 200MB interrupt = sukces
- [ ] Circuit breaker: 3 fails -> OPEN, recovery po 60s
- [ ] IoThrottle: 50 MB/s default, konfigurowalne
- [ ] Idempotency-Key: drugi upload tego samego chunka -> instant 200
- [ ] Telemetria: agent_metrics ma dane, nie ma sekretów w stack trace
- [ ] jlinkDist build dla Linux/Win/Mac/ARM64
- [ ] `--activate TOKEN` dziala, error gdy zly token
- [ ] `--install-service` (Linux systemd) dziala
- [ ] Auto-update channel: sciaga newer version, weryfikuje sha256, atomic restart
- [ ] PrivacyAlert: SSH key NIE jest w backup
- [ ] Disk full handling: graceful degradation
- [ ] OOM resilience: systemd restart
- [ ] Manual drill na RPi 4 (ARM64) — 1GB backup udany

---

## Dodatek A — Linki

- `master-tdd-plan.md` — billing (subskrypcyjne enforcement linki)
- `observability-and-dr-spec.md` — telemetria, alerty
- `buffer-core-master-spec.md` — server-side dla resumable upload
- `crypto-and-compliance-spec.md` — opis ProperCrypto (zamrozone)
- `ci-cd-release-pipeline-spec.md` — jak budowac jlinkDist

## Dodatek B — Glosariusz

- **jlinkDist** — Gradle task generujacy samodzielny artefakt z JRE + jar (`jlink` Java tool)
- **TokenBucket / LeakyBucket** — algorytm throttlingu
- **machineId** — UUID v4 generowany przy pierwszym starcie, identyfikuje fizyczna maszyne
- **serverId** — UUID v4 wygenerowany przez buffer przy aktywacji, identyfikuje logiczny server (1 user moze miec N serverow)
- **Resumable upload** — protokol z `Content-Range` pozwalajacy wznowic upload po interrupcie
- **Circuit Breaker** — pattern: open/closed/half-open
- **Tombstone** — soft-delete marker dla pliku, retencja 30 dni
- **PrivacyAlert** — exception rzucany przez `ExcludeFilter` na wrazliwy plik
- **Telemetria** — heartbeat + metryki + bledy wysylane do buffera
- **POLL_INTERVAL** — czestotliwosc skanowania, default 5 min
