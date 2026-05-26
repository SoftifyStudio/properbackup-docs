# CI/CD & Release Pipeline — Master Plan

Wersja: 1.0 (initial, pre-prod)
Repo: **wszystkie 6** (buffer, agent, shared, web, stack, mc, docs)
Status: SPEC — czeka na implementacje przez kolejnego agenta
Priorytet: **P1**

---

## 1. Cel dokumentu

Plan budowy pipeline'u CI/CD dla calego projektu ProperBackup, od PR walidacji do release na produkcji.

Aktualny stan z notatki Daniela:

> Brak CI na repo. Wszystkie testy uruchamiane lokalnie. Zero GitHub Actions checks.

To jest **fundamentalna luka** dla projektu obslugujacego platnosci klientow. Plan poniżej naprawia ten stan systematycznie, z minimalna inwazyjnoscia (DOTYKAJ tylko nowe `.github/workflows/*.yml`).

### Zakres

- GitHub Actions per repo: build, test, lint
- Test Containers w CI (PostgreSQL)
- Lint i format (Kotlin: ktlint, JS: ESLint, MD: markdownlint)
- Release pipeline: tag → build artifacts → upload to S3/B2 (dla agent)
- Versioning convention (SemVer CalVer hybrid)
- Pre-commit hooks (local)
- Secrets management (GitHub Actions secrets, NIE w gicie)

### Co NIE jest w zakresie

- Self-hosted runners (post-MVP, gdyby koszty GH Actions rosły)
- Continuous Deployment (auto-deploy na produkcje) — na razie **manual deploy** (zwiekszone bezpieczenstwo)
- Performance tests / load tests w CI (post-MVP, k6 / Gatling)
- Mutation testing (post-MVP)

---

## 2. Mapowanie obecnego stanu

| Repo | Build tool | Testy | Lint | CI status |
|------|-----------|-------|------|-----------|
| `properbackup-buffer` | Gradle Kotlin DSL | JUnit | brak (TODO ktlint) | **BRAK CI** |
| `properbackup-shared` | Gradle KMP | JUnit | brak | **BRAK CI** |
| `properbackup-agent` | Gradle Kotlin DSL | JUnit | brak | **BRAK CI** |
| `properbackup-web` | Vite + Vitest | Vitest | brak (TODO ESLint) | **BRAK CI** |
| `properbackup-stack` | Docker compose | brak | brak | **BRAK CI** |
| `properbackup-mc` | (puste placeholder) | brak | brak | **BRAK CI** |
| `properbackup-docs` | brak (MD only) | brak | brak (TODO markdownlint) | **BRAK CI** |

### 2.1 Lokalnie sprawdzone

Aktualne testy z `master-tdd-plan.md` `SubscriptionIntegrationTest.kt` (80+ testow, 2000+ linii) sa **lokalnie uruchamiane** ale **nie wpadaja w żaden CI gate**. Oznacza to:
- PR moze byc zmergowany **bez weryfikacji ze testy zdaja**
- Regresja moze przejsc na produkcje
- Reliance na devin/agent ze "uruchom testy lokalnie" — kruche

---

## 3. DOTYKAJ vs NIE RUSZAJ

### NIE RUSZAJ

- Istniejacy kod produkcyjny (chyba ze test failuje — wtedy fix BUG, nie zmieniaj test)
- `build.gradle.kts` w sposob breaking change (mozna **dodawac** taski, nie usuwac istniejacych)
- `package.json` scripts (mozna **dodawac**)

### DOTYKAJ (mozna modyfikowac)

- Dodanie `.github/workflows/*.yml` per repo
- Dodanie `.pre-commit-config.yaml` per repo
- Dodanie konfiguracji ktlint: `.editorconfig`
- Dodanie konfiguracji ESLint: `.eslintrc.json`
- Dodanie konfiguracji markdownlint: `.markdownlint.json`
- Dodanie skryptu w `package.json` lub Gradle task `lintCheck`
- Update `README.md` per repo z badge CI

### MOZESZ TWORZYC

