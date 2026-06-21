# Recovery Mode E2E Videos

Playwright recordings from live recovery E2E tests on dedyk (51.255.93.127).

## Test Videos

| # | Test | File | Status |
|---|------|------|--------|
| 11 | Recovery Start | `test11-recovery-start.webm` | pending |
| 12 | DRY RUN Preview | `test12-dry-run-preview.webm` | pending |
| 13 | Confirm and Restore | `test13-confirm-and-restore.webm` | pending |
| 14 | Other Server Banner | `test14-other-server-banner.webm` | pending |
| 15 | Cancel During Restoring | `test15-cancel-during-restoring.webm` | pending |
| 16 | Cold Tier Thaw | `test16-cold-tier-thaw.webm` | pending |
| 17 | Concurrent Recovery 409 | `test17-concurrent-recovery-409.webm` | pending |
| 18 | Pre-Recovery Rollback | `test18-pre-recovery-rollback.webm` | pending |

## How to regenerate

```bash
cd properbackup-web
npx playwright test --config tests/e2e/playwright.recovery-qa.config.js
# Then copy videos:
# cp tests/e2e/test-results/recovery-qa/*/video.webm ../properbackup-docs/e2e-videos/recovery/
```
