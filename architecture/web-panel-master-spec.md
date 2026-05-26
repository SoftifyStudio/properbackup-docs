# Web Panel — Master Plan (non-subscription)

Wersja: 1.0 (initial, pre-prod)
Repo: `properbackup-web` (React 19 + Vite + Tailwind, ~30 .jsx)
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P2**

---

## 1. Cel dokumentu

Plan dla **wszystkich elementow web panelu poza subscription/billingowymi** (te sa w `master-tdd-plan.md` `[TDD-F1]`, sekcja 9.3 ProcessingScreen). 

Obejmuje: timeline view, 1-Click Restore, audit PDF download, agent activation UI, alerts resolver, recovery wizard, monitoring tab, polish localization, accessibility.

Brat dokumentu `master-tdd-plan.md` (subscription UI), `buffer-core-master-spec.md` (HTTP API), `observability-and-dr-spec.md` (monitoring UI).

### Co JEST w zakresie

- Timeline/snapshot view per server
- 1-Click Restore wizard
- Audit PDF download UI
- Agent activation flow (UI dla token)
- Add Server modal
- Folder config panel
- Monitoring tab (CPU/RAM/storage usage)
- Alerts page (alerts resolution)
- Recovery wizard (orphan recovery, cold thaw progress)
- Layout: AppHeader, AdminModeBar, LanguageMenu
- i18n (Polish + English fallback)
- Tree directory view
- Crypto-side keys UI (klient klucz local-only)

### Co NIE jest w zakresie

- Subscription/billing UI (w `master-tdd-plan.md`)
- iOS/Android client (post-MVP)
- Marketing/landing page (osobny static site)
- B2B multi-tenant admin (post-MVP)

---

## 2. Mapowanie kodu

### 2.1 Struktura

```
properbackup-web/src/
├── App.jsx                          # router root
├── main.jsx                         # entry
├── alerts/
│   └── AlertResolver.jsx
├── api/                             # HTTP clients
├── auth/
│   ├── AuthContext.jsx              # JWT mgmt
│   ├── AuthLanding.jsx
│   ├── LoginPage.jsx
│   ├── RegisterPage.jsx
│   ├── PasswordStrengthPanel.jsx
│   └── ServiceAdminModal.jsx
├── crypto/                          # client-side encryption (Wyglada na key derivation UI)
├── fixtures/                        # mock data dla testow
├── i18n/
│   ├── I18nContext.jsx
│   └── bold.jsx                     # <Bold/> i18n helper
├── layout/
│   ├── AppHeader.jsx                # main nav
│   ├── AdminModeBar.jsx             # admin mode indicator
│   └── LanguageMenu.jsx
├── recovery/
│   ├── RecoveryWizard.jsx
│   ├── OrphanRecovery.jsx
│   └── ThawProgress.jsx
├── router/                          # routing helpers
├── servers/
│   ├── AddServerModal.jsx
│   ├── ServerCard.jsx
│   ├── SnapshotTimeline.jsx
│   ├── FolderConfigPanel.jsx
│   ├── AgentIndexBanner.jsx
│   └── MonitoringTab.jsx
├── subscription/                    # ← in master-tdd-plan.md
├── tree/
│   └── DirectoryView.jsx
├── bufferConfig.js                  # API base URL
└── index.css
```

### 2.2 Kluczowe routes (assumed z App.jsx)

| Route | Komponent | Status |
|-------|-----------|--------|
| `/` | Landing / dashboard | Istnieje |
| `/auth` | AuthLanding | Istnieje |
| `/login` | LoginPage | Istnieje |
| `/register` | RegisterPage | Istnieje |
| `/panel/processing` | ProcessingScreen (post-Checkout) | **BRAK** (cross-ref master-tdd-plan.md `[TDD-F1]`) |
| `/panel/servers` | List serverow | Istnieje |
| `/panel/servers/:id` | Server detail z timeline | Istnieje (sprawdz) |
| `/panel/servers/:id/restore` | RecoveryWizard | Istnieje |
| `/panel/billing` | SubscriptionPage | Istnieje |
| `/panel/admin` | AdminModeBar features | Istnieje |
| `/panel/audit` | Audit PDF generator | **BRAK / niekompletne** |

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ (zamrozone)