- Wszystkie pliki `.github/workflows/*.yml`
- Skrypty bash w `scripts/ci/*.sh`
- Composite GitHub Actions w `.github/actions/*/action.yml`
- Dependabot config `.github/dependabot.yml`
- CODEOWNERS

---

## 4. Repository setup priorities

Przyszly agent **musi** zaczynac od **buffer**, bo to:
- Najwiecej kodu Kotlin
- Najwiecej krytycznego biznes logic (billing, storage)
- Najwiecej testow do uruchomienia

### 4.1 Standardowy pipeline per repo

```yaml
# .github/workflows/ci.yml (template)
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # for git log / blame
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v3
      - name: Build
        run: ./gradlew build --no-daemon
      - name: Test
        run: ./gradlew test --no-daemon
      - name: Lint
        run: ./gradlew ktlintCheck --no-daemon
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: build/reports/tests/
```

### 4.2 Modyfikacje per-repo

| Repo | Specyficzne |
|------|------------|
| `properbackup-buffer` | + Testcontainers cache, + PG service (port 5432), + integration test job |
| `properbackup-agent` | + jlinkDist build matrix (linux/win/mac/arm64), + cross-platform tests |
| `properbackup-shared` | + KMP tests (JVM + future Native ARM64) |
| `properbackup-web` | + node 22, + Vite build, + Vitest, + Playwright e2e (optional) |
| `properbackup-stack` | + Docker buildx, + docker compose smoke test |
| `properbackup-mc` | + Paper API compat matrix (1.20, 1.21) |
| `properbackup-docs` | + markdownlint, + dead link check, + Vale (style guide), + alternative encoding check |

---

## 5. Test Groups

Numerowanie `[CICD-Xn]`.

### Grupa A: Build pipeline

#### `[CICD-A1]` Buffer build i unit testy

**Cel:** Każdy PR uruchamia `./gradlew build test` w `properbackup-buffer`.

**Wymagania:**
- Java 21 (Temurin)
- Gradle cache (Actions cache: `~/.gradle/caches`)
- Test report jako artifact (UI dostepny w GitHub Actions)
- Failure: PR nie da sie zmergowac

**Plik:** `properbackup-buffer/.github/workflows/ci.yml`

**DoD:**
- Workflow file utworzony
- Pierwszy PR uruchamia CI
- Failed test → PR check checka "Tests: failing"
- Branch protection rule: main wymaga "Tests" check passing
- Build cache: drugi run < 5 min (vs 15 min cold)

#### `[CICD-A2]` Integration tests z Testcontainers

**Cel:** SubscriptionIntegrationTest i podobne testy uruchamia sie w CI z prawdziwym PostgreSQL.

**Wymagania:**
- Docker dostepny w GH Actions (default `ubuntu-latest`)
- Testcontainers wykrywa Docker socket automatycznie
- PostgreSQL container start: <30s
- Total job time: <20 min

**Implementacja:**
```yaml
- name: Run integration tests
  run: ./gradlew integrationTest --no-daemon
  env:
    TESTCONTAINERS_REUSE_ENABLE: "true"
```

**DoD:**
- 80+ testow z SubscriptionIntegrationTest zdaje w CI
- Czas wykonania <15 min
- Test "PostgreSQL container fails to start" → clear error message

#### `[CICD-A3]` Web build + tests + Playwright

**Cel:** `properbackup-web` ma:
- `npm ci` (deterministic install)
- `npm run build` (Vite build)
- `npm run test` (Vitest)
- `npm run e2e` (Playwright, opcjonalnie)

**Plik:** `properbackup-web/.github/workflows/ci.yml`

**DoD:**
- Bundle size check: `dist/` < 500KB gzip (jezeli wieksze, alert in PR comment)
- Playwright runs on Chromium + Firefox + WebKit (matrix)
- Visual regression test (snapshot diff) — post-MVP

#### `[CICD-A4]` Agent multi-platform build

**Cel:** Agent buduje sie dla 4 platform:
- linux-amd64
- linux-arm64
- windows-amd64
- macos-amd64

