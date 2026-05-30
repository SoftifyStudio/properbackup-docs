# Shared Core Architecture — Master Plan (Kotlin Multiplatform, "Jeden JAR")

Wersja: 1.0 (initial, pre-prod)
Repo glowne: `properbackup-shared` (Kotlin Multiplatform — JVM + Native ARM64)
Repo konsumenckie: `properbackup-agent` (VPS), `properbackup-mc` (Paper/Spigot/Folia plugin), future: Fabric mod, Forge mod, iOS, Android, Windows installer
Status: SPEC — fundament kontraktu dla wszystkich srodowisk uruchomieniowych agenta
Priorytet: **P0** (FUNDAMENTAL — przed kazda prac w `agent-vps-master-spec.md` i `minecraft-plugin-master-spec.md`)

---

## 0. Hard Requirements (Immutable Rules) — PRAWO PROJEKTU

> **Te zasady sa NIENARUSZALNE. Kazde naruszenie = automatic rejection PR-a w review.**
>
> Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint` (sekcja 2.1 Master Blueprint — agent jako jeden artefakt KMP)

**HR-1. Jeden JAR — wspolne jadro KMP**
Calosc logiki domenowej agenta (transport, szyfrowanie, kompresja, throttling, scanner, retry, circuit breaker, JWT) ZYJE wylacznie w `properbackup-shared`. Konsumenci (`agent-vps`, `mc-plugin`, future Fabric/Forge) SA cienkimi wrapperami implementujacymi tylko `HostAdapter` interface (lifecycle, scheduler, config persistence, filesystem facade dla danego srodowiska).

**HR-2. Zero duplikacji logiki domenowej w konsumentach**
Konsumenci NIE MOGA reimplementowac niczego co juz istnieje w `shared` (upload, crypto, retry, scanner). Jezeli czegos brak w `shared` — dodaj to do `shared`, nie do konsumenta. Wyjatkiem sa wylacznie integracje z host API (Bukkit listeners, Systemd unit, Fabric ModInitializer).

**HR-3. Wszystkie typy domenowe sa stale (`expect/actual` granica jest waska)**
Jezeli platforma JVM ma 100% zakres potrzebny (a tak jest dla aktualnej palety celow), modul `shared` zostaje w 100% JVM-only **dopoki** nie pojawia sie target Native/JS/iOS. Ale interfejs (`HostAdapter`, `PlatformClock`, `PlatformFs`) ma byc zaprojektowany tak, by **dodanie nowego targetu nie wymagalo refaktora rdzenia** — tylko nowe `actual`-y.

**HR-4. Identycznosc semantyczna across hosts**
Ten sam plik klienta, ten sam klucz, ten sam serwer buffer-a → IDENTYCZNY blob w OVH bez wzgledu na czy upload poszedl z VPS agenta, MC plugin'u, czy (przyszlego) Fabric mod'u. Test cross-host integracji (`SharedCrossHostParityTest`) musi to potwierdzac dla kazdego release.

**HR-5. Header-First Verification (cost optimization z biznesplanu)**
Przed odczytem pelnego obiektu z OVH agent MUSI pobrac wylacznie ostatnie `N` bajtow (header) — sprawdzic czy obiekt istnieje, integralnosc magic bytes, wersja formatu. Dopiero potem download caly. Implementacja w `shared/transport/HeaderFirstReader.kt`. **Oszczednosc egress: krytyczna dla cost guard.**

**HR-6. 4MB chunk dedup boundary (juz w shared)**
Agent dziali pliki na chunki 4MB (sha256 per chunk) i unika reuploadu chunkow ktore juz istnieja na buffer-ze. To jest **istniejacy mechanizm** w `properbackup-shared/.../scanner/DifferentialScanner.kt`. NIE wolno tego usunac ani obejc. Wszystkie nowe transport features (resumable, circuit breaker, JWT) musza wspolpracowac z tym podzialem.

**HR-7. Streaming encryption (no temp plaintext)**
AES-256-GCM strumieniowo — `ProperCrypto.kt` (NIE RUSZAJ) bierze `InputStream` i wypuszcza `OutputStream` w trakcie odczytu. Nigdy nie ma pelnego pliku plaintext na dysku konsumenta po szyfrowaniu. Jedyna persistent kopia plaintext jest w **buforze backendu** (zaszyfrowanym at-rest przez OS / LUKS) i znika w momencie sealed.

**HR-8. JWT 5min bootstrap dla agentow (cross-ref `agent-vps-master-spec.md` AGT-C1)**
Wszystkie hosty agentow uzywaja **tego samego** `JwtClient` z shared. Token zycia 5 min, auto-refresh na 4 min. Konsumenci NIE wystawiaja wlasnego flow auth — tylko deleguja do shared.

**HR-9. Cross-Host Artifact Test (jeden JAR — jeden test suite)**
W CI `properbackup-shared` musi miec test job `cross-host-parity` ktory:
1. Buduje jeden `shared-{version}.jar`
2. Uruchamia `agent-vps` (jvmTest) → ladowac tylko ten JAR + thin host
3. Uruchamia MC plugin (MockBukkit) → ladowac tylko ten JAR + thin host
4. (future) Uruchamia Fabric/Forge mock → tylko ten JAR
5. Kazdy uploaduje **ten sam** 100MB plik testowy → expected: identical SHA-256 blob w mock-OVH

Failure jednego z hostow = blok release. Zero wyjatkow.

**HR-10. Mockowanie tylko granicy (HostAdapter)**
Testy `shared` mock-uja **wylacznie** `HostAdapter` i `PlatformFs`. Nie wolno mockowac wewnetrznej logiki — testy ida przez prawdziwy `BufferUploader`, prawdziwy `RetryPolicy`, prawdziwy `CircuitBreaker`. Mockowanie wewnetrza = nieprawdziwe testy.

---

## 1. Cel dokumentu

Single source of truth dla architektury "jedno jadro, wiele srodowisk uruchomieniowych" w stylu `properbackup-shared` jako **kontrakt** dla wszystkich konsumentow.

Dokument odpowiada na pytania:

1. **Co siedzi w shared, a co w konsumentach?** — twardy podzial odpowiedzialnosci
2. **Jak konsument plugi sie do shared?** — interfejs `HostAdapter` (kontrakt API)
3. **Jak testowac, ze "jeden JAR dziala wszedzie identycznie"?** — cross-host parity tests w CI
4. **Co zrobic, gdy chce sie dodac nowy host (np. Fabric mod, iOS)?** — krok po kroku

Brat dokumentu `agent-vps-master-spec.md`, `minecraft-plugin-master-spec.md`, `buffer-core-master-spec.md`.

### Zakres

- Definicja **`HostAdapter`** interface (lifecycle, scheduler, config, fs)
- Definicja **`PlatformFs`** interface (read/write/lock/atomic-rename, abstrahuje JVM File vs Bukkit DataFolder vs Fabric ConfigDir)
- Definicja **`PlatformClock`**, **`PlatformProcessId`**, **`PlatformNetInfo`** (small KMP-friendly platform primitives)
- **Domain entry points** w shared — co wola host po inicjalizacji
- **Cross-host test plan** — dokladne testy ktore CI musi przejsc
- **Dependency graph** — co konsument musi zaimportowac, czego nie wolno mu zaimportowac
- **Future targets matrix** — co bedzie wymagane gdy dodamy iOS/Android/Windows installer

### Co NIE jest w zakresie

- Implementacja konkretnego hosta — to jest w `agent-vps-master-spec.md` i `minecraft-plugin-master-spec.md`
- Konfiguracja CI dla cross-host parity — to jest w `ci-cd-release-pipeline-spec.md` (sekcja CICD-G)
- Strategia release shared (versioning, publish do Maven) — to jest w `ci-cd-release-pipeline-spec.md` (CICD-D)
- Specyfika OVH/storage — `ovh-cloud-archive-migration-spec.md`
- Buffer-side logika — `buffer-core-master-spec.md`

---

## 2. Mapowanie kodu

### 2.1 Stan obecny w `properbackup-shared`

Plik root: `properbackup-shared/build.gradle.kts` — Kotlin Multiplatform, aktualnie tylko JVM target.

Glowne pakiety (na main, weryfikacja podczas pracy):

| Pakiet | Zawartosc | Stan |
|--------|-----------|------|
| `core.crypto` | `ProperCrypto.kt`, `KeyDerivation.kt`, `HeaderCodec.kt` | **ZAMROZONE** (read-only — patrz `crypto-and-compliance-spec.md`) |
| `core.filename` | `FilenameGrammar.kt` | ZAMROZONE (parser nazw) |
| `core.codec` | `Base62.kt`, `ProperCodec.kt` | ZAMROZONE |
| `scanner` | `DifferentialScanner.kt`, `MetadataCache.kt` | DOTYKAJ (tuning OK) |
| `packer` | `TarGzPacker.kt` | DOTYKAJ |
| `transport` | `BufferUploader.kt`, `RetryPolicy.kt` | DOTYKAJ + rozszerz |
| `activation` | `ActivationClient.kt`, `GlobalConfigWriter.kt` | DOTYKAJ + rozszerz o JWT |
| `logging` | `RemoteTelemetry.kt` | DOTYKAJ |
| `iothrottle` (jezeli istnieje, inaczej dodaj) | `IoThrottle.kt` | DOTYKAJ / NEW |

### 2.2 Konsumenci dzisiaj

| Repo | Status | Konsumuje shared |
|------|--------|------------------|
| `properbackup-agent` | Active (~750 linii `AgentMain.kt` + helpers) | TAK — przez Gradle dependency lub Maven local |
| `properbackup-mc` | Placeholder (1 wiersz README) | NIE jeszcze — `minecraft-plugin-master-spec.md` to wymaga |
| (future) Fabric mod | Nie istnieje | TAK — bedzie wymagac shared |
| (future) Forge mod | Nie istnieje | TAK — bedzie wymagac shared |
| (future) iOS app | Nie istnieje | Wymaga Native target |
| (future) Android app | Nie istnieje | Mozliwe — JVM-based |
| (future) Windows installer | Nie istnieje | TAK — jlinkDist + shared |

### 2.3 Planowane nowe komponenty w shared

```
properbackup-shared/src/commonMain/kotlin/pl/danielniemiec/properbackup/shared/
├── core/                                  # ZAMROZONE
│   ├── crypto/
│   ├── filename/
│   └── codec/
├── host/                                  # NEW — interfejsy konsumenta
│   ├── HostAdapter.kt                     # MAIN contract (lifecycle, scheduler, config)
│   ├── PlatformFs.kt                      # File abstraction
│   ├── PlatformClock.kt                   # Time abstraction
│   ├── PlatformProcessId.kt               # process-id abstraction
│   ├── PlatformNetInfo.kt                 # network info
│   └── HostCapabilities.kt                # what this host supports
├── domain/                                # NEW — domain entry points
│   ├── ProperBackupAgentCore.kt           # main facade — host wola .start()/.stop()/.runBackupNow()
│   ├── BackupOrchestrator.kt              # internal — schedules and runs scan/upload cycles
│   └── ActivationFlow.kt                  # internal — handles /properbackup activate <token>
├── transport/
│   ├── BufferUploader.kt                  # existing — refactor: thin wrapper, no host-specific deps
│   ├── RetryPolicy.kt                     # existing
│   ├── ResumableUpload.kt                 # NEW (cross-ref agent-vps AGT-B3)
│   ├── CircuitBreaker.kt                  # NEW (cross-ref agent-vps AGT-C2)
│   ├── JwtClient.kt                       # NEW — refresh token co 4 min
│   ├── HeaderFirstReader.kt               # NEW — HR-5 implementation
│   └── ChunkDedupIndex.kt                 # existing semantics, ensure 4MB boundary (HR-6)
├── scanner/
│   ├── DifferentialScanner.kt
│   └── MetadataCache.kt
├── packer/
│   └── TarGzPacker.kt
├── activation/
│   ├── ActivationClient.kt
│   └── GlobalConfigWriter.kt              # uses PlatformFs!
├── iothrottle/
│   └── IoThrottle.kt
└── logging/
    └── RemoteTelemetry.kt
