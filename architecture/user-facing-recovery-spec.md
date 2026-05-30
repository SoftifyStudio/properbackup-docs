# User-Facing Recovery Mode — Master Plan (Time-Machine UX)

Wersja: 1.0 (initial, pre-prod)
Repo glowne: `properbackup-web` (UI), `properbackup-buffer` (Recovery Session API), `properbackup-agent` + `properbackup-shared` (restore protocol), `properbackup-docs` (E2E videos + skill)
Status: SPEC — instrukcje dla kolejnych agentow (4 osobne PR-y wynikajace z tego dokumentu)
Priorytet: **P1** (user-facing flagship feature — bez tego klient nie ma "1-Click Restore" w sensie ProperBackup; ratuje cel projektu)

---

## 0. Hard Requirements (Immutable Rules) — PRAWO PROJEKTU

> **Te zasady sa NIENARUSZALNE. Wymuszone przez Daniela jako twardy contract dla user-facing recovery. Kazde naruszenie = automatic rejection PR-a w review.**
>
> Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint` (sekcja 4.2 USP "1-Click Restore + Time Machine UX")
> Architecture foundation: `shared-core-architecture-spec.md` (P0), `buffer-core-master-spec.md` (immutable storage), `ovh-cloud-archive-migration-spec.md` (Hot/Cold tier)

**HR-1. Recovery is a Session, not a Click**
Recovery to **wieloetapowa sesja** z wlasnym state machine, nie jednorazowa akcja. Stany: `IDLE → REQUESTED → PLANNING → THAWING → READY → AGENT_RESTORING → VERIFYING → DONE | FAILED | CANCELLED`. Kazdy stan persystowany w `recovery_session` tabela (Postgres). User moze zamknac browser i otworzyc ponownie — sesja kontynuuje sie po stronie agent+buffer.

**HR-2. Per-Server Lockdown (NIE globalny freeze)**
Recovery Mode blokuje WRITE actions WYLACZNIE na target server. Inne servery uzytkownika pozostaja w pelni funkcjonalne. Zakladki innych serverow pokazuja **warning banner** "Recovery in progress on `<Server X>` (started 14:32, ETA 18 min)". Multi-server account = multi-recovery mozliwy rownolegle (ale max 1 recovery per server).

**HR-3. Time-Machine UX (center-screen overlay)**
Gdy user wejdzie w Recovery Mode na zakladce target server:
- Tab navigation pozostaje aktywne (Files / Timeline / Monitoring / Config) — user moze ogladac stan
- WRITE akcje (start backup, edit config, delete snapshot, restore another snapshot) — disabled z tooltipem "Recovery in progress; akcje pisarskie zablokowane"
- READ akcje (browse files, view timeline, view monitoring) — fully functional
- W srodku ekranu (`position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);`) — duzy panel "Recovery Mode" z:
  - Snapshot timestamp + label
  - Progress bar (sumaryczny % calej recovery)
  - Aktualnie wykonywana operacja ("Restoring 1247 / 3852 files...")
  - Estimated time remaining (na bazie historii agent throughput)
  - Cancel button (z confirmation modal)

**HR-4. DRY RUN Preview MANDATORY**
PRZED rozpoczeciem recovery, agent MUSI wykonac dry-run i pokazac user'owi:
- **Files to restore**: 3 421 (3.2 GB) — pliki ktore byly w snapshot, brak ich lokalnie lub maja inny sha256
- **Files to delete**: 89 (45 MB) — pliki lokalne ktorych nie bylo w snapshot
- **Files unchanged**: 12 458 — pliki ktore matchuja snapshot (skip)
- **Critical files protected**: agent config, ProperBackup state, /proc, /sys, /dev — NIGDY nie usuwane

User MUSI explicitly potwierdzic checkbox "Rozumiem, ze moje obecne pliki zostana zastapione/usuniete" PRZED przejsciem do AGENT_RESTORING. Bez tego checkbox button "Start Recovery" disabled.

**HR-5. Pre-Recovery Snapshot OBOWIAZKOWY**
PRZED przelaczeniem agent w tryb AGENT_RESTORING, agent MUSI utworzyc **pre-recovery snapshot** (snapshot CURRENT state). Powod: jezeli user zda sobie sprawe po recovery ze "wolal wczesniejszy stan", moze undo recovery do pre-recovery snapshot. Pre-recovery snapshot ma typ `PRE_RECOVERY` w `archive_snapshot.snapshot_type` (vs normalne `AUTO`/`MANUAL`/`TOMBSTONE`).

Pre-recovery snapshot nie liczy sie do user storage quota przez 30 dni (grace period). Po 30 dniach moze byc usuniety jezeli klient nie zrobi explicit "Promote to permanent" (zwykly snapshot).

**HR-6. Audit Log Every Action (RODO + customer trust)**
Kazda akcja w recovery session loguje do `audit_log`:
- `RECOVERY_REQUESTED` (user, server, target_snapshot_id, requested_at)
- `RECOVERY_DRY_RUN_COMPUTED` (files_to_restore, files_to_delete, total_bytes)
- `RECOVERY_USER_CONFIRMED` (user_ip, user_agent, confirmation_at)
- `RECOVERY_AGENT_STARTED` (agent_version, host_type)
- `RECOVERY_FILE_RESTORED` (path_hash, sha256_old, sha256_new) — append-only batch insert per 100 plikow
- `RECOVERY_FILE_DELETED` (path_hash, sha256_old)
- `RECOVERY_COMPLETED` (duration_seconds, files_restored, files_deleted, bytes_transferred)
- `RECOVERY_FAILED` (error_type, failed_at_phase)
- `RECOVERY_CANCELLED` (cancelled_at_phase, files_already_restored, rollback_attempted)

Audit PDF (cross-ref `web-panel-master-spec.md` Audit feature) MUSI zawierac dedykowana sekcje "Recovery History" jezeli klient wybierze export.

**HR-7. Resumable on Crash (idempotent per-file)**
Kazda operacja restore (file restore lub delete) MUSI byc idempotent:
- Restore: `download(sha256) → write to .tmp → verify sha256 == expected → atomic rename .tmp → final path`
- Delete: `verify file exists → move to .quarantine/<recovery_id>/<path_hash> → 30-day TTL → permanent delete`

Stan kazdej operacji w SQLite agent (`recovery_operations` tabela): `pending | downloading | writing | verifying | done | failed`. Po crashu agent: na restart wznawia od pierwszej operacji `!= done`. Buffer-side: agent reports back per-100-operations batch progress.

**HR-8. Critical Files Whitelist (never delete)**
Agent NIGDY nie usuwa:
- Swojego configa (`~/.properbackup/config.json` lub `plugins/ProperBackup/config.yml`)
- Swojego state (`~/.properbackup/state.json`, `recovery_state.json`)
- Recovery session quarantine (`~/.properbackup/quarantine/<recovery_id>/`)
- System dirs: `/proc`, `/sys`, `/dev`, `/run`, `C:\Windows\System32` (Windows), `/System` (macOS)
- Symlinki wychodzace poza backup roots (defensywne — bezpieczenstwo path traversal)

Whitelist w `shared/restore/CriticalPathsGuard.kt`. Jezeli plan recovery zawiera path z whitelist → automatic SKIP + log warning.

**HR-9. Cancel Anywhere with Rollback (best-effort)**
User moze CANCEL recovery w kazdym momencie. Behavior per state:
- `REQUESTED / PLANNING`: clean cancel (no agent involvement yet) — IDLE
- `THAWING`: cancel waiting; OVH thaw zostanie wykorzystany w przyszlosci (lub timeout 7d)
- `READY`: clean cancel (nic jeszcze nie wykonal) — IDLE
- `AGENT_RESTORING`: agent dostaje cancel command, konczy biezacy file, **rollback uses pre-recovery snapshot**:
  - Pliki ktore zostaly RESTORED w tej recovery → usuniete (quarantine z TTL)
  - Pliki ktore zostaly DELETED w tej recovery → przywrocone z `.quarantine/<recovery_id>/`
  - **Wynik: state jak przed startem recovery**
- `VERIFYING`: agent finishes verification; user moze choose "accept current state" lub "rollback to pre-recovery"
- `DONE / FAILED`: cancel niedozwolony (uzyj nowej recovery do pre-recovery snapshot)

**HR-10. Cross-Host Identical Behavior (one JAR contract)**
Restore protocol MUSI byc identyczny dla VPS, MC plugin, future Fabric/Forge. Implementacja w `properbackup-shared/restore/` (cross-ref `shared-core-architecture-spec.md` HR-1: Shared-Core Only). Host adapter dostarcza tylko:
- `PlatformFs` — file operations (juz istnieje w shared-core)
- `HostNotifier` — emit "recovery progress" do hosta (Bukkit broadcast vs VPS systemd-notify)

Cross-host parity test (`shared-core-architecture-spec.md` SHC-D): symulowana recovery 100MB scenariusza musi przechodzic identycznie na VPS i MC mock.

---

## 1. Cel dokumentu

Single source of truth dla user-facing **Recovery Mode** — flagowej funkcji ProperBackup pozwalajacej uzytkownikowi przywrocic CALY system do wybranego momentu snapshot (nie tylko pojedynczy plik). Inspirowane Time Machine z macOS, ale dostosowane do specyfiki Cloud Archive (cold tier thaw delays, network constraints, immutable storage).

Dokument zawiera **4 sekcje "implementation plan"** dla kolejnych PR-ow:
- **Sekcja A**: Frontend Recovery Mode UI w `properbackup-web` (1 PR)
- **Sekcja B**: Recovery Session API + state machine w `properbackup-buffer` (1 PR)
- **Sekcja C**: Restore Protocol w `properbackup-agent` + `properbackup-shared` (1 PR)
- **Sekcja D**: E2E Playwright tests + videos w `properbackup-docs` + `properbackup-web/tests/e2e/` (1 PR)

Te 4 PR-y musza byc mergniete w kolejnosci **B → C → A → D** (buffer wystawia API, agent obsluguje, UI uzywa, E2E testuje).

### Zakres

- Definicja Recovery Session state machine (8 stanow, opis kazdego)
- Recovery Mode UI (Time Machine center-screen overlay)
- DRY RUN computation (snapshot diff)
- Pre-recovery snapshot creation
- Audit log every action
- Idempotent per-file operations (resumable on crash)
- Cancel + rollback semantics
- Cross-host parity (VPS == MC plugin)
- E2E test plan (8 testow + videos)

### Co NIE jest w zakresie

- Single-file recovery (juz istnieje: `RecoveryWizard.jsx`, `OrphanRecovery.jsx`) — zostaje bez zmian
- Storage migration / cold tier OVH details — cross-ref `ovh-cloud-archive-migration-spec.md`
- Crypto details — cross-ref `crypto-and-compliance-spec.md`
- Subscription/billing impact — recovery dostepny dla wszystkich active subscriptions (TODO: limit per plan? — patrz Open Questions sekcja 18)
- Restoring do INNEGO servera (cross-restore) — out of scope tej iteracji
- API dla external scripting / CLI recovery — out of scope tej iteracji

---

## 2. Mapowanie kodu (current state — stan na 2026-05-26)

### 2.1 `properbackup-web` (kod istniejacy)

| Plik | Linie | Co robi | Status w recovery |
|------|-------|---------|-------------------|
| `recovery/RecoveryWizard.jsx` | 271 | 4-step modal single-file download/decrypt | **ZOSTAJE** (single-file flow) |
| `recovery/OrphanRecovery.jsx` | 153 | Single-file orphan recovery | **ZOSTAJE** |
| `recovery/ThawProgress.jsx` | 83 | OVH cold tier thaw wait UI | **REUSE** (w nowym Recovery Mode) |
| `servers/SnapshotTimeline.jsx` | 605 | Time-machine stacked day cards | **MODYFIKACJE** (dodac "Restore to this point" button) |
| `tree/DirectoryView.jsx` | ~300 | File tree browser per snapshot | **REUSE** (z RecoveryContext guards) |
| `servers/BackupsPage.jsx` | ~800 | Main backups tab | **MODYFIKACJE** (RecoveryContext integration) |
| `i18n/locales/pl.json` | - | Polish translations | **DODAC** klucze `recovery.mode.*` |
| `i18n/locales/en.json` | - | English translations | **DODAC** klucze `recovery.mode.*` |

### 2.2 `properbackup-buffer` (kod istniejacy)

| Plik | Co robi | Status w recovery |
|------|---------|-------------------|
| `verify/RestoreVerifier.kt` | Weryfikuje integralnosc post-seal | **REUSE** (sprawdzenie czy snapshot da sie restore) |
| `flush/ChunkSealer.kt` | Seal post-flush | **NO CHANGE** |
| `server/ServerHandler.kt` | Server CRUD + agent lifecycle | **MODYFIKACJE** (block write actions during recovery) |
| `BufferMain.kt` | Routes init | **MODYFIKACJE** (mount `/recovery/*` endpoints) |
| `schema.sql` | Database schema | **DODAC** tabela `recovery_session`, `recovery_operation`, `recovery_dry_run` |
| `sse/SseEventBus.kt` | Server-Sent Events | **REUSE** (emit `recovery_progress` events) |
| `logs/AuditLogHandler.kt` (jezeli istnieje, inaczej dodac) | Audit log | **MODYFIKACJE / DODAC** entries dla recovery actions |

### 2.3 `properbackup-agent` + `properbackup-shared` (kod istniejacy)

| Plik | Co robi | Status w recovery |
|------|---------|-------------------|
| `agent/AgentMain.kt` | Main entrypoint, backup loop | **MODYFIKACJE** (subscribe SSE `recovery_command`) |
| `shared/scanner/DifferentialScanner.kt` | Skanowanie + 4MB chunks + sha256 dedup | **REUSE** (do DRY RUN diff) |
| `shared/transport/BufferUploader.kt` | Upload to buffer | **NO CHANGE** (recovery to download, nie upload) |
| `shared/crypto/ProperCrypto.kt` | AES-256-GCM streaming | **REUSE** (decrypt podczas restore) |
| `shared/restore/` | (nie istnieje) | **NEW PACKAGE** — RestoreOrchestrator, SnapshotDiff, FileRestorer, FileDeleter, CriticalPathsGuard |

### 2.4 `properbackup-docs` (kod istniejacy)

| Plik | Co robi | Status w recovery |
|------|---------|-------------------|
| `e2e-videos/README.md` | Index 10 testow E2E | **MODYFIKACJE** (dodac sekcje Recovery: testy 11-18) |
| `e2e-videos/2026-05-26-fixes/` | Videos z 2026-05 | **NO CHANGE** |
| `e2e-videos/recovery/` | (nie istnieje) | **NEW DIR** — videos test11-test18 |
| `.agents/skills/` | (nie istnieje) | **NEW DIR** — recovery-e2e-testing.md skill |

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `recovery/RecoveryWizard.jsx` semantyka 4-step download single file — **ZOSTAJE bez zmian** (uzywany dla single-file flow z DirectoryView)
- `recovery/OrphanRecovery.jsx` — single-file orphan flow
- `crypto/streamingDecrypt.js`, `crypto/headerVerify.js` — decryption logic frozen (RODO compliance)
- `ProperCrypto.kt`, `KeyDerivation.kt`, `HeaderCodec.kt` — zamrozone (cross-ref `crypto-and-compliance-spec.md`)
- `SnapshotTimeline.jsx` time-machine VISUAL design (stacked day cards, depth shrinking) — ZOSTAJE; tylko dodajemy nowy button "Restore to this point" per snapshot
- `i18n` istniejace klucze `recovery.wizard.*`, `recovery.thaw.*`, `recovery.orphan.*` — ZOSTAJA; dodajemy nowy namespace `recovery.mode.*`

### DOTYKAJ (modyfikacja dozwolona)

- `servers/SnapshotTimeline.jsx` — DODAJ button "Restore to this point" per snapshot (otwiera Recovery Mode confirmation)
- `servers/BackupsPage.jsx` — DODAJ RecoveryContext integration (action guards)
- `i18n/locales/pl.json` + `en.json` — DODAJ `recovery.mode.*` namespace
- `BufferMain.kt` — DODAJ routes `/recovery/*`
- `schema.sql` — DODAJ tabele `recovery_session`, `recovery_operation`, `recovery_dry_run`
- `agent/AgentMain.kt` — DODAJ SSE subscription dla `recovery_command`

### MOZESZ TWORZYC (nowe komponenty)

**properbackup-web:**
- `recovery/RecoveryContext.jsx` — React context provider (active recovery sessions per server)
- `recovery/RecoveryModeOverlay.jsx` — center-screen Time Machine overlay
- `recovery/RecoveryWarningBanner.jsx` — banner dla innych zakladek
- `recovery/RecoveryConfirmationModal.jsx` — DRY RUN preview + confirmation checkbox
- `recovery/RecoveryProgressCard.jsx` — progress bar + current operation
- `recovery/RecoveryCancelModal.jsx` — cancel confirmation
- `recovery/RecoveryHistoryPage.jsx` (optional, opcja Audit) — past recoveries lista
- `api/recoveryClient.js` — fetch wrappers dla `/recovery/*` endpointow
- `hooks/useRecoverySession.js` — SSE subscription hook

**properbackup-buffer:**
- `recovery/RecoverySessionStore.kt` — CRUD + state machine
- `recovery/RecoveryHandler.kt` — HTTP handler dla `/recovery/*`
- `recovery/RecoveryGuard.kt` — block write actions during recovery
- `recovery/DryRunComputer.kt` — orchestrate dry run (consult agent via SSE)
- `recovery/RecoveryAuditLog.kt` — append-only log
- `recovery/PreRecoverySnapshotCreator.kt` — trigger pre-recovery snapshot

**properbackup-shared:**
- `restore/RestoreOrchestrator.kt` — top-level orchestration (state machine, resume)
- `restore/SnapshotDiff.kt` — DRY RUN computation (snapshot vs local fs)
- `restore/FileRestorer.kt` — download + decrypt + atomic write
- `restore/FileDeleter.kt` — quarantine + TTL
- `restore/CriticalPathsGuard.kt` — whitelist (never delete)
- `restore/RestoreStateStore.kt` — local SQLite persistence (resume on crash)

**properbackup-docs:**
- `e2e-videos/recovery/` — videos test11-test18
- `.agents/skills/recovery-e2e-testing.md` — Playwright skill

---

## 4. State-of-the-world (rzeczywistosc dzisiaj — 2026-05-26)

### 4.1 Co dziala

- **Single-file recovery (download)**: `RecoveryWizard.jsx` w pelni funkcjonalny — user moze pobrac jeden plik ze snapshotu po podaniu hasla AES.
- **Time-Machine timeline UI**: `SnapshotTimeline.jsx` (605 linii) z animowanymi stacked day cards i depth shrinking. To bardzo dobry wizualny fundament dla Recovery Mode overlay.
- **OVH cold tier thaw progress**: `ThawProgress.jsx` mock mode 5s, prod mode 4h — gotowy do reuse.
- **Buffer integrity check post-seal**: `RestoreVerifier.kt` — kazdy snapshot weryfikowany ze da sie restore (test downloads + decrypts losowe chunki).

### 4.2 Czego brakuje

| Komponent | Status |
|-----------|--------|
| Recovery Session state machine | BRAK |
| Recovery Session DB tables | BRAK |
| `/recovery/*` HTTP endpoints | BRAK |
| Per-server WRITE lockdown w buffer | BRAK |
| Recovery Mode UI overlay (center-screen) | BRAK |
| RecoveryContext (React) | BRAK |
| Recovery warning banner | BRAK |
| Snapshot diff (DRY RUN) | BRAK |
| Pre-recovery snapshot creation | BRAK |
| Agent restore protocol | BRAK (`shared/restore/` package nie istnieje) |
| CriticalPathsGuard | BRAK |
| Quarantine system (`.quarantine/<recovery_id>/`) | BRAK |
| Resume-on-crash dla recovery | BRAK |
| Audit log entries dla recovery | BRAK |
| E2E tests recovery | BRAK |

### 4.3 Co ZOSTANIE jako-jest (zero refactor)

- Wszystkie `crypto/*` files w web i shared
- Wszystkie `recovery/RecoveryWizard.jsx`, `OrphanRecovery.jsx`, `ThawProgress.jsx`
- `SnapshotTimeline.jsx` VISUAL design (stacked cards, depth) — tylko dodatkowy button
- `RestoreVerifier.kt` (juz weryfikuje post-seal)

---

## 5. Domain Model

### 5.1 Recovery Session State Machine

```
                            ┌─────────────────────────────┐
                            │           IDLE              │
                            └──────────────┬──────────────┘
                                           │ user clicks "Restore to this point"
                                           ▼
                            ┌─────────────────────────────┐
                            │         REQUESTED           │  Buffer creates row + audit log
                            └──────────────┬──────────────┘
                                           │ agent receives command + starts DRY RUN
                                           ▼
                            ┌─────────────────────────────┐
                            │         PLANNING            │  Agent computes diff (snapshot vs local)
                            └──────────────┬──────────────┘
                                           │ DRY RUN ready
                                           ▼
                            ┌─────────────────────────────┐
                            │   AWAITING_USER_CONFIRM     │  UI shows DRY RUN preview + checkbox
                            └──────────────┬──────────────┘
                                           │ user confirms; if cold tier:
                                           ▼
                            ┌─────────────────────────────┐
                            │          THAWING            │  OVH cold tier thaw (~4h prod)
                            └──────────────┬──────────────┘
                                           │ thaw done
                                           ▼
                            ┌─────────────────────────────┐
                            │           READY             │  Buffer notifies agent: GO
                            └──────────────┬──────────────┘
                                           │ agent creates pre-recovery snapshot first!
                                           ▼
                            ┌─────────────────────────────┐
                            │      AGENT_RESTORING        │  Per-file: download/delete/skip + resume support
                            └──────────────┬──────────────┘
                                           │ all operations complete
                                           ▼
                            ┌─────────────────────────────┐
                            │         VERIFYING           │  Agent re-scans local fs vs snapshot
                            └──────────────┬──────────────┘
                                ┌─────────┴────────┐
                                │                  │
                          verify OK          verify FAILED
                                │                  │
                                ▼                  ▼
                    ┌──────────────┐    ┌──────────────────┐
                    │     DONE     │    │      FAILED      │
                    └──────────────┘    └──────────────────┘

         Branches (from any state):
              CANCEL → CANCELLED (with rollback if AGENT_RESTORING)
              ERROR  → FAILED
```

### 5.2 Database schema (delta)

```sql
-- nowe tabele

CREATE TABLE recovery_session (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id UUID NOT NULL REFERENCES server(id),
    user_id UUID NOT NULL REFERENCES user_account(id),
    target_snapshot_id UUID NOT NULL REFERENCES archive_snapshot(id),
    state VARCHAR(32) NOT NULL DEFAULT 'REQUESTED',
        -- enum: REQUESTED, PLANNING, AWAITING_USER_CONFIRM, THAWING, READY, AGENT_RESTORING, VERIFYING, DONE, FAILED, CANCELLED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ NULL,
    thaw_started_at TIMESTAMPTZ NULL,
    thaw_completed_at TIMESTAMPTZ NULL,
    agent_started_at TIMESTAMPTZ NULL,
    agent_completed_at TIMESTAMPTZ NULL,
    verifying_started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,
    cancelled_at TIMESTAMPTZ NULL,
    failed_at TIMESTAMPTZ NULL,
    pre_recovery_snapshot_id UUID NULL REFERENCES archive_snapshot(id),
    dry_run_files_to_restore INT NULL,
    dry_run_files_to_delete INT NULL,
    dry_run_files_unchanged INT NULL,
    dry_run_total_bytes BIGINT NULL,
    files_restored INT NOT NULL DEFAULT 0,
    files_deleted INT NOT NULL DEFAULT 0,
    bytes_transferred BIGINT NOT NULL DEFAULT 0,
    failure_reason TEXT NULL,
    cancellation_reason TEXT NULL,
    user_confirmed_via_ip INET NULL,
    user_confirmed_via_user_agent TEXT NULL,
    UNIQUE (server_id) WHERE state NOT IN ('DONE', 'FAILED', 'CANCELLED')  -- only 1 active per server
);

CREATE INDEX idx_recovery_session_user ON recovery_session(user_id);
CREATE INDEX idx_recovery_session_state ON recovery_session(state);
CREATE INDEX idx_recovery_session_server_active ON recovery_session(server_id) WHERE state NOT IN ('DONE', 'FAILED', 'CANCELLED');

CREATE TABLE recovery_operation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recovery_session_id UUID NOT NULL REFERENCES recovery_session(id),
    operation_type VARCHAR(16) NOT NULL,  -- RESTORE, DELETE, SKIP
    path_hash CHAR(64) NOT NULL,           -- sha256(path) — RODO pseudonymisation
    path TEXT NOT NULL,                     -- encrypted at rest TODO
    sha256_target CHAR(64) NULL,           -- sha256 z snapshotu (for RESTORE)
    sha256_local CHAR(64) NULL,            -- sha256 lokalny (for DELETE)
    size_bytes BIGINT NULL,
    state VARCHAR(16) NOT NULL DEFAULT 'pending',  -- pending, downloading, writing, verifying, done, failed
    started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,
    error TEXT NULL
);

CREATE INDEX idx_recovery_op_session ON recovery_operation(recovery_session_id);
CREATE INDEX idx_recovery_op_state ON recovery_operation(recovery_session_id, state);

CREATE TABLE recovery_dry_run (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recovery_session_id UUID NOT NULL REFERENCES recovery_session(id),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    files_to_restore_count INT NOT NULL,
    files_to_restore_size BIGINT NOT NULL,
    files_to_delete_count INT NOT NULL,
    files_to_delete_size BIGINT NOT NULL,
    files_unchanged_count INT NOT NULL,
    critical_files_protected_count INT NOT NULL,
    sample_files_to_restore JSONB NULL,    -- up to 20 sample paths for UI preview
    sample_files_to_delete JSONB NULL,     -- up to 20 sample paths for UI preview
    estimated_duration_seconds INT NULL
);

-- modyfikacje archive_snapshot

ALTER TABLE archive_snapshot ADD COLUMN snapshot_type VARCHAR(32) NOT NULL DEFAULT 'AUTO';
    -- enum: AUTO, MANUAL, TOMBSTONE, PRE_RECOVERY
ALTER TABLE archive_snapshot ADD COLUMN pre_recovery_session_id UUID NULL REFERENCES recovery_session(id);
    -- jezeli snapshot_type = PRE_RECOVERY, link do recovery_session

-- audit_log extensions

ALTER TABLE audit_log ADD COLUMN recovery_session_id UUID NULL REFERENCES recovery_session(id);
```

### 5.3 API contract (Buffer endpoints)

| Endpoint | Method | Auth | Behavior |
|----------|--------|------|----------|
| `/recovery/start` | POST | JWT user | Body: `{server_id, target_snapshot_id}` → Creates `recovery_session` in REQUESTED state. Sends SSE `recovery_command:dry_run` to agent. Returns `{session_id}`. **409 jezeli istnieje active recovery dla servera**. |
| `/recovery/:id` | GET | JWT user | Returns full session state + dry_run + progress. SSE alternative: `/recovery/:id/stream`. |
| `/recovery/:id/stream` | GET (SSE) | JWT user | Streams state transitions + per-file progress events. |
| `/recovery/:id/confirm` | POST | JWT user | Body: `{user_confirmation: true}` → Transitions from AWAITING_USER_CONFIRM → THAWING (or READY jezeli hot tier). |
| `/recovery/:id/cancel` | POST | JWT user | Cancels recovery (rollback if needed). Body: `{reason: "optional text"}`. |
| `/recovery/:id/audit` | GET | JWT user | Returns full audit log entries for this recovery (paginated). |
| `/recovery/history?server_id=` | GET | JWT user | List past recoveries (last 100). |
| `/agent/recovery/poll` | GET | JWT agent | Agent polls for pending recovery commands. Returns command queue. |
| `/agent/recovery/:id/dry_run_result` | POST | JWT agent | Agent reports dry run result to buffer. |
| `/agent/recovery/:id/progress` | POST | JWT agent | Per-100-operations batch progress upload. |
| `/agent/recovery/:id/complete` | POST | JWT agent | Reports final state (DONE / FAILED). |

### 5.4 Recovery Mode UI States (Frontend)

```
ServersPage:
  ├─ ServerCard (no recovery active)
  │    actions: [Backup Now] [Settings] [Restore]
  │
  ├─ ServerCard (RECOVERY ACTIVE on this server)
  │    actions: ALL DISABLED + small "Recovery in progress" badge
  │    click → opens server tab w Recovery Mode
  │
  └─ ServerCard (RECOVERY ACTIVE on OTHER server)
       actions: enabled
       small banner "Recovery in progress on Server X"

ServerDetail (target_server in recovery):
  ┌──────────────────────────────────────────────────────────┐
  │ [Files] [Timeline] [Monitoring] [Config]    ☆ disabled  │  ← tabs enabled, [Restore] [Backup] disabled
  ├──────────────────────────────────────────────────────────┤
  │                                                          │
  │  (background: dim 50% opacity z TimelineView lub        │
  │   FilesView z snapshotu target_snapshot — read-only)    │
  │                                                          │
  │  ┌──────────────────────────────────────────────────┐   │
  │  │                                                  │   │
  │  │   ⚡ RECOVERY MODE ACTIVE                        │   │
  │  │                                                  │   │
  │  │   Restoring server "My VPS" to:                 │   │
  │  │   📅 2026-05-24 14:32 (47 MB snapshot)          │   │
  │  │                                                  │   │
  │  │   Phase: Restoring files (3 / 8)                │   │
  │  │   ████████████░░░░░░░░░░  62%                  │   │
  │  │                                                  │   │
  │  │   Currently: /home/user/docs/report.pdf         │   │
  │  │   ETA: 12 min                                    │   │
  │  │                                                  │   │
  │  │   [ Cancel Recovery ]   [ Hide ]                │   │
  │  │                                                  │   │
  │  └──────────────────────────────────────────────────┘   │
  │                                                          │
  └──────────────────────────────────────────────────────────┘

ServerDetail (other server, recovery on OTHER server):
  ┌──────────────────────────────────────────────────────────┐
  │ ⚠ Recovery in progress on "My VPS" — started 14:32, ETA 18m │
  │ [Files] [Timeline] [Monitoring] [Config] [Backup] [Restore]│   ← all actions enabled
  ├──────────────────────────────────────────────────────────┤
  │                                                          │
  │  (normal server view)                                    │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

### 5.5 Agent restore protocol (high-level flow)

```
1. Agent boots → AgentMain.start()
2. Agent subscribes SSE: GET /sse/agent/<server_id>/stream
3. Agent polls /agent/recovery/poll every 30s as fallback
4. Buffer sends recovery_command:dry_run via SSE
5. Agent:
   a. Fetches snapshot manifest from buffer
   b. Locally scans fs (uses DifferentialScanner.kt, same 4MB chunks)
   c. Computes diff (snapshot.paths vs local.paths)
   d. POST /agent/recovery/<id>/dry_run_result {restored:N, deleted:M, ...}
6. Buffer transitions REQUESTED → PLANNING → AWAITING_USER_CONFIRM
7. UI shows DRY RUN preview
8. User confirms → buffer transitions AWAITING_USER_CONFIRM → THAWING (cold tier) | READY (hot tier)
9. Buffer triggers OVH cold tier thaw if needed (mocked: instant in dev)
10. Buffer sends recovery_command:execute via SSE
11. Agent:
    a. Creates pre-recovery snapshot of CURRENT state (uses normal backup loop)
    b. POST /agent/snapshots PUT {snapshot_type:'PRE_RECOVERY', pre_recovery_session_id:X}
    c. For each recovery_operation in order:
       - DELETE op: move file to .quarantine/<recovery_id>/<path_hash>
       - RESTORE op: download chunk from buffer (decrypt streaming), atomic write
       - SKIP op: log and continue
    d. Every 100 ops, POST /agent/recovery/<id>/progress {files_done:N}
12. After all ops:
    a. Agent re-scans local fs
    b. Computes diff vs target_snapshot
    c. POST /agent/recovery/<id>/complete {success: true, verification:OK}
13. Buffer transitions VERIFYING → DONE
14. UI shows success state
15. Pre-recovery snapshot stays in archive_snapshot with 30-day grace period (no quota counted)
16. .quarantine/<recovery_id>/ scheduled for cleanup in 30 days
```

---

## 6. Pillars of Resilience (architectural defenses)

### 6.1 Race conditions

**Risk:** Two browser tabs init recovery on same server simultaneously → DB has 2 sessions in REQUESTED state.
**Defense:** UNIQUE constraint `recovery_session(server_id) WHERE state NOT IN (DONE, FAILED, CANCELLED)`. Second insert fails with 23505 → API returns 409 z "Recovery already in progress".

### 6.2 Agent crash mid-restore

**Risk:** Agent kill -9 in middle of restoring 1000 files.
**Defense:** Each operation has own state (`pending → downloading → writing → verifying → done`). On agent restart, reads `recovery_operations WHERE state != 'done'` and resumes.

### 6.3 Buffer crash mid-recovery

**Risk:** Buffer kill -9 podczas recovery session.
**Defense:** Recovery session state persisted in Postgres (durable). On buffer restart, all active sessions resume from last persisted state. Agent polls periodically (30s) and discovers buffer is back. SSE auto-reconnect po stronie UI.

### 6.4 User closes browser

**Risk:** User klika "Start Recovery", potem zamyka browser.
**Defense:** Session persisted server-side. User can return any time and see current progress. SSE auto-reconnect na nowym tab. Email notification on completion (cross-ref `web-panel-master-spec.md` Notifications).

### 6.5 OVH cold tier thaw timeout

**Risk:** OVH thaw never completes (7+ days).
**Defense:** Buffer monitors thaw_started_at. After 8h (configurable) → alert. After 7 days → auto-cancel z reason "OVH thaw timeout, please retry".

### 6.6 Pre-recovery snapshot creation fails

**Risk:** Agent cannot create pre-recovery snapshot (disk full, buffer offline).
**Defense:** AGENT_RESTORING fails-safe before starting per-file ops. Recovery transitions to FAILED with reason "Pre-recovery snapshot failed". User informed; manual retry possible.

### 6.7 Path traversal attack

**Risk:** Malicious snapshot contains symlinks pointing outside backup root (`../../../etc/passwd`).
**Defense:** CriticalPathsGuard validates every path against allowlist (user backup roots only). Path traversal attempts → log + skip.

### 6.8 Concurrent recovery on different servers

**Risk:** User starts recovery on Server A, then immediately on Server B. Two agents running restore simultaneously.
**Defense:** Both allowed. Each agent has own state machine. UI shows 2 active recoveries in account settings. Buffer can handle multiple sessions concurrently.

### 6.9 User cancels during VERIFYING

**Risk:** User cancels after all files restored but before verification complete. State unclear.
**Defense:** VERIFYING state ignores cancel until verification complete. Then user must explicitly choose: (a) accept current state DONE, (b) rollback to pre-recovery.

### 6.10 Pre-recovery snapshot deleted accidentally

**Risk:** Pre-recovery snapshot deleted (cleanup cron, user manual) before recovery DONE.
**Defense:** Cannot delete pre_recovery_session_id != NULL snapshots until recovery_session.state IN (DONE confirmed, FAILED, CANCELLED). DB constraint trigger on archive_snapshot DELETE.

---

## 7. Section A — Frontend Recovery Mode UI (PR plan for `properbackup-web`)

### 7.1 Files to add

```
src/recovery/
  RecoveryContext.jsx          # NEW — React context: { activeRecoveries: Map<serverId, session> }
  RecoveryModeOverlay.jsx      # NEW — center-screen Time Machine overlay
  RecoveryWarningBanner.jsx    # NEW — banner dla innych zakladek + ServersPage
  RecoveryConfirmationModal.jsx # NEW — DRY RUN preview + checkbox
  RecoveryProgressCard.jsx     # NEW — used in overlay + standalone
  RecoveryCancelModal.jsx      # NEW — cancel confirmation
  RecoveryHistoryPage.jsx      # NEW (optional, opcja Audit)

src/api/
  recoveryClient.js            # NEW — fetch wrappers (start, status, confirm, cancel, history)

src/hooks/
  useRecoverySession.js        # NEW — SSE subscription + state polling
  useRecoveryContext.js        # NEW — convenience hook

src/i18n/locales/
  pl.json                      # MODIFY — dodac recovery.mode.* keys
  en.json                      # MODIFY — dodac recovery.mode.* keys

src/servers/
  SnapshotTimeline.jsx         # MODIFY — dodac "Restore to this point" button per day card
  BackupsPage.jsx              # MODIFY — RecoveryContext.Provider on top; warning banner if other-server recovery
  ServerCard.jsx               # MODIFY — disable actions if recovery active on this server
  ServersPage.jsx              # MODIFY — warning banner; ServerCard updated

src/App.jsx                    # MODIFY — wrap z RecoveryContext.Provider
```

### 7.2 RecoveryContext API

```javascript
// src/recovery/RecoveryContext.jsx
import { createContext, useContext, useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthContext.jsx';
import { fetchActiveRecoveries } from '../api/recoveryClient.js';

const RecoveryContext = createContext({
  activeRecoveries: new Map(),
  startRecovery: () => {},
  cancelRecovery: () => {},
  isRecoveryActive: (serverId) => false,
  recoveryForServer: (serverId) => null,
});

export function RecoveryProvider({ children }) {
  const { token } = useAuth();
  const [activeRecoveries, setActiveRecoveries] = useState(new Map());

  // Poll active recoveries every 30s + SSE for real-time
  useEffect(() => {
    const interval = setInterval(async () => {
      const sessions = await fetchActiveRecoveries(token);
      const map = new Map(sessions.map(s => [s.server_id, s]));
      setActiveRecoveries(map);
    }, 30_000);
    // Also subscribe to global SSE for recovery events
    return () => clearInterval(interval);
  }, [token]);

  const isRecoveryActive = (serverId) => activeRecoveries.has(serverId);
  const recoveryForServer = (serverId) => activeRecoveries.get(serverId);

  return (
    <RecoveryContext.Provider value={{
      activeRecoveries,
      isRecoveryActive,
      recoveryForServer,
      // ...
    }}>
      {children}
    </RecoveryContext.Provider>
  );
}

export const useRecoveryContext = () => useContext(RecoveryContext);
```

### 7.3 RecoveryModeOverlay component skeleton

```jsx
// src/recovery/RecoveryModeOverlay.jsx
import { useRecoveryContext } from './RecoveryContext.jsx';
import { useI18n } from '../i18n/I18nContext.jsx';
import RecoveryProgressCard from './RecoveryProgressCard.jsx';
import RecoveryCancelModal from './RecoveryCancelModal.jsx';

export default function RecoveryModeOverlay({ serverId }) {
  const { t } = useI18n();
  const { recoveryForServer } = useRecoveryContext();
  const session = recoveryForServer(serverId);
  const [showCancel, setShowCancel] = useState(false);
  const [minimized, setMinimized] = useState(false);

  if (!session) return null;

  return (
    <>
      {/* Backdrop: dim background but allow tab clicks (pointer-events: none on backdrop) */}
      <div className="fixed inset-0 bg-black/40 z-40 pointer-events-none" />

      {/* Center panel: Time Machine style */}
      <div className={`fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-50 ${minimized ? 'w-64' : 'w-[600px] max-w-[90vw]'}`}>
        <div className="bg-panel rounded-xl2 shadow-modal border-2 border-accent p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <RecoveryIcon className="w-6 h-6 text-accent" />
              <h2 className="text-text1 font-bold text-lg">{t('recovery.mode.title')}</h2>
            </div>
            <button onClick={() => setMinimized(!minimized)} className="btn-ghost text-xs">
              {minimized ? t('recovery.mode.expand') : t('recovery.mode.minimize')}
            </button>
          </div>

          {!minimized && (
            <RecoveryProgressCard session={session} />
          )}

          <div className="flex gap-3 mt-4">
            <button onClick={() => setShowCancel(true)} className="btn-danger">
              {t('recovery.mode.cancel')}
            </button>
            <button onClick={() => setMinimized(true)} className="btn-ghost">
              {t('recovery.mode.hide')}
            </button>
          </div>
        </div>
      </div>

      {showCancel && (
        <RecoveryCancelModal
          session={session}
          onClose={() => setShowCancel(false)}
        />
      )}
    </>
  );
}
```

### 7.4 i18n keys

```json
// src/i18n/locales/pl.json (delta)
{
  "recovery": {
    "mode": {
      "title": "Tryb przywracania (Recovery Mode)",
      "subtitle": "Przywracanie serwera \"{{server}}\" do stanu z {{date}}",
      "phasePlanning": "Przygotowywanie planu...",
      "phaseAwaitingConfirm": "Oczekiwanie na potwierdzenie",
      "phaseThawing": "Rozmrazanie z chlodnego archiwum (OVH)",
      "phaseReady": "Gotowe do startu",
      "phaseRestoring": "Przywracanie plikow ({{done}}/{{total}})",
      "phaseVerifying": "Weryfikacja integralnosci",
      "phaseDone": "Zakonczone pomyslnie",
      "phaseFailed": "Niepowodzenie",
      "phaseCancelled": "Anulowane",
      "currentFile": "Aktualnie: {{path}}",
      "eta": "ETA: {{time}}",
      "progressPercent": "{{percent}}% ukonczone",
      "cancel": "Anuluj przywracanie",
      "cancelConfirmTitle": "Anulowac przywracanie?",
      "cancelConfirmBody": "Anulowanie spowoduje przywrocenie systemu do stanu sprzed startu (pre-recovery snapshot). Ta operacja nie jest natychmiastowa.",
      "cancelConfirmAccept": "Tak, anuluj",
      "cancelConfirmReject": "Kontynuuj przywracanie",
      "minimize": "Ukryj",
      "expand": "Rozwin",
      "hide": "Schowaj (kontynuuje w tle)",
      "warningBannerOtherTab": "Trwa przywracanie na serwerze \"{{server}}\" (rozpoczeto {{startTime}}, szacowane zakonczenie {{eta}})",
      "warningBannerOtherTabCta": "Przejdz do serwera",
      "confirmModalTitle": "Potwierdz przywracanie",
      "confirmModalIntro": "Sprawdz dokladnie co zostanie zmienione po stronie Twojego serwera:",
      "confirmModalFilesToRestore": "Plikow do przywrocenia: {{count}} ({{size}})",
      "confirmModalFilesToDelete": "Plikow do usuniecia: {{count}} ({{size}})",
      "confirmModalFilesUnchanged": "Plikow bez zmian: {{count}}",
      "confirmModalCriticalProtected": "Plikow systemowych chronionych: {{count}}",
      "confirmModalSamplesRestore": "Przyklady plikow do przywrocenia:",
      "confirmModalSamplesDelete": "Przyklady plikow do usuniecia:",
      "confirmModalEta": "Szacowany czas trwania: {{time}}",
      "confirmModalAcknowledge": "Rozumiem, ze moje obecne pliki na serwerze zostana zastapione lub usuniete. Przed startem zostanie utworzony 'pre-recovery snapshot' do ktorego mozna wrocic.",
      "confirmModalAccept": "Rozpocznij przywracanie",
      "confirmModalReject": "Anuluj",
      "warningRecoveryInProgressOnThisServer": "Recovery Mode aktywny na tym serwerze. Akcje pisarskie sa zablokowane.",
      "successTitle": "Przywracanie zakonczone pomyslnie",
      "successBody": "Przywrocono {{filesRestored}} plikow, usunieto {{filesDeleted}}. Pre-recovery snapshot dostepny przez 30 dni.",
      "failedTitle": "Przywracanie nieudane",
      "failedBody": "Powod: {{reason}}. Twoj system zostal automatycznie przywrocony do stanu sprzed recovery.",
      "actionDisabledTooltip": "Recovery in progress; akcje pisarskie zablokowane"
    }
  }
}
```

### 7.5 Action guards w istniejacych komponentach

```jsx
// src/servers/ServerCard.jsx (MODIFY)
const { isRecoveryActive } = useRecoveryContext();
const recoveryActive = isRecoveryActive(server.id);

