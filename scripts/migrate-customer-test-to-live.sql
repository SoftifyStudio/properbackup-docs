-- =============================================================================
-- Skrypt migracyjny: Przenoszenie uzytkownikow z test na live Stripe
-- =============================================================================
--
-- KIEDY UZYWAC:
--   Gdy chcesz przelaczac istniejacych uzytkownikow (z test customer_id)
--   na produkcyjne klucze Stripe. UWAGA: ten skrypt NIE tworzy nowych
--   customerow w live Stripe — to robi aplikacja automatycznie przy
--   nastepnym checkout. Skrypt jedynie ustawia flage i czytelnie raportuje
--   stan migracji.
--
-- WAZNE:
--   Stripe customer IDs sa unikalne per srodowisko.
--   cus_xxx z test NIE zadziala z live kluczami.
--   Dlatego po przeniesieniu na live:
--     1. Stary test customer_id zostaje (do ewentualnego powrotu)
--     2. Nowy live customer_id tworzony automatycznie przez aplikacje
--     3. Uzytkownik musi ponownie przejsc checkout w live mode
--
-- =============================================================================

-- 1. AUDIT: Sprawdz stan przed migracja
SELECT
  id,
  email,
  stripe_test_mode,
  stripe_customer_id AS test_customer_id,
  stripe_live_customer_id AS live_customer_id,
  stripe_subscription_id AS test_subscription_id,
  stripe_live_subscription_id AS live_subscription_id,
  subscription_plan,
  subscription_expires_at
FROM users
WHERE stripe_customer_id IS NOT NULL
ORDER BY email;

-- 1a. AUDIT: Sprawdz czy live price IDs sa juz utworzone w Stripe
-- (sa tworzone *lazy* przy pierwszym live checkoutcie)
SELECT plan_key, mode, stripe_price_id, updated_at
FROM stripe_price_config
ORDER BY plan_key, mode;

-- 2. Przelacz wybranego uzytkownika na live
-- ZMIEN 'user@example.com' na email uzytkownika
BEGIN;

UPDATE users
SET stripe_test_mode = FALSE
WHERE email = 'user@example.com';

-- Weryfikacja
SELECT id, email, stripe_test_mode,
       stripe_customer_id, stripe_live_customer_id,
       stripe_subscription_id, stripe_live_subscription_id
FROM users
WHERE email = 'user@example.com';

COMMIT;

-- 3. (OPCJONALNE) Przelacz WSZYSTKICH uzytkownikow na live
-- UWAGA: Uzyj tylko gdy jestes gotowy na produkcje!
-- BEGIN;
-- UPDATE users SET stripe_test_mode = FALSE WHERE stripe_test_mode = TRUE;
-- COMMIT;

-- 4. (OPCJONALNE) Powrot na test
-- UPDATE users SET stripe_test_mode = TRUE WHERE email = 'user@example.com';

-- =============================================================================
-- CO SIE DZIEJE PO MIGRACJI:
--
-- 1. UI wyswietla "Live" zamiast "Test Mode" przy karcie
-- 2. Nastepny checkout:
--    a. Aplikacja sprawdza stripe_live_customer_id → NULL
--    b. Tworzy nowego customera w live Stripe
--    c. Zapisuje do stripe_live_customer_id
--    d. Sprawdza stripe_price_config (plan_key, mode='live') → jesli brak, tworzy
--       Product/Price w live Stripe i zapisuje do bazy (lazy bootstrap)
--    e. Uzytkownik podpina prawdziwa karte
-- 3. Po sukcesie checkoutu:
--    a. Nowy sub ID zapisywany w stripe_live_subscription_id
--    b. Stary stripe_subscription_id (test) pozostaje nietkniety
--       (mozna na niego wrocic flipujac stripe_test_mode = TRUE)
-- 4. Webhooki z live Stripe sa weryfikowane live webhook secret
--    (dual-secret na tym samym endpoincie /api/payment/stripe/webhook)
-- =============================================================================