- `crypto/` — client-side encryption helpers (jezeli istnieja w postaci pomocnikow)
- `auth/AuthContext.jsx` JWT mgmt — semantics stabilna
- `bufferConfig.js` — API endpoint discovery
- Subscription UI (cross-ref `master-tdd-plan.md`)
- LemonSqueezy related (deprecated)

### DOTYKAJ (mozna modyfikowac)

- `App.jsx` — dodawac nowe routes (NIE usuwac istniejacych)
- `layout/AppHeader.jsx` — dodac nowe linki (Audit, Settings)
- `servers/SnapshotTimeline.jsx` — wzbogacić o restore-from-timeline action
- `recovery/RecoveryWizard.jsx` — 1-Click flow
- `servers/MonitoringTab.jsx` — wzbogacic
- `alerts/AlertResolver.jsx` — wzbogacic
- `i18n/I18nContext.jsx` — dodawac nowe klucze

### MOZESZ TWORZYC

- `subscription/ProcessingScreen.jsx` (cross-ref `master-tdd-plan.md` `[TDD-F1]`)
- `audit/AuditReportPage.jsx`
- `settings/SettingsPage.jsx` (preferences, language, etc.)
- `recovery/OneClickRestore.jsx`
- `monitoring/CostBreakdown.jsx`
- `support/SupportPage.jsx`
- Nowe routes w `App.jsx`
- Nowe i18n keys
- Nowe komponenty wspolne (Button, Modal, Toast) jezeli brak

---

## 4. Domain Model

### 4.1 Navigation tree (proponowana)

```
/panel
├── /servers                          # Lista serverow + ServerCard
│   ├── /:id                          # Detail z tabs (Files, Timeline, Monitoring, Config)
│   │   ├── /files                    # Tree view aktualny snapshot
│   │   ├── /timeline                 # SnapshotTimeline
│   │   ├── /monitoring               # MonitoringTab (CPU/RAM/disk)
│   │   ├── /config                   # FolderConfigPanel
│   │   └── /restore                  # RecoveryWizard
│   └── /add                          # AddServerModal (modal route)
├── /audit                            # Audit PDF generator
├── /alerts                           # AlertResolver
├── /billing                          # SubscriptionPage (master-tdd-plan.md)
├── /settings                         # SettingsPage (language, etc.)
├── /admin                            # AdminModeBar features (only if user.is_service_admin)
└── /processing                       # ProcessingScreen (post-Stripe return)
```

### 4.2 Restore flows (single-file vs full-system Recovery Mode)

ProperBackup ma **dwa odrebne flow restore**:

#### A. Single-file restore (download) — istniejacy

User pobiera pojedynczy plik ze snapshota i decryptuje lokalnie w browserze.

```
1. User w DirectoryView klika ikone "Download" przy pliku
2. RecoveryWizard.jsx (existing, 271 linii) — 4-step modal:
   Step 0: Info ze snapshota (path, date, size)
   Step 1: Password verify (Argon2id check via verifyPassword)
   Step 2: ThawProgress.jsx (jezeli cold tier)
   Step 3: Download + decrypt (decryptAndDownload — local AES-GCM)
3. Plik ladowany na user disk
```

**Status:** Implemented (main branch). Bez zmian w tej iteracji.

#### B. Full-system Recovery Mode (Time-Machine) — NOWE

**Single source of truth:** [`user-facing-recovery-spec.md`](user-facing-recovery-spec.md)

User przywraca CALY system serwera do wybranego snapshot (delete-new + restore-old):

