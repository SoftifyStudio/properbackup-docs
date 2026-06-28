# 3. Co jest zrobione, co w toku, co zostało

> Stan na 2026-06-28. To skrót orientacyjny — szczegóły w `../architecture/` i w PR-ach repo.

## ✅ Gotowe (zaimplementowane i testowane)
- **Agent**: skan + dedup (DifferentialScanner, 4 MB chunki), AES-256-GCM, jlinkDist (~61 MB), tryb serwis (systemd) + aktywacja kodem, IoThrottle (dławienie CPU/I-O), resumable upload.
- **Buffer**: persistent-first, paczki 900–950 MB, `BudgetGuard` + `StorageQuotaGuard` (fail-safe), Audit PDF.
- **Storage local-FS**: `LocalFsStorageClient` → zapis na `/mnt/storage` (pivot z Cloud Archive zrobiony).
- **Recovery Mode (Time Machine) — in-place restore zweryfikowany E2E**: klik „Przywróć" w panelu → recovery session przez state machine bufora → agent odtwarza stan snapshotu **w miejscu na serwerze** (literalne cofnięcie na osi czasu: zmienione cofnięte, usunięte odtworzone, dodane po snapshocie skasowane). DRY RUN, pre-recovery snapshot (rollback safety). Test02 UI-driven, zielony 2×, twarde asercje NA SERWERZE (SHA-256 == snapshot + DB `recovery_session='DONE'`) — nagranie `../e2e-videos/2026-06-28-backup-core-pipeline/test02-in-place-restore.webm`. Szczegóły + 3 naprawione błędy: [`../changelog/2026-06-28-in-place-restore-e2e.md`](../changelog/2026-06-28-in-place-restore-e2e.md).
  - ⚠ **Kod tej funkcji czeka na merge** (był w niezmergowanych gałęziach): buffer #44, shared #22, web #54, agent #18 + zależności — patrz changelog (kolejność merge).
- **Web panel**: login/rejestracja/aktywacja, timeline, 1-Click Restore, monitoring, i18n.
- **Płatności (Stripe)**: trial 30 dni, checkout, downgrade-logic, dunning, per-user key isolation — z hardeningiem E2E.

## 🟡 W toku / wymaga domknięcia
- **Pełny zintegrowany E2E na docelowym dedyku, na NAJNOWSZYM kodzie**: agent → buffer → pack → `/mnt/storage` → restore → weryfikacja SHA-256. Na serwerze stoi dziś **stary, ręcznie złożony build** (patrz [`../architecture/deployment-dedicated-server.md`](../architecture/deployment-dedicated-server.md) §4/§6). **Częściowo zrobione:** ścieżka in-place restore została zbudowana, wdrożona do LXC 100 i zweryfikowana E2E (test02, zielony 2×) — patrz changelog 2026-06-28.
- **Merge gałęzi recovery do `main`**: prawdziwy in-place restore działa, ale leży w PR-ach (buffer #44, shared #21→#22, agent #18, web #54). Do ręcznego merge przez Daniela wg kolejności w [`../changelog/2026-06-28-in-place-restore-e2e.md`](../changelog/2026-06-28-in-place-restore-e2e.md).
- **Quota „Opcja 2" w kodzie**: reguła +10%/mc, sufit 2× per tier — sprawdzić, czy `StorageQuotaGuard`/billing liczą zgodnie z kanonem ([`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md) A).
- **Offsite DR (kopia #2)**: na teraz prowizorka „byle gdzie zgrane" (jakakolwiek tania kopia + automat + testowy restore). Docelowo drugi serwer dedykowany (Proxmox Backup Server). OVH cold odrzucone (za drogie).
- **Waluta w panelu**: `properbackup-web` pokazuje USD — uspójnić z PLN.

## ⬜ Do zrobienia (przed „sprzedażą ze spokojną głową")
- Deploy najnowszego kodu na dedyk + zielony pełny E2E (powyżej).
- Landing marketingowy: dziś jest tryb „już wkrótce / zbieram chętnych" w `softify-website` (`/properbackup`) — do rozbudowy o dowody (Audit PDF demo, cennik finalny) przy starcie sprzedaży.
- Legal/RODO: DPA + umowa powierzenia dla offsite DR (drugi serwer/PBS) przed sprzedażą obcym.
- Dystrybucja (GTM): outreach do agencji WP/IT (patrz biznesplan).

## Uwaga o procesie
- **Brak CI** na repo — testy odpalane lokalnie.
- **Devin nie merguje** PR-ów do `main` — merge robi Daniel ręcznie.
