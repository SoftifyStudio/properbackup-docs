# 2026-05-30 — LLD Hardening (odpowiedz na audyt ryzyka)

**PR:** docs#19
**Sesja:** c48e6edcfc8c4729b587caa4577dddfb

## Kontekst

Zewnetrzny audyt techniczny wskazal, ze dokumentacja w `properbackup-docs` daje dobry high-level design, ale agentowi AI brakuje **Low-Level Design** (sygnatury metod, DDL, payloady JSON, threat-modele, niezmienniki), zeby kodowac "na krotkiej smyczy" bez halucynacji.

Audyt zidentyfikowal 4 ryzyka:
1. **Puste implementacje (Black Boxes)** — specy mowia *co*, ale nie *jak*
2. **OVH cold-tier async** — agent moze potraktowac archiwum jak szybki dysk
3. **Shared core regresja** — brak wersjonowania i bramek CI
4. **Trial abuse (najslabszy)** — brak threat modelu

## Co zostalo dodane

### Sekcje LLD w kazdym spec (22 pliki w `/architecture`)

Augmentacja, nie przepisywanie — high-level design zachowany, dodane appendixy/dodatki z:
- Sygnaturami metod (Kotlin)
- Schematami DDL (PostgreSQL)
- Payloadami JSON (request/response)
- Nazwanymi niezmiennikami (np. B-1..B-5, A-1..A-5, K-1..K-5)
- Threat-modelami (trial-abuse AV-1..AV-7)

### Mapa niezmiennikow (pelny indeks)

| Spec | Sekcja LLD | Niezmienniki |
|------|-----------|--------------|
| `trial-abuse-prevention.md` | Threat Model v2 | AV-1..AV-7 |
| `downgrade-logic.md` | Kontrakt metod | I-1..I-5 |
| `subscription-expiration-handling.md` | Access Boundary | `AccessState` FSM |
| `promo-codes.md` | Atomowa redempcja | anty-TOCTOU |
| `stripe-key-isolation.md` | Dual-secret webhook | K-1..K-5 |
| `buffer-core-master-spec.md` | Dodatek C | B-1..B-5 |
| `agent-vps-master-spec.md` | Dodatek C | A-1..A-5, Circuit Breaker |
| `shared-core-architecture-spec.md` | Appendix E | S-1..S-4 |
| `ovh-cloud-archive-migration-spec.md` | Dodatek E | O-1 (`RestoreState` sealed) |
| `user-facing-recovery-spec.md` | Appendix E | R-1 |
| `crypto-and-compliance-spec.md` | Dodatek C | C-1..C-5 |
| `observability-and-dr-spec.md` | Dodatek D | Metryki + alerty per niezmiennik |
| `ci-cd-release-pipeline-spec.md` | Dodatek D | Bramki merge |
| `web-panel-master-spec.md` | Dodatek C | W-1 (`accessState` jedyne zrodlo) |
| `minecraft-plugin-master-spec.md` | Dodatek C | MC-1 |
| `legal-withdrawal-waiver.md` | LLD | L-1 |

### "Zasada smyczy" w README + master-tdd-plan

Nowy wzorzec delegowania zadan agentowi: wskazuj konkretny spec + sekcje LLD + numery niezmiennikow. Np. "zaimplementuj redeem promo wg `promo-codes.md` §5, niezmienniki anty-TOCTOU" — nie "napisz system promo".

## Weryfikacja audytu

| Ryzyko z audytu | Pokrycie po LLD |
|-----------------|-----------------|
| #1 Puste implementacje | Per-metodowe sygnatury + DDL w buffer-core, agent-vps |
| #2 OVH cold-tier async | `RestoreState` sealed interface wymusza async |
| #3 Shared core regresja | SemVer + exact pinning + bramki CI |
| #4 Trial abuse | Threat model 7 wektorow (AV-1..AV-7) + DDL |