```
1. User w SnapshotTimeline klika "Restore to this point" przy snapshot
2. RecoveryConfirmationModal — DRY RUN preview:
   - 3421 files to restore (3.2 GB)
   - 89 files to delete (45 MB)
   - 12458 files unchanged
   - Sample paths (20 each)
   - Estimated time
   - Acknowledge checkbox MANDATORY
3. User confirms → backend creates recovery_session
4. State machine (10 stanow): REQUESTED → PLANNING → AWAITING_USER_CONFIRM
   → THAWING (cold) | READY (hot) → AGENT_RESTORING → VERIFYING → DONE
5. RecoveryModeOverlay (center-screen, Time-Machine UX):
   - Progress bar
   - Current operation
   - ETA
   - Cancel button
6. Per-server lockdown: actions na target server disabled; inne servery OK z warning banner
7. Pre-recovery snapshot OBOWIAZKOWY: utworzony PRZED AGENT_RESTORING
   (30-day grace, undo possible)
8. Cancel anywhere with rollback (uses pre-recovery snapshot)
9. Audit log every action (RODO + customer trust)
```

**Status:** Spec done. Implementation w 4 PR-ach (B → C → A → D):
- Buffer Recovery Session API
- Agent Restore Protocol (uses `properbackup-shared/restore/`)
- Frontend Recovery Mode UI
- E2E Playwright tests + videos

**Patrz:** `user-facing-recovery-spec.md` sekcje 7-10 (per-PR implementation plans).

### 4.3 Timeline view

```
SnapshotTimeline.jsx renderuje:

┌─────────────────────────────────────────────────────────┐
│  Server: My VPS                                         │
│  ↑ filtr daty: [ostatnie 7d] [30d] [90d] [custom]      │
├─────────────────────────────────────────────────────────┤
│  ● 2026-05-26  18:23  47 MB   "auto"     [↻ Restore]   │
│  ●  2026-05-26  12:00  120 MB  "auto"     [↻ Restore]   │
│  ● 2026-05-25  06:00  2.3 GB  "auto"     [↻ Restore]   │
│  ⊘ 2026-05-24  18:00  ---     "tombstone"               │
│  ❄ 2026-05-01  09:00  450 GB  "cold"     [↻ Restore]   │
└─────────────────────────────────────────────────────────┘

Legend:
  ●  Hot tier, ready
  ❄  Cold tier, restore requires rehydration
  ⊘  Tombstone (deleted by agent)
  ✗  Verify failed (alert)
```

### 4.4 Agent activation UI

```
User klika "Add Server" → AddServerModal.jsx:

Step 1: Choose platform
  ☐ Linux (deb/rpm/tar)
  ☐ Windows (zip)
  ☐ Mac (tar.gz)
  ☐ ARM64 (Raspberry Pi)

Step 2: Download instructions
  - Direct download link (sha256 weryfikuj)
  - Command line: ./properbackup-agent --activate <TOKEN>
  - Token generated: ABC-123-XYZ (visible 24h, single-use)

Step 3: Waiting for agent
  - SSE listens on server-activated event
  - Po aktywacji: redirect do server detail
  - Timeout 60 min → token expires, user musi wygenerowac nowy
```

---

## 5. Test Groups

Numerowanie `[WEB-Xn]`.

### Grupa A: Routing & navigation

#### `[WEB-A1]` Route guards

**Cel:** Niezalogowany user → redirect do /auth.

**Implementacja:** PrivateRoute HOC w `router/`.

**DoD:**
- E2E test: bez tokenu access /panel/servers → redirect
- Test "expired token" (401 z buffer) → logout + redirect

#### `[WEB-A2]` Deep-linking i back button

**Cel:** Klient klika link w mailu `/panel/servers/abc-123/restore` → ladowanie poprawne (nie 404).

**DoD:**
- E2E test deep link
- Test "back button po restore" → wraca do timeline (nie do home)

#### `[WEB-A3]` Mobile responsive

**Cel:** UI dziala na 320px szerokosci (najmniejszy ekran).

