# Testowanie odpornosciowe (Resilience Testing)

## Problem

Testy jednostkowe i integracyjne testuja "idealny swiat" (happy path). W praktyce:
- Siec laguje
- Uzytkownik klika 5 razy w przycisk
- Stripe zwraca 500 w losowym momencie
- Dwa requesty uderzaja w baze w tej samej milisekundzie

Testy przechodzace na zielono ≠ system dzialajacy na produkcji.

Lekcja z pluginow Minecraft: testy przechodzily bo wszystko bylo zgodne z dokumentacja zaleznosci, a w praktyce klient nie mogl otworzyc skrzynki bo po drodze wystapil inny event, GUI migalo bo aktualizacje byly zbyt czeste, a na slabym internecie wszystko sie sypalo.

---

## 4 kategorie testow odpornosciowych

### 1. Wolny internet / High Network Latency (Frontend)

**Problem:** Frontend odpytuje backend (polling), siec laguje, UI zaczyna skakac, przyciski pozwalaja na wielokrotne klikniecia.

**Co testowac:**
- Symulacja profilu "Slow 3G" (500ms opoznienie, 5% utraconych pakietow)
- Czy przyciski sa natychmiast blokowane (disabled) po kliknieciu (Double-Click Protection)
- Czy loader jest stabilny (nie miga)
- Czy timeout konczy sie czytelnym komunikatem bledu, nie crashem

**Jak testowac (Playwright E2E):**

```typescript
// Symulacja wolnego internetu
await page.route('**/api/**', async route => {
  await new Promise(r => setTimeout(r, 3000)); // 3s lag
  await route.continue();
});

// Klikniecie w przycisk "Kup subskrypcje"
await page.click('[data-testid="buy-subscription"]');

// Przycisk powinien byc zablokowany natychmiast
await expect(page.locator('[data-testid="buy-subscription"]')).toBeDisabled();

// Loader powinien byc widoczny
await expect(page.locator('[data-testid="loading-spinner"]')).toBeVisible();
```

**Prompt dla Devina:**

```
Musimy przetestowac odpornosc frontendu na wysokie opoznienia sieciowe
(High Network Latency). Napisz testy E2E w Playwright, ktore symuluja
profil sieciowy 'Slow 3G' (opoznienie 500ms, 5% utraconych pakietow)
za pomoca page.route lub wbudowanego throttlingu.

Wymagania:
- Przyciski MUSZA byc natychmiast blokowane (disabled) po kliknieciu
- Stan komponentu nie moze migac — loader ma byc stabilny
- Timeout sieciowy musi konczyc sie czytelnym komunikatem bledu
```

---

### 2. Race Conditions / Wyscigi danych (Backend)

**Problem:** Dwa sprzeczne zdarzenia w tej samej milisekundzie. Np. uzytkownik klika "Anuluj subskrypcje" a w tym samym momencie Stripe wysyla webhook `invoice.paid`. Kto wygra w bazie?

**Co testowac:**
- 10-20 rownoczesnych requestow do tego samego zasobu
- Sprzeczne operacje (cancel + renew) w tym samym momencie
- Deadlock detection
- Spojnosc danych po zakonczeniu wszystkich requestow

**Jak testowac (Kotlin + JUnit):**

```kotlin
@Test
fun `concurrent cancel and webhook must not corrupt data`() {
    val latch = CountDownLatch(1)
    val executor = Executors.newFixedThreadPool(10)
    val errors = ConcurrentLinkedQueue<Throwable>()

    // 5 watkow anuluje subskrypcje
    repeat(5) {
        executor.submit {
            latch.await()
            try { cancelSubscription(userId) }
            catch (e: Exception) { errors.add(e) }
        }
    }

    // 5 watkow symuluje webhook invoice.paid
    repeat(5) {
        executor.submit {
            latch.await()
            try { handleWebhook(invoicePaidPayload) }
            catch (e: Exception) { errors.add(e) }
        }
    }

    latch.countDown() // start wszystkich naraz

    executor.shutdown()
    executor.awaitTermination(30, TimeUnit.SECONDS)

    // Brak deadlockow
    assertTrue(errors.none { it.message?.contains("deadlock") == true })

    // Stan koncowy jest spojny
    val sub = getSubscription(userId)
    assertTrue(sub.status in listOf("cancelled", "active")) // nie "corrupted"
}
```

**Prompt dla Devina:**