```

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone, read-only)

- `core.crypto.*` — patrz `crypto-and-compliance-spec.md`
- `core.filename.FilenameGrammar` — grammar parser, stabilny od miesiecy
- `core.codec.Base62`, `core.codec.ProperCodec`
- Istniejaca semantyka `BufferUploader.upload(path, data, ...)` — **stara metoda musi dalej dzialac dla MC plugin'u**; mozna dodawac NOWE metody (uploadResumable, uploadChunked) ale nie zmieniac semantyki istniejacej

### DOTYKAJ (modyfikacja semantyki dozwolona, ostroznie)

- `transport.RetryPolicy.kt` — rozszerz o backoff strategy
- `transport.BufferUploader.kt` — dodaj nowe metody (resumable, chunked)
- `activation.ActivationClient.kt` — rozszerz o JWT minting
- `scanner.*` — performance tuning, ale wynik (lista plikow) musi byc identyczny
- `iothrottle.IoThrottle.kt` — jezeli juz istnieje, ostrozne tuning

### MOZESZ TWORZYC (nowe komponenty zgodnie z mapowaniem 2.3)

- `host/HostAdapter.kt` i pokrewne interfejsy
- `domain/ProperBackupAgentCore.kt` (facade)
- `transport/ResumableUpload.kt`, `transport/CircuitBreaker.kt`, `transport/JwtClient.kt`, `transport/HeaderFirstReader.kt`
- `iothrottle/IoThrottle.kt` (jezeli brak)
- Cross-host integration tests w `properbackup-shared/src/jvmTest/`

### W konsumentach (`agent-vps`, `mc-plugin`)

- **NIE WOLNO** dodawac logiki ktora ma analog w shared
- Konsument moze miec **tylko**:
  - implementacje `HostAdapter` interface
  - wywolanie `ProperBackupAgentCore.start(adapter)` na lifecycle hook (onEnable / Systemd start)
  - cienkie integracje z host API (Bukkit Listener, Systemd notify, etc.)

---

## 4. State-of-the-world (rzeczywistosc dzisiaj)

### 4.1 Co dziala (potwierdzone)

Z biznesplanu v6 sekcja 2.1 + historia commitow + analizy w `agent-vps-master-spec.md`:

- **`AgentMain.kt` (~750 linii) na branchach `production`/`devin/1779032082-5-feature-production`** — dziala, ma full backup cycle: scan -> diff -> tar.gz -> encrypt -> upload
- **`DifferentialScanner.kt` z 4MB chunkami i sha256 dedupe** — istniejacy, dziala
- **`ProperCrypto.kt` AES-256-GCM streaming + `KeyDerivation.kt` Argon2id** — zamrozone, dziala
- **`BufferUploader.kt`** — istniejacy HTTP klient z prostym retry
- **`ActivationClient.kt`** — istniejacy flow `--activate TOKEN`
- **`GlobalConfigWriter.kt`** — zapis configa w `~/.properbackup/config.json` (POSIX) i `%APPDATA%\properbackup\config.json` (Windows)
- **`MetadataCache.kt`** — cache mtime/size dla speedup re-scan
- **Header-First (z biznesplanu)** — koncepcyjnie obecny, ale **nie jako wydzielony komponent** w obecnym kodzie; do wyodrebnienia w `HeaderFirstReader.kt`

### 4.2 Czego brakuje (gaps blokujace "jeden JAR")

1. **HostAdapter interface** — nie istnieje. AgentMain.kt obecnie bezposrednio uzywa `System.getProperty()`, `File()`, `Runtime.getRuntime()` — nie da sie z tego zrobic plugin'u MC bez refaktora.
2. **`domain/ProperBackupAgentCore.kt` facade** — nie istnieje. Konsument musialby dzis duplikowac orchestracje.
3. **`PlatformFs`** — brakuje. JVM File jest uzywane wszedzie bezposrednio. MC plugin musi pisac w `dataFolder` (Bukkit), nie w `~`.
4. **`JwtClient`** — nie istnieje (cross-ref agent-vps AGT-C1). Obecnie agent uzywa static token z `.env`.
5. **`CircuitBreaker`, `ResumableUpload`** — nie istnieja (cross-ref agent-vps AGT-B3, AGT-C2).
6. **`HeaderFirstReader`** — brakuje wydzielonego komponentu (HR-5).
7. **Cross-host parity test suite** — nie istnieje w `shared/src/jvmTest/`. Bez tego brak gwarancji "jeden JAR dziala wszedzie".
8. **`IoThrottle` per-host config** — istnieje gdzies (sprawdz branch `1779032082`), ale brak konfiguracji per-host (VPS 50MB/s vs MC 25MB/s).

### 4.3 Co ZUSTANIE jako-jest (zero refactor)

- `core.crypto.*` (zamrozone — security)
- `core.filename.FilenameGrammar` (grammar parser)
- `core.codec.*` (Base62, ProperCodec)
- Aktualny `BufferUploader.upload()` jednorazowy (nie chunked) — pozostaje jako fallback dla malych plikow

---

## 5. Domain Model — kluczowe abstrakcje

### 5.1 `HostAdapter` interface (commonMain)

```kotlin
package pl.danielniemiec.properbackup.shared.host

