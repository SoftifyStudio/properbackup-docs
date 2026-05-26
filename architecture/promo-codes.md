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