**Strategy matrix:**
```yaml
strategy:
  matrix:
    include:
      - os: ubuntu-latest
        arch: amd64
        platform: linux-amd64
      - os: ubuntu-latest
        arch: arm64
        platform: linux-arm64
        # qemu setup
      - os: windows-latest
        platform: windows-amd64
      - os: macos-latest
        platform: macos-amd64
```

**Plik:** `properbackup-agent/.github/workflows/ci.yml`

**DoD:**
- 4 artifacts: `properbackup-agent-<platform>-<version>.tar.gz`
- Smoke test: `./properbackup-agent --version` zwraca expected
- ARM64 cross-compile w qemu (slower but works)

#### `[CICD-A5]` Docs build (markdown + links)

**Cel:**
- markdownlint czeka na linty (max 0 errors)
- Dead link checker (`lychee`)
- Pliki bez polskich znakow w nazwach (encoding bezpieczenstwo)

**Plik:** `properbackup-docs/.github/workflows/ci.yml`

**DoD:**
- markdownlint nie zwraca errors
- Lychee nie znajduje broken links
- Plik z polskim znakiem w nazwie → PR fails

### Grupa B: Lint i format

#### `[CICD-B1]` Kotlin ktlint

**Cel:** Standard kodu Kotlin enforced.

**Konfiguracja:** `.editorconfig` na root + ktlint Gradle plugin.

**Pliki:**
- DOTYKAJ: `build.gradle.kts` (dodaj `id("org.jlleitschuh.gradle.ktlint")`)
- NEW: `.editorconfig` (root):
```
root = true
[*.{kt,kts}]
indent_style = space
indent_size = 4
max_line_length = 120
ktlint_standard_no-wildcard-imports = enabled
ktlint_standard_filename = enabled
ktlint_standard_max-line-length = disabled  # do nie blokuje
```

**DoD:**
- PR z naruszeniem ktlint → CI fail
- `./gradlew ktlintFormat` autofixuje wiele warnings

#### `[CICD-B2]` JavaScript/TypeScript ESLint + Prettier

**Cel:** Web ma:
- ESLint (errors + recommended rules)
- Prettier (formatting)
- Husky pre-commit (jezeli developer pisze lokalnie)

**Pliki:**
- NEW: `.eslintrc.json` (`extends: ["react/recommended", "react-hooks/recommended"]`)
- NEW: `.prettierrc.json`
- DOTYKAJ: `package.json` scripts: `"lint": "eslint src/", "lint:fix": "eslint src/ --fix"`

**DoD:**
- PR z naruszeniem ESLint → CI fail
- React hooks rules egzekwowane

#### `[CICD-B3]` Markdownlint

**Cel:** Docs maja konsystentny format.

**Plik:** `.markdownlint.json` (root docs repo):
```json
{
  "MD013": false,
  "MD041": false,
  "MD024": { "siblings_only": true }
}
```

**DoD:**
- Wszystkie pliki w `architecture/` przechodzą lint

### Grupa C: Security

#### `[CICD-C1]` Dependabot

**Cel:** Auto-update dependencies dla security patches.

**Plik per repo:** `.github/dependabot.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: "gradle"
    directory: "/"
    schedule:
      interval: "weekly"
    allow:
      - dependency-type: "production"
    open-pull-requests-limit: 5
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
```

**DoD:**
- Tygodniowo dependabot PRs powstają
- Workflow akceptujacy security patches (minor/patch level) z labelem

#### `[CICD-C2]` Secret scanning

**Cel:** Wykryj sekrety zapisane do gita.

**Opcje:**
- GitHub Advanced Security (free dla public, paid dla private)
- `trufflehog` w pre-commit hook
- `gitleaks` w GH Actions

**Plik:** `.github/workflows/secrets-scan.yml`:
```yaml
on: [pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
```

**DoD:**
- PR z `STRIPE_SECRET_KEY=sk_live_...` w kodzie → fail
- Test ze fake-secret-pattern w docs (np. `<your-key-here>`) NIE failuje

#### `[CICD-C3]` Code scanning (CodeQL)