```
Musimy sprawdzic mechanizm pod katem wspolbieznosci i blokad bazy danych
(Concurrency & Race Conditions). Napisz test integracyjny przy uzyciu
ExecutorService i CountDownLatch w Kotlinie.

Odpal dokladnie w tym samym momencie (paralelnie na 10 watkach) dwa
sprzeczne zadania dla tego samego uzytkownika: jedno anulujace akcje,
drugie ja konczace. Upewnij sie, ze logika uzywa blokowania pesymistycznego
(SELECT FOR UPDATE) lub odpowiedniego poziomu izolacji transakcji, tak
aby baza nigdy nie weszla w Deadlock ani nie pozwolila na niespojnosc danych.
```

---

### 3. Fault Injection / Awarie zewnetrznych API (Stripe, OVH)

**Problem:** Stripe laguje 15 sekund, zwraca 500, albo blokuje nas za rate limit (429). System powinien sie podniesc, nie wywalac.

**Co testowac:**
- Timeout sieciowy (15s opoznienie)
- HTTP 500 (Internal Server Error)
- HTTP 429 (Rate Limit / Too Many Requests)
- Retry z Exponential Backoff
- Czy uzytkownik dostaje czytelny komunikat

**Jak testowac (Kotlin + MockK):**

```kotlin
@Test
fun `StripeHandler retries on 429 Too Many Requests`() {
    val mockStripe = mockk<PaymentIntentCreateParams>()

    var callCount = 0
    every { Customer.create(any(), any()) } answers {
        callCount++
        if (callCount <= 2) {
            throw StripeException("Rate limit exceeded", null, null, 429, null)
        }
        // 3. proba — sukces
        mockCustomer
    }

    val result = stripeHandler.getOrCreateStripeCustomer(userId, email, opts)
    assertEquals(3, callCount) // 2 retry + 1 sukces
    assertNotNull(result)
}

@Test
fun `StripeHandler handles 15s timeout gracefully`() {
    every { Session.create(any(), any()) } answers {
        Thread.sleep(15_000) // symulacja timeout
        throw StripeException("Connection timeout", null, null, 0, null)
    }

    val result = stripeHandler.createCheckoutSession(userId)
    // Powinien zwrocic czytelny blad, nie wywalic aplikacji
    assertTrue(result.isFailure)
    assertTrue(result.error.contains("timeout") || result.error.contains("unavailable"))
}
```

**Prompt dla Devina:**

```
Nie testuj tylko idealnego zachowania Stripe. Napisz test integracyjny
z wstrzykiwaniem bledow (Fault Injection). Stworz mocka klienta Stripe,
ktory losowo:
- Opoznia odpowiedz o 15 sekund (timeout sieciowy)
- Zwraca StripeException z kodem HTTP 429 (Too Many Requests) lub 500

Zweryfikuj, czy system potrafi podniesc sie po bledzie. Wdroz mechanizm
ponawiania prob (Retry z Exponential Backoff i Jitter), aby aplikacja
nie odrzucala transakcji uzytkownika, tylko probowala ponowic.
```

---

### 4. Prawdziwa baza danych w testach (Testcontainers)

**Problem:** Bazy in-memory (H2) zachowuja sie inaczej niz PostgreSQL. Testy przechodzace na H2 moga sie wywalic na produkcji (inna skladnia SQL, inne blokady, inne indeksy).

**Stan w ProperBackup:** Juz uzywamy Testcontainers z prawdziwym PostgreSQL — to jest poprawne. Wszystkie 114 testow uzywa `@Testcontainers` + `PostgreSQLContainer`.

**Prompt (dla nowych modulow):**

```
Zabraniam uzywania baz danych w pamieci (H2) do testow integracyjnych.
Wszystkie testy sprawdzajace logike bazodanowa musza byc uruchamiane
na prawdziwym kontenerze PostgreSQL przy uzyciu Testcontainers.
Test ma fizycznie stawiac strukture z naszego pliku schema.sql.
```

---

## System Guard — szablon do promptow

Dopisuj ten blok na koncu kazdego duzego promptu dla Devina:

