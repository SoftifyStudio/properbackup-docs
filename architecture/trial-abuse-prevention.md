# Trial Abuse Prevention

## Problem

Użytkownik mógł zakładać kolejne konta na nowe adresy e-mail i za każdym razem otrzymywać 30 dni darmowego trialu.

Pierwotnie `trial_expires_at` było ustawiane **retroaktywnie** przez migrację w `schema.sql`, która uruchamiała się przy każdym starcie aplikacji:

```sql
UPDATE users SET trial_expires_at = created_at + INTERVAL '30 days'
  WHERE trial_expires_at IS NULL;
```

To powodowało, że:
1. Każdy nowy użytkownik startował z `trial_expires_at = NULL`
2. Dopiero po restarcie serwera migracja ustawiała datę wygaśnięcia
3. W oknie między rejestracją a restartem trial nie był egzekwowany

## Rozwiązanie

### 1. Trial ustawiany przy rejestracji (UserStore.kt)

```kotlin
companion object {
    const val TRIAL_DAYS = 30
}

fun register(email: String, plainPassword: String): User {
    val now = Instant.now()
    val trialExpires = now.plus(Duration.ofDays(TRIAL_DAYS.toLong()))
    // INSERT INTO users (..., trial_expires_at) VALUES (..., ?)
    ps.setTimestamp(7, Timestamp.from(trialExpires))
}
```

`trial_expires_at` jest teraz ustawiany atomowo razem z `INSERT` — brak okna bez ochrony.

### 2. Migracja z guardem (schema.sql)

```sql
UPDATE users SET trial_expires_at = created_at + INTERVAL '30 days'
  WHERE trial_expires_at IS NULL
    AND subscription_plan IS NULL
    AND ever_subscribed = FALSE;
```

Guard `ever_subscribed = FALSE` zapobiega sytuacji, w której użytkownik, który już kiedyś płacił, dostaje ponownie darmowy trial.

### 3. Stripe jako dodatkowa warstwa

Sam Stripe jest najskuteczniejszą blokadą — ta sama karta kredytowa = ten sam customer, nawet jeśli e-mail jest inny. Konfiguracja w panelu Stripe:
- Ustawienie limitu jednego trialu na kartę
- Rozpoznawanie powtarzających się kart

## Weryfikacja

| Test | Wynik |
|------|-------|
| Nowe konto → `trial_expires_at` = `created_at + 30 dni` | PASS |
| Drugie konto → niezależny `trial_expires_at` | PASS |
| `ever_subscribed = TRUE` → migracja nie nadpisze | PASS |

## Pliki zmienione (warstwa 1 — JUŻ wdrożone)

- `properbackup-buffer/src/main/kotlin/.../auth/UserStore.kt` — dodano `TRIAL_DAYS`, ustawianie `trial_expires_at` przy INSERT
- `properbackup-buffer/src/main/resources/schema.sql` — guard `ever_subscribed = FALSE` w migracji

---

# LLD / Threat Model — Trial Abuse Prevention v2

> **Status:** Powyższe (warstwa 1) jest wdrożone i chroni przed *naiwnym* abuse'em
> (rejestracja → restart → brak ochrony). Poniższa sekcja to **Low-Level Design**
> dla zaawansowanych wektorów ataku. Jest to **kontrakt dla agenta** — opisuje
> dokładne schematy DB, sygnatury metod, payloady i algorytmy decyzyjne, tak aby
> agent nie musiał zgadywać intencji biznesowych. Dopóki sekcja nie jest
> zaimplementowana, traktuj ją jako spec do TDD (najpierw test czerwony).

## 1. Model zagrożeń (threat model)

Cel ataku: uzyskać >1 darmowy trial (30 dni) na to samo "ja ekonomiczne"
(ten sam człowiek / ta sama karta), omijając warstwę 1.