interface HostAdapter {
    // Lifecycle
    val hostType: HostType                  // VPS_STANDALONE | MC_PAPER | MC_SPIGOT | MC_FOLIA | FABRIC_MOD | FORGE_MOD | IOS_APP | ANDROID_APP | WINDOWS_INSTALLER
    val hostVersion: String                 // e.g. "1.21.1-paper" or "5.1.4-systemd"

    // Required platform primitives
    val fs: PlatformFs
    val clock: PlatformClock
    val net: PlatformNetInfo

    // Scheduler — host owns the thread pool / event loop
    fun scheduleRepeating(intervalMillis: Long, task: () -> Unit): Cancellable
    fun scheduleOnce(delayMillis: Long, task: () -> Unit): Cancellable

    // Configuration root — for GlobalConfigWriter
    fun configDir(): String                 // e.g. "/home/user/.properbackup" or "plugins/ProperBackup"
    fun dataDir(): String                   // e.g. "/var/lib/properbackup" or "plugins/ProperBackup/data"

    // Capabilities — declare what this host supports
    fun capabilities(): HostCapabilities

    // Backup roots — co backupowac (host wie najlepiej)
    fun defaultBackupRoots(): List<String>  // VPS: home dirs; MC: world dirs + plugins/* + server.properties

    // Logging hook — host moze chciec rerouter logow (Bukkit Logger vs Logback vs Fabric Logger)
    fun log(level: LogLevel, message: String, throwable: Throwable? = null)
}

enum class HostType { VPS_STANDALONE, MC_PAPER, MC_SPIGOT, MC_FOLIA, FABRIC_MOD, FORGE_MOD, IOS_APP, ANDROID_APP, WINDOWS_INSTALLER }

data class HostCapabilities(
    val supportsBackgroundUpload: Boolean,       // VPS: TRUE; MC: TRUE (server JVM stays up)
    val supportsResumableUpload: Boolean,        // depends on host network stability
    val supportsLongRunningThreads: Boolean,     // MC Folia: ograniczone scheduler
    val maxIoBytesPerSec: Long,                  // host moze deklarować limit; VPS 50MB/s, MC shared host 25MB/s
    val isMultiTenantHost: Boolean,              // MC shared hosting: TRUE
    val supportsFsLocks: Boolean,                // czy fs.lock() dziala (na MC plugin moze nie)
)
```

### 5.2 `PlatformFs` interface

```kotlin
interface PlatformFs {
    fun exists(path: String): Boolean
    fun read(path: String): ByteArray
    fun readStream(path: String): InputStream
    fun write(path: String, data: ByteArray)               // atomic rename via .tmp -> .final
    fun writeStream(path: String): OutputStream            // returns stream that does atomic rename on close()
    fun list(dir: String): List<String>
    fun mkdirs(dir: String)
    fun delete(path: String)
    fun rename(from: String, to: String)
    fun size(path: String): Long
    fun mtime(path: String): Long
    fun lock(path: String): FsLock?                        // host moze zwrocic null jezeli unsupported
    fun freeSpace(dir: String): Long
}

