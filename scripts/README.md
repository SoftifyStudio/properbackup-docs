# Skrypty

Skrypty migracyjne, narzedzia operacyjne i prompty do sesji Devin.

## Skrypty migracyjne

| Skrypt | Opis |
|--------|------|
| [migrate-customer-test-to-live.sql](migrate-customer-test-to-live.sql) | Migracja uzytkownikow z test na live Stripe (zmiana flagi + audit) |

## Prompty do sesji Playwright TDD

Gotowe prompty do kopiowania i wklejania w nowe sesje Devin. Kazdy prompt = jedna grupa
testow (3-6 scenariuszy). Plan referencyjny: [Playwright E2E TDD Plan](../architecture/playwright-tdd-plan.md).

| Prompt | Grupa | Scenariuszy | Priorytet |
|--------|-------|-------------|-----------|
| [Prompt #1 — Stripe & Money](prompts/prompt-01-edge-money.md) | E1: EDGE-MONEY-01..06 | 6 | P0 |
| Prompt #2 — Webhook & Race | E4: EDGE-RACE-01..04 | 4 | P0 |
| Prompt #3 — Trial Abuse & Auth | E2: EDGE-AUTH-01..05 | 5 | P1 |
| Prompt #4 — UI/UX | E3: EDGE-UI-01..06 | 6 | P1 |
| Prompt #5 — Recovery & Storage | E5: EDGE-STORE-01..03 | 3 | P2 |

Prompty #2-#5 beda dodawane po zakonczeniu i review promptu #1.