<button
  className="btn-primary"
  onClick={handleBackupNow}
  disabled={recoveryActive}
  title={recoveryActive ? t('recovery.mode.actionDisabledTooltip') : ''}
>
  Backup Now
</button>
```

### 7.6 DoD dla PR-a frontend

- [ ] All NEW files compile + lint clean (eslint, prettier)
- [ ] All MODIFY files: existing tests pass (jest, vitest)
- [ ] i18n: PL + EN keys complete (no missing keys in production build)
- [ ] RecoveryContext: SSE auto-reconnect on disconnect
- [ ] RecoveryModeOverlay: center-screen positioning correct on mobile (320px) + desktop (1920px)
- [ ] Warning banner: shows on ServersPage + on other-server tabs
- [ ] Action guards: ALL write actions disabled when recovery active (Backup Now, Edit Config, Delete Snapshot, Start Restore, etc.)
- [ ] Tab navigation: works even during recovery
- [ ] Pre-existing recovery (server-side) on page load: UI rehydrates correctly (no flicker)
- [ ] Storybook/manual: 5 screenshots covering states (REQUESTED, AGENT_RESTORING, DONE, FAILED, CANCELLED)
- [ ] PR description includes screenshots

---

## 8. Section B — Buffer Recovery Session API (PR plan for `properbackup-buffer`)

### 8.1 Files to add

```
src/main/kotlin/pl/danielniemiec/properbackup/buffer/recovery/
  RecoverySessionStore.kt         # CRUD + state machine
  RecoveryHandler.kt              # HTTP handlers /recovery/*
  RecoveryGuard.kt                # block write actions when recovery active
  DryRunComputer.kt               # orchestrate dry run with agent
  RecoveryAuditLog.kt             # append-only log writer
  PreRecoverySnapshotCreator.kt   # trigger pre-recovery snapshot
  RecoveryStateMachine.kt         # state transitions + validation
  RecoveryEventBus.kt             # SSE event helpers