interface FsLock : AutoCloseable
```

### 5.3 `PlatformClock` interface

```kotlin
interface PlatformClock {
    fun nowMillis(): Long
    fun nowUtc(): Instant
    fun monotonicMillis(): Long              // for elapsed-time measurements (immune to system clock changes)
}
```

### 5.4 `ProperBackupAgentCore` facade

```kotlin
package pl.danielniemiec.properbackup.shared.domain

class ProperBackupAgentCore(
    private val host: HostAdapter,
    private val config: AgentConfig,
) {
    fun start() {
        // 1. Validate config (activation token, buffer URL, encryption keys)
        // 2. Initialize transport (JwtClient, CircuitBreaker, RetryPolicy)
        // 3. Initialize scanner (DifferentialScanner)
        // 4. Start scheduler via host.scheduleRepeating(...)
        // 5. Register lifecycle hooks (shutdown handler)
    }

    fun stop() { /* graceful shutdown */ }

    fun runBackupNow(): BackupRunResult { /* synchronous trigger */ }

    fun activate(token: String): ActivationResult { /* delegate to ActivationFlow */ }

    fun status(): AgentStatus { /* expose snapshot for host UIs */ }
}
```

### 5.5 Host implementacje (przyklady)

**`agent-vps` (Systemd unit):**

```kotlin
class VpsHostAdapter(
    private val homeDir: String,
) : HostAdapter {
    override val hostType = HostType.VPS_STANDALONE
    override val fs = JvmPlatformFs()
    override val clock = JvmPlatformClock()
    override val net = JvmPlatformNetInfo()

    override fun configDir() = "$homeDir/.properbackup"
    override fun dataDir() = "/var/lib/properbackup"
    override fun defaultBackupRoots() = listOf("$homeDir/Documents", "$homeDir/Pictures")
    override fun capabilities() = HostCapabilities(
        supportsBackgroundUpload = true,
        supportsResumableUpload = true,
        supportsLongRunningThreads = true,
        maxIoBytesPerSec = 50 * 1024 * 1024,  // 50 MB/s
        isMultiTenantHost = false,
        supportsFsLocks = true,
    )

    private val executor = Executors.newScheduledThreadPool(2)
    override fun scheduleRepeating(intervalMillis: Long, task: () -> Unit): Cancellable {
        val f = executor.scheduleAtFixedRate(task, 0, intervalMillis, TimeUnit.MILLISECONDS)
        return Cancellable { f.cancel(false) }
    }
    // ...
}

// AgentMain.kt becomes:
fun main(args: Array<String>) {
    val host = VpsHostAdapter(System.getProperty("user.home"))
    val config = AgentConfig.loadOrActivate(args, host)
    val core = ProperBackupAgentCore(host, config)
    Runtime.getRuntime().addShutdownHook(Thread { core.stop() })
    core.start()
    // main thread keeps process alive — daemon threads from host.scheduler do work
}
```

**`mc-plugin` (Paper/Spigot):**

```kotlin
class PaperHostAdapter(
    private val plugin: ProperBackupPlugin,
) : HostAdapter {
    override val hostType = HostType.MC_PAPER
    override val fs = BukkitPlatformFs(plugin)  // delegates to plugin.dataFolder
    override val clock = JvmPlatformClock()
    override val net = JvmPlatformNetInfo()

    override fun configDir() = plugin.dataFolder.absolutePath
    override fun dataDir() = File(plugin.dataFolder, "data").absolutePath
    override fun defaultBackupRoots(): List<String> {
        // Backup all worlds + plugins/* + server.properties
        val worlds = Bukkit.getWorlds().map { it.worldFolder.absolutePath }
        return worlds + listOf(
            File(plugin.server.worldContainer.parentFile, "plugins").absolutePath,
            File(plugin.server.worldContainer.parentFile, "server.properties").absolutePath,
        )
    }
    override fun capabilities() = HostCapabilities(
        supportsBackgroundUpload = true,
        supportsResumableUpload = true,
        supportsLongRunningThreads = false,  // use Bukkit scheduler!
        maxIoBytesPerSec = 25 * 1024 * 1024,  // 25 MB/s shared hosting safety
        isMultiTenantHost = true,
        supportsFsLocks = false,  // shared FS often unstable for lock
    )

    override fun scheduleRepeating(intervalMillis: Long, task: () -> Unit): Cancellable {
        val ticks = intervalMillis / 50  // Minecraft tick is 50ms
        val taskHandle = plugin.server.scheduler.runTaskTimerAsynchronously(plugin, Runnable { task() }, ticks, ticks)
        return Cancellable { taskHandle.cancel() }
    }
    // ...
}

// PropertyBackupPlugin.kt (JavaPlugin):
class ProperBackupPlugin : JavaPlugin() {
    private lateinit var core: ProperBackupAgentCore

    override fun onEnable() {
        val host = PaperHostAdapter(this)
        val config = AgentConfig.loadOrActivate(emptyArray(), host)
        core = ProperBackupAgentCore(host, config)
        core.start()
        getCommand("properbackup")?.setExecutor(PropertyBackupCommand(core))
    }

    override fun onDisable() {
        core.stop()
    }
}
```

**`fabric-mod` (future):**

```kotlin
class FabricHostAdapter(
    private val mc: MinecraftServer,
    private val modConfigDir: Path,
) : HostAdapter {
    override val hostType = HostType.FABRIC_MOD
    // ... same structure, uses Fabric's scheduler / config dir
}

