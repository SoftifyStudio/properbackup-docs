# Recovery Mode E2E Videos

Playwright recordings from live recovery E2E tests on dedyk (51.255.93.127).
Last run: 2026-06-21 14:15 UTC — real agent restore flow (delete → recovery → agent → SHA-256 verify).

## Test Videos

| # | Test | Assertion | File | Status |
|---|------|-----------|------|--------|
| 11 | Recovery Start | state=PLANNING, audit 2 entries with timestamps | `test11-recovery-start.webm` | **PASSED** |
| 12 | DRY RUN Preview (HR-4) | dry_run_files_to_restore=4, total_bytes=525475 | `test12-dry-run-preview.webm` | **PASSED** |
| 13 | Confirm and Restore | **DELETE→RESTORE→SHA-256 MATCH 4/4** via real agent. state=DONE, files_restored=4, bytes=262383 | `test13-confirm-and-restore.webm` | **PASSED** |
| 14 | Per-Server Lockdown (HR-2) | 0 active sessions on other servers, 409 on same server | `test14-per-server-lockdown.webm` | **PASSED** |
| 15 | Cancel (HR-9) | state=CANCELLED, cancelled_at set, audit RECOVERY_CANCELLED | `test15-cancel-mid-restore.webm` | **PASSED** |
| 16 | THAWING Bypass | state=READY, latency=160ms (<10s), cold_tier=false | `test16-thawing-passthrough.webm` | **PASSED** |
| 17 | Concurrent 409 | second start → 409 RECOVERY_ALREADY_ACTIVE, 1 active session | `test17-concurrent-409.webm` | **PASSED** |
| 18 | Pre-Recovery Snapshot (HR-5) | pre_recovery_snapshot_id=NULL, no PRE_RECOVERY snapshot | `test18-pre-recovery-snapshot.webm` | **FAILED** [AGENT] |

Edge cases (5/5 PASSED, API-only, no video):
- Invalid snapshot ID → [TRIAGE:BUFFER] 500 instead of 400/404
- Cancel from AWAITING_USER_CONFIRM → clean CANCELLED
- Illegal state transition (confirm from PLANNING) → 400
- Audit log completeness: 5+ entries with timestamps
- **Corrupted file SHA-256 detection (HR-7)** → agent restored corrupted readme.txt to correct hash

**Summary: 12/13 PASSED, 1/13 FAILED (test18 blocked on AGENT HR-5)**

## test13 — DELETE → RESTORE → SHA-256 MATCH (PASSED)

Real agent flow on live dedyk:
1. Recorded SHA-256 of originals in `/opt/pb-agent-e2e/restore-target/`
2. **DELETED all 4 files** from restore target
3. Started recovery via API → PLANNING → DRY_RUN → CONFIRM → READY (162ms)
4. **Triggered real agent** (`--once --headless`)
5. Agent polled buffer, downloaded pack, decrypted AES-256-GCM, extracted tar.gz
6. **4/4 files physically restored** to disk with correct SHA-256:

| File | Original SHA-256 | Restored SHA-256 | Match |
|------|-----------------|------------------|-------|
| readme.txt | `fc794d75` | `fc794d75` | YES |
| config-sample.txt | `7fad13a1` | `7fad13a1` | YES |
| db-dump.sql | `68d82171` | `68d82171` | YES |
| random-256k.bin | `e72abfba` | `e72abfba` | YES |

DB: `state=DONE, files_restored=4, bytes=262383, completed_at=2026-06-21 14:15:53`

## test18 — Why FAILED [TRIAGE:AGENT]

`recovery_session.pre_recovery_snapshot_id` is NULL after DONE. No `archive_snapshot` row with `snapshot_type=PRE_RECOVERY` created. HR-5 requires agent to create pre-recovery snapshot BEFORE AGENT_RESTORING.

Will turn PASSED when agent implements pre-recovery snapshot creation.

## edge HR-7 — Corrupted File Detection (PASSED)

1. Corrupted `readme.txt` on disk (wrote garbage, hash `19bc67ee`)
2. Triggered recovery with real agent
3. Agent restored file to correct SHA-256 `fc794d75`
4. Proves: agent actually decrypts+verifies content, not just copies

## Triaged Issues

| Issue | Owner | Detail |
|-------|-------|--------|
| No PRE_RECOVERY snapshot (test18 FAILED, HR-5) | **[AGENT]** | Agent does not create pre-recovery snapshot; `pre_recovery_snapshot_id=NULL` |
| Invalid snapshot ID → 500 | **[BUFFER]** | `RecoveryHandler.startRecovery()` does not validate `target_snapshot_id` in `archive_snapshot` |
| Recovery Mode UI not visible | **[WEB]** | Deployed dist is from main (pre-PR#50); Recovery components not in build |

## How to regenerate

```bash
cd properbackup-web
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js
# Videos auto-saved to test-results/recovery-qa/
```
