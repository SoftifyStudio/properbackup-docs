# Observability & Disaster Recovery — Master Plan

Wersja: 1.0 (initial, pre-prod)
Autor: agent
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P0** (krytyczne, single-point-of-failure projektu)

---

## 1. Cel dokumentu

Single source of truth dla agenta implementujacego warstwe **observability** (logi, metryki, alerty, SLO/SLA) oraz **disaster recovery** (backup PostgreSQL, restore drill, incident runbook) dla calego ProperBackup.

Dokument jest bratem `master-tdd-plan.md` (billing) — ta sama filozofia "minimal invasiveness", DOTYKAJ vs NIE RUSZAJ, TDD workflow.

### Dlaczego to P0

Aktualnie projekt ma **dwa krytyczne single-points-of-failure**:

1. **PostgreSQL na VPS bez automatycznego backupu poza-serwerowego.** Jezeli VPS pada (hardware, hosting provider bankrupt, ransomware, human error `DROP TABLE`), tracimy:
   - Wszystkie konta uzytkownikow
   - Wszystkie metadane backupow (`archive_snapshot`, `file_state`, `paths_index`)
   - Wszystkie zaplacone subskrypcje (`stripe_subscription_id` mapping)
   - Co fizycznie znaczy: **nawet jezeli pliki klienta sa bezpieczne na OVH Cloud Archive, nie wiemy CZYJE one sa i co reprezentuja** — nie da sie ich zrestore'owac
2. **Brak monitoringu / alertingu w produkcji.** Jezeli buffer pada o 3:00 w nocy:
   - Nie wiemy
   - Klienci tez nie wiedza (agenty leca w retry)
   - Pierwszy sygnal: telefon od klienta rano, ze "backupy nie ida"

Bez zaadresowania tych dwoch luk **nie powinno sie wystartowac produkcyjnie**. Master plan billingu nawet wzmianke o tym ma w sekcji 13.3, ale tylko jako pojedyncza linia — tu jest pelny plan implementacji.

### Zakres

- Backup PostgreSQL (logical + physical), retention, encryption, off-server transfer
- Restore drill (kwartalny chaos test)
- Monitoring stack (logi, metryki, traces)
- Alerting (Slack/email/SMS)
- SLO/SLA definicje (RPO/RTO)
- Incident response runbook
- Health endpoints i smoke tests
- Cost monitoring (OVH spend alerts)

### Co NIE jest w zakresie

- Multi-region failover (post-MVP, scaling plan)
- Active-active HA cluster (post-MVP)
- Synthetic transaction monitoring (post-MVP, optional)
- APM tier z transaction tracing (Datadog/NewRelic — koszt, post-MVP)

---

## 2. Mapowanie kodu i infrastruktury

### 2.1 Stan obecny

| Obszar | Plik / Komponent | Stan |
|--------|------------------|------|
| Health endpoint | `properbackup-buffer/.../BufferMain.kt` route `/health` | **JEST** — sprawdza tylko `pg_isready` (przez Hikari pool) |
| Logi aplikacyjne | `properbackup-buffer/.../logs/LogApiHandler.kt` | Logi *od agenta do buffera* (telemetria agenta). NIE logi samego buffera. |
| Stack logi agenta | `properbackup-buffer/.../logs/StackLogStore.kt` | JEST. Buffer przyjmuje stack traces od agenta, trzyma w PG. |
| Metryki agenta | `properbackup-buffer/.../monitoring/AgentMetricsStore.kt` + `agent_metrics` table | JEST. Sample co X sekund, CPU/RAM/disk. |
| Buffer self-logging | `slf4j` + `logback.xml` (jezeli istnieje) | **BRAK** spec — sprawdz `properbackup-buffer/src/main/resources/logback.xml` |
| PostgreSQL backup | (cron na VPS?) | **NIEZNANE** — brak docs, brak skryptu w repo |
| Monitoring zewnetrzny | UptimeRobot? Pingdom? | **BRAK** — brak konfiguracji w docs |
| Alerty | - | **BRAK** |
| Incident runbook | - | **BRAK** |
| SLO/SLA | - | **BRAK** definicji |

### 2.2 Co dodajemy

Wszystko co ponizej **w sekcji 7** (test groups) + **sekcji 9** (skrypty operacyjne).

### 2.3 Repo destinations

| Artefakt | Repo | Sciezka |
|----------|------|---------|
| Backup script | `properbackup-stack` | `scripts/pg-backup.sh` (NEW) |
| Restore script | `properbackup-stack` | `scripts/pg-restore.sh` (NEW) |
| Restore drill test | `properbackup-stack` | `scripts/pg-restore-drill.sh` (NEW) |
| Logback config | `properbackup-buffer` | `src/main/resources/logback-prod.xml` (NEW) |
| Health endpoints | `properbackup-buffer` | `BufferMain.kt` ROUTING (EXTEND, nie podmieniac) |
| Metrics endpoint | `properbackup-buffer` | nowy `MetricsHandler.kt` (NEW) |
| Alerting config | `properbackup-stack` | `monitoring/alerts.yml` (NEW, jezeli Prometheus/Grafana) |
| Runbooks | `properbackup-docs` | `operations/runbook-*.md` (NEW) |
| SLO/SLA docs | `properbackup-docs` | `operations/slo-sla.md` (NEW) |

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `properbackup-buffer/.../BufferMain.kt` — istniejace route handlers (mozna DODAWAC nowe, ale nie modyfikowac istniejacych podpisow)
- `properbackup-buffer/.../db/Database.kt` — Hikari config, connection pool tuning
- `properbackup-buffer/.../flush/BudgetGuard.kt`, `StorageQuotaGuard.kt` — fail-safe contract, nie zmieniac semantyki
- `properbackup-buffer/.../subscription/*` — zostawia master-tdd-plan.md
- `schema.sql` — zadnych zmian (oprocz dodawania **nowych** tabel/widokow)
- Agent (`AgentMain.kt`, `BufferUploader.kt`) — wszystko, oprocz dodania metryk wlasnych

### DOTYKAJ (mozna modyfikowac, ale ostroznie)

