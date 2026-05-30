# Legal — Withdrawal Right Waiver

## Wymóg prawny

Na podstawie **art. 38 pkt 13 ustawy z dnia 30 maja 2014 r. o prawach konsumenta** (Dz.U. 2014 poz. 827), konsument traci prawo do odstąpienia od umowy w terminie 14 dni, jeżeli:

> Świadczenie usługi rozpoczęło się za wyraźną zgodą konsumenta przed upływem terminu do odstąpienia od umowy i po poinformowaniu go o utracie prawa do odstąpienia.

Dotyczy to usług cyfrowych, które rozpoczynają się natychmiast po zakupie — co ma miejsce w ProperBackup (dostęp do backupu jest aktywowany od razu).

## Implementacja

### Tekst klauzuli

**PL:**
> Wyrażam zgodę na natychmiastowe rozpoczęcie świadczenia usługi cyfrowej i przyjmuję do wiadomości, że z chwilą rozpoczęcia świadczenia tracę prawo do odstąpienia od umowy w terminie 14 dni (art. 38 pkt 13 ustawy o prawach konsumenta).

**EN:**
> I consent to the immediate commencement of the digital service and acknowledge that I waive my right of withdrawal within 14 days from the moment the service begins (Art. 38(13) of the Consumer Rights Act).

### Lokalizacja w UI

Tekst jest widoczny **bezpośrednio pod kartami planów** na stronie `/account/subscription`, przed przyciskami "Wybierz i zapłać". Nie jest ukryty w regulaminie — jest wyświetlany jawnie, zgodnie z wymogiem ustawy.

```jsx
<p className="text-[11px] text-text4 leading-relaxed mt-4">
  {t('subscription.withdrawalWaiver')}
</p>
```

### Translations

```json
// pl.json
"withdrawalWaiver": "Wyrażam zgodę na natychmiastowe rozpoczęcie świadczenia usługi cyfrowej i przyjmuję do wiadomości, że z chwilą rozpoczęcia świadczenia tracę prawo do odstąpienia od umowy w terminie 14 dni (art. 38 pkt 13 ustawy o prawach konsumenta)."

// en.json
"withdrawalWaiver": "I consent to the immediate commencement of the digital service and acknowledge that I waive my right of withdrawal within 14 days from the moment the service begins (Art. 38(13) of the Consumer Rights Act)."
```

## Ważne uwagi

1. Klauzula musi być **widoczna bezpośrednio** — ukrycie w T&Cs nie spełnia wymogu
2. Dotyczy zarówno subskrypcji miesięcznej jak i rocznej
3. Widoczna dla użytkowników w wersji trial (przed zakupem) oraz po zakupie
4. Przetłumaczona na oba obsługiwane języki (PL, EN)

## Pliki zmienione

- `properbackup-web/src/subscription/SubscriptionPage.jsx`
- `properbackup-web/src/i18n/locales/pl.json`
- `properbackup-web/src/i18n/locales/en.json`

---

## LLD — utrwalenie zgody (dowód prawny)

> **Luka w obecnej formie:** dokument opisuje *wyświetlenie* klauzuli, ale nie jej
> **utrwalenie**. Dla obrony prawnej (art. 38 pkt 13) musimy umieć udowodnić, że
> dany użytkownik wyraził zgodę, kiedy i na jakiej wersji tekstu. Samo
> wyrenderowanie `<p>` nie jest dowodem.

### 1. Persystencja zgody

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS withdrawal_waiver_at      TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS withdrawal_waiver_version VARCHAR(16);  -- np. 'v1-2026-05'
```

- `withdrawal_waiver_at` — moment akceptacji (UTC).
- `withdrawal_waiver_version` — wersja tekstu klauzuli (gdy zmienimy treść, stare
  zgody zachowują swoją wersję).
- Dodatkowo wpis w `audit_log` (append-only, hash-chain — patrz
  `crypto-and-compliance-spec.md` C-5): `{event:"withdrawal_waiver", userId, version, ip, at}`.

### 2. Kontrakt checkoutu (niezmiennik)

> **Niezmiennik L-1:** `createCheckoutSession` jest **odrzucany** (`400
> WAIVER_REQUIRED`), jeśli `users.withdrawal_waiver_at IS NULL`. Zgoda jest
> warunkiem koniecznym rozpoczęcia płatnej usługi cyfrowej — egzekwowana po
> stronie backendu, nie tylko checkbox w UI.

```kotlin
// StripeHandler.createCheckoutSession(...)
require(user.withdrawalWaiverAt != null) { throw ApiError("WAIVER_REQUIRED") }
```

- Zapis zgody następuje przy świadomej akcji użytkownika (klik „Wybierz i zapłać"
  po wyświetlonej klauzuli), w tej samej transakcji co utworzenie sesji.
- Wersjonowanie: stała `WAIVER_VERSION` w kodzie; zmiana treści ⇒ bump wersji.

### 3. Cross-references

- `crypto-and-compliance-spec.md` C-5 — `audit_log` append-only (dowód zgody).
- `subscription-expiration-handling.md` — checkout flow.
- `stripe-key-isolation.md` — `createCheckoutSession`.
