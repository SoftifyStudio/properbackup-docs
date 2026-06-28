# 3. Co jest zrobione, co w toku, co zostało

> Stan na 2026-06-28. To skrót orientacyjny — szczegóły w `../architecture/` i w PR-ach repo.

## ✅ Gotowe (zaimplementowane i testowane)
- **Agent**: skan + dedup (DifferentialScanner, 4 MB chunki), AES-256-GCM, jlinkDist (~61 MB), tryb serwis (systemd) + aktywacja kodem, IoThrottle (dławienie CPU/I-O), resumable upload.
- **Buffer**: persistent-first, paczki 900–950 MB, `BudgetGuard` + `StorageQuotaGuard` (fail-safe), Audit PDF.
- **Storage local-FS**: `LocalFsStorageClient` → zapis na `/mnt/storage` (pivot z Cloud Archive zrobiony).
- **Recovery Mode (Time Machine)**: state machine, DRY RUN, pre-recovery snapshot, instant restore, banner per-serwer. E2E + nagrania (`../e2e-videos/`).
- **Web panel**: login/rejestracja/aktywacja, timeline, 1-Click Restore, monitoring, i18n.
- **Płatności (Stripe)**: trial 30 dni, checkout, downgrade-logic, dunning, per-user key isolation — z hardeningiem E2E.

## 🟡 W toku / wymaga domknięcia
- **Pełny zintegrowany E2E na docelowym dedyku, na NAJNOWSZYM kodzie**: agent → buffer → pack → `/mnt/storage` → restore → weryfikacja SHA-256. Na serwerze stoi dziś **stary, ręcznie złożony build** (patrz [`../architecture/deployment-dedicated-server.md`](../architecture/deployment-dedicated-server.md) §4/§6).
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
