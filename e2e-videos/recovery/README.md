# Recovery Mode E2E Videos

Playwright recordings from live recovery E2E tests on dedyk (51.255.93.127).
Last run: 2026-06-21 12:57 UTC (buffer restarted 12:35).

## Test Videos

| # | Test | DB Assertion | File | Status |
|---|------|-------------|------|--------|
| 11 | Recovery Start | state=PLANNING, audit 2 entries with timestamps | `test11-recovery-start.webm` | PASSED |
| 12 | DRY RUN Preview (HR-4) | dry_run_files_to_restore=4, total_bytes=525475, audit detail `files_to_restore=4` | `test12-dry-run-preview.webm` | PASSED |
| 13 | Confirm and Restore | DB: state=DONE, files_restored=4, completed_at set. **FILES NOT ON DISK** | `test13-confirm-and-restore.webm` | **FAILED** [AGENT] |
| 14 | Per-Server Lockdown (HR-2) | 0 active sessions on other servers, 409 on same server | `test14-other-server-banner.webm` | PASSED |
| 15 | Cancel (HR-9) | state=CANCELLED, cancelled_at set, confirmed_at set, audit RECOVERY_CANCELLED | `test15-cancel-during-restoring.webm` | PASSED |
| 16 | THAWING Bypass | state=READY, latency=160ms (<10s), thaw_started_at=NULL, thaw_completed_at set | `test16-cold-tier-thaw.webm` | PASSED |
| 17 | Concurrent 409 | second start -> 409 RECOVERY_ALREADY_ACTIVE, DB 1 active session, state=PLANNING | `test17-concurrent-recovery-409.webm` | PASSED |
| 18 | Pre-Recovery Snapshot (HR-5) | pre_recovery_snapshot_id=NULL, no PRE_RECOVERY in archive_snapshot | `test18-pre-recovery-rollback.webm` | **FAILED** [AGENT] |

Edge cases (4/4 PASSED, API-only, no video):
- Invalid snapshot ID -> [TRIAGE:BUFFER] 500 instead of 400/404
- Cancel from AWAITING_USER_CONFIRM -> clean CANCELLED
- Illegal state transition (confirm from PLANNING) -> 400
- Audit log completeness: 5+ entries with timestamps

**Summary: 10/12 PASSED, 2/12 FAILED (blocked on AGENT)**

## Why test13 and test18 are FAILED (not PASSED)

**test13** — DB shows `state=DONE, files_restored=4` but files are NOT physically on the dedyk filesystem (`/home/ubuntu/agent-e2e/test-data/`). The DB counter alone is NOT sufficient proof of restore. Hard assertion: `expect(fileExistsOnDedyk(path)).toBe(true)` + SHA-256 match.

**test18** — `recovery_session.pre_recovery_snapshot_id` is NULL after DONE. No `archive_snapshot` row with `snapshot_type=PRE_RECOVERY` exists. HR-5 requires agent to create pre-recovery snapshot before AGENT_RESTORING.

Both will turn PASSED when: agent runs real restore on dedyk -> files appear on disk with correct SHA-256 -> pre-recovery snapshot created in DB.

## Triaged Issues

| Issue | Owner | Detail |
|-------|-------|--------|
| Files not restored to disk (test13 FAILED) | [AGENT] | Agent container not running on dedyk; DB says DONE but no physical file I/O |
| No PRE_RECOVERY snapshot (test18 FAILED, HR-5) | [AGENT] | Agent does not create pre-recovery snapshot; `pre_recovery_snapshot_id=NULL` |
| Invalid snapshot ID -> 500 | [BUFFER] | `RecoveryHandler.startRecovery()` does not validate `target_snapshot_id` in `archive_snapshot` |
| Recovery Mode UI not visible | [WEB] | Deployed dist is from main (pre-PR#50); Recovery components not in build |

## How to regenerate

```bash
cd properbackup-web
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js
node tests/e2e/helpers/uploadVideos.js
```
