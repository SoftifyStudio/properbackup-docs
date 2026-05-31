# Decyzja: HotPay vs Stripe — wybor providera platnosci

> **Status:** Decyzja podjeta. **Stripe** jest jedynym providerem platnosci w ProperBackup.
> HotPay byl rozpatrywany jako alternatywa dla polskiego rynku, ale zostal odrzucony.

---

## Kontekst

We wczesnej fazie projektu (sesja f90660be, maj 2026) rozwazane byly dwa providery platnosci:

1. **Stripe** — globalny provider, karty kredytowe, subskrypcje, trial, webhook ecosystem
2. **HotPay** — polski provider, BLIK + przelewy bankowe, popularne w Polsce

Implementacja sandbox HotPay zostala rozpoczeta w `properbackup-buffer` (branch z sesji f90660be):
- `POST /payment/simulate` — lokalna symulacja bez zapytan do HotPay
- `POST /payment/notification` — webhook z weryfikacja hash SHA-256
- Wymagane env vars: `HOTPAY_SECRET`, `HOTPAY_NOTIFICATION_PASSWORD`

## Decyzja: Stripe (jedyny provider)

### Dlaczego Stripe

1. **Subskrypcje natywnie** — Stripe obsluguje caly cykl zycia subskrypcji (trial, billing cycle, cancel, reactivate, dunning) bez dodatkowego kodu. HotPay wymagalby recznej implementacji calej logiki billingowej.

2. **Trial abuse prevention** — Stripe card fingerprint pozwala wykrywac te sama karte na roznych kontach. HotPay (BLIK) nie ma odpowiednika — kazda transakcja BLIK jest anonimowa.

3. **Key isolation (test/live)** — Stripe ma natywne dual-environment API (sk_test/sk_live). Cala architektura `StripeKeyProvider` + per-user `stripe_test_mode` jest zbudowana na tym modelu.

4. **Webhook ecosystem** — `checkout.session.completed`, `invoice.paid`, `invoice.payment_failed`, `customer.subscription.updated/deleted` — gotowy event-driven flow. HotPay ma jeden callback `NOTIFICATION_URL`.

5. **Idempotency** — Stripe zapewnia `event.id` per webhook (dedup natywny). `stripe_event_idempotency` table jest calkowicie oparta na tym mechanizmie.

6. **Proration i plan change** — Stripe oblicza proration automatycznie. HotPay nie obsluguje subskrypcji, wiec proration trzeba liczyc recznie.

7. **Zasieg** — ProperBackup celuje nie tylko w polski rynek (VPS/Dedicated sa globalne). Stripe obsluguje 46 krajow i 135+ walut.

### Co tracisz bez HotPay

1. **BLIK** — najpopularniejsza metoda platnosci w Polsce (~70% transakcji online). Stripe obsluguje BLIK od 2023 jako osobna metode platnosci (trzeba wlaczyc w Stripe Dashboard → Payment Methods → BLIK). **Nie trzeba HotPay do obslugi BLIK.**

2. **Polskie przelewy bankowe** — Stripe obsluguje Przelewy24 (P24) jako metode platnosci. **Nie trzeba HotPay.**

3. **Nizsza prowizja** — HotPay moze miec nizsza prowizje niz Stripe dla polskich transakcji. Przy skali <500 klientow roznica jest nieistotna.

## Status kodu HotPay

Kod sandbox HotPay z sesji f90660be **nie zostal zmergowany do main**. Zyl na branchu roboczym i nie ma odpowiadajacego PR-a w `properbackup-buffer`. Zaden spec w `properbackup-docs` nie referencjonuje HotPay.

**Decyzja:** Kod HotPay jest martwy. Nie planujemy go integrować. Jesli w przyszlosci pojawi sie potrzeba (np. klienci odmawiaja podania karty), nalezy wrocic do tematu jako osobny task z nowa specyfikacja.

## Jak wlaczyc BLIK i P24 w Stripe

1. Stripe Dashboard → Settings → Payment Methods
2. Wlacz "BLIK" i "Przelewy24"
3. W `createCheckoutSession()` dodaj `payment_method_types: ["card", "blik", "p24"]`
4. Stripe automatycznie obsluguje reszte (redirect, webhook, itp.)

> **Uwaga:** BLIK w Stripe wymaga jednorazowej aktywacji przez Stripe support
> (formularz w Dashboard). Nie jest dostepny out-of-the-box dla kazdego konta.

---

## Powiazane dokumenty

- [Stripe Key Isolation](stripe-key-isolation.md) — per-user test/live mode
- [Master TDD Plan](master-tdd-plan.md) — testy billingowe i Go/No-Go
- [Operational Risks](operational-risks.md) — ryzyka Stripe
- [Env Reference](../deployment/env-reference.md) — zmienne srodowiskowe Stripe