src/main/resources/db/migration/
  V20260601__add_recovery_tables.sql   # migration script (sekcja 5.2 schema)

src/test/kotlin/pl/danielniemiec/properbackup/buffer/recovery/
  RecoverySessionStoreTest.kt
  RecoveryHandlerTest.kt
  RecoveryGuardTest.kt
  RecoveryStateMachineTest.kt
  PreRecoverySnapshotCreatorTest.kt
  DryRunComputerTest.kt
```

### 8.2 RecoverySessionStore signature

```kotlin
class RecoverySessionStore(private val db: Database) {
    fun create(
        serverId: UUID,
        userId: UUID,
        targetSnapshotId: UUID,
    ): RecoverySession  // 409 if active recovery already exists

    fun byId(id: UUID): RecoverySession?

    fun activeForServer(serverId: UUID): RecoverySession?

    fun activeForUser(userId: UUID): List<RecoverySession>

    fun transition(
        id: UUID,
        from: RecoveryState,
        to: RecoveryState,
        meta: Map<String, Any?> = emptyMap(),
    ): RecoverySession  // throws StateException if from doesn't match current

    fun setDryRun(
        id: UUID,
        filesToRestore: Int,
        filesToDelete: Int,
        filesUnchanged: Int,
        totalBytes: Long,
        sampleRestore: List<String>,
        sampleDelete: List<String>,
        criticalProtected: Int,
        estimatedDurationSec: Int?,
    )