- Dodanie nowych route handlerow do `BufferMain.kt` (`/health/detailed`, `/metrics`, `/ready`, `/live`)
- Dodanie `logback-prod.xml` do `src/main/resources/`
- Dodanie nowych skryptow w `properbackup-stack/scripts/`
- Dodanie nowego docker-compose service: `pb-monitoring` (Grafana/Prometheus stack) — TYLKO opcjonalnie
- Dodanie nowych dokumentow w `properbackup-docs/operations/`

### MOZESZ TWORZYC

- Nowe pliki Kotlin: `MetricsHandler.kt`, `HealthHandler.kt`, `IncidentLogger.kt`
- Nowe tabele:
  - `system_health_check` — history of health checks (optional)
  - `incident_log` — recorded incidents (manual flag + auto)
- Nowe pliki test: `MetricsHandlerTest.kt`, `HealthDetailedTest.kt`
- Skrypty cron: `pg-backup.sh`, `cleanup-old-logs.sh`

---

## 4. Domain Model — Observability Stack

### 4.1 Cztery warstwy

```
+--------------------------------------------------------------+
| L4: ALERTING                                                 |
|     Slack webhook / PagerDuty / SMS (Twilio)                 |
+--------------------------------------------------------------+
| L3: VISUALIZATION + QUERY                                    |
|     Grafana + Loki (logi) + Prometheus (metryki)             |
|     OR: Cloud SaaS — Better Stack / Sentry / Datadog free    |
+--------------------------------------------------------------+
| L2: COLLECTORS                                               |
|     - Promtail (logi z systemd)                              |
|     - node_exporter (CPU/RAM/disk VPS)                       |
|     - postgres_exporter (PG metryki)                         |
|     - cAdvisor (Docker container metryki)                    |
+--------------------------------------------------------------+
| L1: SOURCES                                                  |
|     - properbackup-buffer (logback JSON -> stdout)           |
|     - PostgreSQL (logi w /var/log/postgresql/)               |
|     - System logs (journalctl)                               |
|     - Nginx access/error logs                                |
+--------------------------------------------------------------+
```

### 4.2 Decyzja Stack vs SaaS

Dla MVP rekomenduje **HYBRYDA**:

| Co | Czym | Koszt |
|----|------|-------|
| Logi aplikacyjne | **Better Stack Logs** (free tier 1GB/mies) | 0 zl |
| Uptime monitoring | **UptimeRobot** (free, 50 monitors) | 0 zl |
| Alerty | **Slack webhook** (free) + SMS przez **Twilio** dla P0 | ~10 zl/mies |
| Error tracking | **Sentry** (free, 5K events/mies) | 0 zl |
| Metryki | NA RAZIE — `/metrics` endpoint Prometheus format, ale scrape lokalnie. Przy >50 klientach: postaw Grafana Cloud free tier (10K series) | 0 zl |

Pelny self-hosted stack (Grafana/Loki/Prometheus na VPS) jest **post-MVP**. Marnuje RAM ktorego nie mamy na ARM64.

### 4.3 RPO i RTO (definicje)

- **RPO (Recovery Point Objective):** Ile maksymalnie danych mozemy stracic. Cel: **15 minut** (czyli backup PG nie rzadziej niz co 15min lub WAL streaming).
- **RTO (Recovery Time Objective):** Ile maksymalnie zajmuje przywrocenie uslugi po awarii. Cel: **2h** (restore PG z najnowszego dumpa + DNS switch).
- **MTTR (Mean Time To Repair):** Sredni czas naprawy. Cel: **30min** dla typowych incydentow (restart serwisu, OOM, full disk).

---

## 5. Test Groups

Numerowane jako `[OBS-Xn]` dla grep'ability.

### Grupa A: Health & Readiness Endpoints

#### `[OBS-A1]` `/health` rozszerzone

**Status obecny:** `/health` zwraca 200 OK jezeli `pg_isready` przejdzie. To za mało.

**Cel:** Rozszerzyc o sprawdzenia *wszystkich krytycznych zaleznosci* bez ujawniania szczegolow publicznie.

**Given:**
- Buffer dziala
- PostgreSQL dziala
- OVH Cloud Archive dostepne (lub mock)
- Storage dir zapisywalne

**When:** GET `/health`

**Then:**
- 200 OK z body `{"status":"healthy"}` (nic wiecej publicznie)

**Given:** Storage dir pelne (>95% disk)

**When:** GET `/health`

**Then:**
- 503 Service Unavailable, body `{"status":"degraded"}`

**Pliki:**
- DOTYKAJ: `BufferMain.kt` ROUTE
- NEW: `HealthHandler.kt`

**DoD:**
- 4 sub-cases: healthy / degraded-disk / degraded-db / degraded-storage
- Test z `Testcontainers` (real Postgres start/stop)
- Nigdy nie ujawnia secret/connection-string w response

#### `[OBS-A2]` `/health/detailed` (autoryzowany)

**Cel:** Pelne info dla admina (status PG, OVH, Stripe, disk, RAM) za autoryzacja JWT.

**Given:** Admin token

**When:** GET `/health/detailed` z `Authorization: Bearer <admin-jwt>`

**Then:**
```json
{
  "status": "healthy",
  "checks": {
    "postgres": {"ok": true, "latency_ms": 12, "connections_used": 3, "connections_max": 10},
    "ovh_swift": {"ok": true, "latency_ms": 230, "last_upload_seconds_ago": 42},
    "stripe": {"ok": true, "last_webhook_seconds_ago": 18, "dlq_size": 0},
    "disk": {"ok": true, "used_pct": 67, "free_gb": 124},
    "memory": {"ok": true, "used_pct": 41, "free_mb": 2048}
  },
  "uptime_seconds": 432100,
  "build": "2026.05.26-abc1234"
}
```

**Then (sad path):** bez tokenu — 401.

**DoD:**
- Endpoint zabezpieczony rolą `SERVICE_ADMIN`
- Smoke test: kazda checka zwraca `ok:false` jezeli zalezenie down
- Test ze sfabrykowanym tokenem nie-admina dostaje 403

#### `[OBS-A3]` `/live` (Kubernetes/orchestrator probe)

**Cel:** Zwracaj 200 jezeli proces zyje, bez sprawdzania zaleznosci.

