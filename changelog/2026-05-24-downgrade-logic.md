# Downgrade Logic — bezpieczna zmiana planow

**Data:** 2026-05-24
**PRy:** buffer#21, web#30

## Problem

`activateSubscription` nadpisywala `expiresAt` wartoscia z Stripe (`period_end`), ignorujac ze klient mogl miec dluzsza oplacona date. Kupno monthly przy aktywnym annual (300d left) ustawialo `expiresAt = +31 dni` — klient tracil rok.

`handleSubscriptionDeleted` zawsze kasowala plan + date — anulowanie subskrypcji Stripe oznaczalo utrate oplaconego czasu.

## Rozwiazanie

1. **`activateSubscription`**: `max(currentExpiresAt, stripePeriodEnd)` — nigdy nie skraca oplaconej daty
2. **`handleSubscriptionDeleted`**: jesli `expiresAt > now`, czysci tylko `stripe_subscription_id` (plan + data zostaja)
3. **Frontend**: usuniety downgrade guard (amber warning + disabled button) — wszystkie plany zawsze dostepne

## Efekt

- Klient z annual (300d left) kupuje monthly -> plan=monthly, expiresAt=+300d (nie +31d)
- Klient anuluje subskrypcje -> plan + data zostaja do konca oplaconego okresu
- Zero mozliwosci utraty oplaconego czasu

Pelna specyfikacja: [architecture/downgrade-logic.md](../architecture/downgrade-logic.md)