    fun setPreRecoverySnapshot(id: UUID, snapshotId: UUID)

    fun incrementProgress(id: UUID, filesRestoredDelta: Int, filesDeletedDelta: Int, bytesDelta: Long)

    fun markFailed(id: UUID, reason: String, atPhase: String)

    fun markCancelled(id: UUID, reason: String, atPhase: String)

    fun markDone(id: UUID)
}
```

### 8.3 RecoveryGuard: block write actions

```kotlin
class RecoveryGuard(private val store: RecoverySessionStore) {
    fun ensureNoActiveRecovery(serverId: UUID, action: String) {
        store.activeForServer(serverId)?.let {
            throw RecoveryActiveException(
                serverId = serverId,
                sessionId = it.id,
                blockedAction = action,
            )
        }
    }
}

// Used in:
// - BackupHandler.startBackup() → guard.ensureNoActiveRecovery(serverId, "start_backup")
// - SnapshotHandler.deleteSnapshot() → guard.ensureNoActiveRecovery(serverId, "delete_snapshot")
// - RestoreFileHandler (single file restore) → guard.ensureNoActiveRecovery(serverId, "single_file_restore")
// - ConfigHandler.update() → guard.ensureNoActiveRecovery(serverId, "update_config")
```

### 8.4 RecoveryStateMachine: legal transitions

```kotlin
enum class RecoveryState {
    REQUESTED,
    PLANNING,
    AWAITING_USER_CONFIRM,
    THAWING,
    READY,
    AGENT_RESTORING,
    VERIFYING,
    DONE,
    FAILED,
    CANCELLED,
}