**DoD:**
- Lighthouse audit pass (≥85)
- E2E test Playwright na viewport 320x568

### Grupa B: Timeline & snapshots

#### `[WEB-B1]` Timeline render z paginate

**Given:** Server ma 1000 snapshotow

**When:** GET /panel/servers/:id/timeline

**Then:**
- Pierwsze 50 zaladowane
- Scroll na koniec → fetch kolejne 50 (infinite scroll)
- Brak lag UI na 1000 elementach (virtualizacja jezeli >100)

**DoD:**
- E2E test scroll
- Test "filter ostatnie 7d" → tylko ostatnie 7d wyswietlone (server-side filter)

#### `[WEB-B2]` Restore from snapshot

**When:** Klik "Restore" → RecoveryWizard

**Then:**
- POST /restore/initiate
- Modal Step 4 z SSE listener
- Po complete: snapshot oznaczony "Restored at <time>" w UI

**DoD:**
- E2E happy path
- E2E "restore cancelled by user" → backend dostaje DELETE /restore/:id
- E2E "SSE disconnect" → fallback poll 5s

#### `[WEB-B3]` Cold thaw progress

(Cross-ref `ovh-cloud-archive-migration-spec.md` `[OVH-C2]`)

**Given:** Snapshot w cold tier

**When:** Klik Restore

**Then:**
- ThawProgress.jsx modal pokazuje "Thawing... ETA 8h"
- Progress bar (% based on cron polls)
- "Notify me when ready" checkbox → email po ready

**DoD:**
- E2E test z mock cold snapshot
- Test "thaw failed (OVH timeout)" → komunikat + email support

### Grupa C: 1-Click Restore

#### `[WEB-C1]` Recovery wizard ergonomics

**Cel:** Caly flow od kliku "Restore" do "Done" zajmuje <5 sekund decyzji user'a.

**Implementacja:**
- Default destination (oryginalna sciezka)
- Default "no overwrite warning" jezeli plik nie istnieje
- Progress bar w czasie rzeczywistym
- "Dont wait" option (zamknij modal, work in background)

**DoD:**
- UX test (manual): 5 osob klika "Restore" → wszyscy <30s do wyniku
- E2E: pelen flow w 3 klikach

#### `[WEB-C2]` Bulk restore

**Cel:** User klika "Restore all" na serverze → odzysk całosci ostatniego snapshotu.

**Implementacja:**
- POST /restore/initiate {serverId, mode: 'full', destination}
- Backend tworzy multi-chunk restore (1 request per pack)

**DoD:**
- E2E test 100 plikow restore w one wizard
- Test "partial fail": 5/100 chunkow w cold tier → wizard waits dla cold
- Test cancel mid-restore → backend kasuje in-progress, restored files zostaja

#### `[WEB-C3]` Restore conflict resolution

**Given:** Plik docelowy istnieje na maszynie (nie w cloud restore, ale w local agent restore)

**When:** Restore wykonywany

**Then:**
- UI option: "Skip", "Overwrite", "Rename with .restored suffix"
- Default: "Skip" (safer)

**DoD:**
- E2E test każdej opcji

### Grupa D: Audit & reports

#### `[WEB-D1]` Audit PDF generator UI

**Cel:** User wybiera okres → "Generate report" → download PDF.

**Implementacja:**
- Form: from-date, to-date, serverId (optional, default "all")
- Submit: POST /reports/audit?async=true
- Show jobId, poll status
- Po ready: download link
- Plik retencja 7 dni

**DoD:**
- E2E test: wygeneruj raport, download, weryfikuj PDF parsuje
- Test "okres bez danych" → PDF "no data"
- Test "okres > 1 rok" → confirmation dialog (slow generation)

#### `[WEB-D2]` Storage usage breakdown

**Cel:** Klient widzi gdzie idzie jego storage:
- Per server breakdown
- Per folder breakdown (top 10)
- Per month upload trend

