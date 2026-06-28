# ProperBackup — Session Orchestration Plan (4 rownolegle sesje)

Wersja: 1.1 (2026-06-20)
Status: **AKTYWNY** — instrukcje dla 4 rownolegych sesji Devin
Autor: Manager session (koordynacja)

---

## 0a. AKTUALIZACJA ARCHITEKTURY STORAGE — 2026-06-20 (NADRZEDNA)

> Status: **ZATWIERDZONE przez Daniela.** Ta sekcja ma **PIERWSZENSTWO** nad
> wszystkimi wzmiankami o "OVH Cloud Archive" / "Swift" / "unsealing" /
> "segmentacja DLO/SLO" w dalszej czesci tego dokumentu oraz w
> `ovh-cloud-archive-migration-spec.md`. Gdy cokolwiek ponizej jest sprzeczne z
> ta sekcja — obowiazuje ta sekcja.

### Decyzja
Dane klientow przechowujemy **WYLACZNIE na dedykowanym serwerze OVH**
(Kimsufi KS-STOR, 4x4 TB HDD RAID5 = ~11 TB na `/mnt/storage`).
**NIE replikujemy aplikacyjnie do Cloud Archive ani innej chmury.**

- **Durability / offsite / DR:** kopia #2 docelowo na **drugim serwerze dedykowanym
  (Proxmox Backup Server)** — koszt staly, inkrementalny+dedup. Na teraz: dowolna tania
  kopia offsite („byle gdzie zgrane"). OVH cold odrzucone (za drogie, per-GB).
  Pelny model DR: `pricing-and-storage-economics.md` §9.5 (kierunek 2026-06-28).
- **Restore jest INSTANT** — brak unsealing/thawing. Pliki czytane bezposrednio
  z lokalnego dysku (hot RAID). Offsite sluzy WYLACZNIE do DR (padl caly primary).

### Konsekwencje dla kodu
1. **Storage backend** = interfejs `StorageClient` + `LocalFsStorageClient`
   (zapis paczek 900-950 MB do `/mnt/storage`). Zachowaj interfejs (pluggable na
   przyszlosc), ale **PRIMARY = local FS**.
2. **USUN z critical path:** unseal request/polling, segmentacja DLO/SLO,
   opoznienia `MockSwiftClient`. `OvhSwiftClient` moze zostac w repo za
   interfejsem, ale **NIE jest uzywany w pipeline**.
3. **RECOVERY:** stan `THAWING` staje sie pass-through (no-op) → od razu `READY`.
   Zero zaleznosci od unseal. Brak punktu styku "OVH unseal" miedzy sesjami.
4. **Integrity:** sha256 po zapisie na lokalnym dysku (HEAD/ETag z Swift nieaktualne).
5. **Cennik (sekcja 5):** ceny KLIENTA bez zmian (S/M/L/XL zatwierdzone). Zmienia
   sie tylko NASZA struktura kosztow (flat ~109 zl/mc za serwer zamiast per-GB)
   → marza lepsza. Quota nadal liczona na **fizycznych bajtach po kompresji** na
   lokalnym dysku.

### Deploy / test
- **KANONICZNY cel deploy + storage = dedykowany serwer OVH** (51.255.93.127).
  Pelny opis i stan: **`deployment-dedicated-server.md`** (NAJWAZNIEJSZY dok.
  infrastruktury). Dostep: secret `OVH_DEDICATED_SERVER_PROXMOX_ROOT_PASSWORD`,
  `ssh root@51.255.93.127` → `pct exec 100`. Na dedyku juz dziala stack
  (buffer :8080, postgres, web :80) — ale ze STAREGO kodu.
- **Pelny zintegrowany E2E** (agent→buffer→pack→/mnt/storage→restore→sha256):
  na tym dedyku — koordynuje manager po dostarczeniu PR-ow przez sesje.
- Stary `properbackup-test-server.softify.com.pl` (home.pl) — tymczasowy,
  pomocniczy do per-modul testow jesli potrzeba.

---

## 0. Kontekst i cel

Cztery sesje Devin pracuja rownolegle nad ProperBackup. Kazda sesja ma
**wylaczna wlasnosc** nad okreslonymi plikami/modulami. **Zadna sesja nie dotyka
plikow innej sesji** — naruszenie = automatyczny conflict i reject PR-a.

### Zasady wspolne (obowiazuja KAZDA sesje)

1. **Przeczytaj docs PRZED kodem** — zacznij od `properbackup-docs/architecture/` (ten plik + spec Twojego obszaru)
2. **TDD red-first** — kazdy commit zaczyna sie od czerwonego testu (Testcontainers PostgreSQL, nie H2)
3. **Testy lokalne (./gradlew test)** + **testy na zywo** (deploy na `properbackup-test-server.softify.com.pl`, curl/psql/Playwright)
4. **Kazdy PR bazuje na `main`** — zero stacked PRs. Jesli PR zalezy od innego, napisz w opisie ale nie wlaczaj commitow
5. **Decyzje biznesowe** (ceny, limity, policy) — CZEKAJ na potwierdzenie Daniela. Decyzje techniczne (architektura, wzorce) — dzialaj samodzielnie
6. **Frontend PRy** — nagrywaj Playwright video, wrzucaj link w komentarz PR
7. **Strefy DOTYKAJ vs NIE RUSZAJ** — przestrzegaj stref z odpowiedniego master spec
8. **Komunikacja** — informuj o postepach, pytaj gdy cos nielogiczne lub jest lepsza opcja
9. **Testy E2E na zywo** — deploy na test server, weryfikuj curl + psql + Playwright
10. **SSH do serwera testowego:** `properbackup-test-server.softify.com.pl`, klucz w secret `TEST_SERVER_SECRET_KEY`

### Serwer testowy

- Host: `properbackup-test-server.softify.com.pl` (home.pl VPS)
- Buffer port: 7100
- SSH: klucz ed25519 w secret `TEST_SERVER_SECRET_KEY`
- Stripe sandbox: secret `STRIPE_TEST_WEBHOOK_SECRET`
- Deploy: `./gradlew build` → `scp` JAR → `docker compose restart`

### Kolejnosc mergowania

Sesje tworza PRy NIEZALEZNIE (kazda na swoim branchu, bazujac na `main`).
Daniel merguje recznie po review. Jesli PR zalezy od innego — napisz w opisie.

---

## 1. Sesja BACKUP-CORE — Rdzen systemu backupow

### Cel
Dopracowac i przetestowac caly pipeline backupu od A do Z:
agent scan → dedup → encrypt → upload → buffer receive → seal → pack 900-950MB → flush do storage.

### Spec referencyjny
- `buffer-core-master-spec.md` (P1)
- `shared-core-architecture-spec.md` (P0)
- `agent-vps-master-spec.md` (P1) — TYLKO sekcje transport (resumable upload, circuit breaker, retry)

### Wlasnosc plikow (TYLKO te pliki w PRach)

```
properbackup-buffer/
  src/main/kotlin/.../inbox/          # InboxReceiver, ChunkStorage, DiskGuard, PayloadGuard
  src/main/kotlin/.../flush/          # ChunkSealer, PackBuffer, FlushTrigger, BudgetGuard
  src/main/kotlin/.../flush/StorageQuotaGuard.kt  # wspolne z billing — OSTROZNIE
  src/main/kotlin/.../verify/         # RestoreVerifier
  src/main/kotlin/.../report/         # AuditReportGenerator
  src/main/kotlin/.../ovh/            # OvhSwiftClient, MockSwiftClient, DevSafetyGuard
  src/main/resources/schema.sql       # TYLKO nowe tabele/kolumny (CREATE IF NOT EXISTS)
  src/test/kotlin/.../flush/          # testy pack, seal, flush
  src/test/kotlin/.../inbox/          # testy ingestion
  src/test/kotlin/.../ovh/            # testy OVH client

properbackup-shared/
  src/jvmMain/.../transport/          # BufferUploader, RetryPolicy, ResumableUpload, CircuitBreaker
  src/jvmMain/.../scanner/            # DifferentialScanner, MetadataCache (NIE MODYFIKUJ algorytmu dedup)
  src/jvmTest/.../transport/          # testy

properbackup-stack/
  scripts/ovh-bootstrap.sh            # NOWY — setup OVH container
  docker-compose.yml                  # TYLKO env vars OVH
```

### NIE DOTYKAJ
- `crypto/` (ProperCrypto, KeyDerivation, HeaderCodec) — zamrozone
- `scanner/DifferentialScanner.kt` algorytm — zamrozony (mozna dodac testy)
- `auth/`, `subscription/`, `payment/` — wlasnosc sesji BILLING (juz zrobione)
- `sse/` — wlasnosc sesji WEB-PANEL
- `server/ServerHandler.kt` — wspolne, OSTROZNIE

### Zadania (w kolejnosci priorytetu)

1. **OVH Cloud Archive integration** — rozbudowa `OvhSwiftClient.kt`:
   - Segmentacja DLO/SLO dla obiektow (nasze paczki 900-950MB)
   - Unseal request + polling status (Cloud Archive wymaga unsealing przed GET)
   - Retry z exponential backoff na segmentach
   - Integrity verification: `HEAD` po `PUT`, porownaj ETag/size
   - Test integracyjny na prawdziwym OVH staging container (jesli dostepne credentials)
   - `MockSwiftClient` — symuluj opoznienia unsealing + 5% error rate

2. **Resumable Upload** (w `properbackup-shared`):
   - `ResumableUpload.kt` — Content-Range, Idempotency-Key
   - Test: 1GB upload przerywany na 500MB → wznowienie
   - Circuit Breaker: 3 consecutive 5xx → OPEN 60s → HALF_OPEN probe

3. **Pack pipeline hardening**:
   - Force-flush po 24h (HR-7)
   - Disk-full soft block (HR-10)
   - Crash recovery test (kill -9 mid-write → restart → integrity OK)

4. **Cost monitoring**:
   - `OvhCostTracker.kt` — dzienny job, bytes stored/uploaded per user
   - Tabela `user_storage_daily` (fizyczne bajty z historia)
   - Alert na spike: >50GB/1h per user → soft block

### Uwagi dot. OVH Cloud Archive

**WAZNE:** Uzywamy OVH Cloud Archive (cold storage), NIE zwykly Object Storage.
- Stawka: 0,0000132 PLN netto/GiB/godz (~9,64 PLN netto/TiB/mc)
- Zapis (ingress): 0,04 PLN netto/GiB
- Egress (restore): DARMOWY
- Obiekty wymagaja unsealing przed odczytem (minuty do godzin)
- Segmentacja: obiekty >5GB musza byc uploadowane jako segmenty (DLO/SLO)
- Nasze paczki 900-950MB — powinny isc jako single PUT bez segmentacji
- Szukaj sprawdzonej biblioteki Java/Kotlin do Swift + PCA — jesli nie ma
  godnej zaufania, rozbuduj istniejacy `OvhSwiftClient.kt` z solidnymi testami

### Definition of Done
- `./gradlew test` — 100% PASS
- Deploy na test server → upload pliku → seal → pack → flush → verify integrity
- Crash recovery test: kill -9 mid-pack → restart → zero data loss
- OVH client: PUT 950MB → HEAD verify → unseal → GET → sha256 match
- Force-flush po 24h: test z manipulacja clock

---

## 2. Sesja RECOVERY — Odtwarzanie danych (Time Machine)

### Cel
Pelna implementacja Recovery Mode — od UI po agent restore protocol.
**Recovery MUSI dzialac zawsze.** Potwierdzeniem jest zestaw edge case + happy path testow E2E.

### Spec referencyjny
- `user-facing-recovery-spec.md` (P1) — 10 Hard Requirements, state machine, DRY RUN, rollback

### Wlasnosc plikow

```
properbackup-buffer/
  src/main/kotlin/.../recovery/       # RecoverySession, RecoveryHandler, state machine
  src/main/resources/schema.sql       # tabele recovery_session, recovery_operation (CREATE IF NOT EXISTS)
  src/test/kotlin/.../recovery/       # testy state machine, DRY RUN, cancel

properbackup-shared/
  src/jvmMain/.../restore/            # NOWY katalog — RestoreExecutor, CriticalPathsGuard, PreRecoverySnapshot
  src/jvmTest/.../restore/            # testy restore protocol

properbackup-agent/
  src/main/kotlin/.../restore/        # VPS-specific restore adapter
  (ostroznie — pamietaj HR-1 z agent-vps: Shared-Core Only)

properbackup-web/
  src/recovery/RecoveryMode.jsx       # NOWY — center-screen overlay (Time Machine UX)
  src/recovery/DryRunPreview.jsx      # NOWY — preview co zostanie przywrocone/usuniete
  src/recovery/RecoveryProgress.jsx   # NOWY — progress bar + ETA
  src/servers/SnapshotTimeline.jsx    # MODYFIKUJ — dodaj "Restore to this point" button
  src/servers/BackupsPage.jsx         # MODYFIKUJ — RecoveryContext integration
  src/i18n/locales/pl.json            # klucze recovery.mode.*
  src/i18n/locales/en.json            # klucze recovery.mode.*
  tests/e2e/recovery/                 # Playwright E2E
```

### NIE DOTYKAJ
- `inbox/`, `flush/`, `ovh/` — wlasnosc sesji BACKUP-CORE
- `subscription/`, `payment/` — billing (juz zrobione)
- `auth/` — bez zmian (chyba ze potrzebujesz nowego endpointu recovery-specific)
- Istniejace `RecoveryWizard.jsx`, `OrphanRecovery.jsx` — single-file flow, ZOSTAJE

### Zadania

1. **Recovery Session API** (buffer):
   - State machine: IDLE → REQUESTED → PLANNING → THAWING → READY → AGENT_RESTORING → VERIFYING → DONE | FAILED | CANCELLED
   - `POST /recovery/start` — tworzy sesje, DRY RUN
   - `POST /recovery/confirm` — user potwierdza (checkbox "Rozumiem...")
   - `POST /recovery/cancel` — cancel + rollback (best-effort)
   - `GET /recovery/status` — SSE stream z progressem
   - Audit log KAZDA akcja (HR-6)

2. **Restore Protocol** (shared + agent):
   - `RestoreExecutor.kt` — idempotent per-file (download → .tmp → verify sha256 → atomic rename)
   - `CriticalPathsGuard.kt` — whitelist plikow NIGDY do usuniecia
   - Pre-recovery snapshot OBOWIAZKOWY (HR-5)
   - Resumable on crash: SQLite agent tracking (recovery_operations tabela)
   - Cancel + rollback: pliki z `.quarantine/<recovery_id>/`

3. **Recovery Mode UI** (web):
   - Time Machine overlay (center-screen, fixed position)
   - DRY RUN preview (files to restore, delete, unchanged)
   - Progress bar + ETA
   - "Restore to this point" button na SnapshotTimeline
   - Per-server lockdown (HR-2): inne servery dzialaja normalnie
   - Playwright E2E: happy path + cancel + crash recovery

4. **OVH unsealing flow** (KOORDYNACJA z sesja BACKUP-CORE):
   - Thawing state: request unseal → poll → ready
   - BACKUP-CORE implementuje unseal w OvhSwiftClient
   - RECOVERY uzywa go w RecoverySession state machine
   - Jesli BACKUP-CORE nie ma jeszcze unsealing — uzyj mock delay

### Definition of Done
- Recovery happy path E2E: wybierz snapshot → DRY RUN → confirm → restore → verify → DONE
- Cancel mid-restore → rollback do pre-recovery snapshot → stan jak przed
- Crash agenta mid-restore → restart → wznowienie od ostatniego pliku
- Per-server lockdown: inne servery w koncie dzialaja normalnie podczas recovery
- Playwright video nagrany i wrzucony w komentarz PR

---

## 3. Sesja AGENT — Dystrybucja i instalacja agenta

### Cel
Agent jako samoinstalujacy sie JAR z portable Java (jlink). Linux-first,
architektura gotowa na Windows/macOS/MC.

### Spec referencyjny
- `agent-vps-master-spec.md` (P1)
- `shared-core-architecture-spec.md` (P0)

### Wlasnosc plikow

```
properbackup-agent/
  src/main/kotlin/.../               # AgentMain.kt, VpsHostAdapter, installer
  build.gradle.kts                    # jlinkDist configuration
  scripts/                            # install-service.sh (systemd)

properbackup-shared/
  src/jvmMain/.../activation/         # ActivationClient, GlobalConfigWriter
  src/jvmMain/.../logging/            # RemoteTelemetry, SpotlightStatus
  (transport/ i scanner/ — wspolne z BACKUP-CORE, OSTROZNIE)
```

### NIE DOTYKAJ
- `crypto/` — zamrozone
- `scanner/DifferentialScanner.kt` algorytm — zamrozony
- `transport/BufferUploader.kt` — wspolne z BACKUP-CORE (koordynacja!)
- `restore/` — wlasnosc sesji RECOVERY
- `properbackup-buffer/` — nie dotykaj (buffer to inna sesja)
- `properbackup-web/` — nie dotykaj (web to inna sesja)

### Zadania

1. **jlinkDist build** — samowystarczalny JAR z portable JRE (~61MB):
   - `./gradlew jlinkDist` → archiwum tar.gz z JRE + agent JAR
   - Rozpakowujesz, odpalasz `./properbackup-agent` — dziala bez zainstalowanej Javy
   - Pierwsze uruchomienie: wyswietla KOD DOSTEPU (8-12 znakow) w terminalu
   - Kod wpisujemy w web UI → agent aktywowany

2. **Systemd integration**:
   - Wykryj czy jest sudo: jesli tak → auto-install systemd service
   - Jesli nie → wyswietl komende do skopiowania: `sudo properbackup install-service`
   - Service: auto-start po reboot, auto-restart po crash (RestartSec=5)
   - `properbackup-agent.service` w `/etc/systemd/system/`
   - Status: `systemctl status properbackup-agent`

3. **Heartbeat + monitoring**:
   - Agent pinguje buffer co 60s (heartbeat)
   - Buffer zapisuje `last_heartbeat_at` w tabeli `servers`
   - (Web UI / monitoring — sesja WEB-PANEL uzywa tego do alertow)

4. **Backup scheduling**:
   - Default: co 5 minut differential scan
   - Konfigurowalne przez `config.yml` lub web UI
   - IoThrottle: 50MB/s read, 25% CPU (z `HostAdapter.capabilities()`)

5. **JWT bootstrap**:
   - Activation token → wymiana na 5min JWT (HR-6 z agent-vps-spec)
   - Auto-refresh co 4 min
   - Wszystkie requesty przez `JwtClient.currentToken()`

### Definition of Done
- `./gradlew jlinkDist` → tar.gz < 70MB
- Rozpakuj na czystym Linux → `./properbackup-agent` → wyswietla kod dostepu
- Wpisz kod w web UI → agent aktywowany → differential scan startuje
- `kill -9` agenta → systemd restartuje → agent wznawia prace
- Reboot serwera → agent startuje automatycznie

---

## 4. Sesja WEB-PANEL — Panel, monitoring, powiadomienia

### Cel
Timeline backupow w czasie rzeczywistym, monitoring agentow, powiadomienia
o problemach (email na start, SMS w przyszlosci).

### Spec referencyjny
- `web-panel-master-spec.md` (P2)
- `observability-and-dr-spec.md` (P0) — health endpoints, metryki

### Wlasnosc plikow

```
properbackup-web/
  src/timeline/                       # SnapshotTimeline, TimelineView
  src/monitoring/                     # NOWY — agent health dashboard
  src/notifications/                  # NOWY — ustawienia powiadomien
  src/settings/                       # ustawienia konta, urzadzenia
  src/api/                            # axios wrappers
  src/i18n/locales/{pl,en}.json       # TYLKO klucze monitoring.*, notifications.*
  (NIE DOTYKAJ: src/recovery/ — wlasnosc sesji RECOVERY)
  (NIE DOTYKAJ: src/subscription/ — billing juz zrobione)

properbackup-buffer/
  src/main/kotlin/.../monitoring/     # AgentHealthMonitor (heartbeat tracking)
  src/main/kotlin/.../sse/            # SseEventBus (real-time push)
  src/main/kotlin/.../server/         # ServerHandler — OSTROZNIE, wspolne
  src/main/kotlin/.../notifications/  # NOWY — EmailNotifier, NotificationScheduler
  src/main/resources/schema.sql       # tabele notification_*, alert_* (CREATE IF NOT EXISTS)
  src/test/kotlin/.../monitoring/     # testy
  src/test/kotlin/.../notifications/  # testy
```

### NIE DOTYKAJ
- `inbox/`, `flush/`, `ovh/` — wlasnosc BACKUP-CORE
- `recovery/` — wlasnosc RECOVERY
- `subscription/`, `payment/` — billing (juz zrobione)
- `src/recovery/` w web — wlasnosc RECOVERY

### Zadania

1. **Timeline real-time** (web):
   - Os czasu backupow: kazdy backup jako event na timeline
   - Real-time update przez SSE (SseEventBus)
   - Filtrowanie po serwerze, dacie, typie (AUTO/MANUAL/TOMBSTONE)
   - Status kazdego backupu: IN_PROGRESS / SEALED / FLUSHED / VERIFIED

2. **Storage quota dashboard** (web):
   - Pokazuj: "Wykorzystano X GB / <quota tieru> GB" (fizyczne bajty z historia; quota wg tieru S/M/L/XL, patrz §5)
   - Progress bar z kolorami (zielony < 70%, zolty 70-90%, czerwony > 90%)
   - Powiadomienie w UI gdy blisko limitu
   - Info: "Przejdz na plan roczny" lub "Backup zatrzyma sie za X dni" (szacowanie)
   - Jasne komunikaty: "Nielimitowane urzadzenia — ale wiecej urzadzen = szybsze zuzycie miejsca"

3. **Agent health monitoring**:
   - Dashboard: lista serwerow z statusem (ONLINE/OFFLINE/WARNING)
   - Heartbeat tracking: agent nie odpowiada > 5 min → WARNING, > 30 min → OFFLINE
   - **Email notification** gdy agent OFFLINE a serwer pingable
   - Ustawienia: wlacz/wylacz powiadomienia, email docelowy
   - (Przyszlosc: SMS — przygotuj architekture ale jeszcze nie implementuj)

4. **Backup scheduling UI**:
   - Ustawienie interwalu backupu per serwer (default: co 5 min)
   - Konfiguracja IoThrottle (jesli user chce ograniczyc)
   - Kalendarz: mozliwosc ustawienia okna backupowego (np. 00:00-06:00)

5. **Plan display**:
   - Tiery S/M/L/XL — komunikuj "Unlimited devices" + quota wybranego tieru (patrz §5)
   - (Pelny cennik i quota: §5 nizej + `pricing-and-storage-economics.md` §9)

### Definition of Done
- Timeline: nowy backup pojawia sie w UI w < 3s od seal (SSE)
- Storage quota: prawidlowe zliczanie fizycznych bajtow, progress bar
- Agent offline → email w ciagu 10 min
- Playwright video z calym flow: login → dashboard → timeline → monitoring → ustawienia

---

## 5. Model cenowy — ZATWIERDZONY (2026-06-20, decyzja Daniela)

> ⚠ **Koszt NASZ = STAŁY serwer (dedyk OVH ~135 zł brutto/mc).** Pełny model kosztu,
> marży i quoty: `pricing-and-storage-economics.md` §9 (NADRZĘDNE). Poniższe stawki
> per-GB OVH to już tylko **benchmark/historia**, NIE nasz koszt. Offsite DR robimy
> drugim serwerem (PBS), nie OVH cold (odrzucone jako za drogie) — patrz §9.5.

### Fakty (OVH Cloud Archive — tylko benchmark/historia, netto)
- Storage: 0,0000132 PLN/GiB/godz = **9,64 PLN/TiB/mc netto** = **11,86 PLN/TiB/mc brutto**
- Zapis (ingress): **0,04 PLN/GiB netto** = **0,049 PLN/GiB brutto**
- Egress (restore): **DARMOWY**
- **Kompresja**: GZIPOutputStream PRZED szyfrowaniem = ~40% oszczednosci na storage

### Cennik (FINAL)

Unlimited devices w kazdym tierze. Quota = start quota, rośnie **+10% startu/mc, sufit 2× startu per tier** (Opcja 2 — NIE wspólne 2 TB dla każdego). Pełne liczby: `pricing-and-storage-economics.md` §9.4.
Quota liczona na **fizycznych bajtach po kompresji** (co faktycznie siedzi na dedyku).

| Tier | Start quota | Cena mc | Cena rok (~25% rabat) | Zysk worst case 1mc + 90dni ret. |
|---|---|---|---|---|
| **S** | 150 GB | **29 zl/mc** | **259 zl/rok** | +21 zl ✅ |
| **M** | 300 GB | **39 zl/mc** | **349 zl/rok** | +23 zl ✅ |
| **L** | 500 GB | **59 zl/mc** | **529 zl/rok** | +33 zl ✅ |
| **XL** | 1 TB | **89 zl/mc** | **790 zl/rok** | +31 zl ✅ |

### Zasady

- **Retencja po rezygnacji:** 90 dni. Dane dostepne do restore (canRestore=true), backup zatrzymany (canUpload=false). Po 90 dniach: email ostrzegawczy 7 dni przed → fizyczne usuniecie z serwera/dysku
- **Zacheta do rocznego:** roczny = **pełny sufit tieru (2× start) od razu**, bez progresywnego wzrostu (ZATWIERDZONE 2026-06-21)
- **Downgrade:** jezeli current usage > nowa quota → backup zatrzymany (canUpload=false). Dane przechowywane. Klient musi wyczyscic albo wrocic na wyzszy tier
- **Unlimited devices:** quota WSPOLNA dla wszystkich urzadzen. Web UI jasno komunikuje: "Wiecej urzadzen = szybsze zuzycie limitu"
- **Kompresja:** GZIPOutputStream przed AES-256-GCM. Klient "widzi" wiecej miejsca niz fizycznie zajmuje (bonus)

### Ograniczenia architektoniczne
- Dedup (DifferentialScanner, 4MB chunki) jest KRYTYCZNY dla oplacalnosci
- HR-1 (immutability) = fizyczne bajty TYLKO rosna
- StorageQuotaGuard liczy fizyczne bajty po kompresji → blokuje upload gdy limit osiagniety
- Usuniete pliki przechowywane z flaga `DELETED` (nie fizycznie kasowane)

### Web UI — plan display
- Selektor tierow: S / M / L / XL z cenami
- Toggle: Miesiecznie / Rocznie (z wyrazna oszczednoscia)
- Progress bar: "Wykorzystano X GB / Y GB" (fizyczne po kompresji)
- Kolory: zielony < 70%, zolty 70-90%, czerwony > 90%
- Ostrzezenie: "Backup zatrzyma sie za ~X dni" (szacowanie na podstawie tempa zuzycia)

---

## 5b. Przyszle features — P2 (PO obecnych sesjach)

### Mapa swiata MC z chunk-level restore (P2)
- Interaktywna mapa regionow/chunkow w web panelu
- Parser Anvil (.mca) po stronie buffera — wyciaganie konkretnych chunkow z backup
- Drill-down: region → chunk → diff blokow miedzy snapshotami
- Timeline slider na mapie — stan swiata w dowolnym momencie
- Restore per-chunk: zaznacz chunki na mapie → cofnij
- **KIEDY:** po implementacji agenta MC (properbackup-mc). Na razie file-level restore (sesja RECOVERY)
- Wymaga: parser NBT (biblioteka Querz/NBT, MIT), chunk extraction z .mca, React canvas/SVG grid

---

## 6. Koordynacja miedzy sesjami

### Punkty styku (potencjalne konflikty)

| Punkt styku | Sesja A | Sesja B | Rozwiazanie |
|---|---|---|---|
| `schema.sql` | BACKUP-CORE | RECOVERY, WEB-PANEL | Kazda sesja dodaje TYLKO swoje tabele (CREATE IF NOT EXISTS). Zero modyfikacji istniejacych |
| `BufferMain.kt` | BACKUP-CORE | RECOVERY, WEB-PANEL | Kazda sesja dodaje SWOJE endpointy w wydzielonej sekcji. Nie ruszaj cudzych |
| `StorageQuotaGuard.kt` | BACKUP-CORE | (billing juz zrobione) | BACKUP-CORE jest jedynym wlascicielem |
| `ServerHandler.kt` | AGENT (heartbeat) | WEB-PANEL (monitoring) | WEB-PANEL czyta `last_heartbeat_at`, AGENT go ustawia. Rozne kolumny |
| `transport/` w shared | BACKUP-CORE | AGENT | BACKUP-CORE robi ResumableUpload/CircuitBreaker, AGENT uzywa. Koordynacja: AGENT czeka na PR BACKUP-CORE |
| OVH unseal | BACKUP-CORE | RECOVERY | BACKUP-CORE implementuje w OvhSwiftClient, RECOVERY uzywa. RECOVERY moze uzywac mock delay do czasu gotowosci |

### Zasada ogolna
Jesli sesja potrzebuje czegos z innej sesji — **poinformuj managera (ta sesje)**
i uzyj mock/stub do czasu gotowosci drugiej sesji. NIE czekaj bezczynnie.