class ProperBackupFabricMod : DedicatedServerModInitializer {
    override fun onInitializeServer() {
        ServerLifecycleEvents.SERVER_STARTED.register { server ->
            val host = FabricHostAdapter(server, FabricLoader.getInstance().configDir.resolve("properbackup"))
            val core = ProperBackupAgentCore(host, AgentConfig.load(host))
            core.start()
        }
    }
}
```

---

## 6. Pillars of Resilience (architectural defenses)

### 6.1 Single-Source-of-Truth dla logiki domenowej

**Ryzyko:** Konsument (np. plugin MC) implementuje **wlasne** ponizsze + obejscie circuit breaker'a + dziwny retry. Roznice w zachowaniu na MC vs VPS.

**Obrona:** Cross-host parity test (HR-9). Code review — odrzucamy PR ktory dodaje logike domenowa w konsumencie.

### 6.2 Brak host-specific imports w `shared`

**Ryzyko:** Ktos doda `import java.awt.Robot` lub `import org.bukkit.*` do shared. Wtedy MC plugin nie zbuduje sie bo nie ma `java.awt` (na headless serwerach) lub Fabric mod sie nie zbuduje bo nie ma Bukkit.

**Obrona:** Gradle dependency-rules-test — testowy task w shared sprawdza ze `shared/src/commonMain/` (i `jvmMain` jezeli JVM-only) NIE importuje nic z `bukkit`, `paper`, `fabric`, `forge`, `awt`, `javafx`, `android`. Lista forbidden imports w `ci-cd-release-pipeline-spec.md`.

### 6.3 Configuration injection via HostAdapter

**Ryzyko:** Ktos hardcoduje sciezki `/home/user/.properbackup` w shared. Wtedy MC plugin pisze do `/home/user/` zamiast `plugins/ProperBackup/`.

**Obrona:** Zero direct uzycia `System.getProperty("user.home")` w shared. Tylko `host.configDir()`. Lint rule (CI: detekt + custom rule).

### 6.4 Pinned version of shared per consumer

**Ryzyko:** `agent-vps` uzywa shared v1.5 a `mc-plugin` uzywa shared v1.7. Niespojnosc.

**Obrona:** Wszystkie konsumeci pin pelna wersja shared w `build.gradle.kts`. CI release pipeline (`ci-cd-release-pipeline-spec.md` CICD-D) verifikuje przed release ze wszyscy konsumeci uzywaja tej samej wersji shared.

---

## 7. Test Groups

### 7.1 Group A: HostAdapter contract conformance

#### `[SHC-A1]` HostAdapter implementation must declare HostType

**Given:** Konsument tworzy `class FooHostAdapter : HostAdapter`
**When:** Buduje sie konsumenta
**Then:** Compiler error jezeli `hostType` nie zaimplementowane

**DoD:**
- Test: kompilacja `agent-vps` BEZ `hostType` -> fail
- Test: kompilacja `mc-plugin` BEZ `hostType` -> fail
- Lint rule wymaga `hostType` enum value matching jednemu z `HostType`

#### `[SHC-A2]` configDir() i dataDir() roznia sie per host

**Given:** Test `agent-vps`-host i `mc-plugin`-host
**When:** Wolam `host.configDir()`
**Then:**
- VPS: zwraca `$HOME/.properbackup`
- MC: zwraca `plugins/ProperBackup`
- Roznica jest **wymagana** (jezeli identyczna, blad konfiguracji)

#### `[SHC-A3]` capabilities() reflectue rzeczywiste mozliwosci

**Given:** `MC_PAPER` host
**When:** Wola `capabilities().maxIoBytesPerSec`
**Then:** Zwraca `25 * 1024 * 1024` (25 MB/s) — shared hosting safety

**Given:** `VPS_STANDALONE` host
**When:** `capabilities().maxIoBytesPerSec`
**Then:** Zwraca `50 * 1024 * 1024` (50 MB/s)

### 7.2 Group B: PlatformFs cross-host parity

#### `[SHC-B1]` write atomicity

**Given:** PlatformFs implementation (jvm-default, bukkit-delegated, fabric-delegated)
**When:** `fs.write("/tmp/foo", data)` jest przerwane w polowie (kill -9)
**Then:**
- Po restarcie: plik `/tmp/foo` albo nie istnieje, albo zawiera pelne `data`
- Nigdy nie jest partial (atomic rename `.tmp` -> `.final`)

**DoD:**
- Test JVM: napisz wlasny `JvmPlatformFs.write()` ktory tworzy `.tmp`, kopiuje, `Files.move(...REPLACE_EXISTING, ATOMIC_MOVE)`
- Test crash mid-write via thread interruption + JVM kill simulation
- Cross-host: ten sam test musi przejsc dla `BukkitPlatformFs`

#### `[SHC-B2]` list() returns identical sorted result

**Given:** Katalog z 100 plikami (a.txt, b.txt, ..., z.txt, A.txt, ...)
**When:** `fs.list(dir)` z VPS host vs MC host
**Then:** Identyczna lista (case-sensitive, sorted)

#### `[SHC-B3]` lock() either works or returns null cleanly

**Given:** MC host (shared hosting bez lockow)
**When:** `fs.lock("/var/lib/foo.lock")`
**Then:** Zwraca `null` (nie throw)

**Given:** VPS host
**When:** `fs.lock(...)`
**Then:** Zwraca non-null `FsLock`

### 7.3 Group C: ProperBackupAgentCore lifecycle

#### `[SHC-C1]` start() musi zadzialac na kazdym hoscie

**Given:** Test setup z `MockHostAdapter`
**When:** `core.start()`
**Then:**
- Zaplanowano `scheduleRepeating` z poprawnym intervalem (default 6h albo config)
- JwtClient.initialize() zostal wywolany
- ActivationFlow zwerifikowane (token z configa)
- Brak crashe

**DoD:**
- Test jvm: success
- Test mc-mock-bukkit: success
- Test fabric-mock (jezeli istnieje): success

#### `[SHC-C2]` runBackupNow() jest synchroniczne

**Given:** Core w stanie started
**When:** Wola `runBackupNow()`
**Then:**
- Zwraca `BackupRunResult` w ciagu max N sekund (lub timeout fail)
- Nie blokuje host'a scheduler'a (uzywa thread executor)

#### `[SHC-C3]` stop() jest idempotent

**Given:** Core started
**When:** Wola `stop()`, potem znowu `stop()`
**Then:** Drugi call jest no-op, brak exception

### 7.4 Group D: Cross-host parity (HR-9)

#### `[SHC-D1]` ten sam plik daje identyczny blob na OVH

**Given:**
- Plik testowy 100MB (deterministic content)
- Klient encryption key K (deterministic for test)
- Mock OVH storage

**When:**
- Upload przez VPS host
- Upload przez MC host
- (future) Upload przez Fabric host

**Then:** SHA-256 wszystkich uploadowanych blobow IDENTYCZNY

**DoD:**
- W `shared/src/jvmTest/kotlin/.../CrossHostParityTest.kt`
- Trzy testy: `vpsUpload()`, `paperUpload()`, `crossHostHashMatch()`
- `crossHostHashMatch()` uruchamia oba i `assertEquals(vpsHash, mcHash)`
- CI runs cala matrix

#### `[SHC-D2]` ten sam plik produkuje identyczna ChunkDedupIndex

**Given:** Plik 100MB
**When:** DifferentialScanner runs on VPS vs MC
**Then:** Lista 25 chunkow 4MB ma identyczne sha256 across hosts

#### `[SHC-D3]` Header bytes match across hosts

**Given:** Encrypted blob z VPS i ten sam plaintext z MC
**When:** Wycinamy pierwsze `headerSize` bajtow obu (HeaderFirstReader)
**Then:** Identyczne — magic, version, nonce derived from same key

### 7.5 Group E: Forbidden imports lint

#### `[SHC-E1]` shared nie moze importowac org.bukkit.*

**Given:** Source tree `shared/src/`
**When:** Buduje sie shared
**Then:** Lint task **fail** jezeli znajdzie `import org.bukkit.*` lub `org.spigotmc.*` lub `net.fabricmc.*` lub `net.minecraftforge.*` w `commonMain`/`jvmMain`

**DoD:**
- Gradle custom task `forbiddenImportsCheck` w `shared/build.gradle.kts`
- Powinno przejsc w obecnym kodzie (sprawdz baseline)
- CI runs ten task — fail blokuje merge

#### `[SHC-E2]` shared nie uzywa System.getProperty("user.home")

**Given:** Source tree
**When:** Detekt rule `NoSystemPropertyUserHome`
**Then:** Jezeli znajdzie usage -> fail. Sila przez `host.configDir()`.

### 7.6 Group F: Host capabilities respected

#### `[SHC-F1]` MC host nie urocha dlugich threadow

**Given:** `MC_PAPER` host, capability `supportsLongRunningThreads = false`
**When:** Wola `core.runBackupNow()`
**Then:**
- Wykonuje sie na Bukkit `runTaskAsynchronously` (nie blokuje main tick)
- Backup nie tworzy `new Thread()` bezposrednio

#### `[SHC-F2]` IoThrottle respektuje host limit

**Given:** Host capability `maxIoBytesPerSec = 25 MB/s`
**When:** Upload 1GB pliku
**Then:**
- IoThrottle uses min(host.maxIoBytesPerSec, config.maxIoBytesPerSec)
- Faktyczna predkosc wyniosla ~25 MB/s (mierzone na test)

### 7.7 Group G: Version compatibility

#### `[SHC-G1]` shared v1.X — minor backward-compat

**Given:** Consumer ma shared v1.5 w build.gradle, ale buffer wspolpracuje z shared v1.7+
**When:** Upload chunka
**Then:** Backward-compat — buffer akceptuje header v1.5 (z deprecation warning)

**DoD:**
- HeaderCodec ma `minSupportedVersion` i `maxSupportedVersion`
- Tests covering each minor version pair

#### `[SHC-G2]` major bump = breaking change z migration path

**Given:** shared v2.0 (breaking)
**When:** Consumer v1.X uploads
**Then:** Buffer returns 422 + migration_required = true + URL do upgrade

---

## 8. Edge Cases

| ID | Scenariusz | Spodziewane zachowanie | Test |
|----|-----------|------------------------|------|
| `SHC-E1` | MC plugin reload (mid-upload) | core.stop() musi byc czysty, kolejny onEnable zaczyna od nowa | MockBukkit reload test |
| `SHC-E2` | Folia (regionised threading) | Async tasks must use FoliaAdapter.scheduleAsync (regionised) | Folia mock test |
| `SHC-E3` | VPS Systemd restart mid-backup | Resumable upload kontynuuje od ostatniego chunka | Crash test + restart |
| `SHC-E4` | MC plugin world unload mid-backup | BackupOrchestrator otrzymuje WorldUnloadEvent przez host -> retry next world | MockBukkit event |
| `SHC-E5` | Konsument importuje shared v1.5 + v1.7 (transitive) | Build failure (dependency conflict) | Gradle test |
| `SHC-E6` | Konsument forka shared, dodaje wlasne metody | Lint warning "do not fork shared, contribute upstream" | Convention review |
| `SHC-E7` | MC plugin na Folia (regionised) wola Bukkit.getScheduler() | Capability flag `isFolia=true` -> Force FoliaScheduler | Capability check |
| `SHC-E8` | shared zaktualizowany z breaking changes — konsument na CI fail | CICD-D bumps consumer pin and runs cross-host parity | CI release notes |
| `SHC-E9` | VPS agent + MC plugin oba aktywne dla tego samego user (overlap) | OK — kazdy ma wlasny serverId, niezalezne | Multi-server test |
| `SHC-E10` | MC plugin na server z plugin compat layer (Bukkit -> Paper -> Folia) | Auto-detect via runtime check, wybor odpowiedniego scheduler | Runtime probe |
| `SHC-E11` | Konsument nie implementuje wszystkich `HostAdapter` metod | Kompilator wymusza (abstract) lub explicit `throw UnsupportedOperationException` | Compile test |
| `SHC-E12` | iOS app (future) — bez `java.io.File` | Native Foundation FileManager backed by PlatformFs | Future spec |
| `SHC-E13` | Android app (future) — Scoped Storage post-API 30 | PlatformFs implementation w/ Storage Access Framework | Future spec |
| `SHC-E14` | Konsument forgets `core.stop()` w shutdown | Process leak — JVM shutdown hook auto-stops; warning log | Shutdown hook test |
| `SHC-E15` | Cross-host hash mismatch (regression) | CI fails — release blocked | CrossHostParityTest |

---

## 9. New Components Spec

### 9.1 `HostAdapter` — see section 5.1

### 9.2 `PlatformFs` — see section 5.2

### 9.3 `ProperBackupAgentCore` — see section 5.4

### 9.4 `CrossHostParityTest` (CI-required)

Lokalizacja: `properbackup-shared/src/jvmTest/kotlin/.../CrossHostParityTest.kt`

```kotlin
class CrossHostParityTest {
    @Test fun `vps host upload produces same blob as mc host`() {
        val testFile = generateDeterministic100MbFile()
        val key = EncryptionKey.fromTestVector()

        val vpsHash = uploadViaHost(VpsHostAdapter(tempDir), testFile, key)
        val mcHash = uploadViaHost(MockMcHostAdapter(tempDir), testFile, key)

        assertEquals(vpsHash, mcHash)
    }

