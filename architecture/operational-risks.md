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

### Stan obecny (zaimplementowane)

`StripeKeyProvider.init {}` zglasza trzy warningi przy starcie aplikacji:

```kotlin
// (A) live klucze == test klucze
if (liveSecretKey.isNotBlank() && liveSecretKey == testSecretKey) {
    log.warn("⚠️  STRIPE LIVE KEYS NOT CONFIGURED — live secret key falls back to test secret key. ...")
}
// (B) test klucz ma prefix live
if (testSecretKey.isNotBlank() && testSecretKey.startsWith("sk_live_")) {
    log.error("CRITICAL: STRIPE_TEST_SECRET_KEY has sk_live_ prefix — test/live keys appear swapped!")
}
// (C) live klucz ma prefix test
if (liveSecretKey.isNotBlank() && liveSecretKey != testSecretKey && liveSecretKey.startsWith("sk_test_")) {
    log.error("CRITICAL: STRIPE_LIVE_SECRET_KEY has sk_test_ prefix — live mode would still hit test Stripe!")
}
```

Wszystkie trzy ostrzezenia leca przy starcie backendu — kazdy deploy logu produkcyjnego daje natychmiastowy sygnal o blednej konfiguracji.

### Checklist przed przelaczeniem na live

Pomimo automatycznych warningow, przed wykonaniem `UPDATE users SET stripe_test_mode = FALSE` operator powinien:

- [ ] `STRIPE_LIVE_SECRET_KEY` ustawiony i zaczyna sie od `sk_live_`
- [ ] `STRIPE_LIVE_PUBLIC_KEY` ustawiony i zaczyna sie od `pk_live_`
- [ ] `STRIPE_LIVE_WEBHOOK_SECRET` ustawiony (osobny webhook endpoint w Stripe Dashboard)
- [ ] Webhook endpoint w Stripe Live skonfigurowany na `https://domena/api/payment/stripe/webhook`
- [ ] Test webhook z Stripe Live Dashboard → 200 OK
- [ ] Backend zrestartowany po zmianie `.env` — w logach BRAK warninga "STRIPE LIVE KEYS NOT CONFIGURED"

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

---

## 4. LLD — egzekwowanie i wykrywanie (cross-ref niezmienników)

> Te ryzyka są teraz wsparte konkretnymi niezmiennikami i alertami w pozostałych
> specach. Tabela mapuje ryzyko → mechanizm wykrycia, żeby nie polegać wyłącznie
> na „pamiętaj o `.env`".

| Ryzyko | Niezmiennik / mechanizm | Wykrycie (alert) |
|--------|--------------------------|------------------|
| Fallback test→live (R#1) | `stripe-key-isolation.md` K-3 (fail-closed bez secret), K-5 (lazy live prices) | `WebhookSignatureSpike`, log prefix klucza przy starcie |
| `stripe_event_idempotency` rośnie (R#2) | `buffer-core` PostUploadCleanup §C.3 + cron (sekcja 2) | metryka rozmiaru tabeli; `master-tdd-plan.md` 9.7 |
| Niepoprawny webhook secret (R#3) | dual-secret + `400` (`stripe-key-isolation.md` §3) | `pb_webhook_signature_fail_total` (`observability` D.1) |
| Trial abuse (nowe) | `trial-abuse-prevention.md` AV-1..7 | `WebhookSignatureSpike`, soft-signal review queue |
| Rozjazd wersji shared (nowe) | `shared-core` S-2 (pinning) | `VersionSkew` (`observability` D.2) |

> **Uwaga (audyt):** ryzyko #1 (`.env`) pozostaje **P1 operacyjne**, ale jego
> *skutek* (płatność w trybie test zamiast live) jest teraz obserwowalny przez
> telemetrię wersji/trybu logowaną przez buffer — patrz `stripe-key-isolation.md`
> §C.2 (`mode` zdarzenia) i `observability-and-dr-spec.md` Dodatek D.
