# Recovery Mode E2E Testing — Playwright QA Skill

## When to use this skill
When testing Recovery Mode end-to-end on the live dedyk (51.255.93.127).
Use this for regression testing after any change to buffer, agent, shared, or web recovery code.

## Prerequisites
- SSH access to dedyk: `$OVH_DEDICATED_SERVER_PROXMOX_ROOT_PASSWORD` set
- Buffer running on `:8080`, web panel on `:80`
- PostgreSQL running in Docker on dedyk
- At least one archive_snapshot for e2e-user-001 / server 194efe2e...
- `sshpass` installed locally

## How to run

```bash
cd properbackup-web

# Full QA suite (all 8 tests + edge cases):
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js

# Single test:
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js -g "test11"

# With custom dedyk host:
DEDYK_HOST=51.255.93.127 npx playwright test --config tests/e2e/playwright.recovery-qa.config.js
```

## Test structure

| Test | Name | What it verifies |
|------|------|-----------------|
| 11 | recovery-start | API creates session, DB state=PLANNING, audit log entry |
| 12 | dry-run-preview | DRY RUN file counts in DB, checkbox enforcement (HR-4) |
| 13 | confirm-and-restore | Full happy path to DONE, SHA-256 on disk, pre-recovery snapshot (HR-5) |
| 14 | per-server-lockdown | Other servers unaffected, warning banner (HR-2) |
| 15 | cancel-during-restoring | Cancel → CANCELLED state, rollback (HR-9) |
| 16 | cold-tier-thaw | THAWING bypass with cold_tier=false, latency <10s |
| 17 | concurrent-recovery-409 | Second recovery attempt → 409 conflict |
| 18 | pre-recovery-rollback | PRE_RECOVERY snapshot visible after DONE (HR-5) |

Edge cases: bad snapshot ID, cancel from AWAITING_USER_CONFIRM, illegal state transition, audit log completeness.

## Assertions strategy
- **DB-first**: Every test checks PostgreSQL directly (via SSH → docker exec → psql), NOT just UI
- **Files-on-disk**: SHA-256 of restored files computed on dedyk filesystem
- **API-verified**: State machine transitions checked via buffer API responses
- **UI-last**: UI assertions are secondary — if UI not deployed, tests still verify API+DB

## Triage labels
When a test fails, console output includes triage labels:
- `[TRIAGE:BUFFER]` — fix in properbackup-buffer (API, state machine, DB schema)
- `[TRIAGE:AGENT]` — fix in properbackup-agent (restore protocol, file ops)
- `[TRIAGE:WEB]` — fix in properbackup-web (UI components, routing)
- `[TRIAGE:INFRA]` — fix in infrastructure (SSH, Docker, PostgreSQL, networking)

## Video output
Videos are recorded automatically for every test:
- Location: `tests/e2e/test-results/recovery-qa/`
- Format: `.webm` (Playwright default)
- Copy to docs: `cp tests/e2e/test-results/recovery-qa/*/video.webm ../properbackup-docs/e2e-videos/recovery/testNN-<name>.webm`

## Common pitfalls
- Tests clean recovery_session table per-server before each test (beforeEach hook)
- If tests hang: check SSH connectivity to dedyk and Docker health
- JWT token has a long expiry but may need refresh if dev secret changes
- The buffer has a known gap: READY→AGENT_RESTORING not auto-triggered by poll. Tests work around this.
- If web panel shows old UI (no RecoveryMode components), that's expected until PR#50 dist is deployed