| ID | Wektor ataku | Mechanizm | Skuteczność warstwy 1 | Pokrycie v2 |
|----|--------------|-----------|------------------------|-------------|
| **AV-1** | Nowy e-mail per trial | Rejestracja na `alias+1@gmail.com`, `tempmail.io` itp. | ❌ brak — każdy e-mail = nowy trial | Email canonicalization + disposable blocklist (§3) |
| **AV-2** | Reużycie tej samej karty | Inny e-mail, ta sama karta → Stripe `customer` ten sam | ⚠️ częściowo (zależne od konfiguracji Stripe) | Stripe Radar fingerprint + `card_fingerprint` guard (§4) |
| **AV-3** | Rotacja IP / VPN | Nowe konto z innego IP, by ominąć rate-limit | ❌ brak | IP + ASN soft-signal (§5), NIE jako twardy blocker |
| **AV-4** | Manipulacja webhookiem Stripe | Podrobiony `customer.subscription.created` → "wieczny trial" | ❌ brak (jeśli brak weryfikacji podpisu) | Weryfikacja `Stripe-Signature` + idempotencja (§6) |
| **AV-5** | Race: N równoległych rejestracji | Skrypt tworzy 100 kont w 1s zanim zadziała detekcja | ❌ brak | Rate-limit per IP + unikalny constraint (§5, §7) |
| **AV-6** | Reaktywacja po wygaśnięciu | Skasowanie konta → ponowna rejestracja tym samym e-mailem | ⚠️ zależne od soft-delete | `ever_trialed` na znormalizowanym e-mailu (§3, §7) |
| **AV-7** | Trial → cancel → trial (ten sam user) | Wykorzystanie `subscription.deleted` do resetu flagi trial | ✅ pokryte przez `ever_subscribed` | bez zmian — patrz `downgrade-logic.md` |

> **Zasada projektowa:** **fail-safe ≠ fail-paranoid.** Twarde blokady (hard block)
> stosujemy wyłącznie dla sygnałów o ~zerowym false-positive (AV-2 card fingerprint,
> AV-6 powtórzony e-mail). Sygnały miękkie (AV-3 IP/ASN) NIGDY nie blokują rejestracji
> samodzielnie — służą tylko do scoringu i ręcznego review. Blokowanie legalnego
> klienta jest droższe niż jeden nadużyty trial (19 PLN).

## 2. Architektura komponentu `TrialAbuseGuard`

```
register() ─┬─► EmailNormalizer.canonical(email)          (§3)
            ├─► DisposableDomainCheck.isBlocked(domain)    (§3)
            ├─► SignupFingerprintStore.recordAttempt(...)  (§7)
            └─► AbuseScorer.score(signals) ─► Decision     (§5)
                                              │
checkout() ─► Stripe Radar / card_fingerprint guard (§4) ─┘
```

- NEW: `properbackup-buffer/.../auth/TrialAbuseGuard.kt`
- NEW: `properbackup-buffer/.../auth/EmailNormalizer.kt`
- NEW: `properbackup-buffer/.../auth/SignupFingerprintStore.kt`
- DOTYKAJ: `auth/AuthHandler.kt` (wpięcie guarda w `/auth/register`)
- DOTYKAJ: `payment/StripeHandler.kt` (card fingerprint w `checkout.session.completed`)
- NIE RUSZAJ: `auth/UserStore.kt` semantyka `trial_expires_at` (warstwa 1 zostaje)

## 3. Email canonicalization + disposable blocklist (AV-1, AV-6)

**Cel:** `john.doe+promo@gmail.com`, `JohnDoe@gmail.com`, `j.o.h.n.doe@googlemail.com`
to ten sam człowiek → ten sam `email_canonical`.

```kotlin
object EmailNormalizer {
    private val GMAIL_DOMAINS = setOf("gmail.com", "googlemail.com")

    /** Zwraca formę kanoniczną do deduplikacji trialu (NIE do logowania). */
    fun canonical(raw: String): String {
        val (localRaw, domainRaw) = raw.trim().lowercase().split("@", limit = 2)
        val domain = if (domainRaw == "googlemail.com") "gmail.com" else domainRaw
        var local = localRaw.substringBefore("+")          // usuń sub-adresowanie
        if (domain in GMAIL_DOMAINS) local = local.replace(".", "")  // gmail ignoruje kropki
        return "$local@$domain"
    }
}
```

