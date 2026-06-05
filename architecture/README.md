# Architektura

Dokumentacja decyzji architektonicznych i schematow komponentow.

## Master Spec Plans (TDD + DOTYKAJ vs NIE RUSZAJ)

Ten katalog zawiera kompletna mape dla przyszlych agentow ProperBackup. Kazdy master spec to single source of truth dla okreslonego obszaru projektu. Wszystkie pliki uzywaja identycznego formatu (sekcje Cel/Protokol, Mapa kodu, DOTYKAJ vs NIE RUSZAJ, Domain Model, Test Groups, Edge Cases, DoD, Workflow, Go/No-Go, Appendices).

| Priorytet | Master Plan | Zakres | Repozytoria |
|-----------|-------------|--------|-------------|
| **P0** (fundament) | [Shared Core Architecture](shared-core-architecture-spec.md) | "Jeden JAR" kontrakt KMP, `HostAdapter` interface, cross-host parity tests, forbidden imports lint — fundament dla agent VPS + MC + future Fabric/Forge | `shared`, `agent`, `mc` |
| **P0** | [Observability & DR](observability-and-dr-spec.md) | PostgreSQL backup/restore, monitoring, SLO/SLA, runbooki, status page, cost monitoring | `buffer`, `stack`, `docs` |
| **P0** (billing) | [Master TDD & Resilience Plan](master-tdd-plan.md) | Billing pre-prod hardening: 10 testow A-H, 30+ edge cases, DLQ, agent JWT, ProcessingScreen, dunning, cleanup | `buffer`, `web` |
| **P1** | [Agent VPS](agent-vps-master-spec.md) | Resumable upload, circuit breaker, IoThrottle 50MB/s, JWT 5min, jlinkDist multi-platform, auto-update | `agent`, `shared` |
| **P1** | [OVH Cloud Archive Migration](ovh-cloud-archive-migration-spec.md) ⚠️ *superseded* | Live storage migracja, koszty per GB, cold tier 90d, disaster recovery z OVH, cutover plan — **odejście od Cloud Archive, patrz [Storage Backend Decision](storage-backend-decision.md)** | `buffer`, `stack` |
| **P1** | [CI/CD Release Pipeline](ci-cd-release-pipeline-spec.md) | GitHub Actions per repo, Testcontainers w CI, SemVer/CalVer, release workflow, secret scanning | wszystkie 6 repo |
| **P1** | [Buffer Core (non-billing)](buffer-core-master-spec.md) | Chunk lifecycle, pack 900-950MB STRICT, persistent-first, ChunkSealer, BudgetGuard/StorageQuotaGuard fail-safe, audit PDF | `buffer` |
| **P1** | [User-Facing Recovery Mode](user-facing-recovery-spec.md) | Full-system "Time Machine" restore, Recovery Session state machine (10 stanow), per-server lockdown + warning banner, DRY RUN preview, pre-recovery snapshot, agent restore protocol (delete-then-restore), 8 E2E tests + videos | `web`, `buffer`, `agent`, `shared`, `docs` |
| **P2** | [Web Panel (non-subscription)](web-panel-master-spec.md) | Timeline view, 1-Click Restore, Audit PDF download, agent activation UI, monitoring tab, i18n | `web` |
| **P2** | [Crypto & Compliance](crypto-and-compliance-spec.md) | Audit AES-256-GCM/Argon2id (read-only), RODO art. 32, DPA template, data flow, art. 17 deletion, breach notif | `shared`, `buffer`, `docs/legal/` |
| **P3** | [Minecraft Plugin](minecraft-plugin-master-spec.md) | Paper/Spigot/Folia lifecycle, world save hooks, `/properbackup activate`, compat matrix, plugin reload safety | `mc` |

**Low-Level Design (LLD) — odpowiedź na audyt ryzyka:** każdy spec ma teraz
sekcję LLD (Dodatek/Appendix) z nazwanymi niezmiennikami, sygnaturami metod, DDL
i payloadami API. Pełny indeks: [Master TDD & Resilience Plan → Dodatek E](master-tdd-plan.md#dodatek-e--indeks-lld-odpowiedź-na-audyt-ryzyka).
Delegując zadanie agentowi, wskaż konkretny spec + sekcję LLD + numery
niezmienników, które kod musi spełnić („krótka smycz").

**Hard Requirements (Immutable Rules):** Kazdy spec zawiera sekcje `0. Hard Requirements` na poczatku — to jest **PRAWO PROJEKTU**, nienaruszalne kontrakty potwierdzone przez Daniela. Sa to fundamenty na ktorych stoi cala architektura (jeden JAR KMP, persistent-first buffer, immutable OVH storage, pack 900-950MB strict, header-first verification). Naruszenie HR = automatic rejection PR-a w review. Single Source of Truth: `Biznesplan_ProperBackup_v6_AI_Blueprint`.

Workflow: agent z tych specow startuje czytajac (1) Hard Requirements w sekcji 0, (2) `shared-core-architecture-spec.md` (jezeli pracuje na agencie/MC/shared), (3) wybrany plan zgodny ze swoim zadaniem; trzyma sie sekcji DOTYKAJ/NIE RUSZAJ i Workflow Protocol.

## Pozostala dokumentacja architektoniczna

| Dokument | Opis |
|----------|------|
| [Stripe Key Isolation](stripe-key-isolation.md) | Per-user test/live mode, izolacja kluczy, customer ID separation |
| [Ryzyka operacyjne](operational-risks.md) | Punkty zapalne: fallback kluczy, idempotency cleanup, checklist przed live |
| [Testowanie odpornosciowe](resilience-testing.md) | Chaos engineering, race conditions, fault injection, System Guard szablon |
| [Trial Abuse Prevention](trial-abuse-prevention.md) | Zabezpieczenie przed darmowymi trialami na nowe maile |
| [Subscription Expiration](subscription-expiration-handling.md) | Obsluga wygasania trialu i subskrypcji (UI + backend) |
| [UI Plan Cards Redesign](ui-plan-cards-redesign.md) | Redesign kart planow: aktywny plan, oszczednosci, brak Best Value |
| [Legal Withdrawal Waiver](legal-withdrawal-waiver.md) | Klauzula o zrzeczeniu prawa do odstapienia (art. 38 pkt 13) |
| [Pricing & Storage Economics](pricing-and-storage-economics.md) | **(robocza)** Ekonomia jednostkowa: koszt OVH (plaska stawka), pojecie fizyczne-vs-logiczne bajty, modele A/B/C, dedup jako dzwignia, benchmark iDrive, modele odrzucone. Decyzje: Dodatek F D-5/D-6 |
| [Storage Backend Decision](storage-backend-decision.md) | **(propozycja)** Odejście od OVH Cloud Archive (Swift) — powód operacyjny/zaufania, nie cenowy. Porównanie: OVH S3 / Backblaze B2 / Wasabi / Hetzner Storage Box / MinIO / kolokacja. 3-2-1 na 2 dostawcach. Reframe: realne ryzyko = format+metadane, nie provider |
| [Downgrade Logic](downgrade-logic.md) | Logika zmiany planow — max(currentExpiresAt, stripePeriodEnd), 6 scenariuszy, edge cases |
| [Kody promocyjne](promo-codes.md) | Schemat DB, typy kodow, API, jak dodawac nowe kody |