    @Test fun `differential scanner produces same chunk list`() { /* ... */ }

    @Test fun `header bytes match`() { /* ... */ }
}
```

CI: `ci-cd-release-pipeline-spec.md` job `cross-host-parity` runs this test on every PR.

### 9.5 Forbidden Imports Gradle Task

```kotlin
tasks.register("forbiddenImportsCheck") {
    doLast {
        val forbidden = listOf(
            "import org.bukkit",
            "import org.spigotmc",
            "import io.papermc.paper",
            "import net.fabricmc",
            "import net.minecraftforge",
            "import android",
            "System.getProperty(\"user.home\")",
            "System.getProperty(\"user.dir\")",
        )
        val violations = mutableListOf<String>()
        sourceSets["commonMain"].kotlin.srcDirs.forEach { dir ->
            dir.walkTopDown().filter { it.extension == "kt" }.forEach { file ->
                forbidden.forEach { pattern ->
                    if (file.readText().contains(pattern)) {
                        violations.add("${file.relativeTo(rootDir)}: forbidden '${pattern}'")
                    }
                }
            }
        }
        if (violations.isNotEmpty()) throw GradleException("Forbidden imports:\n${violations.joinToString("\n")}")
    }
}

tasks.named("check") { dependsOn("forbiddenImportsCheck") }
```

---

## 10. Definition of Done

Kazda zmiana w `properbackup-shared` musi spelniac:

1. **Compile** dla wszystkich aktualnych targetow (jvm, jvmTest)
2. **Test green** dla wszystkich Test Groups (SHC-A do SHC-G)
3. **Forbidden imports check** passes (SHC-E)
4. **Cross-host parity test passes** (SHC-D1, D2, D3) — `agent-vps` i `mc-plugin` mock-test uplaod identical blobs
5. **Versioning** — semver bump (patch/minor/major)
6. **Konsumenci nie wymagaja zmian semantycznych** dla patch/minor bump (only major moze)
7. **Lint clean** (detekt, ktlint)
8. **Brak DOTYKAJ-NIE-RUSZAJ naruszen** (core.crypto.*, core.filename.* itd. nie zmienione)
9. **Dokumentacja zaktualizowana** — jezeli dodajesz nowy `HostAdapter` method, opisz w sekcji 5.1
10. **CHANGELOG.md w `properbackup-shared/` zaktualizowany** — co dodane, co changed (semver)

Kazda zmiana w konsumencie (`agent-vps`, `mc-plugin`):

1. **Konsument tylko deklaruje `HostAdapter`** — zero logiki domenowej
2. **Konsument nie dodaje fields/method do shared** (jezeli brak, dodaj w shared)
3. **Konsument robi `core.start(adapter)` i nic wiecej** w lifecycle hook
4. **Konsument testow ma tylko `HostAdapter` impl test** + integration test ze shared (mock buffer)
5. **Konsument NIE forka shared** (z PR-em do shared, jezeli czegos brak)
6. **Cross-host parity test** runs as part of consumer CI
7. **Konsument pin pelna wersja shared** (no dynamic resolution)

---

## 11. Workflow Protocol (TDD red-first)

1. **Find requirement** — z tej spec, z `agent-vps-master-spec.md`, z `minecraft-plugin-master-spec.md`
2. **Red test** — napisz test w `shared/src/jvmTest/` ktory faila (assert nowego zachowania)
3. **Implement minimally** — najmniejsza zmiana w shared
4. **Verify**:
   - Test green
   - `forbiddenImportsCheck` pass
   - `crossHostParityTest` pass
   - Detekt + ktlint green
5. **Bump version** w `shared/build.gradle.kts` (semver)
6. **Update consumers** w osobnych PR-ach — bump shared version pin

**Red lines (zerowa tolerancja):**

- **NIE WOLNO** dodawac logiki domenowej w konsumencie zamiast w shared
- **NIE WOLNO** importowac org.bukkit/paper/fabric/forge w shared
- **NIE WOLNO** uzywac `System.getProperty("user.home")` w shared — tylko host.configDir()
- **NIE WOLNO** mergowac PR-a w shared bez zielonego cross-host parity test
- **NIE WOLNO** zmieniac semantyki `core.crypto.*` (zamrozone)

---

## 12. Senior + QA Paranoid Mode Prompt (do wkleienia na poczatek sesji)

> Pracujesz nad `properbackup-shared` zgodnie z `properbackup-docs/architecture/shared-core-architecture-spec.md`. Twoja praca jest ABSOLUTNIE krytyczna dla projektu — to fundament dla agent VPS, MC plugin i przyszlych Fabric/Forge/iOS.
>
> Przed kazda zmiana sprawdz:
> 1. Czy ta zmiana nalezy do shared czy do konsumenta? (Logika domenowa = shared. Integracja z host = konsument.)
> 2. Czy nie importujesz org.bukkit/paper/fabric/forge w shared?
> 3. Czy nie hardcodujesz sciezki ($HOME, dataFolder, ConfigDir)? Tylko host.configDir().
> 4. Czy zachowujesz cross-host parity? (Test SHC-D1 musi przejsc.)
> 5. Czy nie naruszasz zamrozonych komponentow (core.crypto.*, core.filename.*)?
>
> Pisz red-test first. Bumpuj semver. Bez approve cross-host parity testu — zero merge.
>
> Zlote pytanie: "Czy ta sama logika dziala identycznie na VPS, MC, Fabric, Forge?" Jezeli NIE — refactor.

---

## 13. Go/No-Go Checklist przed pierwszym release shared v1.0

### 13.1 Konsument readiness

- [ ] `agent-vps` uzywa wylacznie `HostAdapter` interface — zero direct file/system calls
- [ ] `mc-plugin` (jezeli zaczety) uzywa `PaperHostAdapter` — zero direct logic
- [ ] Oba konsumeci uzywaja identycznej wersji shared

### 13.2 Cross-host parity

- [ ] `CrossHostParityTest` zielony lokalnie
- [ ] `CrossHostParityTest` zielony w CI
- [ ] Manual test: VPS upload + MC upload tego samego pliku — SHA-256 identical

### 13.3 Lint & forbidden imports

- [ ] `forbiddenImportsCheck` passes
- [ ] Detekt zielony
- [ ] Ktlint zielony

### 13.4 Documentation

- [ ] `properbackup-shared/README.md` zaktualizowany
- [ ] Ten dokument (`shared-core-architecture-spec.md`) zsynchronizowany z kodem
- [ ] Konsument docs (`agent-vps-master-spec.md`, `minecraft-plugin-master-spec.md`) odwoluja sie do tego dokumentu

### 13.5 Future targets readiness

- [ ] Interface design pozwala na dodanie Native target (commonMain JVM-friendly ale `expect/actual` granica zaznaczona)
- [ ] Brak `java.io.File` bezposrednio w `commonMain`
- [ ] Brak `kotlinx.coroutines.Dispatchers.IO` poza `host.scheduleXxx()` API

---

## 14. Appendix A — Glossary

- **Shared Core**: `properbackup-shared` Kotlin Multiplatform library — jedyne miejsce gdzie zyje logika domenowa agenta
- **Consumer / Host**: aplikacja konsumencka uruchamiajaca shared (agent-vps, mc-plugin, future Fabric/Forge/iOS)
- **HostAdapter**: kontrakt interface ktory konsument implementuje dla shared
- **PlatformFs / PlatformClock / PlatformNetInfo**: KMP-friendly primitive abstractions
- **Cross-host parity**: gwarancja ze ten sam input produkuje identyczny output na kazdym hoscie
- **HR-X**: Hard Requirement number X (sekcja 0)

## 15. Appendix B — Cross-references

- `agent-vps-master-spec.md` — jak `agent-vps` implementuje `VpsHostAdapter`
- `minecraft-plugin-master-spec.md` — jak `mc-plugin` implementuje `PaperHostAdapter`
- `buffer-core-master-spec.md` — co buffer expect uploads from agentow (uniform)
- `crypto-and-compliance-spec.md` — core.crypto.* zamrozone (cross-ref tutaj sekcja 3 NIE RUSZAJ)
- `ci-cd-release-pipeline-spec.md` (CICD-G) — CI matrix dla cross-host parity
- `Biznesplan_ProperBackup_v6_AI_Blueprint` — sekcja 2.1 Master Blueprint (Single Source of Truth)

## 16. Appendix C — Decision History

| Data | Decyzja | Powod |
|------|---------|-------|
| 2026-05 | Shared = KMP, ale aktualnie JVM-only | Nie ma celu Native dzisiaj, prosciej zaczac z JVM, KMP-ready dla przyszlosci |
| 2026-05 | HostAdapter interface zamiast dziedziczenia | Konsument moze byc JavaPlugin / DedicatedServerModInitializer / etc. — composition over inheritance |
| 2026-05 | Forbidden imports zamiast modul boundary | Prosciej do reviewu, mniej Gradle config |
| 2026-05 | maxIoBytesPerSec per host capability | VPS i MC maja rozne profile network/cpu — niech host deklaruje |

## 17. Appendix D — Co ten dokument NIE obejmuje

- Konkretna implementacja `JvmPlatformFs` / `BukkitPlatformFs` (to jest w `agent-vps-master-spec.md` / `minecraft-plugin-master-spec.md`)
- Konkretne `BackupOrchestrator` algorytmy (TDD-driven, w `buffer-core-master-spec.md`)
- Stripe billing (`master-tdd-plan.md`)
- OVH migration (`ovh-cloud-archive-migration-spec.md`)
- Web UI (`web-panel-master-spec.md`)

---

## 18. Appendix E — LLD: wersjonowanie i kontrakt regresji (odpowiedź na audyt ryzyka #3)

> **Kontekst audytu:** „Agent naprawiając błąd w VPS może zmodyfikować shared core
> tak, że wysypie kompilację buffera/MC." Ta sekcja zamienia HR-1..HR-10 w
> **operacyjny kontrakt wersjonowania**: shared traktujemy jak **niemodyfikowalną,
> wersjonowaną bibliotekę**, a każda zmiana przechodzi bramkę cross-host parity.

### 18.1 SemVer — polityka

`properbackup-shared` publikuje artefakt `shared-<MAJOR>.<MINOR>.<PATCH>`:

| Zmiana | Bump | Przykład |
|--------|------|----------|
| Nowa metoda/pole opcjonalne, zachowane sygnatury | **MINOR** | nowy `HeaderFirstReader.peek()` |
| Bugfix bez zmiany kontraktu | **PATCH** | poprawka retry backoff |
| Zmiana/usunięcie publicznej sygnatury, zmiana formatu blobu/DTO | **MAJOR** | zmiana `BufferUploader.upload(...)` |

> **Złota zasada:** zmiana, która łamie kompilację KTÓREGOKOLWIEK konsumenta =
> **MAJOR** i wymaga skoordynowanego release wszystkich hostów. Agent NIE robi
> takiej zmiany „przy okazji" fixa — to osobny, świadomy PR z migracją konsumentów.

### 18.2 Pinning i konsumpcja

```kotlin
// gradle: konsument pinuje DOKŁADNĄ wersję (brak '+', brak 'latest.release')
dependencies { implementation("pl.danielniemiec:properbackup-shared:1.4.2") }
```

- Konsumenci pinują dokładną wersję (reprodukowalność buildów).
- Bump wersji u konsumenta to świadomy commit, nie auto-update.
- `shared` eksportuje stałą `SharedVersion.VALUE` — buffer loguje wersję każdego
  podłączonego agenta (telemetria), by wykryć rozjazd w flocie.

### 18.3 Protokół zmiany w shared (obowiązkowy dla agenta)

```
1. Zmiana potrzebna? Czy NA PEWNO w shared (HR-2)? Jeśli to host-specific → do konsumenta.
2. Klasyfikuj bump (18.1). MAJOR → zatrzymaj się, zgłoś Danielowi (skoordynowany release).
3. Red-first test w shared (HR-10: mockuj tylko HostAdapter/PlatformFs).
4. Uruchom `cross-host-parity` (HR-9): agent-vps + MC (MockBukkit) ładują NOWY JAR,
   uploadują ten sam 100MB plik → identyczny SHA-256 blob w mock-OVH.