**Implementacja:**
- NEW: `monitoring/CostBreakdown.jsx`
- GET /api/usage?breakdown=server|folder|month
- Recharts dla wykresow (jezeli juz nie ma chart library, decyzja: tak)

**DoD:**
- E2E: 1 server z 3 folderami → breakdown poprawnie sumuje
- Test "user near quota": badge "Approaching limit" w UI

### Grupa E: Agent activation

#### `[WEB-E1]` Add Server modal happy path

**When:** Klik "Add server" → AddServerModal

**Then:**
- Step 1: pick platform
- Step 2: pokaz download URL + token + sha256
- Step 3: "Waiting for agent..." z SSE listener
- Po activate: redirect do `/panel/servers/<newServerId>`

**DoD:**
- E2E test happy path
- E2E "user closes modal before activation" → token nadal vailid 60 min
- Test "wrong sha256" → user widzi komunikat (after attempted activation)

#### `[WEB-E2]` Token regeneration

**Cel:** Token expired (60 min)? User klika "Regenerate" → nowy token.

**DoD:**
- E2E test
- Test "stary token uzywany po regeneracji" → 400 (token revoked)

#### `[WEB-E3]` Existing server display

**Cel:** User widzi listę aktywnych serverow ze statusem (online/offline).

**Implementacja:**
- ServerCard z polach: name, last-seen, status indicator (green dot/grey/red)
- Status z `agent_metrics.last_heartbeat_at` < 5 min ago

**DoD:**
- E2E: 2 servery, jeden online (recent metrics), drugi offline → ikony rozne
- Test "agent offline >24h" → alert badge

### Grupa F: Folder config

#### `[WEB-F1]` Add backup root

**Cel:** User wybiera ktore foldery agent ma backupowac.

**Implementacja:**
- FolderConfigPanel.jsx
- Tree view (DirectoryView.jsx) z checkboxami
- Save → PUT /servers/:id/backup-roots {roots: [...]}

**DoD:**
- E2E: dodaj root, sprawdz że agent przy next sync pickuje
- Test "removed root": stop backupowania, ale stare snapshoty zostaja (retencja)
- Test "duplicate roots": deduplikuj w UI

#### `[WEB-F2]` Exclude patterns UI

**Cel:** User dodaje wzorce exclude (`*.log`, `node_modules/`).

**Implementacja:**
- Tag input z multi-line
- Save → PUT /servers/:id/exclude-patterns

**DoD:**
- E2E: pattern dodany → agent NIE wysyla zgodnego pliku
- Test "invalid regex" → walidacja w UI (no crash)

### Grupa G: Monitoring tab

#### `[WEB-G1]` Real-time metrics

**Cel:** Live view: CPU/RAM/disk usage agenta.

**Implementacja:**
- SSE listening on `agent_metrics` updates
- Recharts line chart (last 1h, 24h, 7d toggle)
- Manual refresh button

**DoD:**
- E2E: agent live → chart updates co 10s
- Test "agent offline" → chart pokazuje "Last seen X min ago" overlay

#### `[WEB-G2]` Alerts widget

**Cel:** Top czerwone alerty wyswietlane na dashboard.

**Implementacja:**
- AlertResolver.jsx fetches GET /alerts?status=open
- Filter by severity
- Each alert: title, server, time, "Acknowledge" / "Resolve" button

**DoD:**
- E2E: 3 alerty → wyswietlone
- Test "acknowledge" → status='acknowledged', zniknie z domyslnego widoku
- Test ackowledge resync z innym device (multi-tab)

### Grupa H: Localization (i18n)

#### `[WEB-H1]` Polish translation completeness

**Cel:** 100% kluczy ma tlumaczenie polskie.

**Implementacja:**
- `i18n/pl.json`, `i18n/en.json`
- Skrypt CI: porownaj klucze, fail jezeli pl missing

**DoD:**
- Test ze pl.json ma wszystkie klucze z en.json
- Test "missing translation" fallback: ` <missing: foo.bar.baz>` (visible w dev mode)