**Cel:** Statyczna analiza dla Kotlin/JS security issues.

**Plik:** `.github/workflows/codeql.yml` (GitHub-provided template).

**DoD:**
- Tygodniowy scan
- Findings w GH Security tab

#### `[CICD-C4]` License compliance

**Cel:** Sprawdzaj licencje dependencies (no GPL w naszych proprietary repo).

**Tool:** Gradle `license-gradle-plugin` lub `gradle-license-report`.

**DoD:**
- Raport licensow generowany jako artifact w PR
- PR z GPL/AGPL dep → manual review required (label "license-review")

### Grupa D: Pre-commit hooks (lokalne, dev)

#### `[CICD-D1]` Setup pre-commit framework

**Cel:** Developer instaluje raz `pre-commit install` i lokalne commity są walidowane.

**Plik per repo:** `.pre-commit-config.yaml`:
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: [--maxkb=5000]
      - id: detect-private-key
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

**Per-repo dodatkowe hooki:**
- Kotlin: ktlint pre-commit
- Web: ESLint pre-commit (np. Husky)
- Docs: markdownlint

**DoD:**
- `pre-commit install` setupuje hooki
- Commit ze błędem ktlint → block
- Commit z 50MB plikiem → block

### Grupa E: Release pipeline

#### `[CICD-E1]` Tag-driven release

**Cel:** `git tag v2026.05.26` triggeruje release workflow:
- Build artifacts (gradle distTar, jlinkDist)
- Generate changelog z `git log --merges`
- Upload artifacts do **B2** (lub Cloudflare R2)
- Create GitHub Release z notes

**Plik per repo:** `.github/workflows/release.yml`:
```yaml
on:
  push:
    tags:
      - 'v*'
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - ... build ...
      - name: Upload artifacts
        run: rclone copy build/distributions/*.tar.gz b2:properbackup-releases/
      - uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
```

**DoD:**
- Tag `v2026.05.26` triggeruje release w 5 min
- Artefakty dostepne pod URL `https://app.properbackup.pl/downloads/agent-<platform>-2026.05.26.tar.gz`
- sha256 zalaczony jako `*.tar.gz.sha256`

#### `[CICD-E2]` Versioning convention

**Wybierz JEDEN i bezwzglednie trzymaj:**

**Opcja A: CalVer** (zalecane dla SaaS): `YYYY.MM.DD[-rc.N]`
- `2026.05.26` — release dnia
- `2026.05.26-rc.1` — pre-release

**Opcja B: SemVer**: `MAJOR.MINOR.PATCH`
- `1.4.2` — bug fix
- `1.5.0` — feature
- `2.0.0` — breaking change

**Decyzja: CalVer.** Powody:
- SaaS, ciagly release flow
- Klient widzi data z wersji (przejrzystosc)
- Brak debaty o "czy to feature czy breaking change"
- Agent auto-update porownuje stringi liniowo

**DoD:**
- Convention w `CONTRIBUTING.md`
- Skrypt `scripts/ci/cut-release.sh` automatyzuje tag creation z dzisiejsza data

#### `[CICD-E3]` Changelog automation

**Cel:** Po release, `CHANGELOG.md` automatycznie aktualizowany.

**Tool:** `git-cliff` lub `release-please` (Google).