- `email_canonical` zapisywany obok `email` (oryginał używany do logowania/komunikacji).
- **Disposable blocklist:** statyczna lista domen (np. z `disposable-email-domains`),
  ładowana do `Set<String>` przy starcie + cache. Trafienie → **NIE hard block**, ale
  trial = 0 dni (user może kupić plan normalnie). Powód: blocklisty bywają nieaktualne;
  blokowanie rejestracji = utrata legalnych klientów korzystających z firmowych aliasów.

| Reguła | Reakcja |
|--------|---------|
| `email_canonical` już ma `ever_trialed = TRUE` | trial = 0 dni (konto powstaje, ale bez trialu) |
| domena na disposable blocklist | trial = 0 dni + flaga `requires_card_upfront` |
| nowy `email_canonical`, domena OK | trial = 30 dni (warstwa 1) |

## 4. Stripe card fingerprint (AV-2) — najsilniejsza warstwa

Stripe zwraca stabilny `card.fingerprint` dla tej samej karty niezależnie od
`customer`/`email`. To jedyny sygnał o ~zerowym false-positive nadający się na hard block.

```kotlin
// W obsłudze checkout.session.completed / setup_intent.succeeded:
val fp: String = paymentMethod.card.fingerprint   // np. "Xt5EWLLDS7FJjR1c"
when (signupFingerprintStore.cardTrialStatus(fp)) {
    CardTrialStatus.FIRST_TIME -> { /* OK, zapisz fp ↔ userId */ }
    CardTrialStatus.ALREADY_TRIALED -> {
        // Hard rule: ta karta już wykorzystała trial → natychmiastowe przejście na płatność
        userStore.setTrialExpires(userId, Instant.now())   // trial = 0
        audit("trial_blocked_card_fingerprint_reuse", userId, fp.hashed())
    }
}
```

- `card.fingerprint` **nigdy** nie trafia do logów/DB w plaintext — przechowujemy
  `SHA-256(fingerprint + PEPPER)` w `signup_fingerprint.card_fp_hash`.
- Dodatkowo włączyć **Stripe Radar rule**: `block if :card_fingerprint: has >1 trial`.
- Card-first trial (karta wymagana do startu trialu) jest tu kluczowy — bez karty
  na starcie AV-2 nie da się egzekwować. Zgodne z modelem 30-dniowego trialu card-first.

## 5. Scoring miękkich sygnałów (AV-3, AV-5)

```kotlin
data class SignupSignals(
    val emailCanonical: String,
    val ipAddress: String,
    val asn: Int?,            // z GeoIP, opcjonalne
    val disposableDomain: Boolean,
    val accountsFromIpLast24h: Int,
)

enum class Decision { ALLOW_TRIAL, ALLOW_NO_TRIAL, SOFT_REVIEW }

object AbuseScorer {
    fun decide(s: SignupSignals): Decision = when {
        s.disposableDomain -> Decision.ALLOW_NO_TRIAL
        s.accountsFromIpLast24h >= 5 -> Decision.SOFT_REVIEW  // flaga, nie blok
        else -> Decision.ALLOW_TRIAL
    }
}
```

- IP/ASN to **soft-signal**: maksymalnie obniża trial lub flaguje do review,
  NIGDY nie blokuje rejestracji (NAT/CGNAT/akademiki = wiele legalnych kont z 1 IP).
- `accountsFromIpLast24h` liczone z `signup_fingerprint` (§7).

## 6. Twardnienie webhooków Stripe (AV-4)

Patrz też `stripe-key-isolation.md` i `downgrade-logic.md`. Wymogi minimalne:

1. **Weryfikacja podpisu** — `Webhook.constructEvent(payload, sigHeader, endpointSecret)`.
   Brak/niepoprawny `Stripe-Signature` → `400`, zdarzenie odrzucone, log `webhook_sig_invalid`.
2. **Idempotencja** — `event.id` zapisany w `processed_stripe_event(event_id PK)`;
   ponowne dostarczenie = no-op (`200 OK`, bez side-effectów).
3. **Allowlist typów** — przetwarzamy tylko: `checkout.session.completed`,
   `customer.subscription.created|updated|deleted`, `invoice.paid|payment_failed`.
   Pozostałe → `200 OK` + ignor.
