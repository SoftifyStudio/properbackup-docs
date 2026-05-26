# Minecraft Plugin — Master Plan

Wersja: 1.1 (initial, post-MVP placeholder, ready do implementacji) — **2026-05-26: dodano sekcje 0 Hard Requirements + odwolanie do `shared-core-architecture-spec.md` (Daniel ack)**
Repo: `properbackup-mc` (aktualnie placeholder — tylko README)
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P3** (po stabilizacji core: shared #7 + buffer #13)

---

## 0. Hard Requirements (Immutable Rules) — PRAWO PROJEKTU

> **Te zasady sa NIENARUSZALNE. Wymuszone przez Daniela jako twardy contract dla MC plugin. Kazde naruszenie = automatic rejection PR-a w review.**
>
> Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint` (sekcja 2.1 Master Blueprint — "jeden JAR agent KMP, MC plugin to thin wrapper")
> Architecture foundation: `shared-core-architecture-spec.md` (P0, MUSI byc zaimplementowany PRZED tym specem)

**HR-1. Shared-Core Only (zero duplikacji w mc-plugin)**
Cala logika domenowa agenta (transport, szyfrowanie, scanner, retry, circuit breaker, JWT, throttle) ZYJE w `properbackup-shared`. `properbackup-mc` zawiera WYLACZNIE:
- `PaperHostAdapter` (implementujacy `HostAdapter` z shared)
- `ProperBackupPlugin` extends JavaPlugin — wpis onEnable/onDisable
- `BukkitPlatformFs` (delegacja do `plugin.dataFolder` zamiast `~/.properbackup`)
- Komendy `/properbackup activate|status|backupnow|help` (cienkie, delegate do `core`)
- WorldSaveListener — slucha BukkitEvents, woluje `core.runBackupNow()` (lub schedules)

NIE WOLNO duplikowac BufferUploader, ProperCrypto, RetryPolicy, DifferentialScanner w mc-plugin. Jezeli czegos brak w shared — PR do shared.

**HR-2. JEDEN JAR — embedded shared**
Plugin .jar (shadowJar) BUNDLE shared classes (z `properbackup-shared:${version}` zaleznosc). Ta sama wersja shared co `agent-vps`. Test deployment: ten sam plugin .jar dziala na:
- Paper 1.21.x (testowane)
- Spigot 1.21.x (testowane)
- Folia (testowane, regional schedulers)
- Bukkit 1.21.x (fallback — chociaz deprecated)

Cross-host parity test (`shared-core-architecture-spec.md` SHC-D1): plugin uplaod identyczny SHA-256 co VPS dla tego samego pliku.

**HR-3. Future Fabric/Forge mods — ten sam shared, inny wrapper**
Architektura przygotowana dla Fabric mod i Forge mod (post-MVP):
- `FabricHostAdapter` extends `HostAdapter` — uzywa FabricLoader API
- `ForgeHostAdapter` extends `HostAdapter` — uzywa Forge ServerEvents
- KAZDY wrapper to thin layer 50-100 linii, reszta z shared

Decyzja: poczatkowy release tylko Paper/Spigot. Fabric/Forge dodajemy gdy core stabilne (post-launch v1.0).

**HR-4. Plugin Reload Safety**
Paper/Spigot reload (`/reload`) MUSI byc safe:
- `onDisable()` woluje `core.stop()` — graceful shutdown JWT refresh, IoThrottle, scheduler
- Czeka na pending upload max 30s, potem force-kill
- Po reload: `onEnable()` zaczyna od czystej slade, czyta state z `dataFolder/state.json`
- Test: MockBukkit symuluje reload — backupy w toku musza dokończyc lub zostac resumes

**HR-5. World Save Hook (post-`/save-all`)**
WorldSaveListener implementuje `WorldSaveEvent` listener:
- Po `WorldSaveEvent` (lub manual `/save-all`) -> trigger backup tego konkretnego world dir
- Per-world configurable: backup co N save event (default 1 = kazdy save)
- Test: MockBukkit triggers WorldSaveEvent, plugin musi wlasnie wystartowac backup

**HR-6. Activation Token Flow `/properbackup activate <token>`**
- Komenda parse token z arg
- Wywoluje `core.activate(token)` z shared
- Token TRAFIA do `dataFolder/config.yml` (via `BukkitPlatformFs`), NIGDY do `~/.properbackup`
- Po success: ServerStateStore.persist(serverConfig) — zapisuje server_id, jwt, encryption_key

**HR-7. Performance Budget (shared hosting safe)**
Host capability `maxIoBytesPerSec = 25 MB/s`, `cpu_percent = 15%` (shared hosting safety).
- IoThrottle bierze min(host, user_config)
- BackupOrchestrator schedules backups na cron (default: co 6h, configurable)
- Brak long-running threads — uzywa Bukkit `runTaskAsynchronously` (NIE `new Thread()`)
- Memory budget: <100MB working set (shared hosting servers maja czesto 1-2GB RAM total)

**HR-8. Bukkit/Folia Compat Matrix (must-pass)**
Plugin MUSI byc przetestowany na:
- Paper 1.20.x, 1.21.x
- Spigot 1.20.x, 1.21.x
- Folia 1.21.x (regional schedulers — wykrywa runtime czy Bukkit.isFolia())
- Bukkit 1.21.x (fallback, not officially supported)

Compat detection w `PaperHostAdapter` runtime:
- `Bukkit.getServer().javaClass.simpleName` -> identyfikuje host
- `try { Class.forName("io.papermc.paper.threadedregions.RegionizedServer"); isFolia = true } catch...`

**HR-9. NIE WOLNO modyfikowac shared z mc-plugin PR-a**
Jezeli plugin potrzebuje czegos czego brak w shared — **stworz PR do `properbackup-shared` FIRST**, wait for merge, THEN PR do mc-plugin uzywajac nowej wersji. NIE WOLNO fork shared, NIE WOLNO patch shared lokalnie.

**HR-10. Cross-Host Parity Test (Daniel mandatory)**
W CI mc-plugin musi zostac uruchomiony test ktory:
1. Uruchamia MockBukkit server
2. Loaduje plugin .jar (shadowed shared)
3. Plugin aktywuje sie z mock activation token
4. Upload deterministic 100MB test file
5. SHA-256 final blob na mock-OVH = expected hash (taki sam jak `agent-vps`)
6. Failure = blok release

Test live w `properbackup-shared/src/jvmTest/.../CrossHostParityTest.kt` (collocated z VPS test, by gwarantowac identyczna implementacje).

---

## 1. Cel dokumentu

Plan budowy plugin'u Minecraft (Paper/Spigot) do automatycznego backupowania serwerów Minecraft (world data, plugin configs, JAR files) do ProperBackup.

**Status repo `properbackup-mc`:** placeholder — tylko `README.md` z jednym wierszem. Plugin jeszcze nie istnieje. To dokument projektowy dla startu prac.

**Dependency:** `shared #7` (filename grammar, transport BufferUploader) + `buffer #13` (server activation, JWT bootstrap) **musza byc** stabilne **przed startem** tego plugin'u — sa fundamentalne building blocks.

Brat dokumentu `master-tdd-plan.md`, `agent-vps-master-spec.md`, `buffer-core-master-spec.md`.

### Co JEST w zakresie

- Plugin lifecycle (onEnable/onDisable)
- Komenda `/properbackup activate <token>`
- World save hooks (po `/save-all` lub auto-save event)
- Periodic backup scheduling (przykł co 6h)
- Plugin reload safety (state preservation)
- Paper/Spigot/Folia API compatibility matrix
- Minecraft hosting environment specifics (shared resource limits, OOM tendencies)
- Plugin update channel
- Integration z transport layer (BufferUploader, shared)

### Co NIE jest w zakresie

- Modyfikacja kodu shared/buffer (NIE RUSZAJ — to repo separate)
- Bukkit (oryginalny, no longer maintained) — focus tylko Paper/Spigot/Folia
- Fabric/Forge mods (architecturally different, post-MVP separate)
- Bedrock servers (Minecraft Bedrock) — post-MVP separate
- Web UI dla plugin'u (uzywa głównego web panelu poprzez activation token)

---

## 2. Mapowanie kodu (do zbudowania)

### 2.1 Spodziewana struktura repo

```
properbackup-mc/
├── README.md                                # 1-liner, needs expansion
├── LICENSE                                  # ? (sprawdz, jezeli brak: copy z root)
├── build.gradle.kts                         # NEW: Kotlin build
├── settings.gradle.kts                      # NEW
├── plugin.yml                               # Paper plugin descriptor
├── src/main/kotlin/pl/danielniemiec/properbackup/mc/
│   ├── PropertyBackupPlugin.kt              # JavaPlugin entry
│   ├── command/
│   │   ├── PropertyBackupCommand.kt         # /properbackup <subcommand>
│   │   ├── ActivateSubcommand.kt
│   │   ├── StatusSubcommand.kt
│   │   ├── BackupNowSubcommand.kt
│   │   └── HelpSubcommand.kt
│   ├── lifecycle/
│   │   ├── BackupScheduler.kt               # Bukkit scheduler
│   │   ├── WorldSaveListener.kt             # WorldSaveEvent
│   │   └── ShutdownHandler.kt
│   ├── config/
│   │   ├── PluginConfig.kt                  # config.yml
│   │   └── ServerStateStore.kt              # plugins/ProperBackup/state.json
│   ├── transport/
│   │   └── BufferUploaderAdapter.kt         # uses shared BufferUploader
│   └── safety/
│       ├── PluginReloadGuard.kt
│       └── PerformanceGuard.kt
└── src/test/kotlin/...                      # MockBukkit tests
```

### 2.2 Dependencies

```kotlin
// build.gradle.kts (template)
plugins {
    kotlin("jvm") version "2.0.0"
    id("xyz.jpenilla.run-paper") version "2.3.0"
}

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    compileOnly("io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT")
    implementation(project(":properbackup-shared"))  // jezeli local multi-module, inaczej Maven Central
    testImplementation("com.github.seeseemelk:MockBukkit-v1.21:3.X.X")
}
```

**NOTE:** Plugin **shaduje** shared classes do swojego JAR (dla independence od server classpath). Konieczna jest `shadowJar` task.

### 2.3 Plugin metadata (plugin.yml)

```yaml
name: ProperBackup
version: 1.0.0
main: pl.danielniemiec.properbackup.mc.PropertyBackupPlugin
api-version: '1.20'
authors: [Daniel Niemiec]
description: Automatic Minecraft backups to ProperBackup cloud
website: https://app.properbackup.pl
commands:
  properbackup:
    description: ProperBackup management
    permission: properbackup.admin
    usage: /<command> <subcommand>
permissions:
  properbackup.admin:
    description: Manage ProperBackup plugin
    default: op
```

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (cross-repo, frozen)

- `properbackup-shared/.../core/crypto/*` — encryption layer
- `properbackup-shared/.../core/filename/FilenameGrammar.kt`
- `properbackup-shared/.../transport/BufferUploader.kt` public API — plugin uses **public methods only**
- `properbackup-shared/.../activation/*` — activation client
- `properbackup-buffer` — NIE modyfikuj, plugin tylko consumer
- World data files na serwerze Minecraft (oczywiscie — backup, not modify)

### DOTYKAJ (mozna w tym repo)

- `properbackup-mc/build.gradle.kts` — dodaj features
- `properbackup-mc/plugin.yml` — dodaj commands, permissions
- Wszystko w `src/main/kotlin/pl/danielniemiec/properbackup/mc/`

### MOZESZ TWORZYC

- Wszystko w `properbackup-mc/src/`
- Test pliki w `properbackup-mc/src/test/`
- `properbackup-mc/README.md` (rozszerz, instrukcja installation)
- `properbackup-mc/docs/compatibility-matrix.md`

---

## 4. Domain Model

### 4.1 Lifecycle

```
1. Server admin pobiera JAR z app.properbackup.pl
2. Drop do plugins/ folderu
3. /reload lub restart serwera
4. Plugin onEnable():
   - Read plugins/ProperBackup/config.yml
   - Read plugins/ProperBackup/state.json (encryptedKey, serverId, refreshToken if activated)
   - Jezeli unactivated:
     - Log: "ProperBackup not activated. Use /properbackup activate <TOKEN>"
   - Jezeli activated:
     - JWT bootstrap (refresh token → access token)
     - Schedule backup task (BackupScheduler, run every 6h default)
     - Register WorldSaveListener
5. /properbackup activate <token>:
   - ActivationClient.activate(token, machineId, "Minecraft Server")
   - Save state.json with refresh token + serverId
   - Message: "ProperBackup activated! Server ID: ..."
6. /properbackup backup now:
   - Force /save-all 
   - Wait for save complete
   - Trigger backup task immediately
7. Normal operation:
   - World save event (lub scheduled) → backup task runs
   - Backup task: scan plugins/, world/, world_nether/, world_the_end/, server.properties
   - Pack via TarGzPacker (shared)
   - Encrypt (ProperCrypto)
   - Upload (BufferUploader)
   - Report telemetry
8. onDisable():
   - Cancel pending tasks
   - Save state.json (telemetria last-run timestamp)
   - Close BufferUploader connections cleanly
```

### 4.2 Plugin command interface

```
/properbackup help
  Wyswietl liste komend

/properbackup activate <TOKEN>
  Aktywuj plugin z token jednorazowym

/properbackup status
  Pokaz status: connected, last backup, next backup, total uploaded today

/properbackup backup now
  Wymus immediate backup

/properbackup config get|set <key> [value]
  Edycja config przez komende (alternatywa do config.yml)

/properbackup exclude add|remove <pattern>
  Dodaj/usun pattern (np. cache/, *.log)

/properbackup uninstall
  Plugin pozostaje na serwerze, ale state.json kasowany (deactivation)
```

### 4.3 Config (plugins/ProperBackup/config.yml)

```yaml
# Properbackup Minecraft Plugin config

# Activation state w state.json, NIE tutaj (sekrety)

backup:
  interval-hours: 6
  trigger-on-world-save: true
  paths:
    - world/
    - world_nether/
    - world_the_end/
    - plugins/  # zawiera configs innych pluginow
    - server.properties
    - ops.json
    - whitelist.json
  exclude:
    - "*.log"
    - "cache/"
    - "logs/"
    - "*.tmp"
    - "*.pid"
    - "plugins/dynmap/"  # gigantyczny cache, opcjonalne
    - "plugins/CoreProtect/database.db-shm"
    - "plugins/CoreProtect/database.db-wal"

io-throttle:
  enabled: true  # NA Bukkit servers ZAWSZE rekomendowane
  read-mbps: 25  # mniej niz default VPS bo MC server share I/O
  cpu-percent: 15

performance:
  pause-during-backup: false  # jezeli true, server zatrzymuje sie podczas backup
  max-duration-minutes: 10  # timeout (jezeli longer, abort + alert)
  
telemetry:
  enabled: true
  level: normal  # normal | verbose | minimal
```

### 4.4 State (plugins/ProperBackup/state.json)

```json
{
  "version": 1,
  "activated_at": "2026-05-26T18:00:00Z",
  "server_id": "uuid",
  "machine_id": "uuid",
  "refresh_token": "<encrypted by OS keystore if available, else plain>",
  "encryption_password_hint": "<encrypted recovery hint>",
  "last_backup_at": "2026-05-26T18:00:00Z",
  "last_backup_status": "success",
  "total_uploaded_bytes_today": 1234567890,
  "buffer_url": "https://app.properbackup.pl/api"
}
```

**Note:** `refresh_token` w plain ze wzgledu na brak OS keystore w typowym shared MC hosting. Compensating control: world directory ma typowo `rwx------` chmod, tylko process owner czyta.

---

## 5. Test Groups

Numerowanie `[MC-Xn]`.

### Grupa A: Lifecycle

#### `[MC-A1]` Plugin enable/disable

**Given:** JAR upuszczony do plugins/, server restart

**When:** Server starts

**Then:**
- Logs: "[ProperBackup] Loading version 1.0.0..."
- onEnable executed
- jezeli activated: scheduler started, listener registered
- jezeli unactivated: warning log

**DoD:**
- MockBukkit test: server start → plugin loaded
- Test "config.yml missing" → default created
- Test "state.json missing" → no-op (unactivated mode)
- Test "state.json corrupted JSON" → log error, treat as unactivated

#### `[MC-A2]` Plugin reload (Bukkit /reload)

**Given:** Plugin active, backups runnings

**When:** Admin runs `/reload`

**Then:**
- onDisable cancels pending tasks gracefully (do nie zostawiac thread-leak)
- onEnable re-init cleanly
- Existing scheduled backups resume
- Telemetria: "plugin reloaded" event

**DoD:**
- Test ze /reload nie crashuje (MockBukkit)
- Test ze nadchodzacy world save event po reload triggeruje backup (event subscriber re-registered)
- Test "reload mid-backup" — backup task continues lub aborts cleanly (nie zostawia partial)

#### `[MC-A3]` Server shutdown w trakcie backup

**Given:** Backup task running (upload chunks)

**When:** Server admin stops server (Ctrl+C or /stop)

**Then:**
- onDisable executed
- Backup task receives interrupt
- Pending upload: pause (resumable upload, cross-ref `agent-vps-master-spec.md` `[AGT-B3]`)
- Next plugin enable: resume upload od interrupted offset

**DoD:**
- Test stop mid-upload → no corrupted partial
- Test next start → resume Content-Range

### Grupa B: Activation

#### `[MC-B1]` /properbackup activate happy path

**Given:** Plugin loaded, unactivated, valid token `ABC-123-XYZ`

**When:** Op runs `/properbackup activate ABC-123-XYZ`

**Then:**
- ActivationClient.activate(token, machineId, "Minecraft Server: <hostname>")
- 200 response, save state.json
- Message to op: "ProperBackup activated. Server ID: ..."
- First backup task scheduled immediately
- Audit log entry server-side

**Edge cases:**
- Non-op uses command → permission denied
- Token expired (>7 dni) → "Token expired, generate new in web panel"
- Token already used → "Token already used by another machine"
- Buffer offline → "Connection error, retry"

**DoD:**
- MockBukkit test happy path
- Test op-only enforcement
- Test 4 error cases (expired/used/offline/invalid)

#### `[MC-B2]` Re-activation

**Given:** Plugin already activated (state.json exists)

**When:** Op runs `/properbackup activate NEW-TOKEN`

**Then:**
- Confirm: "Server already activated. Re-activate? This will lose access to old backups. [Yes/No]"
- Jezeli No: abort
- Jezeli Yes: backup state.json → state.json.bak, init nowy

**DoD:**
- Test confirmation flow
- Test bak file dla rollback

#### `[MC-B3]` Token from environment variable

**Cel:** Dla auto-deployment (Docker MC), token z env var: `PROPERBACKUP_ACTIVATION_TOKEN`.

**Implementacja:**
- onEnable sprawdza state.json, jezeli unactivated:
  - Sprawdz env var
  - Jezeli set: auto-activate (no /properbackup activate needed)

**DoD:**
- Test env var → auto-activated
- Test env var + state.json present → ignored (state.json wins)

### Grupa C: Backup scheduling

#### `[MC-C1]` Periodic backup

**Given:** Plugin active, config interval=6h

**When:** 6h passed since last backup

**Then:**
- Scheduler triggers backup task
- Backup runs async (NIE blokuje main thread)
- Logs: "[ProperBackup] Backup started" / "Backup complete: 1.2 GB in 5 min"

**DoD:**
- MockBukkit test ze scheduler fires po 6h (mock time)
- Test backup running async (main thread not blocked)
- Test concurrent triggers (manual + scheduled) → 1 wins, 2nd skips

#### `[MC-C2]` World save event trigger

**Given:** Config `trigger-on-world-save: true`

**When:** /save-all executed (or auto-save)

**Then:**
- WorldSaveEvent fired
- Listener triggers backup task po short delay (5s, aby save complete)
- Logs: "[ProperBackup] World saved, starting backup"

**Edge cases:**
- Multiple worlds save w short time → debounce (1 backup, nie 3)
- World save fails → backup NIE triggers (nie ma valid data)

**DoD:**
- MockBukkit test WorldSaveEvent fire → backup scheduled
- Test debounce: 3 events w 10s → 1 backup task

#### `[MC-C3]` Backup task timeout

**Cel:** Backup task nie moze dzialac dłużej niz `max-duration-minutes` (default 10).

**Implementacja:**
- Wrap task w timeout
- Po timeout: cancel, log alert
- Failed backup state.json status="timeout"

**DoD:**
- Test backup task >10 min (simulate slow upload) → killed cleanly
- Test next backup attempt po failure

#### `[MC-C4]` Pause during backup (optional)

**Given:** Config `pause-during-backup: true`

**When:** Backup starts

**Then:**
- `/save-off` (zapobiega writes w trakcie backup)
- Backup runs
- `/save-on` po backup

**Tradeoff:** Mniejszy risk corruption, ale player'zy widza freeze.

**DoD:**
- Test config flag respected
- Test "server crashes mid-pause" — odzyskanie /save-on po restart

### Grupa D: Files i exclusions

#### `[MC-D1]` Default backup paths

**Cel:** Backup obejmuje:
- `world/` (region/, playerdata/, etc.)
- `world_nether/`
- `world_the_end/`
- `plugins/` (configs)
- `server.properties`
- `ops.json`, `whitelist.json`, `banned-players.json`, `banned-ips.json`

**NIE obejmuje (default exclude):**
- `*.log`
- `cache/`
- `logs/`
- `.git/`
- `crash-reports/` (opcjonalnie zostaw)
- `plugins/dynmap/web-cache/` (gigantyczny tile cache)
- `plugins/CoreProtect/database.db-{shm,wal}` (SQLite WAL)
- Database backup tools (Essentials backups, BackupBackup...) — wykluczone (own backup is mc itself)

**DoD:**
- Test scanner enumerates paths zgodnie z config
- Test exclude patterns aplikowane (test `.log` exclude)

#### `[MC-D2]` Plugin data sensitivity

**Cel:** Niektore plugins maja sekrety w configs:
- `plugins/AuthMe/*` (player passwords hashed but still sensitive)
- `plugins/LuckPerms/*` (permissions, ok)
- `plugins/Vault/*`
- `plugins/Multiverse-Core/*`
- API keys w plugin configs (Pterodactyl, Discord webhooks)

**Wymagane:**
- Backup zawiera te pliki (klient tak chce, all configs)
- Encryption boundary (ProperCrypto) chroni przy storage
- Komunikat w README: "All your plugin configs will be backed up encrypted"

**DoD:**
- Test backup includes all configs by default
- Test exclude pattern moze blokowac specific plugins (np. `plugins/AuthMe/*`)

#### `[MC-D3]` World file locking (Minecraft holds open files)

**Problem:** Minecraft server has world files mapped via mmap, exclusive lock.

**Wymagane:**
- Backup uses snapshot mechanism:
  - Either: `/save-off` przed backup (loss player progress mid-backup risk)
  - Or: read with `O_RDONLY` (works on most filesystems even with exclusive lock)
  - Or: copy-on-write filesystem (ZFS/btrfs) snapshot before backup (post-MVP)
- Catch IOException on locked files, log warning, skip
- Region files: skipped jezeli .mca currently being written → next backup will catch

**DoD:**
- Test "file locked" → skip + log warning, no crash
- Test post-backup check: % files successfully read

#### `[MC-D4]` Folia compatibility (regionized threading)

**Folia** is Paper fork z regionized threading (no central main thread).

**Wymagane:**
- Plugin nie zaklada single main thread
- Uses GlobalRegionScheduler dla globalnych zadan
- Per-world scheduling: RegionScheduler dla world data backup

**DoD:**
- Test plugin loads w Folia (separate matrix in CI)
- Test backup task does NOT block any region thread
- Compat matrix: `properbackup-mc/docs/compatibility-matrix.md` z Paper/Folia/Spigot

### Grupa E: Performance

#### `[MC-E1]` IoThrottle dla MC

**Cel:** Backup nie zabija performance serwera Minecraft.

**Implementacja:**
- Cross-ref `agent-vps-master-spec.md` `[AGT-C1]` IoThrottle
- Default w MC: 25 MB/s read (mniej niz default 50 MB/s VPS)
- Reason: MC server share I/O z World R/W → spike przy backup powoduje lag

**DoD:**
- Test backup w trakcie player aktywnosci → TPS (ticks per second) >=18 (akceptowalne, default 20)
- Test config respect (25 MB/s vs 10 MB/s)

#### `[MC-E2]` CPU budget

**Cel:** Backup nie zabija CPU (compression w TarGzPacker).

**Implementacja:**
- Compression w background thread z `nice 19`
- Lub: use compression level 1 (gzip, faster vs compressing)
- Lub: skip compression dla .mca (already compressed via Minecraft chunk format)

**DoD:**
- Benchmark: backup of 5GB world → CPU usage <30% on average

#### `[MC-E3]` Memory budget

**Cel:** Plugin nie powoduje OOM na serwerze Minecraft.

**Wymagane:**
- Streaming read (`Files.newInputStream`)
- TarGzPacker streams chunks (nie loads full plik)
- Max heap usage <100MB during backup (note: small, dedicated to plugin)

**DoD:**
- Profile backup of 5GB world → heap usage <100MB (per profiler)
- Test "OOM resilience": small heap (-Xmx2g) MC server → backup nadal działa

### Grupa F: Telemetria

#### `[MC-F1]` Status command

**When:** `/properbackup status`

**Then:**
- Message:
  ```
  ProperBackup Status:
  - Server ID: abc-123 (xxx@example.com)
  - Activated: 2026-05-26
  - Last backup: 5 min ago (success, 1.2 GB)
  - Next backup: in 5h 55m
  - Total today: 3.4 GB
  - Plan: Pro (1 TB), used: 230 GB
  ```

**DoD:**
- Test command output formatted
- Test "no active subscription" → warning message

#### `[MC-F2]` Remote telemetria

**Cel:** Plugin reportuje status do buffera (heartbeat).

**Implementacja:** Re-use `RemoteTelemetry.kt` z shared.

**Event types:**
- Periodic heartbeat (co 5 min): TPS, player count, last backup status
- Per-backup: success/failure, duration, bytes
- Errors: plugin reload, world save failed, OOM warnings

**DoD:**
- agent_metrics w bufferze ma wpisy z plugin
- Test heartbeat scheduling (mock time)

#### `[MC-F3]` In-game alerts

**Cel:** Alert dla op-ów w game (chat):
- Trial wygasa za 7 dni
- Plan przekroczony (storage cap)
- Backup nieudany 3x z rzedu

**Implementacja:**
- onJoin event: if op, send pending alerts as chat message
- Periodic: kazda godzine sprawdz `users.subscription_status` cache

**DoD:**
- Test alert dispatched do op w chat
- Test non-op ignore (privacy)

### Grupa G: Plugin update channel

#### `[MC-G1]` Auto-update check

**Cel:** Plugin sprawdza co 24h czy jest newer version.

**Implementacja:**
- Re-use `AutoUpdater.kt` z agent (cross-ref `[AGT-E4]`)
- Download nowy JAR do plugins/.updates/
- Na shutdown / reload: move new JAR over old (atomic rename)
- Bukkit reload command picks up new

**Edge case:** MC servers rarely restart. Manual notification po download:

```
[ProperBackup] New version 1.1.0 downloaded. Restart server to apply.
```

**DoD:**
- Test check happy path
- Test "no update" → no-op
- Test sha256 verification

#### `[MC-G2]` Compatibility matrix

**Plik:** `properbackup-mc/docs/compatibility-matrix.md`

| Plugin version | Paper | Spigot | Folia | Bukkit (deprecated) |
|---------------|-------|--------|-------|---------------------|
| 1.0.0 | 1.20.x, 1.21.x | 1.20.x, 1.21.x | Folia 1.21.x | NIE |

**Update procedura:** Test na kazdej nowej MC release → tag plugin version.

---

## 6. Edge Cases (15+)

### 6.1 Server hosting w shared environment (Pterodactyl, MultiCraft)

Klient MA limit RAM (np. 2 GB) + share dysk z innymi VMs.

**Wymagane:**
- IoThrottle bardziej agresywny (10 MB/s default)
- Memory budget strict (`-Xmx512m` jezeli mozliwe, ale plugin sam dziala w JVM serwera)
- Warning w README: "Recommended: 4 GB RAM dla server (2 GB MC + 1 GB buffer + 1 GB rest)"

### 6.2 Pterodactyl auto-restart

Pterodactyl restartuje serwer co N hours (anti-crash policy).

**Wymagane:**
- Plugin onDisable handles graceful shutdown
- Scheduled backups resume po restart (state.json zachowuje schedule)
- Backup mid-restart: resume from interrupted offset

### 6.3 Player count >1000 (large server)

Large MC server, plenty world data (50+ GB).

**Wymagane:**
- IoThrottle dla minimal player impact
- Snapshot mechanism (zostawia world w spokoju w czasie backup)
- Backup duration ~30 min akceptowalny dla 50 GB

### 6.4 World data corruption (Minecraft bug)

Minecraft sometimes corrupts region files (1.X bug).

**Wymagane:**
- Plugin NIE detect corruption (responsibility serwera)
- Backup zachowuje wszystkie chunks "as-is"
- Restore opcja: rollback do snapshot przed corruption

### 6.5 Plugin conflicts

Inne backup plugins (CoreBackup, AutomatBackup, etc.) na tym samym serwerze.

**Wymagane:**
- Detect inne plugins na onEnable (lista w `plugin.yml` `softdepend`)
- Warning: "Detected other backup plugin: CoreBackup. Consider disabling one for performance."
- Plugin nadal działa (no exclusivity check)

### 6.6 Player teleport during backup

Player teleportuje sie w trakcie backup, MC writes new chunk.

**Wymagane:**
- Tolerate: pojedynczy chunk file może być inconsistent (rare)
- Restore time: rollback to consistent state (last valid snapshot)

### 6.7 World too large for plan

Klient Hobby (100 GB) ma world 150 GB.

**Wymagane:**
- onFirst backup: alert ze world > plan cap, suggest upgrade
- Backup tries, blocked by StorageQuotaGuard (server-side, cross-ref `[BUF-A4]`)
- In-game message: "Backup blocked: storage exceeded. Upgrade plan in web panel."

### 6.8 OP runs /properbackup uninstall

**Wymagane:**
- Confirm dialog (chat: "Type /properbackup uninstall confirm")
- Po confirm: state.json kasowany, plugin in unactivated mode
- Buffer-side: server NIE jest kasowany (klient moze re-activate later)
- After 30 dni unactive: buffer cron usuwa server entry (cross-ref `[BUF-D3]`)

### 6.9 Server runs in cracked mode

Server z `online-mode: false`. Nadal works (plugin nie zalezy od Mojang auth).

### 6.10 Operator zmienia hostname

Server.properties zmienia "Server Name". Backup metadata reflects.

**Wymagane:**
- Refresh `machine_name` w bufferze (cross-ref `[BUF-D2]`)

### 6.11 Server has BungeeCord / Velocity proxy

MC cluster z proxy + N backend servers. Plugin tylko backend servers (proxy ne ma world data).

**Wymagane:**
- Plugin enableable tylko na Paper/Spigot (NIE BungeeCord/Velocity — different API)
- onLoad detect platform: `Bukkit.getServer().getName()` → "BungeeCord" → log error, disable

### 6.12 World disk full

Serwer MC dysk pelny (logi, cache).

**Wymagane:**
- Backup waits jezeli /tmp pelny (cant write tar.gz)
- Alert "MC server disk full" w telemetrii

### 6.13 Tar.gz package > 950MB

(Cross-ref `buffer-core-master-spec.md` `[BUF-B1]`)

Server z 950MB+ z world data → 1 single pack.

**Wymagane:**
- Pack splitter (TarGzPacker shared) handles
- Multiple chunks per backup possible

### 6.14 Player griefing — opp lub admin nadużycie

Atakujacy z OP usuwa state.json, plugin staje sie unactivated, future backupy stop.

**Wymagane:**
- Backup w state.json: hash of state.json przed onDisable. Mismatch na onEnable → audit log alert.
- Buffer-side: jezeli no heartbeat >24h → notify owner email "Server offline"

### 6.15 World save event NIE fires (Minecraft bug)

Some Minecraft versions don't fire WorldSaveEvent consistently.

**Wymagane:**
- Fallback: periodic backup (every 6h) nawet jezeli world save event nie nie fires
- Reduces dependency na MC events

### 6.16 Plugin podczas server lag spike

Server lag (TPS <5), backup task scheduling delayed.

**Wymagane:**
- Backup task uses BukkitScheduler (suspends w trakcie lag)
- Tolerance: backup może być late, nie wymagane on-time

---

## 7. Definition of Done

10 kryteriow:

1. Red test first (MockBukkit)
2. Test "plugin loads w Paper 1.21" → green
3. Test "plugin loads w Folia" → green
4. Test "plugin loads w Spigot 1.21" → green
5. No main-thread blocking (async backup task)
6. Brak sekretow w state.json plain (gdy OS keystore dostepny)
7. NIE RUSZAJ shared/buffer respected
8. Telemetria heartbeat dziala (test agent_metrics row)
9. Compat matrix updated
10. README z installation instructions + screenshots

---

## 8. Sequence of work

1. **`[MC-A1]` Plugin enable/disable** — fundament
2. **`[MC-B1]` /properbackup activate happy path** — onboard
3. **`[MC-D1]` Default backup paths + exclude** — co bekupuje
4. **`[MC-D3]` File locking handling** — bezpieczenstwo
5. **`[MC-C1]` Periodic backup scheduling** — core function
6. **`[MC-C2]` World save event trigger** — UX boost
7. **`[MC-E1]` IoThrottle integration** — performance
8. **`[MC-A3]` Shutdown handling** — graceful stop
9. **`[MC-A2]` Plugin reload safety** — operations
10. **`[MC-F1]` Status command** — UX
11. **`[MC-F2]` Remote telemetria** — observability
12. **`[MC-F3]` In-game alerts** — UX
13. **`[MC-G1]` Auto-update check** — long-term maintainability
14. **`[MC-D4]` Folia compatibility** — szerszy market

---

## 9. Go/No-Go checklist

- [ ] Plugin enabled w Paper 1.21
- [ ] Plugin enabled w Folia 1.21
- [ ] /properbackup activate dziala (op + permission check)
- [ ] Periodic 6h scheduling dziala
- [ ] World save event trigger dziala
- [ ] Backup uses streaming (heap <100MB during op)
- [ ] IoThrottle 25 MB/s default w MC
- [ ] /properbackup status returns formatted info
- [ ] State.json saved w plugins/ProperBackup/
- [ ] Telemetry heartbeat agent_metrics
- [ ] In-game alerts dla op (chat) działa
- [ ] /reload safe (no thread leak)
- [ ] Folia: backup nie blokuje region threads
- [ ] Backup task timeout (max-duration-minutes) działa
- [ ] Compat matrix doc utworzony
- [ ] README z installation steps + screenshots
- [ ] Manual test na real Paper server: install JAR + activate + wait 6h + verify backup w web panel

---

## Dodatek A — Linki

- `master-tdd-plan.md` — subscription enforcement (plugin uses same auth boundary)
- `agent-vps-master-spec.md` — wzor (resumable upload, JWT, IoThrottle, AutoUpdater)
- `buffer-core-master-spec.md` — server-side endpointy plugin consumes
- `observability-and-dr-spec.md` — telemetria + metryki
- Paper API docs: https://docs.papermc.io/
- Folia: https://docs.papermc.io/folia/
- MockBukkit: https://github.com/MockBukkit/MockBukkit

## Dodatek B — Glosariusz

- **Paper** — fork Spigot z performance optimizations
- **Spigot** — fork Bukkit z performance optimizations (deprecated baseline)
- **Folia** — Paper fork z regionized threading (latest)
- **Bukkit** — original MC server API (no longer maintained)
- **plugin.yml** — Paper plugin metadata
- **TPS** — Ticks Per Second (server tick rate, target 20)
- **BukkitScheduler** — task scheduler API
- **WorldSaveEvent** — Bukkit event fired po world save
- **op** — operator (admin) player
- **/save-all** — Minecraft command saving wszystkie worlds
- **/save-off** / **/save-on** — disable/enable auto-save
- **.mca** — Minecraft Anvil region file (32x32 chunks)
- **MockBukkit** — testing framework dla plugins
- **shadowJar** — Gradle task ktora bundles dependencies do plugin JAR
- **Pterodactyl** — popular MC hosting panel
- **MultiCraft** — popular MC hosting panel
