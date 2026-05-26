# Architektura

Dokumentacja decyzji architektonicznych i schematow komponentow.

## Master Spec Plans (TDD + DOTYKAJ vs NIE RUSZAJ)

Ten katalog zawiera kompletna mape dla przyszlych agentow ProperBackup. Kazdy master spec to single source of truth dla okreslonego obszaru projektu. Wszystkie pliki uzywaja identycznego formatu (sekcje Cel/Protokol, Mapa kodu, DOTYKAJ vs NIE RUSZAJ, Domain Model, Test Groups, Edge Cases, DoD, Workflow, Go/No-Go, Appendices).

| Priorytet | Master Plan | Zakres | Repozytoria |
|-----------|-------------|--------|-------------|
| **P0** | [Observability & DR](observability-and-dr-spec.md) | PostgreSQL backup/restore, monitoring, SLO/SLA, runbooki, status page, cost monitoring | `buffer`, `stack`, `docs` |
| **P0** (billing) | [Master TDD & Resilience Plan](master-tdd-plan.md) | Billing pre-prod hardening: 10 testow A-H, 30+ edge cases, DLQ, agent JWT, ProcessingScreen, dunning, cleanup | `buffer`, `web` |
| **P1** | [Agent VPS](agent-vps-master-spec.md) | Resumable upload, circuit breaker, IoThrottle 50MB/s, JWT 5min, jlinkDist multi-platform, auto-update | `agent`, `shared` |
| **P1** | [OVH Cloud Archive Migration](ovh-cloud-archive-migration-spec.md) | Live storage migracja, koszty per GB, cold tier 90d, disaster recovery z OVH, cutover plan | `buffer`, `stack` |
| **P1** | [CI/CD Release Pipeline](ci-cd-release-pipeline-spec.md) | GitHub Actions per repo, Testcontainers w CI, SemVer/CalVer, release workflow, secret scanning | wszystkie 6 repo |
| **P1** | [Buffer Core (non-billing)](buffer-core-master-spec.md) | Chunk lifecycle, pack 950MB, ChunkSealer, BudgetGuard/StorageQuotaGuard fail-safe, audit PDF, server lifecycle | `buffer` |
| **P2** | [Web Panel (non-subscription)](web-panel-master-spec.md) | Timeline view, 1-Click Restore, Audit PDF download, agent activation UI, monitoring tab, i18n | `web` |
| **P2** | [Crypto & Compliance](crypto-and-compliance-spec.md) | Audit AES-256-GCM/Argon2id (read-only), RODO art. 32, DPA template, data flow, art. 17 deletion, breach notif | `shared`, `buffer`, `docs/legal/` |
| **P3** | [Minecraft Plugin](minecraft-plugin-master-spec.md) | Paper/Spigot/Folia lifecycle, world save hooks, `/properbackup activate`, compat matrix, plugin reload safety | `mc` |

Workflow: agent z tych specow startuje czytajac `master-tdd-plan.md` (billing wzor), wybiera plan zgodny ze swoim zadaniem, trzyma sie sekcji DOTYKAJ/NIE RUSZAJ i Workflow Protocol.

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
