# Architektura

Dokumentacja decyzji architektonicznych i schematow komponentow.

| Dokument | Opis |
|----------|------|
| **[Master TDD & Resilience Plan](master-tdd-plan.md)** | **Punkt prawdy dla agenta dotwardzajacego billing pre-prod: 10 testow GRUPA A-H, 30+ edge cases, strefy DOTYKAJ vs NIE RUSZAJ, protokol TDD** |
| [Stripe Key Isolation](stripe-key-isolation.md) | Per-user test/live mode, izolacja kluczy, customer ID separation |
| [Ryzyka operacyjne](operational-risks.md) | Punkty zapalne: fallback kluczy, idempotency cleanup, checklist przed live |
| [Testowanie odpornosciowe](resilience-testing.md) | Chaos engineering, race conditions, fault injection, System Guard szablon |
| [Trial Abuse Prevention](trial-abuse-prevention.md) | Zabezpieczenie przed darmowymi trialami na nowe maile |
| [Subscription Expiration](subscription-expiration-handling.md) | Obsluga wygasania trialu i subskrypcji (UI + backend) |
| [UI Plan Cards Redesign](ui-plan-cards-redesign.md) | Redesign kart planow: aktywny plan, oszczednosci, brak Best Value |
| [Legal Withdrawal Waiver](legal-withdrawal-waiver.md) | Klauzula o zrzeczeniu prawa do odstapienia (art. 38 pkt 13) |