**Then:** 200 OK, body `OK`. Nigdy nie powinno zwrocic 5xx jezeli proces sam nie zostal zabity.

#### `[OBS-A4]` `/ready` (Kubernetes/orchestrator probe)

**Cel:** Zwracaj 200 tylko gdy serwis jest gotowy odbierac ruch (PG migracje zakonczone, DB pool zainicjalizowany).

**Pod startup:** Przez pierwsze ~5s `/ready` zwraca 503 (warm-up).

### Grupa B: Logi

#### `[OBS-B1]` Structured logging w JSON

**Status obecny:** Nieznany. **TODO checklisty:** sprawdz `properbackup-buffer/src/main/resources/logback.xml` — czy istnieje, czy uzywa JSON encoder.

**Cel:** Kazdy log z buffera jest JSON-em z polami: `timestamp`, `level`, `logger`, `message`, `traceId`, `spanId`, `userId` (jezeli kontekst), `requestId`.

**Format wymagany:**
```json
{
  "ts": "2026-05-26T18:42:00.123Z",
  "level": "INFO",
  "logger": "pl.danielniemiec.properbackup.buffer.subscription.SubscriptionHandler",
  "msg": "Trial activated",
  "traceId": "abc123",
  "userId": "u_xyz",
  "stripeEventId": "evt_..."
}
```

**Reguly:**
- **NIGDY** nie loguj: hashed_password, stripe secret keys, webhook secrets, JWT tokens, full credit card data, OVH credentials
- Plain text log to stdout (Docker bedzie zbierac), NIE do pliku (file rotation problem na ARM64)

**Pliki:**
- NEW: `properbackup-buffer/src/main/resources/logback-prod.xml`
- Profile: domyslny `logback.xml` (dev, human-readable), `logback-prod.xml` (JSON, prod)

**DoD:**
- Test integracyjny: appender pisze do `ByteArrayOutputStream`, parsuj JSON, sprawdz wymagane pola
- Test "secret leak": zaloguj `password = "..."` i sprawdz ze NIE pojawia sie w outputie (powinien zostac zamaskowany przez Logback masking pattern)

#### `[OBS-B2]` Log levels per package

Wymagana konfiguracja:

| Package | Default level | Prod level |
|---------|--------------|------------|
| `pl.danielniemiec.properbackup.buffer.subscription` | DEBUG | INFO |
| `pl.danielniemiec.properbackup.buffer.ovh` | INFO | INFO |
| `pl.danielniemiec.properbackup.buffer.flush` | INFO | INFO |
| `pl.danielniemiec.properbackup.buffer.payment` | DEBUG | INFO |
| `pl.danielniemiec.properbackup.buffer.auth` | INFO | WARN |
| `com.zaxxer.hikari` | INFO | WARN |
| `org.eclipse.jetty` | WARN | WARN |
| root | INFO | INFO |

#### `[OBS-B3]` Centralne logi (Better Stack / Loki / SaaS)

**Cel:** Logi z **wszystkich** kontenerow (buffer, agent demo, postgres, nginx) ladja w jednym miejscu z pelnotekstowym search.

**Implementacja w stylu MVP:**
- `properbackup-stack/docker-compose.yml` — dodac driver `loki` lub `journald` per service, agent push to `Better Stack Logs` API
- LUB systemd: `journalctl -u properbackup-buffer -f | promtail` (na VPS)

**DoD:**
- Logi z ostatnich 7 dni dostepne w SaaS dashboardzie
- Search po `userId` zwraca wszystkie zdarzenia tego usera (audit trail)
- Search po `stripeEventId` zwraca cala historie przetwarzania webhooka

#### `[OBS-B4]` Retention i kosztorys

| Klasa logu | Retention | Storage |
|-----------|-----------|---------|
| INFO/DEBUG aplikacyjne | 7 dni | Better Stack free tier |
| WARN/ERROR aplikacyjne | 30 dni | Better Stack free tier (compress) |
| Audit log (billing zmiany) | **3 lata** (wymog ksiegowy PL) | PostgreSQL tabela `audit_log` (od master-tdd-plan.md) |
| Stripe webhook RAW | 90 dni | PostgreSQL tabela `stripe_event_idempotency` |
| Nginx access | 14 dni | Local file w `/var/log/nginx/`, rotacja `logrotate` |
| PostgreSQL slow queries (>500ms) | 30 dni | Better Stack |

**DoD:**
- Cron `logrotate` skonfigurowany na VPS
- Test ze "wstawieniem starego rekordu" do `stripe_event_idempotency` z `created_at = now() - 100 days` i sprawdzeniem ze cleanup go usuwa

### Grupa C: Metryki

#### `[OBS-C1]` Endpoint `/metrics` w formacie Prometheus

**Cel:** Buffer wystawia metryki w formacie Prometheus na `/metrics` (autoryzowany lub IP-whitelisted).

**Wymagane metryki:**

| Metric | Type | Labels | Co mierzy |
|--------|------|--------|-----------|
| `pb_http_requests_total` | counter | `method`, `route`, `status` | Liczba requestow |
| `pb_http_request_duration_seconds` | histogram | `method`, `route` | Czas odpowiedzi |
| `pb_db_pool_connections_active` | gauge | - | Aktywne polaczenia Hikari |
| `pb_db_pool_connections_idle` | gauge | - | Idle |
| `pb_db_query_duration_seconds` | histogram | `query_class` | Czas zapytan |
| `pb_chunks_received_total` | counter | `user_id_hash` | Chunki od agentow |
| `pb_chunks_uploaded_to_ovh_total` | counter | - | Chunki przeniesione na OVH |
| `pb_chunks_failed_total` | counter | `reason` | Bledy (budget/quota/auth/storage) |
| `pb_stripe_webhooks_received_total` | counter | `event_type`, `status` | Webhooki przetworzone |
| `pb_stripe_dlq_size` | gauge | - | Aktualnie w DLQ |
| `pb_subscriptions_active` | gauge | `plan` | Aktywne subskrypcje |
| `pb_subscriptions_trialing` | gauge | - | W trialu |
| `pb_subscriptions_past_due` | gauge | - | Past due |
| `pb_ovh_bytes_uploaded_total` | counter | - | Bajty na OVH (do liczenia kosztow) |
| `pb_ovh_api_errors_total` | counter | `code` | Bledy 4xx/5xx od OVH |
| `pb_uptime_seconds` | gauge | - | Uptime procesu |

