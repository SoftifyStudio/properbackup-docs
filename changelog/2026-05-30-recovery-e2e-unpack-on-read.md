# 2026-05-30 — Recovery E2E + Unpack-on-Read

**PRy:** buffer#24 (Recovery Session API), buffer#25 (unpack-on-read), web#34 (Playwright E2E recovery), web#35 (natywne wideo + SHA-256 verify), docs#20 (wideo recovery)
**Sesje:** Playwright E2E restore sessions

## Co zostalo dodane/zmienione

### Unpack-on-Read (properbackup-buffer)

Problem: po `ChunkSealer.seal()` indywidualny plik z `LocalObjectStore` byl kasowany, a dane ladowaly do packa (`PackBuffer`). `ObjectReadFacade` nie widzial plikow w packach — restore zwracal 404.

Rozwiazanie:
- **`ObjectReadFacade.getMerged()`** — nowy fallback chain: `local → packBuffer → archive`. Jesli plik nie istnieje jako osobny blob, szuka go w packu, a na koniec w archiwum (OVH/mock).
- **`PackBuffer.readObjectFromAnyServer(objectName)`** — skanuje packi we wszystkich katalogach serwerow. Endpointy `/objects/{name}` i `RestoreVerifier` nie musza znac `serverId`.
- **`BufferMain.kt`** — `ObjectReadFacade` dostaje `packBuffer` w konstruktorze.
- **Fail-safe** — brak obiektu = jawny 404, brak cichego pomijania.

### Recovery Session API (properbackup-buffer)

Implementacja sekcji B ze specyfikacji `user-facing-recovery-spec.md`:
- **State machine** — 10 stanow sesji recovery (CREATED → VALIDATING → READY → DOWNLOADING → ... → COMPLETED/FAILED)
- **Store** — `RecoverySessionStore.kt` (PostgreSQL CRUD + status transitions)
- **Guard** — per-server lockdown podczas aktywnej sesji recovery
- **HTTP endpoints** — `POST /recovery/sessions`, `GET /recovery/sessions/{id}`, `POST /recovery/sessions/{id}/start`

### Playwright E2E Recovery Test (properbackup-web)

Dwa testy na zywym serwerze testowym (`properbackup-test-server.softify.com.pl`):

| # | Test | Opis | Status |
|---|------|------|--------|
| 1 | API restore | Bezposredni GET na endpoint → pobranie pliku → SHA-256 verify | PASS |
| 2 | UI restore | Login → Timeline → klik snapshot → Download → AES-256-GCM decrypt → tar xzf → SHA-256 = oryginal (`c985a725...dbe32`) | PASS |

- **Natywne wideo Playwright** — `playwright.config.js` z `outputDir: 'test-results'`, video recording per test.
- **SHA-256 integrity** — hash oryginalnego pliku policzony przed backupem, porownany z plikiem po restore. Zero halucynacji — twarde dowody.
- **Klauzula uczciwosci** — agent nie moze mockowac SHA-256, skipowac testow ani oslabiach asercji.

### Nagranie E2E (properbackup-docs)

- `e2e-videos/2026-05-30-recovery/test01-recovery-restore.webm` — natywne wideo Playwright z testu UI restore.
- Wpis w `e2e-videos/README.md` — tabela z wynikami.

## Pliki zmienione

### properbackup-buffer
- `ObjectReadFacade.kt` — nowy fallback chain (local → pack → archive)
- `PackBuffer.kt` — `readObjectFromAnyServer(objectName)`
- `BufferMain.kt` — wiring packBuffer do ObjectReadFacade
- `RecoverySessionStore.kt` — nowy plik (state machine + PostgreSQL)
- `RecoverySessionGuard.kt` — nowy plik (per-server lockdown)
- `RecoveryHandler.kt` — nowy plik (HTTP endpoints)

### properbackup-web
- `tests/e2e/recovery-e2e.spec.js` — 2 testy (API + UI restore)
- `playwright.config.js` — `outputDir`, video recording

### properbackup-docs
- `e2e-videos/2026-05-30-recovery/test01-recovery-restore.webm`
- `e2e-videos/README.md` — sekcja "Videos (2026-05-30 — recovery restore)"