object RecoveryStateMachine {
    private val legalTransitions: Map<RecoveryState, Set<RecoveryState>> = mapOf(
        REQUESTED to setOf(PLANNING, CANCELLED, FAILED),
        PLANNING to setOf(AWAITING_USER_CONFIRM, FAILED, CANCELLED),
        AWAITING_USER_CONFIRM to setOf(THAWING, READY, CANCELLED, FAILED),
        THAWING to setOf(READY, CANCELLED, FAILED),
        READY to setOf(AGENT_RESTORING, CANCELLED, FAILED),
        AGENT_RESTORING to setOf(VERIFYING, FAILED, CANCELLED),
        VERIFYING to setOf(DONE, FAILED),
        // terminal states
        DONE to emptySet(),
        FAILED to emptySet(),
        CANCELLED to emptySet(),
    )

    fun isLegal(from: RecoveryState, to: RecoveryState): Boolean =
        legalTransitions[from]?.contains(to) == true

    fun ensureLegal(from: RecoveryState, to: RecoveryState) {
        require(isLegal(from, to)) { "Illegal recovery state transition: $from → $to" }
    }
}
```

### 8.5 DoD dla PR-a buffer

- [ ] DB migration runs cleanly on existing dev DB
- [ ] All new HTTP endpoints return correct status codes (200, 201, 401, 403, 404, 409, 503)
- [ ] State machine: all 28 legal transitions tested + 60+ illegal transitions rejected
- [ ] Guard: every write endpoint protected (lint check or test that asserts guard usage)
- [ ] Audit log: every state transition logs entry
- [ ] Pre-recovery snapshot creation: works on mock storage (Testcontainers PG + mock OVH)
- [ ] Concurrent recovery test: 2 simultaneous POST /recovery/start on same server → 1 success, 1x 409
- [ ] SSE events emitted on every transition (test via SseEventBus mock)
- [ ] Recovery during buffer crash: full recovery resumable on restart
- [ ] All endpoints behind JWT auth (cross-ref `agent-vps-master-spec.md` HR-6)
- [ ] 100% unit test coverage for RecoveryStateMachine + RecoverySessionStore
- [ ] Integration test: full flow REQUESTED → DONE in Testcontainers (without real agent — uses RecoveryHandlerStub)

---

## 9. Section C — Agent Restore Protocol (PR plan for `properbackup-agent` + `properbackup-shared`)

### 9.1 Files to add (in `properbackup-shared/`)

```
properbackup-shared/src/commonMain/kotlin/.../shared/restore/
  RestoreOrchestrator.kt          # top-level orchestration
  SnapshotDiff.kt                  # DRY RUN computation
  FileRestorer.kt                  # download + decrypt + atomic write
  FileDeleter.kt                   # quarantine + TTL
  CriticalPathsGuard.kt            # whitelist
  RestoreStateStore.kt             # local SQLite persistence
  RestoreCommandPoller.kt          # poll buffer for commands
  RestoreProgressReporter.kt       # batch progress upload to buffer
  RestoreException.kt              # error types
```

### 9.2 RestoreOrchestrator skeleton

```kotlin
package pl.danielniemiec.properbackup.shared.restore

