# Architektura

Dokumentacja decyzji architektonicznych i schematow komponentow.

| Dokument | Opis |
|----------|------|
| [Stripe Key Isolation](stripe-key-isolation.md) | Per-user test/live mode, izolacja kluczy, customer ID separation |
| [Ryzyka operacyjne](operational-risks.md) | Punkty zapalne: fallback kluczy, idempotency cleanup, checklist przed live |
| [Testowanie odpornosciowe](resilience-testing.md) | Chaos engineering, race conditions, fault injection, System Guard szablon |