4. **Brak zaufania do pól z body** dla decyzji o trialu — `trial_expires_at`
   wyliczamy serwerowo (warstwa 1), nigdy z payloadu webhooka.

## 7. Schemat bazy danych (PostgreSQL)

```sql
-- Migracja: VXXXX__trial_abuse_v2.sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_canonical VARCHAR(320);
ALTER TABLE users ADD COLUMN IF NOT EXISTS ever_trialed BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_users_email_canonical ON users(email_canonical);

CREATE TABLE IF NOT EXISTS signup_fingerprint (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT REFERENCES users(id) ON DELETE SET NULL,
    email_canonical VARCHAR(320) NOT NULL,
    ip_address      INET,
    asn             INTEGER,
    card_fp_hash    CHAR(64),               -- SHA-256(fingerprint + PEPPER), NULL do checkout
    disposable      BOOLEAN NOT NULL DEFAULT FALSE,
    decision        VARCHAR(16) NOT NULL,   -- allow_trial | allow_no_trial | soft_review
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fp_ip_time ON signup_fingerprint(ip_address, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_fp_card_trial
    ON signup_fingerprint(card_fp_hash) WHERE card_fp_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS processed_stripe_event (
    event_id     VARCHAR(64) PRIMARY KEY,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

> **fail-safe DB:** jeśli `signup_fingerprint`/GeoIP są niedostępne podczas rejestracji,
> guard degraduje do warstwy 1 (trial przyznany), ale **NIE** przyznaje trialu, jeśli
> `users.ever_trialed = TRUE` dla danego `email_canonical` (ten odczyt jest w tej samej
> transakcji co INSERT usera, więc zawsze dostępny).

## 8. Sygnatury API guarda

```kotlin
class TrialAbuseGuard(
    private val fingerprints: SignupFingerprintStore,
    private val disposable: DisposableDomainCheck,
    private val clock: Clock,
) {
    /** Wołane w transakcji rejestracji (ten sam conn co INSERT usera). */
    fun evaluateRegistration(conn: Connection, email: String, ip: String): TrialGrant

    /** Wołane przy checkout.session.completed po pobraniu PaymentMethod. */
    fun evaluateCard(conn: Connection, userId: Long, cardFingerprint: String): CardTrialStatus
}

data class TrialGrant(val trialDays: Int, val decision: Decision, val requiresCardUpfront: Boolean)
```

## 9. Macierz testów akceptacyjnych (TDD, Testcontainers + PostgreSQL 16)

| Test | Wektor | Oczekiwanie |
|------|--------|-------------|
| `john+1@gmail.com` po `john@gmail.com` | AV-1 | drugi trial = 0 dni (`ever_trialed`) |
| `j.o.h.n@gmail.com` ≡ `john@gmail.com` | AV-1 | canonical kolizja → trial = 0 |
| domena `tempmail.io` | AV-1 | trial = 0 + `requires_card_upfront` |
| ta sama karta, inny e-mail | AV-2 | `CardTrialStatus.ALREADY_TRIALED` → trial = 0 |
| 6 rejestracji z 1 IP / 24h | AV-3/5 | `SOFT_REVIEW`, ale rejestracja przechodzi (brak blokady) |
| webhook bez `Stripe-Signature` | AV-4 | `400`, brak side-effectu |
| ten sam `event.id` 2× | AV-4 | drugi = no-op (idempotencja) |
| GeoIP down podczas rejestracji | fail-safe | trial przyznany (degradacja do warstwy 1) |
| legalny user z firmowego NAT (5 kont) | false-positive | wszystkie konta aktywne, brak hard block |

## 10. Cross-references

- `stripe-key-isolation.md` — izolacja kluczy/endpoint secret per środowisko (AV-4).
- `downgrade-logic.md` — `ever_subscribed`, `handleSubscriptionDeleted` (AV-7).
- `subscription-expiration-handling.md` — co po wygaśnięciu trialu.
- `master-tdd-plan.md` — sekcja edge/abuse, mapowanie testów GRUPA A..H.