5. Zielony parity = warunek konieczny mergu. Czerwony u JEDNEGO hosta = blok.
6. Bump SemVer + zaktualizuj pin u WSZYSTKICH konsumentów w tym samym release.
```

### 18.4 Bramka regresji w CI (egzekwowanie)

| Bramka | Warunek przejścia | Realizuje HR |
|--------|--------------------|--------------|
| `compile-all-consumers` | agent-vps + mc-plugin kompilują się z nowym `shared` JAR | HR-1, HR-2 |
| `cross-host-parity` | identyczny blob SHA-256 ze wszystkich hostów dla 100MB pliku | HR-4, HR-9 |
| `forbidden-imports` | konsument nie importuje wewnętrznych pakietów shared poza kontraktem | HR-2 |
| `format-compat` | magic bytes + wersja formatu blobu niezmienione (lub MAJOR bump) | HR-5, HR-7 |

> Patrz `ci-cd-release-pipeline-spec.md` (CICD-G) — konkretne joby. Dopóki bramka
> `cross-host-parity` nie jest zielona, **żaden** PR dotykający shared nie wchodzi.

### 18.5 Niezmienniki

| # | Niezmiennik | Cross-ref |
|---|-------------|-----------|
| S-1 | Zmiana łamiąca kompilację konsumenta = MAJOR + skoordynowany release | 18.1, 18.3 |
| S-2 | Konsumenci pinują dokładną wersję (brak auto-update) | 18.2 |
| S-3 | Merge do shared niemożliwy bez zielonego `cross-host-parity` | 18.4, HR-9 |
| S-4 | Format blobu (magic bytes/wersja) stabilny w obrębie MAJOR | HR-5, HR-7 |
