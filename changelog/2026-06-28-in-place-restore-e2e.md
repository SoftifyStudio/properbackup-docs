# 2026-06-28 — In-place restore (cofnięcie na osi czasu): E2E + naprawa kodu

## Po co
Wcześniejszy test odzyskiwania (test01) przechodził ścieżką **„Download and decrypt"** —
panel pobierał zaszyfrowany `.tar.gz` na dysk użytkownika i deszyfrował go w przeglądarce.
To NIE jest obietnica produktu. Klient ma kliknąć **„Przywróć"** na osi czasu, a stan
z danego snapshotu ma wrócić **w miejscu na serwerze** (agent zapisuje pliki z powrotem do
oryginalnych ścieżek), niezawodnie — literalne „cofnięcie na osi czasu”.

## Diagnoza (sedno problemu)
Prawdziwy in-place restore **był napisany, ale nigdy nie trafił do `main`** (ten sam wzorzec
co zgubiony PR #27):
- **buffer (`main`)** — pełny backend recovery ISTNIAŁ i był wdrożony (state machine
  `REQUESTED→PLANNING→AWAITING_USER_CONFIRM→READY→AGENT_RESTORING→VERIFYING→DONE`,
  `PreRecoverySnapshotCreator`, DryRun). ✅
- **web (`main`)** — BRAK przycisku „Przywróć na serwer"; tylko `RecoveryWizard`
  (Download and decrypt). Pełne UI Recovery Mode było w niezmergowanej gałęzi.
- **agent / shared (`main`)** — BRAK restore-protocol (agent nie pobierał snapshotu i nie
  zapisywał plików z powrotem). Kod tylko w gałęziach.

## Co zrobione
- Wybrano **jeden kanon** implementacji agenta (restore-protocol, który deszyfruje pack,
  rozpakowuje i zapisuje pliki do oryginalnych ścieżek; `SnapshotDiff` kasuje pliki dodane po
  snapshocie, `CriticalPathsGuard` chroni ścieżki systemowe). Druga, niekompletna
  implementacja odrzucona.
- Zintegrowano UI Recovery Mode do `web` i wdrożono na LXC 100 (przycisk „Przywróć” na
  Timeline → start modal → dry-run → confirmation modal → progress overlay → DONE).
- Zbudowano **test02 — in-place restore E2E** (Playwright, UI-driven, wbudowane nagrywanie).

### Semantyka (zatwierdzona)
Literalne cofnięcie na osi czasu: po przywróceniu snapshotu S1 katalog objęty backupem
wygląda 1:1 jak w S1 — pliki **zmienione** cofnięte, **usunięte** odtworzone, **dodane po S1
skasowane**. Ścieżki systemowe chronione (`CriticalPathsGuard`); nic poza scope backupu nie
jest kasowane.

## 3 naprawione błędy (red-first, w KODZIE — nie obejścia)
1. **shared** — `RestoreOrchestrator.executeDryRun` bez fallbacku; agent padał na dry_run
   (buffer nie ma `/agent/snapshot/{id}/files` → 404). Dodano `deriveSnapshotFilesFromArchive`
   (pobiera pack → deszyfruje → liczy listę plików — to samo źródło prawdy co restore).
2. **buffer** — brak `POST /agent/recovery/{id}/started`; sesja utykała w `READY`
   (READY→VERIFYING nielegalne). Dodano handler `READY→AGENT_RESTORING` + `/pre_snapshot`
   (HR-5) + `id` w listingu `archive_snapshot` (bez tego przycisk „Przywróć” był no-opem).
3. **web** — backend dochodził do DONE, ale UI tego nie pokazywał: SSE niesie identyfikator
   jako `sessionId`, a overlay/REST używają `id` → overlay nie miał id do pollowania, kontekst
   kasował sesje terminalne. Normalizacja `id`←`sessionId` + latch id w overlayu.

Agent: bez zmian kodu (wiring był już poprawny na gałęzi restore-protocol).

## Dowód (test02 — zielony 2× pod rząd, workers=1, ~55 s)
UI: login formularzem → Timeline → klik „Przywróć” → dry-run (restore 2 / delete 1) →
confirm → AGENT_RESTORING → VERIFYING → **DONE** („Recovery Mode — Completed successfully”).

Twarde asercje **na serwerze** (przez `pct exec 100` na LXC 100, NIE w UI):
- `sha256sum` plików w katalogu źródłowym == zestaw SHA-256 ze snapshotu S1,
- plik dodany po S1 (`file-added-after-s1.txt`) **nie istnieje** (literalne cofnięcie),
- PostgreSQL: `recovery_session.state='DONE'`,
- `pre_recovery_snapshot_id` istnieje i jest typu `PRE_RECOVERY` (rollback safety).

Nagranie: `e2e-videos/2026-06-28-backup-core-pipeline/test02-in-place-restore.webm`
(test01 nietknięty). Kod testu: `properbackup-web/tests/e2e/in-place-restore-e2e.spec.js`
+ helper `tests/e2e/helpers/dedyk.js` (SSH→`pct exec 100`, `sha256sum`, `psql`).

## PR-y (do ręcznego merge — Devin nie merguje)
Prawdziwa funkcja leżała w niezmergowanych gałęziach, więc do wdrożenia w `main` trzeba
zmergować łańcuch w kolejności:

1. **shared #21** (restore-protocol) → **shared #22** (dry-run fallback; oparty na #21)
2. **agent #18** (restore-protocol — żeby agent z `main` miał protokół)
3. **buffer #44** (fix state machine; base `main`; **zastępuje** wcześniejszy buffer #43)
4. **web #54** (agent-driven restore UI + test02 E2E; base `main`; zawiera całe UI,
   **zastępuje** web #51 / #50)
5. **docs #33** (nagranie test02 + README) — *już zmergowane*

Uwagi:
- `web #54` może pokazywać status „unstable” tylko dlatego, że repo nie ma CI (brak checków) —
  nie z powodu błędu.
- Zdublowane/zastąpione PR-y do zamknięcia: buffer #43, web #51, web #50.

## Twarde zasady utrzymane
LXC 100 wyłącznie (kontener Minecraft CT102 nietknięty), Playwright z wbudowanym nagrywaniem,
write-back nagrań do `e2e-videos/` (append-only, test01 nienadpisany), red-first, zielony 2×,
asercje DB-first + SHA-256 na serwerze, brak podkręcania testów pod zielony pasek.