**Pliki:**
- NEW: `properbackup-buffer/.../monitoring/MetricsHandler.kt`
- NEW: `properbackup-buffer/.../monitoring/MetricsRegistry.kt` (singleton, prosty in-memory licznik bez bibliotek)
- LUB: dodac `io.micrometer:micrometer-registry-prometheus` (1 dependency, dobrze testowany)

**Rekomendacja:** Micrometer Prometheus. NIE pisz wlasnego — to bezsens kiedy biblioteka ma 100K+ downloads/mies.

**DoD:**
- Endpoint zwraca tekst Prometheus format (kontrola `Content-Type: text/plain; version=0.0.4`)
- Test: po wykonaniu N requestow do `/api/...`, `pb_http_requests_total{route="..."}` rosnie o N
- Test: zliczanie nie wycieka pamieci (test 100K request, RAM nie rosnie wiecej niz X MB)

#### `[OBS-C2]` Agent metrics (extension)

**Status obecny:** `AgentMetricsStore` zapisuje CPU/RAM/disk samplem co interval do PG.

**Brakuje:**
- Metryki transferu: `pb_agent_uploaded_bytes_total`, `pb_agent_upload_errors_total`
- Metryki resumable: `pb_agent_resume_attempts_total`, `pb_agent_resume_success_total`
- Metryki circuit breakera: `pb_agent_circuit_breaker_state` (0=closed, 1=open, 2=half-open)

**Wszystko trafia do tabeli `agent_metrics` LUB do osobnej `agent_transport_metrics`** — decyzja agenta implementujacego.

### Grupa D: Alerty

#### `[OBS-D1]` Krytyczne alerty (P0, SMS+Slack)

| Alert | Warunek | Threshold | Co robi receiver |
|-------|---------|-----------|------------------|
| **Buffer down** | `/health` nieosiagalny >2 min | 1x | Restart procesu, sprawdz logi |
| **PostgreSQL down** | `pg_isready` fail | >30s | Failover na replica (gdy istnieje) lub restore |
| **OVH Cloud Archive down** | `pb_ovh_api_errors_total` rate >5/min | 5min | Wlacz fallback to local storage, alert |
| **Disk pelny (>95%)** | `pb_disk_used_pct > 95` | 1x | Trigger cleanup, alert |
| **Trial abuse spike** | new accounts/hour > 50 | 1x | Mozliwy atak, sprawdz `users` |
| **Stripe webhook DLQ rośnie** | `pb_stripe_dlq_size > 10` | 1x | Sprawdz logi, replay |
| **Payment failure spike** | `payment_failed/total > 0.3` | 5min | Problem z procesorem? Sprawdz Stripe status |

#### `[OBS-D2]` Ostrzezenia (P1, tylko Slack)

| Alert | Warunek | Threshold |
|-------|---------|-----------|
| Slow PG queries | p95 latency >500ms | 5min |
| OVH latency wysoka | p95 >2s | 5min |
| Hikari pool busy | active >80% pool size | 10min |
| Agent connections drop | active agents -50% in 5min | 5min |
| Past due users growing | >5% all paid users | 1h |

#### `[OBS-D3]` Notyfikacje (P2, daily digest)

- Liczba nowych userow / dzien
- Liczba aktywnych subskrypcji
- Trial -> paid conversion rate (7-day rolling)
- Total bytes on OVH
- MRR (monthly recurring revenue) snapshot

**Implementacja:** prosta cron job ktora zbiera SELECT-y z PG i wysyla na Slack o 9:00 codziennie.

#### `[OBS-D4]` Test alertingu (chaos drill)

Raz na miesiac admin recznie:
1. Zatrzymuje buffer container
2. Czeka 3 min
3. Sprawdza czy SMS przyszedl, Slack alert poszedl, on-call to widzi

**DoD:** Procedura w `properbackup-docs/operations/runbook-alerting-drill.md`

### Grupa E: PostgreSQL Backup & Restore

#### `[OBS-E1]` Logical backup `pg_dump`

**Cel:** Codzienny pelny dump bazy do **off-server** location (S3 / OVH Object Storage / Backblaze B2).

**Skrypt:** `properbackup-stack/scripts/pg-backup.sh`

```bash
#!/usr/bin/env bash
# pg-backup.sh — daily logical backup with off-server encrypted upload
set -euo pipefail

BACKUP_DIR=/var/backups/properbackup
DATE=$(date +%Y%m%d-%H%M)
DUMP_FILE="$BACKUP_DIR/pb-$DATE.sql.gz.enc"

mkdir -p "$BACKUP_DIR"

# 1. Dump + compress + encrypt
pg_dump -h db -U properbackup -d properbackup --no-owner --no-acl \
  | gzip -9 \
  | gpg --symmetric --cipher-algo AES256 --batch --passphrase-file /etc/pb/backup.key \
  > "$DUMP_FILE"

# 2. Upload to off-server (rclone with B2 remote)
rclone copy "$DUMP_FILE" b2:properbackup-db-backups/

# 3. Verify uploaded (size check)
LOCAL_SIZE=$(stat -c%s "$DUMP_FILE")
REMOTE_SIZE=$(rclone size --json b2:properbackup-db-backups/$(basename $DUMP_FILE) | jq .bytes)
if [ "$LOCAL_SIZE" != "$REMOTE_SIZE" ]; then
  echo "ERROR: size mismatch" >&2
  exit 1
fi

# 4. Local retention: keep 7 days, delete older
find "$BACKUP_DIR" -name "pb-*.sql.gz.enc" -mtime +7 -delete

# 5. Remote retention: B2 lifecycle policy (NIE w skrypcie, w B2 console)

# 6. Heartbeat ping (healthchecks.io)
curl -fsS --retry 3 "$PB_BACKUP_HEARTBEAT_URL"
```

