# System kodów promocyjnych (Promo Codes)

## Gdzie przechowywane

Kody promocyjne przechowywane są w **PostgreSQL** w tabeli `promo_code`. Wykorzystanie kodów przez użytkowników śledzi tabela `promo_code_usage`.

## Schemat bazy danych

### Tabela `promo_code`

```sql
CREATE TABLE IF NOT EXISTS promo_code (
  id                BIGSERIAL PRIMARY KEY,
  code              VARCHAR(64) UNIQUE NOT NULL,
  type              VARCHAR(16) NOT NULL DEFAULT 'percentage',
  discount_percent  INT,          -- rabat procentowy (np. 50 = 50%)
  discount_grosz    INT,          -- rabat kwotowy w groszach (np. 500 = 5.00 PLN)
  applicable_plan   VARCHAR(16),  -- NULL = wszystkie plany, 'monthly' lub 'annual'
  max_uses          INT  NOT NULL DEFAULT 1,
  used_count        INT  NOT NULL DEFAULT 0,
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Tabela `promo_code_usage`

```sql
CREATE TABLE IF NOT EXISTS promo_code_usage (
  id             BIGSERIAL PRIMARY KEY,
  promo_code_id  BIGINT      NOT NULL REFERENCES promo_code(id),
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stripe_session VARCHAR(128),
  used_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Unique constraint: jeden użytkownik może użyć danego kodu tylko raz
CREATE UNIQUE INDEX uq_promo_usage_per_user ON promo_code_usage(promo_code_id, user_id);
```

## Typy kodów

| Typ | Opis | Pola |
|-----|------|------|
| `percentage` | Rabat procentowy od ceny bazowej | `discount_percent` (np. 50 = 50%) |
| `fixed` | Rabat kwotowy w groszach | `discount_grosz` (np. 500 = 5.00 PLN) |
| `first_order` | Rabat tylko dla nowych klientów (nigdy wcześniej nie subskrybowali) | `discount_percent` (zwykle 100) |
| `one_time` | Jednorazowy kod — każdy użytkownik może użyć max 1 raz | `discount_percent` lub `discount_grosz` |

### Pole `applicable_plan`

- `NULL` — kod działa na oba plany (monthly i annual)
- `'monthly'` — tylko plan miesięczny
- `'annual'` — tylko plan roczny

## Plany subskrypcyjne (ceny)

Ceny zdefiniowane są jako stałe w kodzie backendu (`StripeHandler.kt`):

```kotlin
const val MONTHLY_PRICE_PLN = 1900L   // 19.00 PLN brutto (grosze)
const val ANNUAL_PRICE_PLN = 19000L   // 190.00 PLN brutto (grosze)
```

Ceny są **brutto (z VAT 23%)**. Backend automatycznie tworzy produkty i ceny w Stripe przy starcie (`ensureProductAndPrices()`).

## Jak dodać nowy kod promocyjny

### Przez SQL (bezpośrednio w bazie)

Połącz się z bazą na serwerze:

```bash
ssh root@properbackup-test-server.softify.com.pl
docker exec -it properbackup-db psql -U properbackup -d properbackup
```

Przykłady:

```sql
-- 50% rabatu na wszystkie plany, max 100 użyć, ważny do końca 2027
INSERT INTO promo_code (code, type, discount_percent, max_uses, active, expires_at)
VALUES ('PROMO-50', 'percentage', 50, 100, true, '2027-01-01');

-- 20% rabatu
INSERT INTO promo_code (code, type, discount_percent, max_uses, active, expires_at)
VALUES ('WELCOME-20', 'percentage', 20, 100, true, '2027-01-01');

-- 5 PLN rabatu kwotowego (500 groszy)
INSERT INTO promo_code (code, type, discount_grosz, max_uses, active, expires_at)
VALUES ('FLAT-500', 'fixed', 500, 100, true, '2027-01-01');

-- 30% tylko na plan roczny
INSERT INTO promo_code (code, type, discount_percent, applicable_plan, max_uses, active, expires_at)
VALUES ('ANNUAL-30', 'percentage', 30, 'annual', 100, true, '2027-01-01');

-- 100% zniżki tylko dla nowych klientów, plan miesięczny
INSERT INTO promo_code (code, type, discount_percent, applicable_plan, max_uses, active, expires_at)
VALUES ('FIRST-FREE', 'first_order', 100, 'monthly', 100, true, '2027-01-01');
```

### Dezaktywacja kodu

```sql
UPDATE promo_code SET active = false WHERE code = 'PROMO-50';
```

### Sprawdzenie statystyk użycia

```sql
SELECT pc.code, pc.type, pc.discount_percent, pc.used_count, pc.max_uses, pc.active,
       COUNT(pu.id) AS actual_uses
FROM promo_code pc
LEFT JOIN promo_code_usage pu ON pu.promo_code_id = pc.id
GROUP BY pc.id
ORDER BY pc.created_at DESC;
```

## API endpointy

| Metoda | Endpoint | Opis |
|--------|----------|------|
| POST | `/api/payment/validate-promo` | Walidacja kodu (bez użycia). Body: `{"code": "PROMO-50"}` |

Odpowiedź (valid):
```json
{
  "valid": true,
  "code": "PROMO-50",
  "type": "percentage",
  "discountPercent": 50,
  "discountGrosze": null,
  "applicablePlan": null
}
```

Odpowiedź (invalid):
```json
{
  "valid": false,
  "reason": "not_found_or_expired"
}
```

Możliwe `reason`:
- `not_found_or_expired` — kod nie istnieje, wygasł lub wyczerpany
- `not_eligible_first_order` — kod `first_order` a użytkownik już miał subskrypcję
- `already_used_by_user` — kod `one_time` już użyty przez tego użytkownika
- `code_required` — nie podano kodu

## Przepływ w UI

1. Użytkownik wpisuje kod w panelu "Kod promocyjny" na stronie subskrypcji
2. Kliknięcie "Sprawdź kod" wywołuje `POST /api/payment/validate-promo`
3. Jeśli kod valid — frontend przelicza ceny z rabatem w czasie rzeczywistym
4. Rabat jest uwzględniany przy tworzeniu sesji Stripe Checkout (kupon jednorazowy)
5. Po płatności backend zapisuje użycie kodu w `promo_code_usage` i inkrementuje `used_count`

## Aktualnie skonfigurowane kody (serwer testowy)

| Kod | Typ | Rabat | Plan | Max użyć |
|-----|-----|-------|------|----------|
| `PROMO-50` | percentage | 50% | wszystkie | 100 |
| `WELCOME-20` | percentage | 20% | wszystkie | 100 |
| `FLAT-500` | fixed | 5.00 PLN | wszystkie | 100 |
| `ANNUAL-30` | percentage | 30% | roczny | 100 |
| `FIRST-FREE` | first_order | 100% | miesięczny | 100 |

---

# LLD — atomowa redempcja, race conditions i abuse

> Sekcja referencyjna dla agenta. `validate-promo` jest tylko podglądem — prawdziwa
> redempcja (inkrementacja `used_count` + zapis `promo_code_usage`) MUSI być atomowa,
> bo inaczej kod z `max_uses=100` da się wykorzystać 200× przy współbieżności.

## 1. Atomowa redempcja (anty-race)

**Zły wzorzec (TOCTOU):** `SELECT used_count` → sprawdź `< max_uses` → `UPDATE +1`.
Dwa równoległe checkouty przeczytają tę samą wartość i oba przejdą.

**Dobry wzorzec — warunkowy UPDATE w jednej instrukcji:**

```sql
-- Redempcja: zwraca 1 wiersz tylko jeśli limit nie wyczerpany. Inkrementacja warunkowa.
UPDATE promo_code
   SET used_count = used_count + 1
 WHERE code = ?
   AND active = TRUE
   AND (expires_at IS NULL OR expires_at > now())
   AND used_count < max_uses
RETURNING id, type, discount_percent, discount_grosz, applicable_plan;
-- 0 wierszy => kod wyczerpany/nieaktywny/wygasł => odrzuć checkout
```

```sql
-- Per-user limit (one_time): unikalny indeks robi robotę, łapiemy wyjątek.
INSERT INTO promo_code_usage (promo_code_id, user_id, stripe_session)
VALUES (?, ?, ?);
-- ON CONFLICT (promo_code_id, user_id) DO NOTHING => already_used_by_user
```

> **Kolejność i transakcja:** redempcja odbywa się dopiero przy potwierdzonej
> płatności (`checkout.session.completed`), w **tej samej transakcji** co
> `activateSubscription`. Jeśli płatność padnie — rollback cofa `used_count`.
> `validate-promo` (preview) NIGDY nie inkrementuje.

## 2. Sygnatury

```kotlin
sealed interface PromoResult {
    data class Valid(val code: String, val type: PromoType, val discountGrosze: Long, val applicablePlan: Plan?) : PromoResult
    data class Invalid(val reason: String) : PromoResult   // not_found_or_expired | not_eligible_first_order | already_used_by_user | code_required
}

class PromoService(private val ds: DataSource) {
    /** Bez side-effectu. Czyta stan + sprawdza eligibility usera. */
    fun validate(code: String, userId: String, plan: Plan): PromoResult

    /** Side-effect: atomowa inkrementacja + INSERT usage. W transakcji checkoutu. */
    fun redeem(conn: Connection, code: String, userId: String, plan: Plan, stripeSession: String): PromoResult
}
```

## 3. Stacking / interakcja z proracją

- **Kolejność:** `cena_bazowa → proration (downgrade-logic) → promo`. Promo liczone
  od ceny **po proracji**.
- **Clamp:** `suma_rabatów = min(cena_bazowa, proration + promo)` — nigdy poniżej `0`.
- **first_order:** eligible tylko gdy `users.ever_subscribed = FALSE` (jeden SELECT
  w `validate`/`redeem`); spójne z `trial-abuse-prevention.md`.
- **Brak łączenia wielu kodów:** jeden kod per checkout (frontend wysyła max 1 `code`).

## 4. Wektory abuse i obrona

| Wektor | Obrona |
|--------|--------|
| Współbieżny checkout > `max_uses` | warunkowy `UPDATE ... WHERE used_count < max_uses RETURNING` (§1) |
| Ten sam user redeemuje `one_time` 2× | unikalny indeks `uq_promo_usage_per_user` + `ON CONFLICT DO NOTHING` |
| `first_order` po wcześniejszej subskrypcji | guard `ever_subscribed = FALSE` |
| Redempcja bez płatności (porzucony checkout) | redempcja dopiero w `checkout.session.completed`, w transakcji |
| Brute-force zgadywanie kodów | rate-limit na `/validate-promo` (np. 10/min/IP) + brak rozróżnienia `not_found` od `expired` |
| 100% promo + proration → kwota ujemna | clamp `coerceAtLeast(0)`; Stripe min. kwota → fallback na `customer.balance` |

## 5. Testy akceptacyjne (TDD, Testcontainers)

| Test | Oczekiwanie |
|------|-------------|
| 200 wątków redeem kodu `max_uses=100` | dokładnie 100 sukcesów, 100 `not_found_or_expired` |
| `one_time` ten sam user 2× | drugi → `already_used_by_user`, brak 2. wiersza usage |
| `first_order` user z `ever_subscribed=TRUE` | `not_eligible_first_order` |
| płatność faila po redeem | rollback → `used_count` bez zmian |
| promo 30% na annual po proracji 300d | rabat ≤ cena planu, brak wartości ujemnej |

## 6. Cross-references

- `downgrade-logic.md` — proration `capped + overflow`, transakcyjność checkoutu.
- `subscription-expiration-handling.md` §3 — kolejność proration ↔ promo.
- `trial-abuse-prevention.md` — `ever_subscribed`, rate-limit endpointów.