**Konwencja commitow:** [Conventional Commits](https://www.conventionalcommits.org/):
- `feat: ...`
- `fix: ...`
- `docs: ...`
- `refactor: ...`
- `test: ...`
- `chore: ...`

**DoD:**
- Każdy release ma changelog generated
- Commit konwencja egzekwowana przez commitlint w pre-commit

#### `[CICD-E4]` Deploy do produkcji (manual gate)

**Cel:** Po release, manual approval, potem auto-deploy na VPS.

**Implementacja:**
- Workflow `deploy-prod.yml` z `environment: production`
- GitHub Environments z required reviewers (Daniel)
- Deploy: SSH na VPS, `docker compose pull && docker compose up -d`

**DoD:**
- Tag → release artifact → manual approval → SSH deploy → smoke test → rollback gate
- Po deploy: `/health` 200 → Slack "Deploy successful"
- `/health` 5xx przez 2 min → auto-rollback (`docker compose rollback`)

#### `[CICD-E5]` Rollback procedure

**Cel:** Po niepoprawnym deploy, jednoklikowy rollback.

**Plik:** `properbackup-docs/operations/runbook-rollback-deploy.md`

**Procedura:**
1. `docker compose pull --tag=<previous-version>`
2. `docker compose up -d`
3. Smoke test `/health`
4. Slack notify

**DoD:**
- Procedura testowana w drill (raz na kwartal)

### Grupa F: Documentation gates

#### `[CICD-F1]` PR template enforcement

**Cel:** Każdy PR ma wypelniony template (juz uzywany).

**Plik:** `.github/pull_request_template.md` per repo.

**Walidacja:** GitHub Action sprawdza ze PR body ma sekcje:
- `## Summary`
- `## Review & Testing Checklist for Human`

**DoD:**
- PR bez template → label "needs-template", komentarz auto-bot

#### `[CICD-F2]` CHANGELOG update required

**Cel:** Każda zmiana userland-visible musi update'owac `CHANGELOG.md`.

**Implementacja:** Workflow sprawdza ze CHANGELOG.md byl zmodyfikowany (chyba ze PR ma label `chore` / `internal`).

**DoD:**
- PR feature/fix bez CHANGELOG update → CI warning
- PR z labelem `chore` → CI pomija check

### Grupa G: Performance & cost

#### `[CICD-G1]` Workflow runtime budget

**Cel:** CI nie kosztuje >X USD/mies.

**GitHub Actions free tier dla private repos:** 2000 min/mies.

**Estymacja:**
- Buffer CI: ~15 min/PR, 20 PRs/mies = 300 min
- Web CI: ~5 min/PR = 100 min
- Agent CI matrix 4x: ~15 min total = 300 min
- Shared CI: ~10 min = 200 min
- Total: ~900 min/mies < 2000 free tier

**DoD:**
- Monitor GH Actions usage w admin dashboard
- Alert gdy >80% free tier

#### `[CICD-G2]` Cache optimization

**Cel:** Wszystkie repo aggressively cache:
- Gradle: `~/.gradle/caches`, `~/.gradle/wrapper`
- npm: `~/.npm`
- Testcontainers Docker images
- Build outputs (build/)

**DoD:**
- Cold run: <15 min
- Warm run: <5 min
- Cache hit rate >80%

---

## 6. Pre-commit local setup

### 6.1 Wymagane narzedzia developera

```bash
# Linux/Mac
pip install pre-commit
brew install ktlint  # OR: gradle wrapper handles ktlint
npm install -g markdownlint-cli
```

### 6.2 Per-repo setup (jednorazowe)

```bash
cd properbackup-buffer
pre-commit install
pre-commit run --all-files  # validate everything passes
```

### 6.3 Default commit flow

```
git add .
git commit -m "feat: add foo"
# pre-commit hooks run:
#   - trailing whitespace
#   - ktlint check
#   - gitleaks
#   - markdownlint
# Jezeli ktlint failuje:
#   - autofix: ktlint -F
#   - retry commit
```

---

## 7. Secrets management

### 7.1 GitHub Actions secrets per repo

Konfigurowane w `Settings → Secrets → Actions`:

| Secret | Repo | Use |
|--------|------|-----|
| `B2_KEY_ID` | wszystkie | rclone upload releases |
| `B2_APPLICATION_KEY` | wszystkie | rclone |
| `DEPLOY_SSH_KEY` | buffer, web | SSH na VPS |
| `STRIPE_TEST_SECRET_KEY` | buffer | integration tests |
| `STRIPE_TEST_WEBHOOK_SECRET` | buffer | webhook tests |
| `SLACK_WEBHOOK_RELEASE` | wszystkie | Notify release |
| `GH_TOKEN_RELEASE` | wszystkie | Create GH releases |

### 7.2 Secrets w 1Password

- Backup wszystkich secrets w 1Password Vault "ProperBackup Production"
- Rotacja raz na rok (Q1) — wszystkie keys
- Audit log: kto, kiedy, dlaczego (`audit/secret-rotation-log.md`)

### 7.3 Local dev secrets

`.env.local` per repo, **never** w gicie.
Plik `.env.example` z placeholderami w gicie.

---

## 8. Edge Cases

### 8.1 GitHub Actions outage

CI nie dziala, blokuje wszystkie merge.

**Wymagane:**
- Override admin merge (manual w GH UI)
- Status page komunikuje "CI degraded"

### 8.2 Test flaky

Test passuje 80% czasu (np. race condition w Testcontainers).

**Wymagane:**
- `@RetryingTest(3)` annotation
- W CI: track flaky tests w `flaky-tests.txt`, dziewieć z dziesieciu requestow musza zdawac
- Alert: > 3 flaky tests → naprawa pilna

### 8.3 Cache corruption

`~/.gradle/caches` corrupted, build failuje.

**Wymagane:**
- Workflow input: `clear_cache: true` jako manual trigger
- Auto-purge cache co 30 dni

### 8.4 PR od fork (security)

Contributor zewnetrzny robi PR z forka. CI uruchamiany z secrets?

**Wymagane:**
- Forks NIE maja dostępu do secrets (GH default)
- Sensitive jobs (deploy, release) tylko na pushes from internal branches
- `pull_request_target` zamiast `pull_request` tylko po peer review

### 8.5 Gradle daemon OOM

W CI Java OOM przy duzych testach.

**Wymagane:**
- `org.gradle.jvmargs=-Xmx4g` w `gradle.properties`
- `--no-daemon` w CI (clean state per run)

### 8.6 Test fails na main (broken main)

Race: dwa PRs mergowane jeden po drugim, integracyjnie sie psuja.

**Wymagane:**
- Branch protection rule: "require up-to-date branch before merge"
- Merge queue (GH feature) — sekwencyjny merge z testem

### 8.7 Dependency vulnerability bez auto-fix

Dependabot alert, ale tylko ze major version bump (breaking).

**Wymagane:**
- Triage w ciagu 7 dni
- Severity HIGH/CRITICAL: priority task
- Severity LOW: zostaw na nastepny sprint

### 8.8 Docker rate limit (Docker Hub)

CI sciaga obrazy, Docker Hub rate-limit 100 req/6h dla anon users.

**Wymagane:**
- Konto Docker Hub (paid: 10 USD/mies) lub
- Mirror w GHCR (`docker login ghcr.io`)

### 8.9 GHCR storage limit

Docker images w GHCR rosną.

**Wymagane:**
- Retention policy: `<branch-name>` tagi keep 30 dni
- `latest` tag keep
- Tag `v*` keep indefinite (releases)

### 8.10 Test report bardzo duzy

Test report >100MB jako artifact.

**Wymagane:**
- Cleanup `build/reports/tests/*/screenshots/` przed upload (jezeli e2e Playwright)
- Artifact retention: 30 dni

---

## 9. Definition of Done

Per task `[CICD-Xn]`:

1. **Red test first** (gdy aplikable, np. workflow file)
2. **Workflow zaprojektowany pod GH Actions free tier** (nie palac billing)
3. **Brak secrets w yamlach** (wszystko przez `${{ secrets.* }}`)
4. **Cache configured** (Gradle, npm, Docker)
5. **Timeout per job** (default 30 min, alert jezeli wykracza)
6. **DOTYKAJ zone respected** (tylko `.github/`, `package.json`, `build.gradle.kts` additions)
7. **README badge added** dla CI status (npmjs/shields.io)
8. **Branch protection updated** po pierwszym successful run
9. **Smoke test:** trigger workflow manualnie, sprawdz green
10. **Docs:** dodaj sekcje w `properbackup-docs/operations/ci-cd.md` z linkami

---

## 10. Sequence of work

1. **`[CICD-A1]` Buffer build + unit tests** — fundament, najwazniejsze repo
2. **`[CICD-A2]` Buffer integration tests** (Testcontainers) — chronisz billing logic
3. **`[CICD-B1]` Kotlin ktlint** — kod style
4. **`[CICD-C2]` Secret scanning** — bezpieczenstwo
5. **`[CICD-D1]` Pre-commit hooks** — local quality
6. **`[CICD-A3]` Web build + tests** — frontend
7. **`[CICD-B2]` ESLint + Prettier** — JS style
8. **`[CICD-A5]` Docs lint** — markdown quality
9. **`[CICD-A4]` Agent multi-platform build** — distribution
10. **`[CICD-E2]` Versioning convention (CalVer)** — przed pierwszym release
11. **`[CICD-E1]` Tag-driven release pipeline** — distributability
12. **`[CICD-E3]` Changelog automation**
13. **`[CICD-E4]` Deploy to prod (manual gate)** — production deployment
14. **`[CICD-E5]` Rollback procedure**
15. **`[CICD-C1]` Dependabot** — long-term sec maintenance
16. **`[CICD-C3]` CodeQL** — static analysis
17. **`[CICD-F1]` PR template enforcement**
18. **`[CICD-F2]` CHANGELOG update enforcement**
19. **`[CICD-G1]` + `[CICD-G2]` Budget + cache optimization** — operational tuning

---

## 11. Go/No-Go checklist

Przed pierwszym oficjalnym release:

- [ ] Buffer CI green dla main branch
- [ ] Agent CI green, 4 platform artifacts
- [ ] Web CI green, bundle size <500KB
- [ ] Shared CI green
- [ ] Docs CI green (markdownlint, dead links)
- [ ] Branch protection on main: required checks = `Build`, `Test`, `Lint`
- [ ] Pre-commit hooks documented w README per repo
- [ ] Secret scanning aktywny (gitleaks lub GH Advanced Security)
- [ ] Dependabot aktywny, pierwszy PR przetestowany
- [ ] Conventional commits enforced (commitlint)
- [ ] CalVer convention zatwierdzony, w `CONTRIBUTING.md`
- [ ] Release workflow przetestowany na pre-release tag (`v2026.05.26-rc.1`)
- [ ] Deploy to prod workflow przetestowany na staging environment
- [ ] Rollback drill udany (manual, raz)
- [ ] CHANGELOG.md istnieje per repo
- [ ] CONTRIBUTING.md per repo z setup instructions
- [ ] CODE_OF_CONDUCT.md (jezeli open-source plan)
- [ ] SECURITY.md per repo (vulnerability disclosure)

---

## Dodatek A — Linki

- `master-tdd-plan.md` — billing tests w CI
- `agent-vps-master-spec.md` — agent build matrix
- `observability-and-dr-spec.md` — monitoring deployowane przez CI
- `ovh-cloud-archive-migration-spec.md` — OVH staging credentials w CI secrets

## Dodatek B — GitHub Actions cost estimation

| Repo | Avg PR/mies | Avg job min/PR | Total min/mies |
|------|------------|---------------|---------------|
| buffer | 25 | 15 | 375 |
| web | 15 | 5 | 75 |
| agent | 10 | 20 (matrix x4) | 200 |
| shared | 8 | 8 | 64 |
| stack | 5 | 3 | 15 |
| docs | 10 | 2 | 20 |
| **Total** | | | **~750 min/mies** |

GH Free tier: 2000 min/mies → **mamy 60% naciagniecia**.

Releases (~1/tydzien): +50 min = nadal w free tier.

## Dodatek C — Glosariusz

- **CalVer** — Calendar Versioning, format `YYYY.MM.DD`
- **SemVer** — Semantic Versioning, `MAJOR.MINOR.PATCH`
- **Conventional Commits** — convention `<type>: <description>`
- **Dependabot** — GitHub bot dla dependency updates
- **CodeQL** — GitHub statyczna analiza
- **gitleaks** — secret scanner
- **ktlint** — Kotlin linter
- **GHCR** — GitHub Container Registry
- **B2** — Backblaze B2 (S3-compatible object storage)
- **Branch protection** — GitHub rule enforcing CI passing przed merge