**Wymagania:**
- Cron: `0 3 * * *` (codziennie 03:00 UTC)
- B2 bucket `properbackup-db-backups` z lifecycle policy: 30 dni hot, potem cold storage 1 rok, potem delete
- `/etc/pb/backup.key` — 32-byte random, **nie w gicie**, kopia w 1Password
- Heartbeat: jezeli backup nie wykona sie w 26h → healthchecks.io wysyla alert

**DoD:**
- Pojedynczy dump 100% odzyskiwalny (E2 test)
- Dump zaszyfrowany — bez klucza nie da sie odczytac
- Retention dziala (test: utworz 10 starych dumpow, uruchom skrypt, sprawdz ze tylko 7 zostalo)
- Heartbeat dziala (zarejestrowany w healthchecks.io z webhook do Slack)

#### `[OBS-E2]` Physical backup / WAL streaming (opcjonalnie, post-MVP)

Dla RPO < 15min potrzebne **PostgreSQL streaming replication** lub **WAL archiving (continuous archiving)**.

MVP: nie robimy. Dzienny dump = RPO 24h. Po dotarciu do >50 platnych klientow — wlacz WAL archiving (`pgBackRest` lub `wal-g`).

**TODO przyszly agent:** dodaj `[OBS-E2]` do roadmapy gdy MRR > 5000 PLN.

#### `[OBS-E3]` Restore procedure (runbook)

**Plik:** `properbackup-docs/operations/runbook-pg-restore.md`

```markdown
# Runbook: Disaster Recovery — PostgreSQL Restore

## Pre-conditions
- PostgreSQL container running (lub fresh install)
- Backup file dostepny lokalnie lub na B2
- Klucz GPG dostepny w 1Password
- Maintenance window ogloszony klientom (Twitter, status page)

## Steps

### 1. Stop buffer (no new writes)
```
ssh prod-vps
docker compose stop buffer
```

### 2. Backup current state (in case)
```
docker compose exec db pg_dump -U properbackup properbackup > /tmp/pre-restore-$(date +%s).sql
```

### 3. Drop current DB and recreate
```
docker compose exec db psql -U postgres -c "DROP DATABASE properbackup;"
docker compose exec db psql -U postgres -c "CREATE DATABASE properbackup OWNER properbackup;"
```

### 4. Download backup from B2
```
rclone copy b2:properbackup-db-backups/pb-YYYYMMDD-HHMM.sql.gz.enc /tmp/
```

### 5. Decrypt + restore
```
gpg --decrypt --batch --passphrase-file /etc/pb/backup.key /tmp/pb-*.sql.gz.enc \
  | gunzip \
  | docker compose exec -T db psql -U properbackup properbackup
```

### 6. Verify
```sql
SELECT COUNT(*) FROM users;        -- Powinno byc niezerowe
SELECT MAX(created_at) FROM users; -- Powinno byc <26h temu
SELECT COUNT(*) FROM archive_snapshot;
```

### 7. Start buffer
```
docker compose start buffer
docker compose logs -f buffer | head -50
```

### 8. Post-restore checklist
- [ ] `/health` returns 200
- [ ] Wyslij test webhook ze Stripe (Dashboard -> Webhooks -> Send test)
- [ ] Sprawdz `stripe_event_idempotency` — powinien byc rekord
- [ ] Sprawdz `agent_metrics` — agenty zaczynaja sie odzywac
- [ ] Powiadom klientow: status page green
```

#### `[OBS-E4]` Restore drill (kwartalny test)

**Raz na 3 miesiace** admin recznie wykonuje restore na separate staging VPS i weryfikuje:
- Czy procedura dziala
- Czy klucz GPG dziala
- Czy dane sa kompletne (sample 100 random user accounts)
- Ile czasu zajmuje restore (cel: <2h)

**Plik:** `properbackup-docs/operations/runbook-restore-drill.md`

**DoD:**
- Drill udokumentowany (data, kto, ile zajeto, problemy)
- Jezeli RTO przekroczony — task na poprawe procesu
- Wynik drilla aktualizuje SLA dokument

### Grupa F: Incident Response

#### `[OBS-F1]` Incident classification

| Severity | Definicja | Response time | Eskalacja |
|----------|-----------|---------------|-----------|
| **SEV-1** | Wszystkim klientom nie dziala upload (>50% userow). Money loss. | <15 min | Daniel + on-call SMS |
| **SEV-2** | Czesc klientow ma problem (<50%). Stripe ok. | <1h | Slack |
| **SEV-3** | Funkcjonalnosc poboczna nie dziala (np. Audit PDF). | <8h | Daily digest |
| **SEV-4** | Cosmetic / UX bug. | Next sprint | Backlog |

#### `[OBS-F2]` Incident response runbook (generic)

**Plik:** `properbackup-docs/operations/runbook-incident-response.md`

Standard SRE template:

```markdown
1. **Acknowledge** — odpowiedz alertowi w 5min (potwierdzenie ze ktos to widzi)
2. **Classify** — SEV-1/2/3/4
3. **Communicate** — status page update, Slack #incidents
4. **Investigate** — logi, metryki, hipotezy
5. **Mitigate** — przywroc usluge (rollback / restart / failover)
6. **Resolve** — root cause fix
7. **Postmortem** — w 72h od SEV-1, blameless template
```

#### `[OBS-F3]` Specific runbooki (TODO przyszly agent)

| Runbook | Plik |
|---------|------|
| Buffer down | `runbook-buffer-down.md` |
| PostgreSQL down | `runbook-pg-down.md` |
| OVH Cloud Archive down | `runbook-ovh-down.md` |
| Stripe webhook spam | `runbook-stripe-webhook-spam.md` |
| Disk full | `runbook-disk-full.md` |
| Trial abuse attack | `runbook-trial-abuse.md` |
| Unauthorized access detected | `runbook-security-breach.md` |
| OOM kill | `runbook-oom.md` |

Każdy runbook ma sekcje: **Symptomy** / **Diagnoza** / **Mitigation steps** / **Rollback** / **Postmortem template**.

### Grupa G: Status Page (publiczna)

#### `[OBS-G1]` Public status page

**Cel:** Klienci moga sprawdzic czy ProperBackup ma incydent.