#### `[WEB-H2]` Date/time formatting

**Cel:** Format dat zgodnie z locale.
- Polish: "26 maj 2026, 18:23"
- English: "May 26, 2026 6:23 PM"

**Implementacja:** `Intl.DateTimeFormat`.

**DoD:**
- E2E test obu locales
- Test "user changes language mid-session" → dynamic re-render

#### `[WEB-H3]` Polish characters (diakrytyki)

**Cel:** Wszystkie polskie znaki (zwlaszcza w UI) renderuja sie poprawnie: ąęcńółśźż.

**DoD:**
- Visual test: strona Polish renderuje znaki bez tofu/?
- Font fallback: jezeli specific font nie ma znaku, system fallback

### Grupa I: Accessibility

#### `[WEB-I1]` Keyboard navigation

**Cel:** Caly panel uzywalny tylko z klawiatury (Tab, Enter, Esc, arrow keys).

**DoD:**
- Lighthouse a11y audit ≥90
- Manual test: caly flow restore wykonany tylko klawiatura

#### `[WEB-I2]` Screen reader

**Cel:** WCAG 2.1 AA basics.

**Implementacja:**
- Aria-labels na interactive elements
- Heading hierarchy (h1 → h2 → h3, bez skoku)
- Focus indicators visible

**DoD:**
- axe-core scan: 0 critical issues
- Manual test ChromeVox

#### `[WEB-I3]` Color contrast

**Cel:** WCAG AA contrast ratios (4.5:1 dla text, 3:1 dla large text).

**Tailwind config:** verify default theme passes.

**DoD:**
- axe-core scan: 0 contrast issues
- Dark mode (jezeli istnieje): tez passa

### Grupa J: Performance

#### `[WEB-J1]` Bundle size

**Cel:** `dist/` zip <500KB gzip.

**Implementacja:**
- Code splitting per route
- Lazy loading dla rzadko uzywanych (RecoveryWizard, AuditReportPage)
- Tree shaking dla unused i18n keys

**DoD:**
- CI gate: `npm run build` produces <500KB
- Bundle analyzer report w PR

#### `[WEB-J2]` First Contentful Paint <2s

**Cel:** Lighthouse FCP <2s na 3G.

**Implementacja:**
- Critical CSS inlined
- Preload font
- Defer non-critical JS

**DoD:**
- Lighthouse audit pass on mobile 3G simulation

#### `[WEB-J3]` Memory leak prevention

**Cel:** Long-running session (uzytkownik otwarty 24h) nie pamietuje OOM.

**Implementacja:**
- SSE cleanup w `useEffect` return
- Recharts cleanup
- Modal unmount cleanup

**DoD:**
- Manual test: open panel 8h, sprawdz memory profile (Chrome DevTools)
- E2E ze "100 modal open/close cycles" → no leak

---

## 6. Edge Cases (15+)

### 6.1 SSE odlaczenie i reconnect

Klient na slabym Wi-Fi, SSE drop co 5 min.

**Wymagane:**
- Auto-reconnect z exp backoff (1s, 2s, 4s, 8s, max 30s)
- "Reconnecting..." badge w UI
- Po reconnect: re-fetch wszystkie stale data (snapshot list, alerts)

### 6.2 Token JWT expired w trakcie sesji

Klient otwiera panel 9h, JWT 8h.

**Wymagane:**
- Refresh token flow (auto)
- Po 401 z bufera: refresh JWT silently
- Jezeli refresh failuje: logout + redirect z message "Sesja wygasla"

### 6.3 Cofniecie back po Checkout

(Cross-ref `master-tdd-plan.md` `[TDD-F2]`)

User wraca z Checkoutu na `/panel/processing`, naciska "back".

**Wymagane:**
- Browser detects history pop → redirect do `/panel/billing` (nie wraca do Stripe)

### 6.4 Multi-tab edycja folderu

User edytuje FolderConfigPanel w 2 tabach. Race.