class RestoreOrchestrator(
    private val host: HostAdapter,
    private val bufferClient: BufferClient,
    private val sessionId: UUID,
    private val targetSnapshotId: UUID,
    private val stateStore: RestoreStateStore,
    private val criticalPaths: CriticalPathsGuard,
    private val crypto: ProperCrypto,
) {
    suspend fun start() {
        try {
            // Phase 1: DRY RUN
            val diff = computeDryRun()
            bufferClient.reportDryRun(sessionId, diff)

            // Wait for buffer confirmation (READY state)
            waitForReady()

            // Phase 2: PRE-RECOVERY SNAPSHOT
            val preRecoverySnapshotId = createPreRecoverySnapshot()
            bufferClient.setPreRecoverySnapshot(sessionId, preRecoverySnapshotId)

            // Phase 3: EXECUTE OPERATIONS
            for (op in diff.operations) {
                if (criticalPaths.isProtected(op.path)) {
                    logSkip(op, "critical")
                    continue
                }
                executeOperation(op)
                reportProgressIfBatched()
            }

            // Phase 4: VERIFY
            val verify = verifyFinalState()
            bufferClient.reportComplete(sessionId, success = verify.ok, verify = verify)
        } catch (e: CancellationException) {
            rollback()
            bufferClient.markCancelled(sessionId, e.message ?: "cancelled")
        } catch (e: Exception) {
            host.log(LogLevel.ERROR, "Restore failed", e)
            attemptRollback()
            bufferClient.markFailed(sessionId, e.message ?: "unknown")
        }
    }

    private suspend fun computeDryRun(): SnapshotDiff { /* ... */ }
    private suspend fun executeOperation(op: RecoveryOperation) { /* ... */ }
    private suspend fun rollback() { /* ... */ }
    private suspend fun verifyFinalState(): VerifyResult { /* ... */ }
}
```

### 9.3 SnapshotDiff algorithm

```kotlin
class SnapshotDiff(
    private val host: HostAdapter,
    private val scanner: DifferentialScanner,
) {
    fun compute(snapshot: SnapshotManifest, backupRoots: List<String>): DiffResult {
        // 1. Snapshot files map: path → sha256
        val snapshotMap = snapshot.files.associateBy { it.path }

        // 2. Local files map (uses existing DifferentialScanner)
        val localMap = scanner.scan(backupRoots).associateBy { it.path }

        val toRestore = mutableListOf<RecoveryOperation>()
        val toDelete = mutableListOf<RecoveryOperation>()
        val unchanged = mutableListOf<RecoveryOperation>()

        // Files in snapshot but not local OR with different sha256 → RESTORE
        for ((path, snapFile) in snapshotMap) {
            val local = localMap[path]
            if (local == null || local.sha256 != snapFile.sha256) {
                toRestore.add(RecoveryOperation(
                    type = OperationType.RESTORE,
                    path = path,
                    sha256Target = snapFile.sha256,
                    sha256Local = local?.sha256,
                    size = snapFile.size,
                ))
            } else {
                unchanged.add(RecoveryOperation(type = OperationType.SKIP, path = path, sha256Target = snapFile.sha256, sha256Local = local.sha256, size = local.size))
            }
        }

        // Files local but not in snapshot → DELETE
        for ((path, localFile) in localMap) {
            if (!snapshotMap.containsKey(path)) {
                toDelete.add(RecoveryOperation(
                    type = OperationType.DELETE,
                    path = path,
                    sha256Local = localFile.sha256,
                    size = localFile.size,
                ))
            }
        }

        return DiffResult(
            toRestore = toRestore,
            toDelete = toDelete,
            unchanged = unchanged,
            totalBytes = toRestore.sumOf { it.size },
        )
    }
}
```

### 9.4 FileRestorer (atomic + resumable)

```kotlin
class FileRestorer(
    private val host: HostAdapter,
    private val bufferClient: BufferClient,
    private val crypto: ProperCrypto,
    private val stateStore: RestoreStateStore,
) {
    suspend fun restore(op: RecoveryOperation) {
        val fs = host.fs
        val tmpPath = "${op.path}.recovery-${UUID.randomUUID()}.tmp"

        stateStore.markState(op.id, "downloading")
        val encryptedBytes = bufferClient.downloadChunk(op.sha256Target!!)

        stateStore.markState(op.id, "writing")
        val plaintext = crypto.decrypt(encryptedBytes)
        fs.writeStream(tmpPath).use { it.write(plaintext) }

        stateStore.markState(op.id, "verifying")
        val written = fs.read(tmpPath)
        val sha = SHA256.hash(written)
        if (sha != op.sha256Target) {
            fs.delete(tmpPath)
            throw RestoreException.VerifyFailed(op.path, expected = op.sha256Target!!, actual = sha)
        }

        // Atomic rename
        fs.rename(tmpPath, op.path)
        stateStore.markState(op.id, "done")
    }
}
```

### 9.5 FileDeleter (quarantine)

```kotlin
class FileDeleter(
    private val host: HostAdapter,
    private val stateStore: RestoreStateStore,
    private val recoverySessionId: UUID,
) {
    private val quarantineDir = "${host.dataDir()}/quarantine/${recoverySessionId}"

    suspend fun delete(op: RecoveryOperation) {
        val fs = host.fs
        fs.mkdirs(quarantineDir)
        val pathHash = SHA256.hash(op.path.toByteArray()).substring(0, 32)
        val quarantinePath = "$quarantineDir/$pathHash"

        stateStore.markState(op.id, "downloading")  // misnomer: moving
        fs.rename(op.path, quarantinePath)

        stateStore.markState(op.id, "done")

        // metadata: store original path for potential rollback
        fs.write("$quarantinePath.meta", "{\"originalPath\":\"${op.path}\"}".toByteArray())
    }
}
```

### 9.6 CriticalPathsGuard whitelist

```kotlin
class CriticalPathsGuard(
    private val host: HostAdapter,
) {
    private val staticWhitelist = listOf(
        // Per-platform critical paths
        "/proc/", "/sys/", "/dev/", "/run/",       // POSIX
        "C:\\Windows\\System32\\", "C:\\Windows\\WinSxS\\",  // Windows
        "/System/", "/private/var/db/",            // macOS
    )

    fun isProtected(path: String): Boolean {
        val normalized = host.fs.normalize(path)

        // 1. Static whitelist
        if (staticWhitelist.any { normalized.startsWith(it) }) return true

        // 2. Agent config + state (NEVER delete)
        if (normalized.startsWith(host.configDir())) return true
        if (normalized.startsWith(host.dataDir())) return true

        // 3. Symlinks pointing outside backup roots — DEFENSIVE
        if (host.fs.isSymlink(path)) {
            val target = host.fs.symlinkTarget(path)
            if (host.defaultBackupRoots().none { target.startsWith(it) }) return true
        }

        return false
    }
}
```

### 9.7 DoD dla PR-a agent + shared

- [ ] `properbackup-shared/src/jvmTest/.../restore/` ma 100% coverage critical paths
- [ ] DRY RUN test: 1000 files (300 restore, 50 delete, 650 unchanged) → wynik matches expected
- [ ] FileRestorer crash test: kill -9 mid-write → restart resumes correctly
- [ ] FileDeleter quarantine test: deleted files recoverable from quarantine
- [ ] CriticalPathsGuard test: 100+ adversarial paths (../../../etc/passwd, symlinks, etc.)
- [ ] Cross-host parity test (SHC-D z `shared-core-architecture-spec.md`): VPS + MC mock identical restore result
- [ ] Rollback test: cancel during AGENT_RESTORING → pre-recovery snapshot restored correctly
- [ ] Pre-recovery snapshot creation: uses existing backup loop (no duplication)
- [ ] Progress reporting: every 100 operations or 30s, whichever first
- [ ] Resume on agent restart: state persisted in RestoreStateStore (SQLite)
- [ ] Idempotent file write: re-running same op on already-restored file is no-op
- [ ] Audit log: every operation reported to buffer
- [ ] Documentation: ZADANIE-AGENT.md w `properbackup-agent` z step-by-step instructions

---

## 10. Section D — E2E Playwright Tests + Videos (PR plan for `properbackup-docs` + `properbackup-web/tests/e2e/`)

### 10.1 Files to add

```
properbackup-web/tests/e2e/
  group-i-recovery.spec.js        # NEW — 8 tests
  helpers/
    recoveryHelper.js              # NEW — start recovery, wait for state, etc.
    mockAgentRecovery.js           # NEW — mock agent that simulates restore

properbackup-docs/
  e2e-videos/
    recovery/                      # NEW DIR
      test11-recovery-start.webm
      test12-dry-run-preview.webm
      test13-confirm-and-restore.webm
      test14-other-server-banner.webm
      test15-cancel-during-restoring.webm
      test16-cold-tier-thaw.webm
      test17-concurrent-recovery-409.webm
      test18-pre-recovery-rollback.webm
    README.md                       # MODIFY — dodac sekcje 11-18 do tabeli
  .agents/skills/
    recovery-e2e-testing.md        # NEW — Playwright skill
```

### 10.2 Test list

| # | Test name | Scenariusz | Czas |
|---|-----------|-----------|------|
| 11 | `test11-recovery-start` | User w SnapshotTimeline klika "Restore to this point" → RecoveryConfirmationModal otwiera sie z loadingiem (PLANNING state) | ~10s |
| 12 | `test12-dry-run-preview` | Po PLANNING → AWAITING_USER_CONFIRM, modal pokazuje DRY RUN (3421 files restore, 89 delete, etc.) + sample paths + checkbox disabled przed acknowledge | ~15s |
| 13 | `test13-confirm-and-restore` | User klika acknowledge checkbox → "Start Recovery" → modal closes → RecoveryModeOverlay center-screen → progress bar updates → DONE notification | ~60s |
| 14 | `test14-other-server-banner` | W trakcie recovery na Server A, user otwiera Server B tab → widzi warning banner "Recovery in progress on Server A" + wszystkie akcje na Server B dzialaja normalnie | ~20s |
| 15 | `test15-cancel-during-restoring` | Recovery w stanie AGENT_RESTORING, user klika Cancel → confirmation modal → "Tak, anuluj" → state transitions to CANCELLED → pre-recovery snapshot zostaje active | ~30s |
| 16 | `test16-cold-tier-thaw` | Recovery target snapshot na cold tier → po confirm, state THAWING → ThawProgress visible → po thaw, agent restart → DONE | ~45s |
| 17 | `test17-concurrent-recovery-409` | Server A w recovery, user otwiera drugą zakladke i klika Restore na tym samym Server A → API zwraca 409 → UI pokazuje toast "Recovery already in progress" | ~10s |
| 18 | `test18-pre-recovery-rollback` | Po DONE recovery, user widzi w SnapshotTimeline pre-recovery snapshot z badge "PRE-RECOVERY (30d grace)" → moze kliknac "Restore to here" zeby cofnac recovery | ~40s |

### 10.3 Test infrastructure (helpers)

```javascript
// tests/e2e/helpers/recoveryHelper.js
export async function startRecoveryViaUI(page, serverId, snapshotId) {
  await page.goto(`/panel/servers/${serverId}/timeline`);
  await page.click(`[data-testid="snapshot-${snapshotId}"] [data-testid="restore-to-here-btn"]`);
  await page.waitForSelector('[data-testid="recovery-confirmation-modal"]');
}

export async function confirmRecoveryWithDryRun(page) {
  await page.waitForSelector('[data-testid="dry-run-summary"]', { timeout: 30_000 });
  await page.check('[data-testid="recovery-acknowledge-checkbox"]');
  await page.click('[data-testid="recovery-start-btn"]');
}

export async function waitForRecoveryState(page, expectedState, timeoutMs = 60_000) {
  await page.waitForFunction(
    (state) => document.querySelector('[data-recovery-state]')?.getAttribute('data-recovery-state') === state,
    expectedState,
    { timeout: timeoutMs }
  );
}

