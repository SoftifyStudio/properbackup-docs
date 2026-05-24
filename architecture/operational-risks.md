# Ryzyka operacyjne — punkty zapalne

Nawet najlepszy kod nie przewidzi wszystkiego. Ponizej lista znanych ryzyk operacyjnych i jak sie przed nimi chronic.

---

## 1. Fallback kluczy Stripe: test zamiast live (RYZYKO BIZNESOWE)

### Problem

`StripeKeyProvider` ma wbudowany fallback: jesli `STRIPE_LIVE_SECRET_KEY` nie jest ustawiony, live klucz = test klucz. To oznacza:

- Jesli zapomnisz ustawic `STRIPE_LIVE_SECRET_KEY` na produkcji...
- ...i przelaczysz uzytkownika na `stripe_test_mode = FALSE`...
- ...system bedzie pobieral platnosci **testowe** zamiast prawdziwych
- Uzytkownik zobaczy "Live" w UI, ale platnosc trafi do Stripe TEST dashboard
- **Strata przychodu** — realne pieniadze nie zostana pobrane

### Jak sie chronic

#### A. Walidacja przy starcie aplikacji (rekomendacja)

Dodaj sprawdzenie w `StripeKeyProvider.init {}`:

```kotlin
init {
    // ... istniejacy kod logowania prefixow ...

    // OSTRZEZENIE: live klucze == test klucze
    if (liveSecretKey == testSecretKey && testSecretKey.isNotBlank()) {
        log.warn("⚠️ STRIPE LIVE KEYS ARE IDENTICAL TO TEST KEYS — " +
            "live billing will use test Stripe. Set STRIPE_LIVE_SECRET_KEY " +
            "before promoting any user to stripe_test_mode=FALSE")
    }
}
```

#### B. Sprawdzenie prefix klucza

Stripe klucze test zawsze zaczynaja sie od `sk_test_`, a live od `sk_live_`. Mozna dodac walidacje:

```kotlin
if (!testMode && liveSecretKey.startsWith("sk_test_")) {
    log.error("CRITICAL: User {} is in LIVE mode but LIVE key has test prefix!", userId)
    // Opcjonalnie: zablokuj platnosc lub fallback na test z logiem
}
```

#### C. Checklist przed przelaczeniem na live

Przed wykonaniem `UPDATE users SET stripe_test_mode = FALSE`:

- [ ] `STRIPE_LIVE_SECRET_KEY` ustawiony i zaczyna sie od `sk_live_`
- [ ] `STRIPE_LIVE_PUBLIC_KEY` ustawiony i zaczyna sie od `pk_live_`
- [ ] `STRIPE_LIVE_WEBHOOK_SECRET` ustawiony (osobny webhook endpoint w Stripe Dashboard)
- [ ] Webhook endpoint w Stripe Live skonfigurowany na `https://domena/api/payment/stripe/webhook`
- [ ] Test webhook z Stripe Live Dashboard → 200 OK
- [ ] Backend zrestartowany po zmianie `.env`

---

## 2. Tabela stripe_event_idempotency — rosnie w nieskonczonosc

### Problem

Tabela `stripe_event_idempotency` przechowuje ID kazdego przetworzonego eventu Stripe (zapobiega podwojnemu przetwarzaniu). Kazdy webhook = nowy wiersz. Tabela **nigdy nie jest czyszczona**.

Przy ruchu:
- 100 uzytkownikow × 12 eventow/mies = ~1200 wierszy/mies = ~14 400/rok
- 10 000 uzytkownikow = ~1 440 000/rok

Same stringi (event ID + timestamp), wiec rozmiar to ~50-100 MB/rok przy duzym ruchu. Nie krytyczne natychmiast, ale bez czyszczenia baza rosnie bez limitu.

### Rozwiazanie: Cron czyszczacy stare rekordy

```sql
-- Usun rekordy starsze niz 90 dni (Stripe nie wysyla retry po >72h)
DELETE FROM stripe_event_idempotency
WHERE created_at < NOW() - INTERVAL '90 days';
```

#### Crontab (codziennie o 3:00 w nocy)

```bash
# Dodaj do crontab
sudo crontab -e

# Wklej:
0 3 * * * psql -h localhost -U properbackup -d properbackup -c "DELETE FROM stripe_event_idempotency WHERE created_at < NOW() - INTERVAL '90 days';" >> /var/log/properbackup-cleanup.log 2>&1
```

#### Alternatywa: Scheduled task w aplikacji

Mozna tez dodac czyszczenie w samym backendzie (np. `ScheduledExecutorService`):

```kotlin
// W BufferMain.kt, po starcie aplikacji:
val cleanupExecutor = Executors.newSingleThreadScheduledExecutor()
cleanupExecutor.scheduleAtFixedRate({
    try {
        db.getConnection().use { conn ->
            val deleted = conn.prepareStatement(
                "DELETE FROM stripe_event_idempotency WHERE created_at < NOW() - INTERVAL '90 days'"
            ).use { it.executeUpdate() }
            if (deleted > 0) log.info("Cleaned up {} stale idempotency records", deleted)
        }
    } catch (e: Exception) {
        log.warn("Idempotency cleanup failed: {}", e.message)
    }
}, 1, 24, TimeUnit.HOURS) // co 24h, start po 1h od uruchomienia
```

### Dlaczego 90 dni a nie 30?

Stripe moze retry webhook do 72h po pierwszym wyslaniu. 90 dni daje duzy margines bezpieczenstwa — nigdy nie skasujesz rekordu ktory Stripe moglby jeszcze retry'owac.

---

## 3. Podsumowanie: co jest NAPRAWDE wazne

| Ryzyko | Prawdopodobienstwo | Wplyw | Priorytet |
|--------|-------------------|-------|-----------|
| Brak live kluczy → test platnosci | Srednie | Wysoki (strata przychodu) | **P1** |
| Idempotency table rosnie | Niskie | Niski (powolny wzrost) | **P3** |
| Niepoprawny webhook secret | Niskie | Sredni (platnosci nie aktywowane) | **P2** |

**Wniosek:** Najwiekszym zagrozeniem jest konfiguracja serwera (`.env`), nie kod. System jest technicznie dobrze zabezpieczony — pilnuj kluczy.