**Wymagane:**
- API PUT z `If-Match: <etag>` header
- 412 Precondition Failed → reload, retry
- Komunikat "Konfiguracja zmieniona w innym oknie. Odswiezono."

### 6.5 Modal otwarty + url change (deep link)

User otworzyl AddServerModal, drugi tab nawiguje do innego /panel/.

**Wymagane:**
- Modal w state, nie w URL (chyba ze user copy-paste'uje)
- Po nav: modal zamknij

### 6.6 Dark mode / reduced motion

User ma OS-level "prefers-reduced-motion".

**Wymagane:**
- CSS `@media (prefers-reduced-motion: reduce)` → wylacz wszystkie transitions
- Progress bar zostaje, ale bez pulse animation

### 6.7 Wielkie raporty audit (slow)

Klient wygenerował raport rok-długi → PDF 50MB.

**Wymagane:**
- Show progress bar (% via SSE) zamiast spinner
- Po ready: download link visible
- Truncated info "PDF zawiera 12 mies — sredni czas generacji: 25s"

### 6.8 Cofnieta restore wizard

User wpolprzelocie kliknal "X" w RecoveryWizard.

**Wymagane:**
- Backend dostaje DELETE /restore/:id
- Already-downloaded files zostaja (nie kasujemy z agent local)
- Restored entries w archive_snapshot oznaczone "partial restore"

### 6.9 Browser crashed during restore

User Chrome crashed. Restore byl w toku.

**Wymagane:**
- Backend kontynuuje restore (nie zalezy od UI keep-alive)
- User po re-open panel widzi "Restore in progress: 47%" z resumed progress

### 6.10 Logowanie SSO (post-MVP)

User chce uzyc Google OAuth.

**Decyzja:** Post-MVP, na razie tylko email+password.

### 6.11 Forgotten password

Klient zapomnial hasla.

**Wymagane:**
- POST /auth/forgot-password {email}
- Email z linkiem (jednorazowy token 1h)
- Strona reset → POST /auth/reset {token, newPassword}

(Ten flow powinien istnieć — sprawdz pre-existing pages)

### 6.12 Password change

User chce zmienic haslo.

**Wymagane:**
- Settings page → "Change password" form
- Old password required
- New password >= 12 chars (zod schema)
- PUT /auth/password
- Po sukcesie: invalidate inne sesje (`audit_log` "password_changed")

### 6.13 Email change

User zmienia adres email.

**Wymagane:**
- Settings → "Change email"
- Old email + nowe email → email verification flow
- Po klik linka w mailu: email updated
- Stripe customer email tez updated (synchronizacja)
- Audit log

### 6.14 Account deletion (GDPR)

User chce skasowac swoje konto.

**Wymagane (cross-ref `crypto-and-compliance-spec.md`):**
- Settings → "Delete account"
- Type "DELETE" do potwierdzenia
- 7-dniowy grace period (mozliwosc anulacji)
- Po 7d: hard delete (cascade)
- Email po wykonaniu

### 6.15 Slow connection (3G)

User na pociagu, 3G slabe.

**Wymagane:**
- Optimistic UI: po klik "Restore" pokazuje confirmation natychmiast, czekaj na backend
- Skeleton screens
- Toasts "Slow connection" gdy timeout 10s

### 6.16 Concurrent same user multi-device

User na phone + laptop jednoczesnie.

**Wymagane:**
- Wszystkie aktywne sesje widoczne w Settings → "Active sessions"
- "Sign out other devices" button (cross-ref backend audit_log)

### 6.17 Disposable email blocked (cross-ref master-tdd-plan.md 9.8)

User rejestruje sie z `temp@10minutemail.com`.

**Wymagane:**
- Registration form weryfikuje email domain w sync (sklepowa lista)
- Komunikat "Domena nie jest dozwolona"

### 6.18 Stripe Checkout return → /processing race

(Cross-ref `master-tdd-plan.md` `[TDD-F1]`)

User wraca z Checkout, webhook jeszcze nie przyszedl → `subscription_status` = none.

**Wymagane:**
- ProcessingScreen.jsx czeka 30s na SSE event `subscription_updated`
- Po sukcesie redirect do dashboard
- Po 30s timeout: pokazuje "Sprawdzanie statusu..." z manual refresh

---

## 7. Definition of Done

10 kryteriow:

1. Component test (React Testing Library) red-first
2. E2E test (Playwright) happy path
3. Visual regression test (snapshot) (post-MVP)
4. a11y check (axe-core w komponencie)
5. i18n keys w pl.json i en.json
6. Mobile responsive (320px min width)
7. Lighthouse audit ≥85 (per-route)
8. Bundle size budget respected
9. DOTYKAJ zone respected
10. Backend API contract documented w PR

---

## 8. Sequence of work

1. **`[WEB-F1]` Add Server modal — token gen** (cross-ref `[BUF-D1]`)
2. **`[WEB-E1]` Existing server display + activation tracking**
3. **`[WEB-B1]` Timeline render z paginate**
4. **`[WEB-C1]` Recovery wizard 1-Click happy path**
5. **`[WEB-B3]` Cold thaw progress**
6. **`[WEB-D1]` Audit PDF generator UI**
7. **`[WEB-G1]` Real-time metrics (SSE chart)**
8. **`[WEB-G2]` Alerts widget**
9. **`[WEB-F2]` Exclude patterns UI**
10. **`[WEB-H1]` i18n completeness check** (po wszystkich nowych key'ach)
11. **`[WEB-I1]` Keyboard navigation review**
12. **`[WEB-J1]` Bundle size optimization**
13. **6.12-6.14: settings page (password change, email change, account deletion)**

---

## 9. Go/No-Go checklist

- [ ] Add Server flow dziala (token gen → agent activate → server visible)
- [ ] Timeline pokazuje snapshoty, paginate, filter
- [ ] 1-Click Restore happy path udany na test data
- [ ] Cold thaw progress modal pokazuje ETA
- [ ] Audit PDF generuje sie i downloaduje
- [ ] Monitoring tab pokazuje real-time CPU/RAM
- [ ] Alerts widget pokazuje open alerts
- [ ] Polish translation 100%
- [ ] Mobile 320px wide nie psuje layout
- [ ] Bundle <500KB gzip
- [ ] Lighthouse mobile ≥85 wszystkie metryki
- [ ] a11y axe-core scan: 0 critical
- [ ] Settings page (password, email, delete account) dziala
- [ ] Recovery wizard cancel mid-flow czysci backend
- [ ] SSE auto-reconnect po network drop dziala
- [ ] Multi-tab race: PUT z If-Match etag chroni przed lost update

---

## Dodatek A — Linki

- `master-tdd-plan.md` — subscription UI, ProcessingScreen
- `buffer-core-master-spec.md` — API endpoints konsumowane przez web
- `agent-vps-master-spec.md` — activation flow (token shared)
- `ovh-cloud-archive-migration-spec.md` — cold tier UX
- `observability-and-dr-spec.md` — monitoring UI consumes pb_* metrics
- `crypto-and-compliance-spec.md` — account deletion flow

## Dodatek B — Glosariusz

- **SSE** — Server-Sent Events (HTTP push)
- **JWT** — JSON Web Token
- **Etag** — HTTP header for optimistic concurrency control
- **a11y** — accessibility (a + 11 chars + y)
- **i18n** — internationalization
- **WCAG** — Web Content Accessibility Guidelines
- **PWA** — Progressive Web App (post-MVP, gdyby chciec offline support)
- **FCP** — First Contentful Paint
- **LCP** — Largest Contentful Paint
- **CLS** — Cumulative Layout Shift
- **Snapshot timeline** — chronological view of backups per server
- **Cold thaw** — rehydration z cold tier (4-12h)
- **Tombstone** — soft-delete marker w timeline