export async function cancelRecovery(page) {
  await page.click('[data-testid="recovery-cancel-btn"]');
  await page.click('[data-testid="recovery-cancel-confirm-yes"]');
}
```

### 10.4 Test environment

- Same setup as existing tests A-H (live test server `properbackup-test-server.softify.com.pl`)
- New env var `PROPERBACKUP_RECOVERY_TEST_MODE=true` — buffer uses MockAgent (simulates restore in <30s instead of real agent)
- Mock agent: implementuje `recovery_command:dry_run` i `recovery_command:execute` via direct DB inserts simulating agent reports

### 10.5 Videos

- Playwright config: `video: 'on'` for these tests
- Output: `playwright-report/` → automated upload do `docs/e2e-videos/recovery/`
- Naming: `testNN-<short-description>.webm`

### 10.6 Skill

```markdown
# .agents/skills/recovery-e2e-testing.md

## When to use this skill
When testing Recovery Mode end-to-end in properbackup-web.

## How to run
\`\`\`bash
cd properbackup-web
PROPERBACKUP_RECOVERY_TEST_MODE=true npx playwright test tests/e2e/group-i-recovery.spec.js --workers=1
\`\`\`

## Test structure
- Each test has 4 phases: setup (create test user, register agent, do backup), recovery flow, assertions, cleanup
- Test data: deterministic — same file content, same paths, same timestamps
- Videos: saved to `playwright-report/data/<test-id>/video.webm`

## Common pitfalls
- Don't forget MockAgent setup — without `PROPERBACKUP_RECOVERY_TEST_MODE=true`, tests will hang waiting for real agent
- Clean recovery_session, recovery_operation, recovery_dry_run between tests
- Pre-recovery snapshots are auto-created — they fill archive_snapshot fast; clean per test group
```

### 10.7 DoD dla PR-a docs+tests

- [ ] All 8 tests pass locally (workers=1 to avoid race)
- [ ] Videos generated and copied to `docs/e2e-videos/recovery/`
- [ ] `docs/e2e-videos/README.md` updated with tests 11-18 table rows
- [ ] Skill file in `.agents/skills/recovery-e2e-testing.md`
- [ ] CI integration: `properbackup-web` workflow runs group-i (`ci-cd-release-pipeline-spec.md` cross-ref)
- [ ] Test reproducibility: same test run 3x → 3x success (no flakes)
- [ ] PR description includes table of test descriptions + video links

---

## 11. Test Groups (overall, cross-cutting)

### 11.1 Group A: Session lifecycle

#### `[REC-A1]` Happy path: REQUESTED → DONE

**Given:** User has active server with snapshot S; OVH hot tier
**When:** User clicks "Restore to this point" on S; agent completes restore
**Then:**
- State transitions: REQUESTED → PLANNING → AWAITING_USER_CONFIRM → READY → AGENT_RESTORING → VERIFYING → DONE
- audit_log has 9+ entries
- recovery_operation rows: all in 'done' state
- archive_snapshot has new PRE_RECOVERY entry
- UI shows DONE notification

#### `[REC-A2]` Cancel before AGENT_RESTORING

**Given:** Recovery in AWAITING_USER_CONFIRM
**When:** User clicks Cancel
**Then:**
- State → CANCELLED
- No pre-recovery snapshot created (not yet)
- No agent involvement
- audit_log: RECOVERY_CANCELLED entry

#### `[REC-A3]` Cancel during AGENT_RESTORING (with rollback)

**Given:** Recovery in AGENT_RESTORING (50% done)
**When:** User clicks Cancel
**Then:**
- Agent finishes current file
- Rollback initiated: pre-recovery snapshot operations reversed
- State → CANCELLED
- All quarantined files restored
- All new restored files removed
- audit_log: RECOVERY_CANCELLED + rollback details

#### `[REC-A4]` 409 on concurrent recovery

**Given:** Active recovery on Server A
**When:** POST /recovery/start with same server_id
**Then:** 409 Conflict with body `{error: "recovery_already_active", session_id: "<existing>"}`

#### `[REC-A5]` State machine: illegal transitions rejected

**Given:** Recovery in REQUESTED
**When:** Direct DB or API attempt to transition to AGENT_RESTORING (skipping intermediate states)
**Then:** Rejected with IllegalStateTransition exception

### 11.2 Group B: DRY RUN

#### `[REC-B1]` Diff computation correctness

**Given:** Snapshot has 1000 files (sha256s), local has 850 files (700 match, 150 different, 300 missing snapshot)
**When:** Agent computes dry run
**Then:**
- toRestore = 450 (150 different + 300 missing)
- toDelete = 150 (local files not in snapshot — wait, let me recheck: 850 local total, 700 matching → 150 different/local-only; if 300 missing in local that are in snapshot, then local has 850 - 700 = 150 local-only)
- Refine: snapshot=1000, local=850, matching=700; snapshot-only=300 (RESTORE); local-only=150 (DELETE); matching=700 (SKIP)
- unchanged = 700

#### `[REC-B2]` Critical paths protected

**Given:** Local has `/proc/cpuinfo`, `~/.properbackup/config.json`, `../../../etc/passwd` (symlink)
**When:** Dry run computed
**Then:**
- Critical paths NOT in toRestore or toDelete
- criticalFilesProtected counter incremented

#### `[REC-B3]` Sample files in UI preview

**Given:** Dry run with 5000 files to restore
**When:** UI fetches dry run result
**Then:**
- `sample_files_to_restore` array has 20 (configurable max)
- Random sample (not first 20) — for diversity

### 11.3 Group C: Resilience

#### `[REC-C1]` Agent crash mid-restore

**Given:** Recovery AGENT_RESTORING, 5000 operations total, 2000 done, agent crashes
**When:** Agent restarts
**Then:**
- Agent reads recovery_state.json (SQLite)
- Resumes from operation 2001
- Final state: all 5000 done

#### `[REC-C2]` Buffer crash during AGENT_RESTORING

**Given:** Recovery AGENT_RESTORING, buffer crashes
**When:** Buffer restarts after 5 min
**Then:**
- Buffer rehydrates active recovery sessions from DB
- Agent's progress reports queue up; processes on buffer restart
- Recovery continues without user intervention

#### `[REC-C3]` Pre-recovery snapshot creation fails

**Given:** Recovery in READY, agent tries to create pre-recovery snapshot, buffer offline
**When:** Agent attempts upload of pre-recovery snapshot
**Then:**
- Agent retries with exponential backoff (5s, 30s, 5min)
- If 3 retries fail → recovery → FAILED with reason "Pre-recovery snapshot creation failed"
- No file modifications performed

### 11.4 Group D: UI integration

#### `[REC-D1]` Multi-tab user

**Given:** User opens Server A on Tab 1 (starts recovery), then opens Server A on Tab 2
**When:** Tab 2 loads
**Then:**
- Tab 2 sees Recovery Mode overlay immediately (state hydrated from server)
- Both tabs show same progress (SSE real-time sync)

#### `[REC-D2]` Browser closed during recovery

**Given:** Recovery AGENT_RESTORING, user closes browser
**When:** User opens new browser session after 10 min
**Then:**
- RecoveryContext fetches active recoveries on auth init
- UI shows current state (correct phase, progress)

#### `[REC-D3]` Mobile viewport

**Given:** Recovery Mode overlay on 320px viewport
**When:** Overlay renders
**Then:**
- Width adapts to 90vw
- All controls accessible (no overflow)
- Cancel button visible

### 11.5 Group E: Audit

#### `[REC-E1]` Audit log completeness

**Given:** Recovery from REQUESTED to DONE
**When:** Query audit_log WHERE recovery_session_id = X
**Then:**
- 9+ entries (per state transition + operations batches)
- Each entry has user_ip, user_agent, timestamp
- audit PDF export includes all entries

#### `[REC-E2]` Per-operation audit batched

**Given:** Recovery with 5000 operations
**When:** Audit log queried
**Then:**
- RECOVERY_FILE_RESTORED entries batched (1 per 100 ops = 50 entries)
- Each batch has files_restored_count + sample paths

---

## 12. Edge Cases

| ID | Scenariusz | Spodziewane zachowanie |
|----|-----------|------------------------|
| `REC-EC1` | Snapshot target deleted between start and execute | FAILED z reason "target_snapshot_deleted" |
| `REC-EC2` | User subscription expired mid-recovery | Recovery continues (already paid for); no new recoveries possible |
| `REC-EC3` | Server unregistered mid-recovery | FAILED z reason "server_unregistered"; cleanup quarantine |
| `REC-EC4` | OVH thaw fails permanently | FAILED z reason "thaw_unavailable"; recommend manual support contact |
| `REC-EC5` | Disk full during restore | Agent pauses, alerts user; user frees space → resume from paused state |
| `REC-EC6` | Symlink loop in target snapshot | Detect via depth limit (max 32 redirects); skip + log |
| `REC-EC7` | Unicode/non-ASCII paths | Use UTF-8 throughout; test specific scenarios (emoji, Polish chars, RTL Arabic) |
| `REC-EC8` | File with same name as recovery_id quarantine dir | Quarantine paths use UUID + sha256(path) — collision-free |
| `REC-EC9` | Concurrent backup attempt during recovery | RecoveryGuard blocks; backup endpoint returns 423 Locked |
| `REC-EC10` | Pre-recovery snapshot exceeds storage quota | Pre-recovery is in 30-day grace period (not counted to quota); BUT actual disk space must be available — alert if buffer disk >80% |
| `REC-EC11` | Recovery to a snapshot that is itself PRE_RECOVERY | Allowed (chain of recoveries possible) |
| `REC-EC12` | User changes account email mid-recovery | Continues without interruption |
| `REC-EC13` | Two browsers, two different users (admin + customer) on same recovery | Both see same state; both can cancel (audit logs which user) |
| `REC-EC14` | Network partition: agent can reach buffer but cannot reach OVH | FAILED z reason "ovh_unreachable"; retry recoverable |
| `REC-EC15` | Time skew between agent and buffer >5 min | Recovery still works (uses UUID, not timestamps for correlation) |
| `REC-EC16` | Custom backup roots (user changed config) post-snapshot | Use snapshot's recorded backup_roots, not current config |
| `REC-EC17` | Agent version mismatch (snapshot v1.0, agent v2.0) | Agent supports backward-compat read; new agent restores old snapshots |
| `REC-EC18` | Encryption key changed between snapshot and now | DECRYPT FAILS at file 1; FAILED z reason "encryption_key_changed"; user must restore from older snapshot |
| `REC-EC19` | User has multiple servers, recovery on one stalls | Other servers fully usable; alert if recovery stuck >24h |
| `REC-EC20` | Pre-recovery snapshot itself fails verify | Recovery FAILED before AGENT_RESTORING; no harm done |

---

## 13. Definition of Done (overall)

### 13.1 Specs (this PR — docs only)

- [ ] `user-facing-recovery-spec.md` complete (1500+ linii, sections 0-17)
- [ ] `web-panel-master-spec.md` modified — section 4.2 references new spec
- [ ] `agent-vps-master-spec.md` modified — "Restore Protocol" section added
- [ ] `buffer-core-master-spec.md` modified — "Recovery Session lifecycle" section added
- [ ] `architecture/README.md` updated — new spec in table