**Opcje:**
1. **statuspage.io** — 79 USD/mies za free tier z ograniczeniami. Drogo.
2. **Self-hosted Uptime Kuma** — free, na osobnym VPS (1 EUR/mies Hetzner). Rekomendacja.
3. **Better Stack Status Page** — free 5 monitors. Rekomendacja na start.

**Plik:** `properbackup-docs/operations/status-page-setup.md`

**Monitorowane services:**
- API (https://app.properbackup.pl/api/health)
- Web panel (https://app.properbackup.pl)
- Storage OVH (jezeli ma public health endpoint)

**DoD:**
- URL `status.properbackup.pl` dziala
- Auto-update statusu z UptimeRobot/Better Stack
- Możliwosc manualnego ogloszenia incydentu

### Grupa H: Cost Monitoring

#### `[OBS-H1]` OVH spend alert

**Cel:** Alert gdy zuzycie OVH Cloud Archive przekroczy X GB / Y PLN dziennie.

**Metryki:**
- `pb_ovh_bytes_uploaded_total` (z `[OBS-C1]`)
- Dzienny delta (cron job liczy `today_total - yesterday_total`)

**Threshold (przyklad):**
- Daily upload > 100 GB → Slack warning
- Daily upload > 500 GB → Slack alert
- Monthly upload > X TB → SMS alert (X = budzet)

**DoD:**
- Cron skrypt liczy daily, alertuje gdy >threshold
- Threshold konfigurowalny w `.env`

#### `[OBS-H2]` PostgreSQL spend alert

VPS Hetzner ma flat fee, ale dysk moze rosnac. Alert gdy `pg_database_size('properbackup') > 80% disk`.

#### `[OBS-H3]` Stripe spend alert

Stripe bierze 1.4% + 0.25 EUR per transakcja. Dla 100 klientow x 19 PLN = 1900 PLN/mies, Stripe fee ~50 PLN/mies. Alert gdy fee >5% revenue.

---

## 6. SLO / SLA

### 6.1 SLO (Service Level Objective) — wewnetrzne cele

| Metryka | Cel | Period |
|---------|-----|--------|
| API availability | 99.5% (3.6h downtime/mies) | 30d rolling |
| API latency p95 | <500ms | 7d |
| Successful chunk upload rate | >99% | 7d |
| Successful restore rate | 100% (zero data loss) | indefinite |
| Stripe webhook processing | 100% (DLQ + replay) | indefinite |
| Backup completion | 100% (1 dump/day) | 7d rolling |

### 6.2 SLA (Service Level Agreement) — komunikowane klientowi

**Hobby plan (19 PLN/mies):**
- Best effort. Brak credit refundu za downtime.
- Backup wykonywany "regularnie" (vague).

**Pro plan (~50 PLN/mies post-MVP):**
- 99% uptime / mies. Przy <99% klient dostaje 10% credit nastepnego miesiaca.

**B2B Enterprise (post-MVP):**
- 99.9% uptime + RPO 1h + RTO 4h. Custom SLA.

### 6.3 Status communication

| Wydarzenie | Kanal |
|------------|-------|
| Planowane maintenance | Email klientom 48h wczesniej + status page banner 1h przed |
| Awaria nieplanowana | Status page natychmiast, email po incydencie |
| Postmortem | Blog post po SEV-1 |

---

## 7. Edge Cases (15+)

### 7.1 Awaria PG w trakcie webhooka Stripe

Webhook przychodzi, buffer probuje zapisac do `stripe_event_idempotency`, PG `connection refused`. **Co sie dzieje?**

**Wymagane zachowanie:**
- Webhook zwraca Stripe **500** (nie 200) → Stripe ponowi
- Po przywroceniu PG, Stripe retry przejdzie OK
- Idempotency zapobiega podwojnemu przetworzeniu

**Test:** Testcontainers, zatrzymaj PG container w sredku transakcji, sprawdz response 5xx.

### 7.2 Awaria w trakcie chunk upload

Agent uploaduje chunk 500MB, w polowie buffer ginie (OOM). **Co sie dzieje?**

**Wymagane zachowanie:**
- Chunk w inbox jest w stanie `partial`, nie `sealed`
- Po restart agent retry z resumable upload (range start)
- Inbox cleanup task po 24h kasuje partial

**Test:** Simulate kill -9 w polowie upload, restart, sprawdz ze agent dokoncza.

### 7.3 Cron pg-backup w trakcie heavy write

`pg_dump` powinien dzialac z `--data-only --serializable-deferrable` aby nie blokowac writes. **Co sie dzieje gdy nie?**

**Wymagane zachowanie:**
- `pg_dump` w trybie `--snapshot` lub `--serializable-deferrable`
- Brak deadlock z webhookami pisanymi w tym samym czasie

**Test:** Uruchom pg-backup w trakcie testowej fali 100 webhookow.

### 7.4 GPG klucz utracony

Klucz `/etc/pb/backup.key` utracony (skasowany, hacker, disk failure). **Co sie dzieje?**

**Wymagane zachowanie:**
- Wszystkie dotychczasowe dumpy bezuzyteczne
- **Procedura:** Klucz MUST byc w 1Password z aliasem "ProperBackup DB Backup Key 2026"
- Drill: usun klucz lokalnie, przywroc z 1Password, sprawdz restore z najnowszego dumpa

**Test:** Manual drill kwartalny.

### 7.5 B2 bucket niedostepny (Backblaze outage)

`rclone copy` fail. **Co sie dzieje?**

**Wymagane zachowanie:**
- Skrypt retry 3x z backoff
- Po 3 failach: zostaw dump lokalnie, alert "off-server upload failed"
- Nastepny dzien sprobuje znowu

**Test:** Mock rclone error w skrypcie, sprawdz alert.

### 7.6 Disk full w trakcie pg-backup

Lokalny dump rosnie do 5GB, dysk pelny. **Co sie dzieje?**

**Wymagane zachowanie:**
- `set -euo pipefail` w skrypcie wykryje failed `pg_dump`
- Alert: "Backup failed: disk full"
- Cron NIE proboj usuwac istniejacych dumpow (mogly byc unverified)

**Test:** Simulate disk full, sprawdz alert.

### 7.7 Stary webhook Stripe przyszedl po 7 dniach

Stripe ma retry policy 3 dni, ale moze probowac. Webhook ze starym timestampem. **Co sie dzieje?**

**Wymagane zachowanie:**
- Tolerancja zegara w `master-tdd-plan.md` mowi 5min
- Webhook >5min different from server time: **403** (potencjalny replay attack)
- Mimo wszystko zapisz to do `stripe_event_idempotency_rejected` z reason

**Test:** Wyslij webhook z `Stripe-Signature` timestamp = now() - 10 dni, sprawdz 403.

### 7.8 OOM kill buffera w trakcie webhooka

VPS na granicy RAM, JVM dostaje OOM signal. **Co sie dzieje?**

**Wymagane zachowanie:**
- Webhook nie skomitowal → Stripe retry
- Idempotency table pusta → retry przejdzie
- Heap dump zapisany do `/var/log/properbackup/heap-dump.hprof`
- Alert "OOM detected"

**Test:** Ustaw `-Xmx128m` (zbyt malo), wymus heavy load, sprawdz że recovery działa.

### 7.9 Log spam / log injection

Klient (atakujacy) wysyla request z `?email=user@example.com\nfake-log-line` (CRLF injection). **Co sie dzieje?**

**Wymagane zachowanie:**
- Logback escapes newlines w `%msg`
- Test: zaloguj string z `\n` i sprawdz że output ma `\\n`

### 7.10 Metryki rosna w nieskonczonosc (cardinality explosion)

Bug: ktos uzywa `user_id` jako label w Prometheus. **Co sie dzieje?**

**Wymagane zachowanie:**
- Labels musza miec **niska kardynalnosc** (max 100 unique values per label)
- `user_id_hash` (sha256 truncated to 4 chars) zamiast `user_id` jezeli koniecznie
- Lepiej: w ogole nie loguj per-user metryk, agreguj

**Test:** Sztywny limit w `MetricsRegistry.kt` — odmowa rejestracji metryki z >100 unique label values.

### 7.11 Stary Slack webhook URL ujawniony

Webhook URL byl w gicie i ktos go znalazl. **Co sie dzieje?**

**Wymagane zachowanie:**
- Slack pozwala rotowac webhook URL
- Procedura: Slack admin -> Apps -> Incoming Webhooks -> regenerate
- Update `.env` na VPS
- Stary URL dostaje 404 dla atakujacego

**Test:** Manual procedura, raz na rok.

### 7.12 Restore z bardzo starego dumpa (schema mismatch)

Restore dumpa z 6 miesiecy temu, ale schema obecnie ma nowe kolumny. **Co sie dzieje?**

**Wymagane zachowanie:**
- `schema.sql` po restore musi byc replayed (CREATE TABLE IF NOT EXISTS dla nowych)
- Migracje z `properbackup-buffer/.../db/Database.kt` (jezeli istnieja) musza byc rerunable

**Test:** Restore dumpa z fake-starego (zrzut z 7 dni temu), uruchom buffer, sprawdz `/health`.

### 7.13 Race condition na backup cron

Backup cron uruchamia sie codziennie 03:00. Zegar VPS drifts, cron uruchamia sie 2x. **Co sie dzieje?**

**Wymagane zachowanie:**
- Skrypt uzywa `flock` na lockfile
- Drugi process zwraca natychmiast bez bledu

**Test:** Uruchom 2x rownolegle, sprawdz że tylko jeden dump powstal.

### 7.14 GPG passphrase mismatch

Backup szyfrowany kluczem A, ale w `/etc/pb/backup.key` jest klucz B (po manual error). **Co sie dzieje?**

**Wymagane zachowanie:**
- Skrypt `pg-backup.sh` weryfikuje *zaraz po szyfrowaniu* ze potrafi odszyfrowac (round-trip)
- Jezeli round-trip fail: dump skasowany, alert, exit 1

**Test:** Manipuluj klucz, sprawdz ze backup failuje cleaned.

### 7.15 Brak monitoringu monitoringu (UptimeRobot down)

UptimeRobot sam ma awarie. **Co sie dzieje?**

**Wymagane zachowanie:**
- **Dwa** niezalezne monitory: UptimeRobot + Better Stack
- Jezeli jeden alertuje a drugi nie → moze to byc problem monitoringu, nie aplikacji
- Daniel sprawdza recznie

---

## 8. Definition of Done (per task)

Każdy task z grup A-H spełnia 10 kryteriow:

1. **Red test first.** Test pokazuje brak feature → fail. Implementacja → pass.
2. **No new top-level dependencies bez approval** (Daniel akceptuje `micrometer-registry-prometheus` osobno).
3. **No secrets in code.** Wszystkie tokens / keys w env vars.
4. **No secrets in logs.** Test "secret leak" musi passowac.
5. **DOTYKAJ zone respected.** PR diff nie modyfikuje plikow z NIE RUSZAJ.
6. **Docs updated.** Runbook .md zaktualizowany jezeli dotyczy.
7. **Smoke test on test server.** Po deploy na `properbackup-test-server.softify.com.pl` task ma byc weryfikowany.
8. **Idempotent (jezeli dotyczy).** Skrypty cron musza byc bezpieczne do wielokrotnego uruchomienia.
9. **Telemetry.** Każdy nowy worker / cron ma swoj metric i alert.
10. **Rollback plan.** PR opisuje *jak* cofnąc zmiane jezeli psuje produkcje.

---

## 9. Skrypty operacyjne — biblioteka

### 9.1 `pg-backup.sh`
(zobacz `[OBS-E1]`)

### 9.2 `pg-restore.sh`

```bash
#!/usr/bin/env bash
# Restore z encrypted dumpa. Wymaga: $BACKUP_FILE i klucza w /etc/pb/backup.key
set -euo pipefail

BACKUP_FILE="${1:?usage: $0 <encrypted-dump>}"

# Confirm action
read -p "RESTORE WILL OVERWRITE PRODUCTION DB. Type 'yes-i-am-sure': " ANSWER
[ "$ANSWER" = "yes-i-am-sure" ] || exit 1

# Stop buffer
docker compose stop buffer

# Backup current state (safety)
docker compose exec -T db pg_dump -U properbackup properbackup \
  | gzip > "/var/backups/pre-restore-$(date +%s).sql.gz"

# Drop + recreate
docker compose exec db psql -U postgres -c "DROP DATABASE properbackup;"
docker compose exec db psql -U postgres -c "CREATE DATABASE properbackup OWNER properbackup;"

# Decrypt + restore
gpg --decrypt --batch --passphrase-file /etc/pb/backup.key "$BACKUP_FILE" \
  | gunzip \
  | docker compose exec -T db psql -U properbackup properbackup

# Start buffer
docker compose start buffer

# Smoke check
sleep 10
curl -fsS http://localhost:7100/health | grep -q '"status":"healthy"' || {
  echo "ERROR: buffer not healthy after restore" >&2
  exit 1
}

echo "Restore complete."
```

### 9.3 `pg-restore-drill.sh`

Kwartalny drill na separate staging VPS. Procedura w `runbook-restore-drill.md`.

### 9.4 `daily-digest.sh`

Cron 09:00 codziennie, wysyla Slack message z biz metrykami.

### 9.5 `cleanup-old-logs.sh`

Cron 04:00 codziennie, kasuje rekordy z `stripe_event_idempotency` starsze niz 90 dni, `agent_metrics` starsze niz 30 dni, etc. (cross-ref `master-tdd-plan.md` sekcja 9.7).

---

## 10. Sequence of work (rekomendowana kolejnosc implementacji)

Przyszly agent **powinien** implementowac w tej kolejnosci:

1. **`[OBS-E1]` PostgreSQL backup script + cron + B2 upload** — bo bez tego nie powinno sie isc live z prawdziwymi platnoscami
2. **`[OBS-E3]` Restore runbook** — z odpalonym manual drill — *sprawdz ze backup naprawde dziala*
3. **`[OBS-A1]` /health rozszerzone + `[OBS-A3]` /live + `[OBS-A4]` /ready** — minimum dla orchestration
4. **`[OBS-D1]` Krytyczne alerty (P0) + Slack integration** — żeby cokolwiek bylo widac
5. **`[OBS-G1]` Status page (Better Stack free)** — komunikacja z klientem
6. **`[OBS-B1]` Structured JSON logging** — bez tego debug w produkcji to slepa uliczka
7. **`[OBS-B3]` Centralne logi (Better Stack)** — zeby moc grep'owac
8. **`[OBS-C1]` Metryki Prometheus format** — fundament dla grafiki / dashboardow
9. **`[OBS-F1]` + `[OBS-F2]` + `[OBS-F3]` Incident response runbooki** — gdy juz masz logi/metryki/alerty, to pisz playbooki
10. **`[OBS-H1]` Cost monitoring** — żeby nie zbankrutowac przez OVH spike

---

## 11. Go/No-Go checklist przed flipnieciem na live

- [ ] `pg-backup.sh` dziala 7 dni z rzedu bez bledu
- [ ] **Restore drill przeszedl** (probowales przywrocic baze z dumpa na staging) — bez tego nie idz live
- [ ] Klucz GPG w 1Password z aliasem
- [ ] `/health`, `/live`, `/ready` zaimplementowane i odpytywane przez UptimeRobot
- [ ] Slack webhook integracja dziala (test message)
- [ ] SMS alert dziala (Twilio sandbox test)
- [ ] Status page na `status.properbackup.pl` zywy
- [ ] Logback JSON profile aktywny w produkcji
- [ ] Logi z ostatnich 7 dni widoczne w Better Stack
- [ ] `/metrics` zwraca dane (sprawdz ręcznie)
- [ ] Daily digest cron zaplanowany, pierwsza wiadomosc poszla
- [ ] Cost alert ustawiony na OVH (>X GB/dzien)
- [ ] Incident response runbook **przeczytany przez Daniela na glos**, każdy krok ma sens
- [ ] SLO/SLA documents merged
- [ ] Status page ma 3+ monitorowane endpointy

Tylko po ✓ wszystkich powyzszych: flipnij feature flag, wpusc pierwszego prawdziwego usera.

---

## Dodatek A — Stack zalecenia z konkretnymi cenami

| Komponent | Stack | Cena MVP |
|-----------|-------|----------|
| Off-server backup | Backblaze B2 (1GB free, 0.005 USD/GB) | ~1 USD/mies |
| Encryption | GPG symmetric (free) | 0 |
| Heartbeat | healthchecks.io free tier | 0 |
| Uptime monitoring | UptimeRobot free + Better Stack free | 0 |
| Status page | Better Stack free | 0 |
| Slack | Slack free tier | 0 |
| SMS alerts | Twilio Pay-as-you-go | ~0.05 USD/SMS |
| Logi | Better Stack free 1GB/mies | 0 |
| Error tracking | Sentry free 5K events/mies | 0 |
| Metryki dashboard | Self-hosted Grafana (post-MVP) | 0 (na VPS) |
| APM | (nie potrzebne na MVP) | 0 |

**Total MVP koszt: ~1-3 USD/mies.** Skalujemy gdy mamy >100 klientow.

## Dodatek B — Linki do innych Master Planow

- `master-tdd-plan.md` — billing/Stripe
- `agent-vps-master-spec.md` — agent VPS resilience
- `ovh-cloud-archive-migration-spec.md` — migracja na produkcyjny storage
- `buffer-core-master-spec.md` — chunk lifecycle non-billing
- `ci-cd-release-pipeline-spec.md` — CI/CD
- `crypto-and-compliance-spec.md` — RODO/DPA

## Dodatek C — Glosariusz

- **RPO** — Recovery Point Objective. Max akceptowalna utrata danych.
- **RTO** — Recovery Time Objective. Max czas do przywrocenia uslugi.
- **MTTR** — Mean Time To Repair. Sredni czas naprawy.
- **SLO** — Service Level Objective. Wewnetrzny cel.
- **SLA** — Service Level Agreement. Kontrakt z klientem.
- **SEV** — Severity. Klasyfikacja powagi incydentu.
- **Postmortem** — Blameless review po incydencie.
- **DLQ** — Dead Letter Queue. Zobacz `master-tdd-plan.md`.
- **WAL** — Write-Ahead Log w PostgreSQL.
- **Heartbeat** — Cron job ktory pinguje healthchecks.io żeby udowodnic ze dziala.
