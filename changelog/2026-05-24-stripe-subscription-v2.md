# 2026-05-24 — Stripe Subscription v2 (platnosci Stripe)

**PRy:** buffer (branch `devin/1779463462-promo-subscription-v2`), web (branch `devin/1779463463-promo-subscription-v2`)
**Sesja:** 6ea5938bcdce4e45840dfe3fc20c1cbd

## Co zostalo dodane

### System platnosci Stripe

- **Checkout Session** — tworzenie sesji Stripe Checkout z:
  - Przelaczaniem miedzy planem miesicznym (19 PLN/mies) i rocznym (190 PLN/rok)
  - Idempotency key per checkout (zapobiega duplikatom)
  - Automatyczne anulowanie i refund istniejacych subskrypcji przy zmianie planu
  - Prorated billing przy upgrade/downgrade
  - 30-dniowy trial

- **Webhook Handler** — obsluga zdarzen Stripe:
  - `checkout.session.completed` — aktywacja subskrypcji
  - `invoice.paid` — odnowienie subskrypcji
  - `customer.subscription.updated` — aktualizacja statusu
  - Idempotency table (`stripe_event_idempotency`) — zapobiega podwojnemu przetwarzaniu
  - Fail-closed: brak webhook secret = odrzucenie wszystkich payloadow

- **Verify Session** — endpoint do weryfikacji statusu sesji checkout z frontendu

- **Card Info** — endpoint do pobierania informacji o podpietej karcie (brand, last4, exp)

- **Cancel/Reactivate** — endpointy do anulowania i reaktywacji subskrypcji

### System promo kodow

- **PromoCodeHandler** — obsluga kodow promocyjnych:
  - Kody jednorazowe i wielorazowe
  - Walidacja: czy kod istnieje, czy nie wygasl, czy user jest eligible (first-order)
  - Automatyczne tworzenie Stripe Coupon per checkout session
  - Tracking: kto uzywal, kiedy, w jakiej sesji

### System gift kodow

- **GiftCodeHandler** — obsluga kodow podarunkowych:
  - Generowanie kodow z okresem waznosci
  - Aktywacja: natychmiastowe przedluzenie subskrypcji
  - Tracking: kto generowal, kto uzyl

### Customer Balance / Credit

- Endpoint do odczytywania kredytu uzytkownika ze Stripe Customer Balance
- Wyswietlanie w UI: "Twoj kredyt: X PLN"

### Subscription Page (frontend)

- Strona subskrypcji z:
  - Kartami planow (miesiezny/roczny) z cenami brutto/netto
  - Sekcja metody platnosci (dodawanie/zmiana karty)
  - Panel promo kodow
  - Status subskrypcji (aktywna/anulowana/trial)
  - Pricing: dekompozycja VAT 23%
  - Responsywny design

### Baza danych

- Tabele: `promo_codes`, `promo_code_usage`, `gift_codes`, `stripe_event_idempotency`, `subscription_audit_log`, `stripe_price_config`, `subscription_config`
- Kolumny w `users`: `stripe_customer_id`, `stripe_subscription_id`, `subscription_cancel_at_period_end`, `ever_subscribed`

### Testy

- 100+ testow integracyjnych w `SubscriptionIntegrationTest.kt`
- Testy: cykl zycia subskrypcji, promo kody, gift kody, idempotency, webhook signature, audit log, prorated billing, VAT, concurrent checkouts