### 13.2 Per-PR DoD (cross-ref sections 7.6, 8.5, 9.7, 10.7)

Każda z 4 nastepnych PR-ow ma wlasne DoD w odpowiedniej sekcji powyzej. Wymagane przed merge:

1. **PR Frontend (web)**: 7.6 — lint clean, i18n complete, screenshots
2. **PR Buffer**: 8.5 — DB migration green, 100% state machine test coverage
3. **PR Agent + Shared**: 9.7 — cross-host parity test green, crash test green
4. **PR Docs + E2E**: 10.7 — 8 tests pass, videos in repo, skill in `.agents/skills/`

### 13.3 Integration DoD (post-all-PRs)

- [ ] End-to-end: real customer can perform recovery from web UI (test mode)
- [ ] Audit PDF export includes Recovery History
- [ ] Recovery completes <5 min for 1GB snapshot in test env
- [ ] Recovery for 10GB snapshot tested in staging (real OVH cold tier)
- [ ] Rollback tested with real customer-like data (1000+ files, mixed sizes)
- [ ] Documentation review by senior engineer
- [ ] Security review: SAST + auth/authz check on all endpoints

---

## 14. Workflow Protocol (per-PR, TDD red-first)

### 14.1 PR Buffer (B)

1. Write `RecoverySessionStoreTest.kt` — red
2. Implement `RecoverySessionStore.kt` — green
3. Write `RecoveryStateMachineTest.kt` — red
4. Implement `RecoveryStateMachine.kt` — green
5. ...repeat for Guard, DryRunComputer, PreRecoverySnapshotCreator
6. Write `RecoveryHandlerTest.kt` (integration with Javalin) — red
7. Implement `RecoveryHandler.kt` — green
8. DB migration: write SQL, run on dev Testcontainers, verify
9. End-to-end test: REQUESTED → DONE in Testcontainers (stub agent)
10. Update `BufferMain.kt` to mount routes
11. Lint clean, all tests green, commit, PR

### 14.2 PR Agent + Shared (C)

1. In shared: write `SnapshotDiffTest.kt` — red
2. Implement `SnapshotDiff.kt` — green
3. ...repeat for FileRestorer, FileDeleter, CriticalPathsGuard, RestoreStateStore
4. Cross-host parity test: VPS + MC mock — green
5. In agent: SSE subscription + RestoreOrchestrator invocation
6. Crash test (kill -9 mid-write) — resume green
7. Lint clean, all tests green, commit, PR

### 14.3 PR Frontend (A)

1. Storybook (jezeli istnieje): create stories for each component
2. Unit tests (vitest): RecoveryContext, hooks — green
3. Manual: dev env with running buffer + mock agent → verify flows
4. i18n: add PL + EN keys; manual switch test
5. Screenshots: capture 5 states for PR description
6. Lint clean, build green, commit, PR

### 14.4 PR Docs + E2E (D)

1. Write Playwright tests (red — fail without infrastructure)
2. Create test helpers (recoveryHelper.js, mockAgentRecovery.js)
3. Run tests against test server with mock agent → green
4. Generate videos, copy to docs
5. Update README in `e2e-videos/`
6. Write skill markdown
7. PR docs + tests + videos

---

## 15. Go/No-Go Checklist (przed launchem)

### 15.1 Functional

- [ ] Happy path: 100MB snapshot recovery completes <2 min (test env)
- [ ] Cancel happy path: rollback within 30s
- [ ] 1GB snapshot recovery completes <10 min
- [ ] 10GB snapshot recovery completes <60 min (production-like)
- [ ] Cold tier recovery: thaw + recovery completes within OVH SLA

### 15.2 Resilience

- [ ] Agent crash test: 100% success rate over 100 runs
- [ ] Buffer crash test: 100% success rate over 50 runs
- [ ] Concurrent recovery test: no race conditions in 100 attempts
- [ ] Network partition: graceful failure with clear error

### 15.3 Security

- [ ] All endpoints behind JWT auth
- [ ] User can only cancel own recoveries (RBAC)
- [ ] Path traversal blocked
- [ ] Audit log tamper-proof (append-only, signed?)

### 15.4 UX

- [ ] Recovery Mode visible on mobile (320px)
- [ ] All error states have user-friendly messages
- [ ] Cancel + retry works without manual intervention
- [ ] Multi-language: PL + EN both complete

### 15.5 Compliance

- [ ] Audit log includes user_ip, user_agent, timestamp
- [ ] Pre-recovery snapshot kept for 30 days (grace period)
- [ ] User can export recovery history (Audit PDF)
- [ ] GDPR Right to be Forgotten: deleting user account purges recovery history

---

## 16. Appendix A — Glossary

- **Recovery Mode**: User-facing state where target server is in process of being restored to a snapshot
- **Recovery Session**: Database entity representing a single recovery attempt (state machine)
- **DRY RUN**: Pre-execution computation of file diff (what will be restored/deleted/skipped)
- **Pre-Recovery Snapshot**: Snapshot of CURRENT state taken before AGENT_RESTORING starts (allows rollback)
- **Quarantine**: Temporary storage of deleted files during recovery (30-day TTL for rollback support)
- **CriticalPathsGuard**: Whitelist preventing deletion of system/agent files
- **REC-X**: Test ID for Recovery test cases in this spec
- **`recovery_session`, `recovery_operation`, `recovery_dry_run`**: Database tables (sekcja 5.2)

## 17. Appendix B — Cross-references

- `shared-core-architecture-spec.md` HR-1 (Shared Core), SHC-D (cross-host parity)
- `buffer-core-master-spec.md` HR-3 (immutable storage), HR-9 (at-rest encryption)
- `agent-vps-master-spec.md` HR-3 (header-first), HR-7 (resumable upload)
- `web-panel-master-spec.md` section 4.2 (Restore flow, single-file existing)
- `ovh-cloud-archive-migration-spec.md` HR-7 (cold tier transition)
- `crypto-and-compliance-spec.md` AES-256-GCM streaming (used in FileRestorer)
- `ci-cd-release-pipeline-spec.md` (E2E job in CI per repo)
- `observability-and-dr-spec.md` (audit log retention + DR procedures)
- `master-tdd-plan.md` `[TDD-F1]` ProcessingScreen pattern (we mirror for RecoveryModeOverlay)
- `Biznesplan_ProperBackup_v6_AI_Blueprint` (Single Source of Truth, sekcja 4.2 USP "1-Click Restore")

## 18. Appendix C — Open Questions (to discuss before implementation)

1. **Recovery limits per subscription tier?** — Czy Free trial users moga recovery? Czy limit X recoveries/month?
2. **Multi-region OVH** — Czy klient ma wybor "restore from primary region" vs "from secondary"?
3. **Partial recovery** — Czy user moze wybrac TYLKO niektore pliki/folders zamiast calego snapshota? (out-of-scope tej iteracji, ale TODO future)
4. **Email notification** — Czy wysylamy email gdy recovery DONE/FAILED? Per state?
5. **Concurrent recovery + active backup** — Czy podczas recovery na Server A, backup na Server A jest zablokowany (HR-2 mowi tak); ale co z auto-scheduled backups? Czy reschedule po recovery DONE?
6. **Pre-recovery snapshot promotion** — Czy user moze "Save permanently" pre-recovery snapshot (zeby nie znikal po 30 dniach)?
7. **Recovery time estimate algorithm** — Bazujac na historii agent throughput? Pierwsze recovery bez historii = jaki default ETA?

## 19. Appendix D — Decision History

| Data | Decyzja | Powod |
|------|---------|-------|
| 2026-05-26 | Per-server lockdown zamiast globalnego | Multi-server users nie chca freeze calego account |
| 2026-05-26 | Pre-recovery snapshot OBOWIAZKOWY | Safety net dla "rozmyslilam sie" — user moze undo |
| 2026-05-26 | DRY RUN preview MANDATORY (checkbox) | UX: brak nieprzemyslanych restore; security: user sees consequences |
| 2026-05-26 | 30-day grace period dla pre-recovery snapshot | Balance UX (undo possible) vs koszty storage |
| 2026-05-26 | Quarantine zamiast permanent delete | Allows rollback w cancel scenario |
| 2026-05-26 | State machine z 10 stanami (zamiast 4) | Granularity dla UX + analytics + audit |
| 2026-05-26 | Recovery Mode UI = center-screen overlay | Time Machine inspired; user wie ze "system w trybie specjalnym" |
| 2026-05-26 | E2E test count = 8 | Cover happy + cancel + concurrent + edge cases bez over-testing |
| 2026-05-26 | Webm video format dla testow | Playwright native, zgodne z konwencja `e2e-videos/` |

---

## 20. Appendix E — LLD: cross-spec invariants (kontrakt dla agenta)

> Recovery dotyka WSZYSTKICH warstw (UI, buffer, agent, shared, OVH). Ta tabela
> spina niezmienniki z pozostałych speców, żeby agent nie złamał ich „od strony
> recovery". Każdy wiersz ma test ochronny w odpowiednim specu.

| Niezmiennik | Źródło | Znaczenie dla recovery |
|-------------|--------|------------------------|
| `canRestore` ZAWSZE `true` (anti-hostage) | `subscription-expiration-handling.md` §2 | restore działa nawet w `LOCKED_EXPIRED` — wygaśnięcie nie blokuje odzyskania danych |
| Async cold restore (O-1: `get()` zwraca stan, nie bajty) | `ovh-cloud-archive-migration-spec.md` E.1 | stan `THAWING` mapuje 1:1 na `restore_request.status=pending`; UI poll po `etaAt` |
| Upload/restore resumowalny po crashu (A-4) | `agent-vps-master-spec.md` C.4 | agent wznawia full-system restore od pierwszego pliku `!= DONE` |
| Cross-host parity (HR-4) | `shared-core-architecture-spec.md` | ten sam blob odtwarza się identycznie na VPS i MC |
| Pre-recovery snapshot 30-day grace + quarantine | sekcja 5 (ten spec) | rollback możliwy po `cancel`; quarantine ≠ permanent delete |

### 20.1 Mapowanie stanów recovery ↔ tabele

```
RecoverySession.state = THAWING   <-> restore_request.status = pending  (eta_at)
RecoverySession.state = READY     <-> restore_request.status = ready    (expires_at = ready_at + 3d)
RecoverySession.state = RESTORING <-> agent upload_queue: chunki QUEUED->DONE (parytet z §6)
```

> **Niezmiennik R-1:** `RecoverySession` nigdy nie przechodzi do `RESTORING`
> dopóki wszystkie wymagane `restore_request` nie są `ready` (brak częściowego
> restore z na wpół odmrożonych danych).

### 20.2 Cross-references

- `ovh-cloud-archive-migration-spec.md` Dodatek E — async restore, `restore_request`.
- `subscription-expiration-handling.md` §2 — `canRestore`, Access Boundary.
- `agent-vps-master-spec.md` C.4 — maszyna stanów uploadu/restore.