```
======================================================================
[SENIOR DEVELOPER & QA PARANOID MODE: ON]

Zanim przejdziesz do pisania logiki, zmien swoja role. Nie jestes juz
tylko wykonawca happy path. Jestes teraz paranoicznym profesjonalnym
testerem i glownym architektem systemu.

Twoim zadaniem jest AKTYWNE szukanie luk i potencjalnych awarii
produkcyjnych w tym, co wlasnie budujesz. Przed napisaniem kodu
odpowiedz sobie (i uwzglednij to w testach) na ponizsze pytania:

1. ASYNCHRONICZNOSC I LAGI: Co sie stanie, jesli siec/API zlaguje na
   10 sekund? Czy interfejs zablokuje przyciski (Double-Click Protection),
   czy pozwoli uzytkownikowi klikac w kolko i wysylac zdublowane requesty?

2. WYSCIGI (RACE CONDITIONS): Co jesli uzytkownik kliknie dwie sprzeczne
   akcje w tej samej milisekundzie? Czy baza danych uzywa odpowiednich
   blokad (np. SELECT FOR UPDATE), zeby uniknac Deadlocka lub niespojnosci?

3. FAULT INJECTION: Jak system zachowa sie, gdy zewnetrzne API (Stripe/OVH)
   rzuci bledem 500 lub 429 (Rate Limit)? Czy mamy mechanizm ponawiania
   (Retry + Exponential Backoff)?

4. SRODOWISKO: Czy Twoje testy integracyjne uzywaja Testcontainers z
   prawdziwym PostgreSQL, czy oszukujesz na bazie H2 w pamieci?
   (Wymagam prawdziwego Postgresa).

OCZEKIWANIE: Kazda znaleziona luka musi zostac pokryta dedykowanym,
negatywnym testem integracyjnym (failing test) ZANIM poprawisz kod
biznesowy.
======================================================================
```

### Dlaczego to dziala?

1. **Wymusza "Paranoid Mode"** — zmusza AI do wyjscia z roli "bota do pisania kodu" i wejscia w role hakera/testera
2. **Blokuje "pojscie na latwizne"** — jawne wskazanie punktow (Double-Click, Race Conditions, Testcontainers) odcina mozliwosc zignorowania tych problemow
3. **Narzuca TDD** — jesli Devin musi najpierw napisac test ktory nie przechodzi, to automatycznie zmusza go do napisania kodu odpornego na ten konkretny problem

---

## Strategia testowania per komponent

| Komponent | Kategoria testow | Priorytet |
|-----------|------------------|-----------|
| **SubscriptionPage.jsx** | Slow 3G, Double-Click, Loader stability | P1 |
| **StripeHandler** | Fault Injection (429, 500, timeout), Race Conditions | P1 |
| **Webhook endpoint** | Concurrent webhooks, Dual-secret, Replay attack | P1 |
| **Agent upload** | Large file + slow network, Interrupted upload, Resume | P2 |
| **BudgetGuard** | DB down during check, Concurrent flush | P2 |
| **StorageQuotaGuard** | DB down, OVH timeout | P2 |

## Podsumowanie

Twoja rola jako Senior Dev/Architekta: **byc "czarnym charakterem"**. Kiedy dajesz Devinowi zadanie, zadaj sobie pytanie:

> "Co najgorszego moze sie tu stac od strony infrastruktury i sieci?"

Zamiast pisac:
> "Napisz obsluge przycisku i pobieranie danych"

Pisz:
> "Napisz pobieranie danych, ale przetestuj sytuacje, w ktorej odpowiedz idzie 10 sekund, a uzytkownik w tym czasie klika w piec innych miejsc. UI nie ma prawa sie rozjechac."

W ten sposob Devin przestanie pisac kod "w ciemno" i zacznie budowac system pancerny.

---

## Mapowanie kategorii → konkretne niezmienniki (LLD)

> 4 kategorie testów odporności mają teraz konkretne, nazwane niezmienniki w
> specach. Test odpornościowy NIE jest abstrakcyjny — sprawdza konkretny `I-x`/`B-x`/`O-x`.

| Kategoria | Konkretny test (gdzie) |
|-----------|------------------------|
| **Awaria zależności** (DB/sieć down) | guardy fail-safe `buffer-core` B-1 (DB down ⇒ blokada); agent Circuit Breaker `agent-vps` C.2 |
| **Współbieżność / race** | 8-wątkowy `activateSubscription` (`downgrade` I-3); 200-wątkowy redeem promo (`promo-codes` §5) |
| **Wolne odpowiedzi / timeouty** | async cold restore `ovh` O-1 (Rehydrating, nie timeout); SSE backpressure `web-panel` C.2 |
| **Nieprawidłowe/wrogie wejście** | `PayloadGuard` magic bytes (`buffer-core` BUF-A2); webhook signature (`trial-abuse` AV-4); SQL injection w nazwie serwera (`buffer-core` 6.16) |

> **Reguła:** każdy nowy niezmiennik (`*-N` w specach) powinien mieć przypisany
> test z jednej z tych 4 kategorii. Brak testu odpornościowego dla niezmiennika =
> niezmiennik „na papierze".

Cross-ref: `buffer-core-master-spec.md`, `downgrade-logic.md`, `promo-codes.md`,
`ovh-cloud-archive-migration-spec.md`, `trial-abuse-prevention.md`.
