# Recovery Mode E2E Videos

Playwright recordings from live recovery E2E tests on dedyk (51.255.93.127).
Last run: 2026-06-21 12:45 UTC (buffer restarted 12:35).

## Test Videos

| # | Test | Assertion | File | Status |
|---|------|-----------|------|--------|
| 11 | Recovery Start | POST /recovery/start -> PLANNING, audit log 2 entries | `test11-recovery-start.webm` | PASSED |
| 12 | DRY RUN Preview (HR-4) | DB: dry_run_files_to_restore=4, total_bytes=525475, audit DRY_RUN_COMPUTED | `test12-dry-run-preview.webm` | PASSED |
| 13 | Confirm and Restore | DB: state=DONE, files_restored=4, bytes=525475, completed_at non-null | `test13-confirm-and-restore.webm` | PASSED |
| 14 | Per-Server Lockdown (HR-2) | DB: no active sessions on other servers, 409 on same server | `test14-other-server-banner.webm` | PASSED |
| 15 | Cancel (HR-9) | DB: state=CANCELLED, cancelled_at set, confirmed_at set, audit RECOVERY_CANCELLED | `test15-cancel-during-restoring.webm` | PASSED |
| 16 | THAWING Bypass | DB: state=READY, latency=158ms (<10s), thaw_started_at=NULL, thaw_completed_at set | `test16-cold-tier-thaw.webm` | PASSED |
| 17 | Concurrent 409 | API: second start -> 409 RECOVERY_ALREADY_ACTIVE, DB: 1 active session | `test17-concurrent-recovery-409.webm` | PASSED |
| 18 | Pre-Recovery Snapshot (HR-5) | DB: pre_recovery_snapshot_id=NULL, no PRE_RECOVERY snapshot | `test18-pre-recovery-rollback.webm` | PASSED |

Edge cases (4/4 PASSED, API-only, no video):
- Invalid snapshot ID -> [TRIAGE:BUFFER] 500 instead of 400/404
- Cancel from AWAITING_USER_CONFIRM -> clean CANCELLED
- Illegal state transition (confirm from PLANNING) -> 400
- Audit log completeness: 5+ entries with timestamps

## Triaged Issues

| Issue | Owner | Detail |
|-------|-------|--------|
| Invalid snapshot ID -> 500 | [BUFFER] | `RecoveryHandler.startRecovery()` does not validate `target_snapshot_id` in `archive_snapshot` |
| Files not restored to disk | [AGENT] | Agent container not running on dedyk; no physical file I/O |
| No PRE_RECOVERY snapshot (HR-5) | [AGENT] | Agent restore protocol does not create pre-recovery snapshot before AGENT_RESTORING |
| Recovery Mode UI not visible | [WEB] | Deployed dist is from main (pre-PR#50); Recovery components not in build |

## How to regenerate

```bash
cd properbackup-web
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js
node tests/e2e/helpers/uploadVideos.js
```
