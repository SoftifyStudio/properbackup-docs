# ProperBackup — Master TDD & Resilience Plan (pre-prod hardening)

> **Status:** Plan referencyjny. Pojedynczy punkt prawdy dla agenta, ktory bedzie
> dotwardzal modul subskrypcyjny/billingowy **przed pierwszym uruchomieniem na
> produkcji**. Cala obecna implementacja zyje wylacznie na serwerze testowym
> (`properbackup-test-server.softify.com.pl`) z kluczami Stripe w trybie
> sandbox. Zadne realne pieniadze nie sa jeszcze obciazane.
>
> **Cel tego dokumentu:** dac nastepnemu agentowi pelna i zwarta baze wiedzy,
> z ktorej moze pracowac w trybie *minimal-invasive TDD*: najpierw test, potem
> kod, bez rozkopywania calego repo i bez powielania istniejacych modulow.

---

## Spis tresci

1. [Cel i protokol pracy z tym dokumentem](#1-cel-i-protokol-pracy-z-tym-dokumentem)
2. [Stos i mapa repo](#2-stos-i-mapa-repo)
3. [Co JUZ jest zaimplementowane (state-of-the-world)](#3-co-juz-jest-zaimplementowane-state-of-the-world)
4. [Strefy "DOTYKAJ" vs "NIE RUSZAJ"](#4-strefy-dotykaj-vs-nie-ruszaj)
5. [Model domenowy billingu i maszyna stanow (Access Boundary)](#5-model-domenowy-billingu-i-maszyna-stanow-access-boundary)
6. [Filary odpornosci (Resilience Pillars)](#6-filary-odpornosci-resilience-pillars)
7. [10 testow akceptacyjnych (GRUPA A..H) z mapowaniem do plikow](#7-10-testow-akceptacyjnych-grupa-ah-z-mapowaniem-do-plikow)
8. [Dodatkowe pominiete przypadki (Edge / Abuse / Race / Money)](#8-dodatkowe-pominiete-przypadki-edge--abuse--race--money)
9. [Specyfikacja techniczna nowych komponentow](#9-specyfikacja-techniczna-nowych-komponentow)
10. [Definition of Done per test](#10-definition-of-done-per-test)
11. [TDD Workflow Protocol (jak agent ma pracowac)](#11-tdd-workflow-protocol-jak-agent-ma-pracowac)
12. [Prompt szablon "Senior + QA Paranoid Mode"](#12-prompt-szablon-senior--qa-paranoid-mode)
13. [Checklist Go/No-Go przed live](#13-checklist-gono-go-przed-live)

---

## 1. Cel i protokol pracy z tym dokumentem

### 1.1. Czego ten dokument NIE jest

- **Nie jest** zachęta do refactoru. Modul subskrypcji ma duzy implementowany
  zakres na branchu `devin/1779812528-trial-abuse-pastdue`. Wiekszosc punktow
  z testow 1–10 jest juz **czesciowo** zaimplementowana. Zadanie agenta to
  *domykanie luk i dokrecanie skreconych srubek*, nie pisanie modulu od zera.
- **Nie jest** specyfikacja nowych feature'ow biznesowych. Trzymamy sie
  produktu opisanego w `Biznesplan_ProperBackup_v6.2_NAJLEPSZY.docx`:
  19 PLN/mies, 190 PLN/rok, 30-dniowy trial card-first, OVH Cloud Archive.

### 1.2. Czym ten dokument JEST

- **Pelnym kontraktem testowym** dla kazdej krytycznej sciezki billingowej.
- **Punktem prawdy** o tym, ktore pliki/tabele juz istnieja, a ktorych nie
  trzeba tworzyc od nowa.
- **Map'a stref**: gdzie agent moze pisac, gdzie nie wolno mu ruszac.
- **Lista wszystkich znanych pulapek** (race conditions, money leaks, abuse
  vectors) z konkretnymi testami pokrywajacymi.
- **Protokolem TDD** — najpierw test failing, potem kod, potem zielony test.

### 1.3. Jak agent ma czytac ten dokument

```
1. Sekcja 4 (DOTYKAJ vs NIE RUSZAJ) — przeczytaj pierwsze. To definiuje
   blast radius. Zaden inny plik niz wymienione w "DOTYKAJ" nie powinien
   pojawic sie w diff'ie PR-a.

2. Sekcja 3 (state-of-the-world) — sprawdz status implementacji per test.
   Jesli test ma juz adekwatne pokrycie -> NIE pisz drugiego. Dopisz do
   istniejacego pliku integracyjnego.

3. Sekcja 7 (10 testow) + Sekcja 8 (edge cases) — to twoja kolejka prac.
   Dziala punkt po punkcie.

4. Sekcja 11 (TDD workflow) — twoj wewnetrzny loop dla kazdego punktu.

5. Sekcja 13 (Go/No-Go) — przed PR-em.
```

### 1.4. Jedna zelazna zasada

> **Kazdy commit musi zaczynac sie od czerwonego testu integracyjnego na
> prawdziwym PostgreSQL (Testcontainers). Brak czerwonego testu = brak commitu.**

---

## 2. Stos i mapa repo

| Warstwa | Repo | Stack |
|---------|------|-------|
| Backend | `properbackup-buffer` | Kotlin 21, Javalin, PostgreSQL 16, Stripe Java SDK, OpenStack Swift, Testcontainers, JUnit 5 |
| Agent | `properbackup-agent` | Kotlin Multiplatform JVM, jlinkDist (~61MB), BouncyCastle, AES-256-GCM |
| Shared | `properbackup-shared` | Kotlin Multiplatform — wspoldzielone DTO, RetryPolicy, BufferUploader, ProperCrypto |
| Web | `properbackup-web` | React 18 + Vite + Tailwind, Web Crypto API, react-router-dom |
| Stack | `properbackup-stack` | Docker Compose (postgres + buffer + agent + web + nginx) |
| MC plugin | `properbackup-mc` | Kotlin/Java plugin Paper |
| Docs | `properbackup-docs` | **To repo. Wszystkie zmiany dokumentacyjne ladja tutaj.** |

### 2.1. Kluczowe sciezki w `properbackup-buffer`

Naming convention: pakiet `pl.danielniemiec.properbackup.buffer.<module>`.

```
src/main/kotlin/pl/danielniemiec/properbackup/buffer/
├── BufferMain.kt                              # router + DI wiring
├── auth/
│   ├── UserStore.kt                           # CRUD users + trial_expires_at
│   ├── AuthHandler.kt                         # /auth/register, /auth/login
│   ├── JwtService.kt                          # 5min agent JWT (do napisania)
│   └── JwtFilter.kt                           # Javalin filter
├── subscription/
│   ├── SubscriptionHandler.kt                 # /account/subscription endpoint
│   ├── SubscriptionGuard.kt                   # Access Boundary
│   └── TrialNotifier.kt                       # email dunning seq (do napisania)
├── payment/
│   ├── StripeHandler.kt                       # 60+ metod Stripe API
│   ├── StripeKeyProvider.kt                   # per-user test/live keys
│   ├── PromoCodeHandler.kt                    # kody promo
│   ├── GiftCodeHandler.kt                     # kody gift
│   ├── HotPayHandler.kt                       # legacy alt payment
│   └── LemonSqueezyHandler.kt                 # legacy alt payment
├── flush/
│   ├── ChunkSealer.kt                         # seal -> archive
│   ├── PackBuffer.kt                          # 950MB pakowanie
│   ├── FlushTrigger.kt                        # cron flush
│   ├── BudgetGuard.kt                         # rate limit flush
│   └── StorageQuotaGuard.kt                   # billing enforcement layer
├── inbox/
│   ├── InboxReceiver.kt                       # chunk ingestion
│   ├── ChunkStorage.kt
│   ├── DiskGuard.kt
│   └── PayloadGuard.kt
├── server/
│   ├── ServerHandler.kt                       # /agent/status, /agent/files/state
│   ├── ActivationTokenStore.kt                # 1-time activation codes
│   └── ServerStore.kt
├── sse/
│   └── SseEventBus.kt                         # push do panelu (used in Test 8)
├── verify/
│   └── RestoreVerifier.kt                     # auto-test restore
├── report/
│   └── AuditReportGenerator.kt                # PDF Audit Report
└── ovh/
    ├── OvhSwiftClient.kt                      # OVH Cloud Archive client
    ├── MockSwiftClient.kt                     # local dev
    └── DevSafetyGuard.kt
```

### 2.2. Kluczowe sciezki w `properbackup-web`

```
src/
├── subscription/
│   └── SubscriptionPage.jsx                   # plan cards + Stripe Checkout
├── auth/                                       # login/register
├── timeline/                                   # historia backupow + restore
├── api/                                        # axios wrappers
└── i18n/locales/{pl,en}.json                   # tlumaczenia (waiver tekst)
```

### 2.3. Kluczowe sciezki w `properbackup-shared`

```
src/jvmMain/kotlin/pl/danielniemiec/properbackup/agent/
├── transport/
│   ├── BufferUploader.kt                       # POST do buffer
│   └── RetryPolicy.kt                          # exponential backoff (juz jest)
├── activation/
│   ├── ActivationClient.kt                     # token -> machine_identity
│   └── GlobalConfigWriter.kt
└── scanner/
    └── DifferentialScanner.kt                  # xxHash rolling
```

---

## 3. Co JUZ jest zaimplementowane (state-of-the-world)

**Branch referencyjny:** `properbackup-buffer:origin/devin/1779812528-trial-abuse-pastdue`.
Agent musi *najpierw zmergowac* lub *rebase'owac na* aktualny stan przed
zaczeciem prac.

### 3.1. Schema (PostgreSQL)

Tabele juz istniejace (w `schema.sql`):

| Tabela | Funkcja |
|--------|---------|
| `users` | + `subscription_plan`, `subscription_expires_at`, `subscription_cancel_at_period_end`, `stripe_customer_id`, `stripe_subscription_id`, `stripe_live_customer_id`, `stripe_live_subscription_id`, `stripe_test_mode`, `stripe_card_fingerprint`, `subscription_payment_status`, `trial_expires_at`, `last_trial_notification`, `ever_subscribed` |
| `stripe_event` | Append-only log eventow Stripe per user |
| `stripe_event_idempotency` | Klucz: `stripe_event_id` (PRIMARY KEY) — dedup webhookow |
| `stripe_price_config` | `(plan_key, mode)` -> `stripe_price_id` |
| `subscription_config` | KV: `vat_rate=0.23`, inne flagi |
| `subscription_audit_log` | Append-only audyt zmian billingowych |
| `promo_code` + `promo_code_usage` | Kody promo z first_order / max_uses |
| `gift_code` | Kody podarunkowe |
| `archive_snapshot` | Metadane zarchiwizowanych chunkow (do StorageQuotaGuard) |
| `machine_agent_status`, `machine_file_state`, `machine_file_event` | Telemetria agenta |
| `buffer_pack`, `archive_chunk` | Pakowanie 950MB |
| `verification_result` | Auto-test restore |
| `agent_metrics` | CPU/RAM/per-core, partycjonowane |
| `service_admin_codes` | Backup admin login |
| `data_retention_config` | TTL na logach |
| `flush_budget` | BudgetGuard ledger |

### 3.2. Webhook events handled

`StripeHandler.handleWebhook()` (linia ~651-669):

```kotlin
when (event.type) {
  "checkout.session.completed"      -> handleCheckoutCompleted(event, webhookOpts)
  "invoice.paid"                    -> handleInvoicePaid(event, webhookOpts)
  "invoice.payment_failed"          -> handleInvoicePaymentFailed(event)
  "customer.subscription.deleted"   -> handleSubscriptionDeleted(event)
  "customer.subscription.updated"   -> handleSubscriptionUpdated(event, webhookOpts)
  else                              -> log.debug("unhandled event type={}", ...)
}
```

### 3.3. Pokrycie testowe (branch `devin/1779812528-trial-abuse-pastdue`)

`src/test/kotlin/.../payment/SubscriptionIntegrationTest.kt` — **2000+ linii, ~80 testow**.
Pokrywaja (skroty cytatow nazw testow):

- Trial lifecycle, activate monthly/annual, save subscription/customer ID
- Cancel/Reactivate flow, deactivate
- Proration: 15 dni left, capped, zero, downgrade annual->monthly, edge 500+ days
- VAT decomposition (P1-3, P1-6)
- Promo codes: percentage, fixed, expired, max_uses, first_order, parallel race
- Audit log entries
- Webhook idempotency (P1-1) — `tryClaimStripeEventId` returns true once
- Webhook fail-closed (P1-2) — blank secret = 503
- Webhook signature: missing header = 400, tampered = 400, valid = OK
- StorageQuotaGuard: blocks gdy trial+sub expired, permits gdy trial active
- StripeKeyProvider: test/live switching, RequestOptions carry correct key,
  fallback live->test, dual-secret webhook
- Concurrent activateSubscription (race test)
- `findByIdForUpdate` (SELECT FOR UPDATE)
- `withRetry`: 429 retry, MAX_RETRIES exhausted, 4xx nie retry
- Test 1..10 (jako `Test N - new client no plan buys Monthly`)
- Trial abuse: card fingerprint, ever_subscribed
- past_due grace, transition to unpaid

`StripePerModeIsolationTest.kt` — dodatkowy plik per-mode izolacji.

### 3.4. Co dziala na test serverze (potwierdzone E2E 10/10 PASSED)

Z `changelog/2026-05-24-e2e-test-report-subscription-fixes.md` i sesji
`f6c20819` (PR #11/#12/#13 do docs):

- Rejestracja konta + trial_expires_at = created_at + 30d
- UI redesign plan cards (AKTYWNY PLAN badge, brak Best Value)
- Stripe Checkout monthly/annual ze sandboxem
- Cancel + Reactivate
- Trial abuse: dwie karty na 4242 -> trial skrocony do now()
- Wygasanie trialu (przesuniecie zegara +31d)
- Klauzula art. 38 pkt 13 (pl/en)

### 3.5. Co jest **w toku** / niepelne / wymaga TDD

Mimo szerokiego pokrycia, ponizsze obszary maja luki:

| Obszar | Stan | Akcja |
|--------|------|-------|
| Optimistic Locking (kolumna `version`) | Brak. Uzywany jest SELECT FOR UPDATE (pessimistic) | Sekcja 8.3 — decyzja + test out-of-order webhook |
| Dead-Letter Queue dla webhookow | Brak. Sa retry'e Stripe, ale brak naszej DLQ tabeli | Sekcja 9.1 — tabela `stripe_webhook_dlq` + replay tool |
| Trial abuse heuristics > samego fingerprint | Brak. Brak rate limit/disposable/IP geo | Sekcja 8.5 — `TrialAbuseHeuristics` jako pluggable layer |
| Agent JWT (5 min, krotkotrwaly) | Brak. Uzywany jest staly `UPLOAD_TOKEN` w env | Sekcja 9.2 — `JwtService.issueAgentToken(serverId, ttl=5m)` |
| SSE post-checkout waiting screen | SSE bus jest (`SseEventBus.kt`), ale frontend nie ma jeszcze "/panel/processing" route | Sekcja 9.3 — endpoint + komponent React |
| Email dunning sequence (T+0, T+3, T+7) | `TrialNotifier.kt` istnieje, ale tylko `last_trial_notification` | Sekcja 9.4 — rozszerzyc o `subscription_payment_status='past_due'` |
| Out-of-order webhook protection (timestamp) | Idempotency `event.id` jest, ale brak `event.created` ordering check | Sekcja 8.4 — kolumna `last_stripe_event_at` + guard |
| Resumable uploads agent | BufferUploader posiada retry, brak HTTP Range | Sekcja 9.5 — Content-Range w `POST /agent/chunks/{id}/append` |
| Circuit breaker agent | Brak | Sekcja 9.6 — prosty CB w `RetryPolicy.kt` (3 strikes -> open 60s) |
| Idempotency cleanup cron | Udokumentowane, ale nie zaimplementowane jako scheduled task | Sekcja 9.7 |
| Clock skew tolerance (webhook) | Stripe SDK domyslnie ma 5min — trzeba potwierdzic uzycie | Sekcja 7.3 weryfikacja |
| StorageQuotaGuard pod DB-down | StorageQuotaGuard istnieje, ale brak testu "DB unavailable -> fail-closed" | Sekcja 7.9 / 8.10 |
| Double-Click Protection (web) | Niepotwierdzone, brak playwright e2e dla Slow 3G | Sekcja 7.10 |
| Webhook clock skew false-positive test | Brak | Sekcja 7.3 weryfikacja |
| Concurrent cancel+invoice.paid race test | Race test istnieje dla activate, brak dla cancel vs paid | Sekcja 8.1 |

---

## 4. Strefy "DOTYKAJ" vs "NIE RUSZAJ"

> Agent ma traktowac te liste jak instrukcje *blast radius*. Jesli planowana
> zmiana wymagalaby ruszenia czegokolwiek z listy "NIE RUSZAJ", **agent musi
> zatrzymac sie i zglosic do uzytkownika** zamiast forsowac zmiane.

### 4.1. DOTYKAJ (zielona strefa)

Pliki, ktore agent **ma prawo** modyfikowac w ramach prac z tego planu:

```
properbackup-buffer/
  src/main/resources/schema.sql          # tylko ALTER TABLE ADD COLUMN
                                          # IF NOT EXISTS / CREATE TABLE IF
                                          # NOT EXISTS / CREATE INDEX IF NOT
                                          # EXISTS — nigdy DROP/RENAME
  src/main/kotlin/.../subscription/      # SubscriptionHandler, SubscriptionGuard,
                                          # TrialNotifier
  src/main/kotlin/.../payment/           # StripeHandler, StripeKeyProvider
                                          # (tylko nowe metody / drobne fixy)
  src/main/kotlin/.../auth/JwtService.kt # rozszerzenie o issueAgentToken
  src/main/kotlin/.../auth/UserStore.kt  # tylko nowe kolumny + accessory
  src/main/kotlin/.../flush/StorageQuotaGuard.kt
  src/main/kotlin/.../sse/SseEventBus.kt # tylko jesli brakuje topica
  src/test/kotlin/.../payment/           # nowe testy + dopelnienia
  src/test/kotlin/.../flush/             # nowe testy QuotaGuard pod DB-down

properbackup-web/
  src/subscription/SubscriptionPage.jsx  # double-click guard, processing screen
  src/subscription/ProcessingScreen.jsx  # NOWY plik (SSE listener)
  src/api/subscription.js                # axios wrapper, retry
  src/i18n/locales/{pl,en}.json          # tylko nowe klucze

properbackup-shared/
  src/jvmMain/.../transport/RetryPolicy.kt   # dorzucic circuit breaker
  src/jvmMain/.../transport/BufferUploader.kt # resumable uploads

properbackup-agent/
  (NIC bez wyraznej zgody — patrz sekcja 9.5/9.6)

properbackup-docs/
  WSZYSTKO — to repo jest do dokumentacji
```

### 4.2. NIE RUSZAJ (czerwona strefa)

Pliki/zasoby, ktorych agent NIE WOLNO ruszac bez ponownej dyskusji z uzytkownikiem:

```
- BufferMain.kt — main router. Nowe endpointy dodaj jako *_Handler i wiruj
  w wyraznie wyodrebnionej sekcji `wireBilling(...)`. NIE wlewaj logiki do
  BufferMain.

- ChunkSealer.kt / PackBuffer.kt / ovh/* — warstwa storage. Storage layer
  ma sie zachowywac dokladnie jak teraz. Jedyna interakcja billingu to
  pre-flight gate przez StorageQuotaGuard.

- Database.kt, schema.sql DROP/RENAME — zero destructive migrations. Tylko
  CREATE/ALTER ADD IF NOT EXISTS. Nazwy kolumn istniejacych sa zamrozone.

- LemonSqueezyHandler.kt / HotPayHandler.kt — legacy. Zostawiamy in-place
  do czasu kompletnej migracji. NIE refactoruj.

- Test files dla istniejacych funkcji (te ktore juz przechodza). Wolno
  *dopisac* nowe @Test, nie wolno usuwac/przepisywac istniejacych.

- Crypto:
  - ProperCrypto.kt, KeyDerivation.kt, HeaderCodec.kt — zero dotykania.
  - AES-256-GCM + Argon2id sa zamrozone.

- DifferentialScanner.kt, ExcludeFilter.kt — algorytm rolling hash i
  privacy alerts. Zero zmian.

- AppHeader.jsx (poza dropdown menu juz dodanym w sesji f6c20819).
- React Router config — nie zmieniaj sciezek istniejacych.
```

### 4.3. Zaleznosci PR-ow (kolejnosc merge)

Z poprzedniej sesji (note `note-f0e05275`):

```
shared #6 -> shared #7
agent #7 -> agent #8 -> agent #9
buffer #13 (i wyzej)
web #22 -> web #23
mc #1 (na koncu — po shared #7 i buffer #13)
```

Agent musi **pracowac na branchu**, **nie** wlewac kodu do main. Devin nie ma
uprawnien do merge — kazdy PR wymaga manualnego review/approve od uzytkownika.

---

## 5. Model domenowy billingu i maszyna stanow (Access Boundary)

### 5.1. Dwa zegary

Backend operuje na **dwoch niezaleznych znacznikach czasu**:

| Pole | Zrodlo | Semantyka |
|------|--------|-----------|
| `users.trial_expires_at` | nasze — ustawiane przy rejestracji *card-first*: jezeli zarejestrowany ale przed pierwszym Stripe checkout, brak trialu. Jezeli przeszedl Stripe Checkout z `trial_period_days=30`, ustawiamy = `trial_end` z subscription | Kiedy konczy sie darmowy okres uzytkownika |
| `users.subscription_expires_at` | webhook Stripe (`current_period_end`) | Kiedy konczy sie aktualnie oplacony okres |

> **WAZNE:** Z biznesplanu i sesji f6c20819 wynika, ze trial jest *card-first*:
> uzytkownik **musi** przejsc Stripe Checkout z karta zanim trial sie zacznie.
> Stary model "trial od rejestracji" zostal porzucony — patrz komentarz w
> `schema.sql`: *"Legacy backfill removed: trial no longer starts at registration."*

### 5.2. Maszyna stanow domenowych

Stan biznesowy obliczany w `SubscriptionGuard.computeAccess(user, now)`:

```
                                     ┌─────────────┐
                                     │   none      │  brak karty / brak Stripe sub
                                     │  (pending   │  Frontend: niebieski banner +
                                     │   payment)  │  CTA "Rozpocznij trial"
                                     │             │  Agent: 403 NO_ACTIVE_SUBSCRIPTION
                                     └──────┬──────┘
                            checkout.session   │
                            .completed         │
                                               ▼
                                     ┌─────────────┐
                                     │  trialing   │  trial_expires_at > now()
                                     │             │  Pelen dostep. Badge "Trial Xd"
                                     └──────┬──────┘
                            invoice.paid       │
                            (po trial_end)     │
                                               ▼
                                     ┌─────────────┐  ┌──────────────────────┐
                                     │   active    │->│  active + cancel_    │
                                     │             │  │  at_period_end=true  │
                                     │             │  │  (anulowane, do      │
                                     │             │  │   konca okresu)      │
                                     └──────┬──────┘  └──────────┬───────────┘
                            invoice.payment_failed │             │
                                                   ▼             │ czas mija
                                     ┌─────────────────┐         ▼
                                     │  past_due_grace │  ┌──────────────┐
                                     │  canUpload:true │  │   expired    │
                                     │  canRestore:true│  │ canUpload:F  │
                                     └─────────┬───────┘  │ canRestore:F │
                              po N retry'ach   │          └──────────────┘
                                               ▼                  ▲
                                     ┌─────────────────┐           │
                                     │ past_due_       │           │
                                     │ suspended       │ Stripe    │
                                     │ canUpload:false │ konczy    │
                                     │ canRestore:true │ retry'e   │
                                     └─────────────────┘──────────►│
```

### 5.3. Decision table `Access Boundary`

Kanoniczna tabela odpowiedzi `SubscriptionGuard`:

| Stan | `canUpload` | `canRestore` | `agentAuthError` | UI badge |
|------|-------------|--------------|------------------|----------|
| none | false | false | `403 NO_ACTIVE_SUBSCRIPTION` | niebieski "Wybierz plan" |
| trialing | true | true | OK | zielony "Trial Xd" |
| active | true | true | OK | zielony "Aktywna" |
| active + cancel_at_period_end | true | true | OK | zielony "Aktywna (Anulowana — nie zostanie odnowiona)" |
| past_due_grace | true | true | OK | zolty "Problem z platnoscia. Ponowimy automatycznie" |
| past_due_suspended | false | true | `403 SUBSCRIPTION_PAST_DUE` | czerwony "Zaplac, by wznowic backup" |
| expired (canceled) | false | false | `403 SUBSCRIPTION_EXPIRED` | czerwony "Subskrypcja wygasla" |

> Granica `past_due_grace -> past_due_suspended`: Stripe robi 4 retry'e
> domyslnie w cyklu Smart Retries (3, 5, 7, 14 dni). My przechodzimy na
> `suspended` dopiero po finalnym `customer.subscription.updated` z
> `status='unpaid'` lub `customer.subscription.deleted`. **Nigdy** nie
> przechodzimy na suspended z naszej strony przed Stripe.

### 5.4. Mapowanie statusow Stripe -> nasz `subscription_payment_status`

| Stripe sub.status | Nasze `subscription_payment_status` | Nasze `subscription_plan` |
|-------------------|-------------------------------------|---------------------------|
| trialing | `NULL` (healthy) | `monthly` lub `annual` |
| active | `NULL` (healthy) | `monthly` lub `annual` |
| past_due | `past_due` | bez zmian |
| unpaid | `unpaid` | bez zmian (gate przez Guard) |
| canceled | `NULL` (po wygasniciu wyzeruj plan) | `NULL` po `period_end` |
| incomplete / incomplete_expired | `incomplete` (treat as none) | `NULL` |

---

## 6. Filary odpornosci (Resilience Pillars)

Cztery kategorie pochodza z `architecture/resilience-testing.md`. Tutaj
formalizujemy je jako *bramy* — kazdy test z sekcji 7 i 8 musi byc
zaklasyfikowany do >=1 filaru:

### Filar P1 — Wolny internet / High Network Latency (Frontend)

Profil testowy Playwright: 500ms opoznienie + 5% loss + 3000ms route delay.
Wymagania:

- Kazdy przycisk wykonujacy mutacje (Checkout, Cancel, Reactivate, Change Plan)
  ma `disabled` natychmiast po kliknieciu (Double-Click Protection).
- Loader jest stabilny — brak migotania w stan komponentu podczas opoznienia.
- Timeout sieciowy konczy sie czytelnym komunikatem (`toast.error`), nie
  bialym ekranem.

### Filar P2 — Race Conditions (Backend)

ExecutorService + CountDownLatch. 10-20 watkow per scenariusz. Wymagania:

- Zaden test nie konczy sie deadlockiem (Postgres logi).
- Stan koncowy jest *spojny* — czyli jeden ze zdefiniowanych terminali maszyny
  stanow, nigdy "korupcja" (np. plan=monthly + sub_id=NULL).
- Wszystkie krytyczne sciezki uzywaja albo SELECT FOR UPDATE (pessimistic)
  albo kolumny version (optimistic) — patrz sekcja 8.3 dla decyzji.

### Filar P3 — Fault Injection (Stripe, OVH)

Mock zwraca losowo:

- HTTP 429 (rate limit) -> retry z exponential backoff + jitter, max 3 proby
- HTTP 500 (server error) -> identycznie
- Timeout 15s -> przerwij, retry, finalnie zwroc clean error do uzytkownika
- HTTP 401/403 (auth) -> **bez retry** (tylko alert log + fail)

`withRetry` w `StripeHandler.kt` juz to robi — test `withRetry retries on
RateLimitException then succeeds` jest zielony. Brakuje:

- Test dla 500 (nie tylko 429)
- Test dla timeout 15s
- Test dla `OVH 503` w `StorageQuotaGuard` (sciezka zapisu)

### Filar P4 — Real Postgres only (Testcontainers)

Zero in-memory DB. Wszystkie testy logiki bazodanowej startuja
`@Testcontainers PostgreSQLContainer` z `schema.sql`. Branch
`devin/1779812528-trial-abuse-pastdue` juz to ma — agent ma **nie wprowadzac**
H2 mock-ow nawet "tymczasowo".

---

## 7. 10 testow akceptacyjnych (GRUPA A..H) z mapowaniem do plikow

Naming convention dla nowych testow: w pliku
`SubscriptionIntegrationTest.kt`, prefix `[TDD-A1]`, `[TDD-A2]`, ... w nazwie
funkcji testowej. Pozwala to grep'em szybko zlokalizowac dany test.

### GRUPA A — Rejestracja i stan oczekiwania

#### Test 1: `[TDD-A1]` Rejestracja + brak dostepu (pending payment)

**Filar:** P4
**Status:** czesciowo pokryte (`user starts with trial - no subscription plan`).
Brakuje konkretnego asercji o ksztaltie odpowiedzi 403.

**Given/When/Then:**

```
GIVEN: nowy user zarejestrowany przez POST /auth/register (email weryfikowany)
WHEN:  agent wysyla GET /agent/status z naglowkiem Authorization=Bearer <upload_token>
THEN:  status=403, body={"code":"NO_ACTIVE_SUBSCRIPTION","message":"..."}

GIVEN: ten sam user w panelu webowym
WHEN:  GET /account/subscription
THEN:  response.subscriptionStatus="none", trialExpiresAt=null, stripeSubscriptionId=null

GIVEN: ten sam user w UI subscription page
WHEN:  klika "Rozpocznij trial" BEZ zaznaczonego checkboxa zgody na art. 38 pkt 13
THEN:  przycisk jest `disabled`, brak requestu do backendu

GIVEN: ten sam user, zaznacza checkbox
WHEN:  klika "Rozpocznij trial"
THEN:  redirect na checkout.stripe.com, w request do Stripe trial_period_days=30
```

**Mapowanie do plikow:**

- `properbackup-buffer/.../auth/UserStore.kt::register()`
- `properbackup-buffer/.../subscription/SubscriptionHandler.kt::getSubscription()`
- `properbackup-buffer/.../server/ServerHandler.kt::handleAgentStatus()` (gdzie 403 leci)
- `properbackup-web/.../subscription/SubscriptionPage.jsx`
- `properbackup-web/.../i18n/locales/pl.json::withdrawalWaiver`

**Audit log:** `subscription_audit_log` INSERT z `action='registration_no_plan'`,
`user_id=...`, `created_at=NOW()`.

---

### GRUPA B — Aktywacja trialu i Stripe Checkout

#### Test 2: `[TDD-B1]` Generowanie sesji Checkout (trial + idempotency key)

**Filar:** P3, P4
**Status:** pokryte. Test `checkout idempotency-key is deterministic within a time bucket (P2-7)`.

**Given/When/Then:**

```
GIVEN: user z trial_expires_at=NULL, ever_subscribed=false
WHEN:  POST /account/subscription/checkout {plan: "monthly"}
THEN:
  - response.url zaczyna sie od "https://checkout.stripe.com/"
  - w mocku Stripe widac wywolanie Session.create z:
      subscription_data.trial_period_days = 30
      line_items[0].price = "price_test_monthly"  (z stripe_price_config)
      success_url = "https://panel.../panel?session_id={CHECKOUT_SESSION_ID}"
      cancel_url = "https://panel.../account/subscription"
  - RequestOptions zawiera Idempotency-Key
  - Idempotency-Key jest deterministyczny w obrebie 60s window
    (kolejne POST w ciagu 60s -> ten sam key -> Stripe zwraca ta sama sesje)

GIVEN: ten sam user, ten sam plan, 70s pozniej
WHEN:  POST /account/subscription/checkout {plan: "monthly"}
THEN:  Idempotency-Key inny (rozne time bucket)
```

**Edge cases:**

- `ever_subscribed=true` (user juz kiedys placil i anulowal) -> brak trial_period_days
  (Test 7 — trial abuse fallback).
- User ma aktywna subskrypcje monthly i prosi o annual -> NIE Checkout, lecz
  Subscriptions.update (Test 6).

**Mapowanie:**

- `StripeHandler.kt::createCheckoutSession(userId, plan)`
- `StripeHandler.kt::buildIdempotencyKey(userId, plan, timestampBucket)`

---

#### Test 3: `[TDD-B2]` Webhook signature + idempotency + DLQ

**Filar:** P2, P3, P4
**Status:** czesciowo pokryte (signature, idempotency). Brakuje DLQ replay.

**Given/When/Then:**

```
GIVEN: poprawny payload Stripe z `Stripe-Signature` headerem podpisanym TEST secret
WHEN:  POST /api/payment/stripe/webhook
THEN:  200 OK; users.subscription_plan='monthly', stripe_subscription_id ustawiony,
       current_period_end ustawione na trial_end ze Stripe,
       subscription_audit_log INSERT action='checkout_completed'

GIVEN: ten sam event (event.id) ponownie wyslany przez Stripe (retry)
WHEN:  POST /api/payment/stripe/webhook
THEN:  200 OK, ZERO mutacji w bazie (idempotency claim w stripe_event_idempotency)
       (test juz istnieje: `webhook idempotency - tryClaimStripeEventId returns true once then false`)

GIVEN: payload z tampered signature
WHEN:  POST /api/payment/stripe/webhook
THEN:  400 Bad Request (test juz istnieje)

GIVEN: blank STRIPE_TEST_WEBHOOK_SECRET
WHEN:  POST /api/payment/stripe/webhook
THEN:  503 Service Unavailable (fail-closed) (test juz istnieje)

[NOWY — DLQ]
GIVEN: poprawny webhook, ale DB rzuca SQLException 5 razy z rzedu
WHEN:  consumer probuje przetworzyc
THEN:  - po 5 retry'ach event ladzie do stripe_webhook_dlq
       - Stripe dostaje 200 OK (zeby zwolnic kolejke)
       - admin moze wywolac POST /admin/webhooks/replay/{event_id} -> reprocesuje

[NOWY — Clock Skew]
GIVEN: payload z Stripe-Signature timestamp = NOW - 4 min
WHEN:  POST /api/payment/stripe/webhook
THEN:  200 OK (tolerancja 5 min w Stripe SDK domyslnie — TEST POTWIERDZAJACY)

GIVEN: payload z timestamp = NOW - 6 min
WHEN:  POST /api/payment/stripe/webhook
THEN:  400 (poza tolerancja)

[NOWY — Out-of-order]
GIVEN: webhook A (event.created = 1000), webhook B (event.created = 1050)
WHEN:  B przychodzi pierwsze, A drugi
THEN:  B aplikowany, A *odrzucany* (last_stripe_event_at > A.created),
       ale event A trafia do stripe_event jako "stale" z flagą is_stale=true
       (append-only audit, no DB mutation)
```

**Mapowanie:**

- `StripeHandler.kt::handleWebhook(payload, sigHeader, mode)`
- `StripeHandler.kt::tryClaimStripeEventId(eventId, eventType)`
- **NOWY:** `StripeHandler.kt::queueToDlq(eventId, payload, lastError)`
- **NOWY:** `payment/WebhookReplayHandler.kt` (POST /admin/webhooks/replay/...)
- **NOWY schema:** tabela `stripe_webhook_dlq` (patrz Sekcja 9.1)

---

### GRUPA C — Zarzadzanie subskrypcja w trakcie trialu

#### Test 4: `[TDD-C1]` Cancel (cancel_at_period_end=true) + optimistic/pessimistic locking

**Filar:** P2, P4
**Status:** test bazowy istnieje (`set cancel at period end`, `concurrent
activateSubscription calls`). Brakuje testu race cancel vs invoice.paid.

**Given/When/Then:**

```
GIVEN: user z aktywnym trialem (subscription_plan='monthly', cancel_at_period_end=false)
WHEN:  POST /account/subscription/cancel
THEN:  - Stripe.Subscriptions.update wywolane z cancel_at_period_end=true,
         Idempotency-Key obecny
       - po webhook customer.subscription.updated: users.subscription_cancel_at_period_end=true
       - subscription_plan POZOSTAJE 'monthly' (uzytkownik nadal ma dostep)
       - subscription_audit_log INSERT action='cancel_at_period_end'

[NOWY — Race]
GIVEN: aktywny user, watek A: cancel, watek B: webhook invoice.paid (jednoczesnie)
WHEN:  10 watkow cancel + 10 watkow invoice.paid uderza w ten sam user.id w t. samym ms
THEN:  - zaden watek nie konczy sie ConcurrentModificationException
       - stan koncowy: jeden z dwoch wariantow:
         (a) cancel + invoice.paid: subscription_plan='monthly',
             cancel_at_period_end=true, subscription_expires_at=current_period_end
         (b) invoice.paid + cancel: identyczny stan koncowy
       - subscription_audit_log ma DOKLADNIE 1 wpis 'cancel' i >=1 'invoice_paid'
       - brak deadlocku w pg_stat_activity
```

**Decyzja:** Uzywamy **SELECT FOR UPDATE** w `UserStore.findByIdForUpdate(userId)`
opakowane w `Database.withTransaction { ... }`. Test `findByIdForUpdate
acquires row lock within a transaction` juz to weryfikuje. Optimistic
locking (kolumna version) dorzucamy *tylko* dla `stripe_event` jako
wymuszenie ordering — patrz Sekcja 8.3.

**Mapowanie:**

- `SubscriptionHandler.kt::cancelSubscription(userId)`
- `StripeHandler.kt::cancelSubscriptionAtPeriodEnd(userId)`
- `UserStore.kt::findByIdForUpdate(userId)`

---

#### Test 5: `[TDD-C2]` Cofniecie cancel (reactivate) przed konca trialu

**Filar:** P2, P4
**Status:** pokryte (`reactivate - clear cancel at period end`).

**Given/When/Then:**

```
GIVEN: user z subscription_cancel_at_period_end=true, plan='monthly', sub_id ustawiony
WHEN:  POST /account/subscription/reactivate
THEN:  - Stripe.Subscriptions.update wywolane z cancel_at_period_end=false,
         Idempotency-Key obecny
       - po webhook: users.subscription_cancel_at_period_end=false
       - subscription_audit_log INSERT action='reactivate'
       - UI usuwa dopisek "(Anulowana...)"

GIVEN: user z cancel_at_period_end=true, ale subscription_expires_at < NOW()
WHEN:  POST /account/subscription/reactivate
THEN:  409 expired_must_recheckout (test juz istnieje:
       `reactivate on locally-expired DB row returns 409 expired_must_recheckout (P2-12)`)
```

---

### GRUPA D — Zmiany planow w trialu

#### Test 6: `[TDD-D1]` Monthly <-> Annual w trialu bez przedwczesnego obciazenia

**Filar:** P2, P3, P4
**Status:** pokryte funkcyjnie (`upgrade from monthly to annual`,
proration tests). Brakuje testu, ze trial_end zostaje *zachowany*.

**Given/When/Then:**

```
GIVEN: user z monthly, w trialu (trial_end = NOW + 18 dni), card-first
WHEN:  POST /account/subscription/change-plan {plan: "annual"}
THEN:  - NIE tworzy nowej Checkout session (Stripe.Subscriptions.update)
       - request do Stripe zawiera:
         * items[0].price = "price_test_annual"
         * trial_end = (oryginalne trial_end, NIE zmienione)
         * proration_behavior = 'none'
         * Idempotency-Key
       - UI komunikat: "Plan zmieniony. Pierwsza platnosc za plan roczny
         zostanie pobrana dopiero po zakonczeniu trialu (DD.MM.YYYY)."
       - subscription_audit_log INSERT action='plan_change_to_annual'
       - users.subscription_plan NIE zmienia sie do czasu webhooka
         customer.subscription.updated, ktory potwierdza items[0].price

GIVEN: ten sam user, ale subscription_plan='monthly', NIE w trialu (trial_end < NOW)
WHEN:  zmiana monthly -> annual
THEN:  - Stripe.Subscriptions.update z proration_behavior='create_prorations'
       - klient widzi kredyt w invoice
       - test juz pokrywa: `upgrade MONTHLY to ANNUAL no overflow`
```

**Mapowanie:**

- `SubscriptionHandler.kt::changePlan(userId, newPlan)`
- `StripeHandler.kt::updateSubscriptionPlan(userId, newPlan, preserveTrialEnd)`

---

### GRUPA E — Trial abuse prevention

#### Test 7: `[TDD-E1]` Wielopoziomowa detekcja trial abuse

**Filar:** P2, P3, P4
**Status:** czesciowo. Fingerprint zapisywany (`stripe_card_fingerprint`),
ale brak `TrialAbuseHeuristics` jako warstwy.

**Given/When/Then:**

```
GIVEN: konto A — uzyto karty 4242424242424242, trial aktywny
WHEN:  konto B (nowy email) probuje aktywowac trial ta sama karta
THEN:
  Stripe Checkout PRZECHODZI (Stripe sam nie blokuje na etapie wpisywania
  karty — to fakt, NIE blad). Po webhook checkout.session.completed:
  - StripeHandler pobiera payment_method.card.fingerprint
  - sprawdza users WHERE stripe_card_fingerprint = ? AND ever_subscribed=true
        OR trial_expires_at IS NOT NULL
  - jezeli znaleziono: Stripe.Subscriptions.update(trial_end='now') →
    skraca trial natychmiast
  - users.trial_expires_at = NOW(),
    users.abuse_blocked = true (NOWA kolumna),
    subscription_audit_log INSERT action='trial_abuse_fingerprint_match'
  - frontend (po SSE event) wyswietla: "Wykryto wczesniej uzyta karte —
    trial juz nie obowiazuje. Aby kontynuowac, oplac plan."

[NOWE warstwy abuse detection — opcjonalne ale rekomendowane]
1. Rate limit rejestracji: max 3 rejestracje per IP per 1h (juz brak — DODAC)
2. Disposable email list (mailinator.com, 10minutemail itd.) — blokada na
   etapie /auth/register
3. Velocity check: konto<24h + checkout od razu + ta sama karta co inne konto<7d
   -> abuse_score+50 (heurystyka)
4. Device fingerprinting (frontend): canvas + UA + screen + timezone hash,
   wysylany przy /auth/register. Match z innym kontem -> abuse_score+30
5. Geo IP: rejestracja z roznych krajow w <1h na ten sam fingerprint -> +20
6. abuse_score >= 70 -> shorten trial = NOW
```

**WAZNE biznesowe:** abuse detection jest *soft* (heurystyki, false-positives
moga sie zdarzyc). Dlatego kluczowe sa:

- Audyt: kazda decyzja w `subscription_audit_log` z `score` i `reasons`
- Mozliwosc manualnego override: admin endpoint POST /admin/users/{id}/clear-abuse-block
- Komunikacja: UI nigdy nie mowi "wykryto fraud", tylko "potrzebna platnosc"

**Mapowanie:**

- **NOWY:** `payment/TrialAbuseHeuristics.kt`
- `StripeHandler.kt::activateSubscription()` (wstrzyknac wywolanie heurystyki)
- **NOWE schema columns:**
  - `users.abuse_blocked BOOLEAN NOT NULL DEFAULT FALSE`
  - `users.abuse_score INTEGER NOT NULL DEFAULT 0`
  - `users.last_seen_ip INET`
  - `users.device_fingerprint VARCHAR(64)`

---

### GRUPA F — Asynchronicznosc i wyscigi

#### Test 8: `[TDD-F1]` SSE waiting screen po checkout

**Filar:** P1, P2
**Status:** SseEventBus istnieje (`sse/SseEventBus.kt`, eventy
`snapshotCreated` itd.), ale brak `subscription_activated` topica i routa
`/panel/processing`.

**Given/When/Then:**

```
GIVEN: user po Stripe Checkout (sukces karty), redirect na /panel?session_id=cs_test_...
       Backend NIE odebral jeszcze webhooka -> users.subscription_plan=NULL
WHEN:  Frontend laduje /panel
THEN:  - Frontend wykrywa subscription_plan=NULL + session_id w URL -> wyswietla
         "ProcessingScreen" zamiast 403 / kierowania na /account/subscription
       - ProcessingScreen otwiera EventSource('/api/sse/events?topic=subscription')
       - W ciagu max 30s przychodzi event {type:'subscription_activated', plan:'monthly'}
       - ProcessingScreen znika, panel renderuje sie z aktywna subskrypcja
       - Jezeli 30s timeout: komunikat "Operacja w toku. Odswiez za chwile."
       - Jezeli SSE rzuci error przed eventem: fallback do polling
         GET /account/subscription co 3s, max 10 prob

[NOWY backend]
- StripeHandler.handleCheckoutCompleted() na koncu robi:
    sseEventBus.publish("subscription", userId, mapOf(
       "type" to "subscription_activated",
       "plan" to plan,
       "trialExpiresAt" to trialEnd
    ))
- SSE auth: jwt query param (juz dziala wg historycznego fixa)
```

**Test integracyjny (Kotlin):**

```kotlin
@Test
fun `[TDD-F1] SSE pushes subscription_activated after webhook processed`() {
    val user = createUser()
    val sseClient = SseTestClient.connect("/api/sse/events?token=${user.jwt}&topic=subscription")

    handleWebhook(checkoutCompletedPayload(user))

    val event = sseClient.awaitEvent(timeout = Duration.ofSeconds(5))
    assertEquals("subscription_activated", event.data["type"])
    assertEquals("monthly", event.data["plan"])
}
```

**Test Playwright (web):**

```typescript
test('[TDD-F1] processing screen vanishes after SSE event', async ({ page }) => {
  await mockBackend(page, { delaySubscription: 2000 });
  await page.goto('/panel?session_id=cs_test_xyz');
  await expect(page.locator('[data-testid="processing-screen"]')).toBeVisible();
  await expect(page.locator('[data-testid="dashboard"]')).toBeVisible({ timeout: 4000 });
});
```

---

### GRUPA G — Storage / Agent enforcement

#### Test 9: `[TDD-G1]` Storage Auth Boundary + JWT agent + DB-down fail-closed

**Filar:** P2, P3, P4
**Status:** StorageQuotaGuard pokrywa happy path. Brakuje 5min JWT i testu pod DB-down.

**Given/When/Then:**

```
[A. JWT agent]
GIVEN: agent zarejestrowany (activation token zamieniony na server_id)
WHEN:  agent wola POST /agent/session/start -> dostaje JWT ttl=5min
THEN:  - kazdy chunk upload POST /agent/chunks zawiera Authorization: Bearer <jwt>
       - JWT zawiera claim subscription_status, weryfikowany on-token-issue
       - po 5min agent automatycznie wola refresh -> nowy JWT
       - StorageQuotaGuard NIE robi SELECT z DB per chunk (bo claim w JWT wystarcza
         na 5min window)

[B. Wygasniecie w trakcie wlasciwego uploadu duzego chunka]
GIVEN: agent ma JWT (subscription_status='active'), zaczyna upload 50GB chunka.
       Po 60s admin zmienia w bazie subscription_plan=NULL
WHEN:  agent wysyla kolejny POST /agent/chunks/{id}/append
THEN:  - JWT nadal wazny (5min) -> request przyjety
       - ALE: StorageQuotaGuard.preFlight() przy seal (PackBuffer.sealAndStore)
         robi SELECT z DB, wykrywa 'none' -> rzuca SubscriptionExpiredException
       - inbox/* zawierajacy partial chunk jest pozostawiony do TTL cleanup
         (DiskGuard) — fizycznie nie ma penalizacji za par bajtow w buforze
       - PackBuffer NIE seal'uje chunka, archive_snapshot NIE jest INSERT
       - agent dostaje response 403 {"code":"SUBSCRIPTION_EXPIRED"}
       - agent przerywa upload i loguje do machine_file_event

[C. DB unavailable fail-closed]
GIVEN: StorageQuotaGuard wywolany, ale DB rzuca PSQLException("connection refused")
WHEN:  PackBuffer.sealAndStore probuje zapytac StorageQuotaGuard.canUpload(userId)
THEN:  - StorageQuotaGuard.canUpload zwraca FALSE (fail-closed, NIE fail-open)
       - PackBuffer rzuca QuotaCheckUnavailableException
       - chunk NIE jest sealowany do OVH
       - log.error z full stacktrace
       - alert do operator (prometheus/log-based)

[D. Audit log]
- Kazda blokada (B lub C) -> subscription_audit_log INSERT action='agent_blocked_subscription_expired' lub 'agent_blocked_db_unavailable'
```

**Test Kotlin (D):**

```kotlin
@Test
fun `[TDD-G1c] StorageQuotaGuard fail-closed when DB unavailable`() {
    val faultyDb = mockk<DataSource>()
    every { faultyDb.connection } throws PSQLException("connection refused", PSQLState.CONNECTION_FAILURE)
    val guard = StorageQuotaGuard(faultyDb)

    val result = guard.canUpload(userId = "any")

    assertFalse(result, "Guard must fail-closed when DB unreachable")
}
```

---

### GRUPA H — Dunning flow

#### Test 10: `[TDD-H1]` invoice.payment_failed + grace + email dunning + agent retry

**Filar:** P1, P2, P3, P4
**Status:** webhook handled, status='past_due'. Brakuje sekwencji emaili i UI yellow banner.

**Given/When/Then:**

```
GIVEN: user z aktywna subskrypcja, dzien 30, automatyczne obciazenie odrzucone
WHEN:  Stripe wysyla webhook invoice.payment_failed
THEN:  - users.subscription_payment_status='past_due' (optimistic update via FOR UPDATE)
       - users.subscription_plan POZOSTAJE 'monthly' (Stripe Smart Retries)
       - subscription_audit_log INSERT action='past_due_started'
       - email automatyczny: "Nie udalo sie pobrac platnosci. Twoj backup nadal dziala."
       - UI banner: zolty z CTA "Zaktualizuj karte"
       - SubscriptionGuard.computeAccess => past_due_grace (canUpload:true, canRestore:true)
       - agent nadal dziala (JWT->subscription_status='past_due_grace' jest dozwolone w guard)

GIVEN: Stripe wykonuje 4 retry'e w cyklu Smart Retries (3, 5, 7, 14 dni)
WHEN:  uzytkownik aktualizuje karte przed 4 retry
THEN:  Stripe automatycznie probuje od razu, sukces -> webhook invoice.paid ->
       past_due_grace -> active

GIVEN: 4 retry'e Stripe nieudane, Stripe konczy cykl
WHEN:  webhook customer.subscription.updated(status='unpaid')
THEN:  users.subscription_payment_status='unpaid'
       SubscriptionGuard => past_due_suspended (canUpload:false, canRestore:true)
       agent: 403 SUBSCRIPTION_PAST_DUE przy upload, 200 przy restore
       email: "Ostatnie wezwanie. Aktualizuj karte by wznowic backup"

GIVEN: brak akcji uzytkownika
WHEN:  webhook customer.subscription.deleted
THEN:  users.subscription_plan=NULL, subscription_expires_at=NOW()
       SubscriptionGuard => expired
       email: "Subskrypcja zamknieta. Twoje dane sa bezpieczne przez 30 dni"
```

**Sekwencja emaili (NOWY mechanizm):**

| Trigger | Czas po past_due | Tresc |
|---------|------------------|-------|
| invoice.payment_failed (pierwsza proba) | T+0 | "Problem z platnoscia. Ponowimy automatycznie" |
| Stripe retry #2 nieudane | T+3 dni | "Nadal nie udalo sie pobrac. Aktualizuj karte" |
| Stripe retry #4 nieudane (last attempt) | T+14 dni | "Ostatnie wezwanie. Po 30 dniach konto wygasnie" |
| customer.subscription.deleted | T+~21 dni | "Subskrypcja zamknieta. Dane bezpieczne przez 30 dni" |

**Implementacja w `TrialNotifier.kt`:**

```kotlin
class TrialNotifier(private val db: DataSource, private val mailer: Mailer) {
    fun checkAndNotify(now: Instant = Instant.now()) {
        // Trial expiring soon (T-3, T-1, T-0)
        // Past_due dunning (T+0, T+3, T+14)
        // Subscription expired (T+0 post-deletion)
        // Idempotency via users.last_trial_notification kolumna
    }
}
```

**Agent retry/backoff (RetryPolicy.kt rozszerzenie):**

```kotlin
class RetryPolicy(
    val maxRetries: Int = 5,
    val baseDelay: Duration = Duration.ofSeconds(2),
    val maxDelay: Duration = Duration.ofMinutes(5),
    val jitter: Double = 0.1,
    val circuitBreaker: CircuitBreaker = CircuitBreaker(threshold = 3, openDuration = Duration.ofMinutes(1))
) {
    fun <T> withRetry(block: () -> T): T { ... }
}

class CircuitBreaker(val threshold: Int, val openDuration: Duration) {
    private var failures = 0
    private var openedAt: Instant? = null

    fun beforeCall() {
        if (openedAt != null && Duration.between(openedAt!!, Instant.now()) < openDuration) {
            throw CircuitOpenException()
        }
    }
    fun onSuccess() { failures = 0; openedAt = null }
    fun onFailure() {
        failures++
        if (failures >= threshold) openedAt = Instant.now()
    }
}
```

---

## 8. Dodatkowe pominiete przypadki (Edge / Abuse / Race / Money)

Ponizsze przypadki nie pojawiaja sie wprost w Twoich 10 testach, ale agent
**musi** je pokryc — kazdy to potencjalny incydent finansowy lub
bezpieczenstwa.

### 8.1. Race: cancel + invoice.paid (same ms)

Patrz Test 4 powyzej, sekcja "NOWY — Race".

### 8.2. Race: 10 rownoczesnych checkoutow tego samego usera

```kotlin
@Test
fun `[TDD-EDGE-1] 10 concurrent checkout POSTs produce 1 stripe session`() {
    val user = createTrialUser()
    val results = (1..10).map {
        async { http.post("/account/subscription/checkout", body = mapOf("plan" to "monthly")) }
    }.awaitAll()

    val uniqueSessions = results.map { it.body["sessionId"] }.distinct()
    assertEquals(1, uniqueSessions.size, "Idempotency-Key must dedupe in 60s bucket")
}
```

### 8.3. Out-of-order webhooks (timestamp ordering)

Sekcja 7.3 [NOWY — Out-of-order]. Dodaj kolumne:

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_stripe_event_at TIMESTAMPTZ;
```

`StripeHandler.applyMutationGuarded(user, eventCreated, mutation)`:

```kotlin
withRowLock(user.id) { latest ->
    if (eventCreated.isBefore(latest.lastStripeEventAt ?: Instant.EPOCH)) {
        log.warn("Stale webhook event ignored (out-of-order)")
        appendStripeEvent(user.id, eventCreated, status = "stale_ignored")
        return@withRowLock
    }
    mutation(latest)
    setLastStripeEventAt(user.id, eventCreated)
}
```

**Decyzja architektoniczna:** *NIE* dodajemy pelnego optimistic locking
(`version` column) bo SELECT FOR UPDATE + last_stripe_event_at jest prostsze
i wystarczajace dla tego ruchu (~100 webhookow/dzien przy 100 klientach).
`stripe_event` tabela jest append-only audit.

### 8.4. Money: VAT calc precision (grosze, nie zlote)

Wszystkie kwoty w bazie i Stripe API w **groszach** (long, nie double).
Test juz pokrywa (`VAT decomposition - 19 PLN gross at 23 percent invariant`).
Agent musi pamietac:

- `subscription_config.vat_rate` = '0.23' (string), parse jako BigDecimal
- `priceGrosze = 1900` (monthly), `19000` (annual)
- VAT decomposition: `vatGrosze = priceGrosze * 23 / 123` (round HALF_UP)
- `netGrosze = priceGrosze - vatGrosze`

### 8.5. Money: refund po cancelImmediate

Test juz pokrywa (`cancelImmediate deactivates subscription and returns
prorated refund amount`). Edge case ktorego brakuje:

```kotlin
@Test
fun `[TDD-EDGE-2] cancelImmediate respects 100% refund window (within 14 days, but only if user did NOT waive)`() {
    // Skoro art. 38 pkt 13 jest zaznaczony, klient ZRZEKL sie prawa do
    // odstapienia. Pelny refund powinien byc DENIED przez backend.
    // ALE: prorated refund (np. 10 dni z 30) jest OK.
    val user = createActiveUser(daysIntoSubscription = 10)
    val response = http.post("/account/subscription/cancel-immediate?confirm=true")
    assertEquals("prorated", response.body["refundType"])
    assertNotEquals("full", response.body["refundType"])
}
```

### 8.6. Money: gift code stacking nie dziala dla Stripe subskrybowanego

Test juz pokrywa (`gift code redeem on stripe-subscribed user is rejected`).
Sprawdzic ze status `past_due_grace` rowniez odrzuca.

### 8.7. Race: promo code parallel claim

Test juz pokrywa (`markPromoCodeUsed under TRUE parallel race rejects everyone past max_uses`).

### 8.8. Edge: user tworzy konto, nigdy nie wchodzi w Checkout — uciekajace zasoby

```sql
-- Cleanup pending users po 30 dniach
DELETE FROM users
WHERE stripe_subscription_id IS NULL
  AND trial_expires_at IS NULL
  AND ever_subscribed = false
  AND created_at < NOW() - INTERVAL '30 days';
```

Scheduled task w `BufferMain`, codziennie o 4:00. **Audyt:** zanim DELETE,
copy do `users_cleanup_log` jako compliance trail.

### 8.9. Edge: stripe_event_idempotency rosnie w nieskonczonosc

Pokryte w `operational-risks.md` sekcja 2. Brakuje implementacji scheduled
task:

```kotlin
cleanupExecutor.scheduleAtFixedRate({
    db.connection.use { conn ->
        val deleted = conn.prepareStatement(
            "DELETE FROM stripe_event_idempotency WHERE created_at < NOW() - INTERVAL '90 days'"
        ).executeUpdate()
        log.info("Cleaned {} idempotency records", deleted)
    }
}, 1, 24, TimeUnit.HOURS)
```

### 8.10. Edge: StorageQuotaGuard pod 50GB upload (storage layer protection)

Sekcja 7.9 [B+C]. Test musi byc *integracyjny* — nie unitowy mock — bo wymaga:

- prawdziwy PostgreSQL (Testcontainers)
- mock OVH Swift (MockSwiftClient juz istnieje)
- agent upload realnego 50MB chunka (skalowany)
- symulacja zmiany subscription_status w trakcie uploadu

### 8.11. Stripe fallback: live klucze identyczne z test (config warning)

Pokryte w `operational-risks.md` sekcja 1. Test integracyjny:

```kotlin
@Test
fun `[TDD-EDGE-3] StripeKeyProvider warns when live == test keys`() {
    val logCapture = LogCaptureExtension.capture()
    StripeKeyProvider(
        testSecretKey = "sk_test_xxx",
        liveSecretKey = "sk_test_xxx", // ZAMIAST sk_live_
        ...
    )
    assertTrue(logCapture.warnings.any { it.contains("STRIPE LIVE KEYS ARE IDENTICAL TO TEST") })
}
```

### 8.12. Webhook: utracone polaczenie podczas DB commit

```
GIVEN: webhook handler skonczyl INSERT do stripe_event_idempotency,
       ale przed COMMIT-em proces sie crashuje
WHEN:  Stripe retry'uje (po 1 min) ten sam event.id
THEN:  - INSERT do stripe_event_idempotency dziala (poprzedni COMMIT sie nie
         odbyl, wiersz nie istnieje)
       - mutacja na users dziala normalnie
       - audit log dostaje wpis
```

Pokryte przez idempotency, ale jako *integration test* z `pg_terminate_backend`
w trakcie transakcji byloby zlote (low priority).

### 8.13. Stripe sandbox: webhook z fake card 4000000000000341 (always decline)

```
GIVEN: user przechodzi Checkout z karta 4000000000000341 (sandbox decline)
WHEN:  Stripe wysyla webhook checkout.session.completed (BO checkout sie udal,
       ale subscription = incomplete)
THEN:  - users.subscription_plan POZOSTAJE NULL
       - subscription_audit_log INSERT action='checkout_incomplete'
       - frontend dostaje SSE event 'subscription_incomplete' -> redirect na
         "/account/subscription?error=card_declined"
```

### 8.14. Sub-second timing: Stripe webhook race z redirect

Pokryte w Test 8 (sekcja 7.8). Dodatkowy edge:

```
GIVEN: webhook przyszedl PRZED redirect z Stripe (rzadkie ale realne)
WHEN:  frontend laduje /panel?session_id=...
THEN:  Frontend sprawdza subscription_plan PRZED otwarciem SSE — widzi 'monthly'
       i pomija ProcessingScreen, idzie wprost do dashboard
```

### 8.15. Browser back button po Stripe Checkout

```
GIVEN: user przeszedl Checkout, jest na /panel
WHEN:  klika "wstecz" w przegladarce
THEN:  Frontend NIE wraca do Stripe (Stripe wymusza, success_url ustawiony
       jako absolute URL). Wraca do /account/subscription, ktora pokazuje
       aktywna subskrypcje, brak duplikatu checkoutu.
```

### 8.16. Email: weryfikacja nie ukonczona, ale user proboje Stripe Checkout

```
GIVEN: user zarejestrowany, ale email_verified=false
WHEN:  POST /account/subscription/checkout
THEN:  403 EMAIL_NOT_VERIFIED. Frontend wyswietla "Potwierdz email aby kontynuowac"
```

### 8.17. Stripe customer ID kolizja test/live

Pokryte (`stripe_customer_id` vs `stripe_live_customer_id`). Test waznosci:

```kotlin
@Test
fun `[TDD-EDGE-4] switching user to live mode does NOT reuse test customer ID`() {
    val user = createUserWithTestStripeCustomer("cus_test_xxx")
    flipUserToLiveMode(user.id)
    val customerId = stripeHandler.getStripeCustomerId(user.id)
    assertNull(customerId) // brak live customer ID jeszcze
    // pierwsze wywolanie ensureStripeCustomer w live mode tworzy nowego
    val newId = stripeHandler.getOrCreateStripeCustomer(user.id, "test@x.com")
    assertNotEquals("cus_test_xxx", newId)
    assertTrue(newId.startsWith("cus_"))
}
```

### 8.18. Stripe Price config: brakuje plan_key=monthly mode=live

```
GIVEN: stripe_price_config zawiera tylko (monthly, test) i (annual, test)
WHEN:  admin flip'uje uzytkownika na live mode i user klika Checkout
THEN:  500 lub clean error "Live price ID not configured. Run schema migration
       and seed stripe_price_config(plan_key, mode='live')"
       NIE wolno fallbackowac na test price ID
```

### 8.19. UI: countdown timer drift

Frontend wyswietla `Math.floor((trialExpiresAt - now) / 86400000)` — moze
pokazac "29 dni" zamiast "30" jezeli kontrast czasu klienta vs serwera. Fix:
backend powinien zwracac `daysRemaining: number` zamiast tylko ISO timestamp,
zeby UI nie liczyl.

### 8.20. Logging: Stripe key wyciekly w stack trace

Test sekcji 3 `operational-risks.md`:

```kotlin
@Test
fun `[TDD-EDGE-5] StripeHandler error log NEVER contains raw key`() {
    val logCapture = LogCaptureExtension.capture()
    every { Customer.create(any(), any()) } throws RuntimeException("debug: sk_test_xxx_secret")
    stripeHandler.getOrCreateStripeCustomer("user-1", "x@x", testMode = true)
    val logs = logCapture.allMessages
    assertFalse(logs.any { it.contains("sk_test_xxx_secret") })
    assertFalse(logs.any { it.contains("sk_test_") }) // tylko 8-char prefix
}
```

### 8.21. Frontend: zmiana planu w trakcie processingu

```
GIVEN: user kliknal Checkout, jest na ProcessingScreen (SSE waiting)
WHEN:  klika "Wstecz", przelacza zakladke na Annual, klika "Wybierz Annual"
THEN:  Frontend BLOKUJE drugie wywolanie checkout pokim ProcessingScreen aktywny
       (mutex). Po pojawieniu sie subscription_activated, user moze normalnie
       zmienic plan przez "Zmien plan" (Test 6).
```

### 8.22. Concurrent: dwa webhooki tego samego event.id rownoczesnie

```kotlin
@Test
fun `[TDD-EDGE-6] two concurrent webhooks with same event.id process exactly once`() {
    val event = checkoutCompletedEvent("evt_test_unique_xxx", userId)
    val results = (1..5).map {
        async { handleWebhook(event.payload, event.signature) }
    }.awaitAll()
    // Tylko 1 powinien wykonac mutacje, reszta 200 OK ale skip
    val mutationCount = subscriptionAuditLog.count(action = "checkout_completed", userId = userId)
    assertEquals(1, mutationCount)
}
```

### 8.23. Edge: subscription_expires_at + cancel_at_period_end ale Stripe podaje period_end pozniej

Stripe webhook moze zmienic period_end (np. user dodal nowy okres recznie).
Test: ufamy Stripe, nadpisujemy lokalnie zawsze gdy event.created > last_stripe_event_at.

### 8.24. Multi-tenant: jedna z tabel ma row-level security?

NIE. ProperBackup nie uzywa RLS. Wszystkie zapytania jawnie filtruja
WHERE user_id = ?. Test:

```kotlin
@Test
fun `[TDD-EDGE-7] user A cannot see user B subscription_audit_log via API`() {
    val a = createUser(); val b = createUser()
    flipUserToActive(b)
    val logs = http.withAuth(a.jwt).get("/account/audit-log").body["entries"]
    assertTrue(logs.none { it["userId"] == b.id })
}
```

### 8.25. Locale: subscription_audit_log timestamps z UTC

Wszystkie timestamps zapisywane jako TIMESTAMPTZ, serializowane jako ISO-8601
z `+00:00`. Frontend konwertuje do local timezone.

### 8.26. Edge: agent restart w trakcie chunka

(Pokryte przez resumable upload — sekcja 9.5)

### 8.27. Storage: zwracanie 401 Unauthorized z OVH

```
GIVEN: OVH credentials wygasly (token refresh failed)
WHEN:  PackBuffer.flush proboje upload do OVH
THEN:  - retry 3 razy z exponential backoff
       - po 3 nieudanych: log.error + alert
       - chunk zostaje w buffer/pack do recznej interwencji
       - StorageQuotaGuard NIE pozwala na nowe uploady (fail-closed)
       - users.subscription_status NIE jest zmieniany (to nasz problem, nie klienta)
```

### 8.28. Webhook signature: dual-secret leakage

Test juz pokrywa (`webhook dual-secret verification accepts test-mode webhook`).
Edge:

```
GIVEN: STRIPE_TEST_WEBHOOK_SECRET = "whsec_aaa", STRIPE_LIVE_WEBHOOK_SECRET = "whsec_bbb"
WHEN:  payload podpisany "whsec_bbb" (live) przychodzi
THEN:  webhookSecretCandidates() proboje OBA, znajduje match dla bbb,
       processuje event WITH stripe_test_mode=false dla user'a powiazanego.
       NIE odrzuca jako "test secret mismatch".
```

### 8.29. UI: dlugie email > 64 znakow

```
GIVEN: email "very.long.email.with.over.sixty.four.characters@example.com" (>64)
WHEN:  rejestracja
THEN:  400 EMAIL_TOO_LONG. Backend constraint zgodny z RFC 5321 (lokalnie 64, total 254)
```

### 8.30. Stripe Webhook ordering: customer.subscription.deleted PRZED checkout.session.completed

Niemozliwe w praktyce (Stripe ordering), ale defensive:

```
GIVEN: subscription deleted przyszlo PRZED completed (np. test scenariusz)
WHEN:  oba dotarly
THEN:  deleted aplikuje sie tylko jezeli last_stripe_event_at < deleted.created.
       Jezeli completed przyszedl pozniej z eventCreated < deleted.created -> ignore.
```

---

## 9. Specyfikacja techniczna nowych komponentow

### 9.1. Dead-Letter Queue dla webhookow

**Plik:** `properbackup-buffer/src/main/kotlin/.../payment/WebhookDlq.kt` (NOWY)

```sql
CREATE TABLE IF NOT EXISTS stripe_webhook_dlq (
  id BIGSERIAL PRIMARY KEY,
  stripe_event_id VARCHAR(64) NOT NULL,
  event_type VARCHAR(128) NOT NULL,
  payload TEXT NOT NULL,
  signature_header TEXT NOT NULL,
  retry_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_stripe_webhook_dlq_unresolved
  ON stripe_webhook_dlq(resolved_at) WHERE resolved_at IS NULL;
```

**API:**

```kotlin
class WebhookDlq(private val db: DataSource) {
    fun enqueue(eventId: String, eventType: String, payload: String, sigHeader: String, error: Throwable) { ... }
    fun listUnresolved(limit: Int = 100): List<DlqEntry>
    fun replay(id: Long, handler: WebhookHandler): ReplayResult
    fun markResolved(id: Long)
}
```

**Admin endpoint:**

```
POST /admin/webhooks/dlq/{id}/replay      → reprocesuje event
GET  /admin/webhooks/dlq                  → lista pending
```

Wymaga `serviceAdminAuth` filter (juz istnieje w `ServiceAdminCodeStore`).

### 9.2. Agent JWT (krotkotrwaly)

**Plik:** `auth/JwtService.kt` (rozszerzenie istniejacego)

```kotlin
class JwtService(private val secret: String) {
    private val ACCESS_TTL = Duration.ofMinutes(5)
    private val PANEL_TTL = Duration.ofHours(12)

    fun issueAgentToken(serverId: String, subscriptionStatus: String): String {
        val claims = mapOf(
            "sub" to serverId,
            "type" to "agent",
            "subscriptionStatus" to subscriptionStatus,
            "exp" to Instant.now().plus(ACCESS_TTL).epochSecond
        )
        return signedJwt(claims)
    }
    fun issuePanelToken(userId: String): String { ... }
    fun validate(token: String): TokenClaims
}
```

**Endpoint:** `POST /agent/session/start` (Authorization: Bearer <UPLOAD_TOKEN>)
zwraca `{accessToken, expiresIn=300, refreshAfter=240}`.

Agent woła refresh przy ttl < 60s.

### 9.3. ProcessingScreen (web)

**Plik:** `properbackup-web/src/subscription/ProcessingScreen.jsx` (NOWY)

```jsx
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { t } from '../i18n';

export default function ProcessingScreen() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const [status, setStatus] = useState('waiting');
  const sessionId = params.get('session_id');

  useEffect(() => {
    if (!sessionId) { navigate('/panel'); return; }

    const sse = new EventSource(`/api/sse/events?topic=subscription&token=${getJwt()}`);
    let timeoutId = setTimeout(() => setStatus('timeout'), 30000);

    sse.addEventListener('subscription_activated', () => {
      clearTimeout(timeoutId);
      sse.close();
      navigate('/panel', { replace: true });
    });
    sse.addEventListener('subscription_incomplete', () => {
      clearTimeout(timeoutId);
      sse.close();
      navigate('/account/subscription?error=card_declined', { replace: true });
    });
    sse.onerror = () => { setStatus('fallback_polling'); /* polling start */ };

    return () => { sse.close(); clearTimeout(timeoutId); };
  }, [sessionId]);

  return (
    <div data-testid="processing-screen" className="...">
      <Spinner />
      <h2>{t('subscription.processing.title')}</h2>
      <p>{t('subscription.processing.desc')}</p>
      {status === 'timeout' && <button onClick={() => location.reload()}>{t('common.refresh')}</button>}
    </div>
  );
}
```

**Route:** w `src/router/AppRouter.jsx`, dodac `<Route path="/panel" element={<PanelOrProcessing />} />` gdzie `PanelOrProcessing` warunkowo renderuje ProcessingScreen lub Dashboard.

### 9.4. TrialNotifier rozszerzenie (dunning emails)

**Plik:** `subscription/TrialNotifier.kt` (rozszerzenie istniejacego)

Dodatkowe kolumny w users:

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_past_due_notification VARCHAR(16);
-- values: 'past_due_t0', 'past_due_t3', 'past_due_t14', 'final_cancellation'
```

Scheduled task w `BufferMain` (codziennie o 9:00):

```kotlin
trialNotifier.runDailyCheck(now = Instant.now())
```

Tresc emaili w `i18n/locales/pl.json`:

```json
"email.pastDue.t0.subject": "Problem z platnoscia za ProperBackup",
"email.pastDue.t0.body": "...",
"email.pastDue.t3.subject": "Ponawiamy probe pobrania platnosci",
"email.pastDue.t14.subject": "Ostatnie wezwanie",
"email.subCanceled.subject": "Twoja subskrypcja zostala zamknieta"
```

### 9.5. Resumable uploads (agent)

**Plik:** `properbackup-shared/src/jvmMain/.../transport/BufferUploader.kt`

API:

```
POST /agent/chunks/{chunkId}/init        → zwraca uploadUrl + uploadId
PUT  /agent/chunks/{chunkId}/append      → Content-Range: bytes 0-X/Y
                                            (idempotent — server liczy received bytes)
POST /agent/chunks/{chunkId}/finalize    → walidacja, seal trigger
```

Agent przed kazdym PUT sprawdza `GET /agent/chunks/{chunkId}/offset` i wznawia od tego miejsca.

### 9.6. Circuit breaker (agent)

Sekcja 7.10 [agent retry/backoff] — kod podany powyzej.

### 9.7. Cleanup cron tasks

W `BufferMain.kt` po inicjalizacji:

```kotlin
val cleanupExecutor = Executors.newSingleThreadScheduledExecutor()

// stripe_event_idempotency: 90 dni TTL
cleanupExecutor.scheduleAtFixedRate(::cleanupIdempotency, 1, 24, TimeUnit.HOURS)

// users (pending, never paid): 30 dni TTL
cleanupExecutor.scheduleAtFixedRate(::cleanupAbandonedUsers, 2, 24, TimeUnit.HOURS)

// subscription_audit_log: ZACHOWAC FOREVER (compliance)
// stripe_webhook_dlq: rezolwowane > 30 dni TTL
cleanupExecutor.scheduleAtFixedRate(::cleanupResolvedDlq, 3, 24, TimeUnit.HOURS)

// trial/past_due notifications (codziennie o 9:00)
cleanupExecutor.schedule(::runDailyDunning, secondsUntil9am(), TimeUnit.SECONDS)
```

---

## 10. Definition of Done per test

Kazdy test z sekcji 7+8 jest "Done" gdy spelnia **wszystkie** ponizsze:

1. **Czerwony test napisany pierwszy.** Commit z testem (failing) jest
   w git log PRZED commitem implementacji. Recenzent moze to zweryfikowac
   `git log --oneline --reverse <branch> ^main`.

2. **Test integracyjny na Testcontainers PostgreSQL.** Brak in-memory.

3. **Test obejmuje pelen Given/When/Then** opisany w sekcji 7/8 (nie wycieta wersja).

4. **`subscription_audit_log` zawiera odpowiedni wpis** — sprawdzone w teste
   przez `assertEquals` na rows count + action name.

5. **Logi NIE zawieraja sekretow.** Test `LogCaptureExtension` (jak w
   sekcji 8.20) potwierdza.

6. **Idempotency-Key obecny** dla kazdego outbound Stripe call (RequestOptions
   inspekcja w mocku).

7. **Brak deadlockow** w `pg_stat_activity` po teste (sprawdzany przez
   `@AfterEach` cleanup).

8. **Dla testow web (P1):** Playwright Slow 3G profile +
   Double-Click assertion.

9. **PR description** zawiera w sekcji "Tests" jawne `[TDD-Xn] - X passing, Y failing` przed merge'em.

10. **Brak zmian w plikach z sekcji 4.2 (NIE RUSZAJ)**, weryfikowalne
    `git diff --stat` w PR.

---

## 11. TDD Workflow Protocol (jak agent ma pracowac)

Dla **kazdego** punktu z sekcji 7/8, agent wykonuje sciscle:

```
┌────────────────────────────────────────────────────────────────────┐
│  Krok 1: SCOPE                                                     │
│  - Otworz ten dokument                                             │
│  - Wybierz JEDEN test (np. [TDD-A1])                               │
│  - Sprawdz status w sekcji 3.5 — czy juz jest implementacja?       │
│    * Jezeli TAK -> dopisz tylko brakujace asercje                  │
│    * Jezeli NIE -> przejdz do Krok 2                               │
│  - Sprawdz sekcje 4 — ktore pliki bedziesz modyfikowac?            │
│    Jezeli jakikolwiek jest w "NIE RUSZAJ" -> STOP, zapytaj usera.  │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Krok 2: RED TEST                                                  │
│  - Napisz failing test w SubscriptionIntegrationTest.kt z prefix   │
│    [TDD-Xn]                                                         │
│  - Uruchom test, potwierdz ze jest CZERWONY (FAIL)                 │
│  - git add -p <test_file>; git commit -m "test([TDD-Xn]): failing  │
│    integration test for ..."                                       │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Krok 3: GREEN IMPL                                                │
│  - Napisz MINIMALNY kod ktory robi test zielonym                   │
│  - Zero ingerencji w "NIE RUSZAJ" files                            │
│  - Zero refactoru istniejacych metod (nawet "drobnych poprawek")   │
│  - Uruchom CALY suite testow integracyjnych (./gradlew test)       │
│  - Wszystkie testy musza byc zielone                               │
│  - git commit -m "feat([TDD-Xn]): minimal impl for ..."            │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Krok 4: REFACTOR (opcjonalny, w obrebie zielonej strefy)          │
│  - Jezeli kod ktory napisales w Krok 3 jest "smelly", *teraz*      │
│    mozesz refactorowac — w obrebie plikow DOTYKAJ.                 │
│  - Uruchom testy ponownie po kazdym kroku.                         │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Krok 5: AUDIT TRAIL                                               │
│  - Sprawdz ze subscription_audit_log dostaje wpisy w odpowiednich  │
│    miejscach                                                       │
│  - Sprawdz ze logi NIE zawieraja sekretow                          │
│  - Jezeli zmieniales schema -> sprawdz ze migracja jest IF NOT     │
│    EXISTS i nie ma DROP/RENAME                                     │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Krok 6: PR / NASTEPNY TEST                                        │
│  - Po kazdych 3-5 [TDD-Xn] pokrytych -> push branch + utworz PR    │
│    (granularnosc daje uzytkownikowi szanse na review)              │
│  - PR title: "feat: TDD batch — [TDD-A1, TDD-A2, TDD-A3]"          │
│  - PR description: tabelka "Tests added: ..."                      │
└────────────────────────────────────────────────────────────────────┘
```

**Czerwone linie ktorych nie wolno przekroczyc:**

- NIE komituj implementacji bez wczesniejszego czerwonego testu w tym samym branchu.
- NIE skipuj testow z `@Disabled` zeby PR przeszedl.
- NIE modyfikuj istniejacych zielonych testow zeby "pasowaly do nowego kodu" —
  jezeli istniejacy test ma nie miec sensu, **zglos to do uzytkownika** i pozostaw
  istniejacy + dodaj nowy obok.
- NIE merge'uj PR-ow samodzielnie. Devin nie ma uprawnien do main —
  wymaga zatwierdzenia uzytkownika.

---

## 12. Prompt szablon "Senior + QA Paranoid Mode"

Dla **kazdej** sesji ktora zaczyna prace z tego planu, doklej ten blok na
poczatku promptu (kontynuacja `architecture/resilience-testing.md` System Guard):

```
═══════════════════════════════════════════════════════════════════════
[ROLE: SENIOR DEVELOPER & QA PARANOID + CFO PARANOID]
═══════════════════════════════════════════════════════════════════════

Pracujesz nad ProperBackup (micro-SaaS, 19 PLN/mies, Stripe billing).
Twoja praca dotyczy KASY KLIENTOW. Nie ma miejsca na "pojde na latwizne".

Twoje role:
1. SENIOR DEV — piszesz minimalny, schludny Kotlin/React.
2. QA PARANOID — szukasz race condition, timeoutow, dead-letterow.
3. CFO PARANOID — pytasz "co jesli zaplacimy klientowi 2x", "co jesli
   damy mu trial 2x", "co jesli storage layer wzaiazl pieniadze przed
   webhook'iem"?

Zasady twardych:
- Master TDD Plan (docs/architecture/master-tdd-plan.md) jest twoim
  pojedynczym punktem prawdy. Trzymasz sie sekcji DOTYKAJ vs NIE RUSZAJ.
- Czerwony test PIERWSZY, kod drugi. Bez wyjatkow.
- Wszystkie testy logiki bazodanowej dzialaja na Testcontainers PostgreSQL.
- Outbound API call do Stripe -> ZAWSZE Idempotency-Key.
- Inbound webhook -> ZAWSZE signature verify + idempotency claim + audit log.
- Brak ruszania crypto (ProperCrypto, KeyDerivation).
- Brak ruszania storage layer (ChunkSealer, OvhSwiftClient).
- Brak modyfikacji istniejacych testow zielonych.

Przed napisaniem kazdej metody odpowiedz na 4 pytania:
1. ASYNCHRONICZNOSC: co jesli siec / Stripe / DB zlaguje 15s?
2. WYSCIGI: co jesli ten user kliknie 5 razy w 100ms?
3. FAULT INJECTION: co jesli Stripe odpowie 429 lub 500?
4. KASA: co najgorszego dla naszej kasy moze sie stac w tej sciezce?

KAZDA znaleziona luka = osobny czerwony test PRZED kodem.
═══════════════════════════════════════════════════════════════════════
```

---

## 13. Checklist Go/No-Go przed live

> **Ostatnia aktualizacja:** 2026-05-31 (sesja docs update).
> Legenda: [x] = potwierdzone, [ ] = oczekuje, [~] = czesciowo / wymaga weryfikacji.

Przed flip'em pierwszego usera na `stripe_test_mode=FALSE`:

### 13.1. Konfiguracja serwera

> **Status: KOD GOTOWY, KONFIGURACJA OCZEKUJE.**
> `StripeKeyProvider`, `docker-compose.yml` i `env-reference.md` obsluguja dual-key
> (test/live). Ponizsze punkty dotycza konfiguracji srodowiska produkcyjnego —
> wpisania prawdziwych kluczy live i weryfikacji endpointu webhook.

- [ ] `STRIPE_LIVE_SECRET_KEY` ustawione i zaczyna sie od `sk_live_`
- [ ] `STRIPE_LIVE_PUBLIC_KEY` ustawione i zaczyna sie od `pk_live_`
- [ ] `STRIPE_LIVE_WEBHOOK_SECRET` ustawione (osobny endpoint w Stripe Dashboard)
- [ ] Webhook endpoint w Stripe Live skonfigurowany: `https://panel.../api/payment/stripe/webhook`
- [ ] Test webhook z Stripe Live Dashboard -> 200 OK w naszych logach
- [ ] `stripe_price_config` zawiera (monthly, live) i (annual, live) z prawdziwymi `price_live_xxx` ID
- [ ] Backend zrestartowany po zmianach `.env`
- [x] `StripeKeyProvider` przy starcie loguje "TEST keys: sk_test_..." i "LIVE keys: sk_live_..." (rozne prefixy) — *zaimplementowane w `StripeKeyProvider.kt`, potwierdzone w changelog 2026-05-24*

### 13.2. Testy

> **Status: WSZYSTKIE TESTY ZIELONE (stan na 2026-05-30).**

- [x] CALY suite `SubscriptionIntegrationTest.kt` (TDD-A1 ... TDD-EDGE-7) zielony — *~80 testow, 2000+ linii, potwierdzone na branchu `devin/1779812528-trial-abuse-pastdue`*
- [x] CALY suite `StripePerModeIsolationTest.kt` zielony — *11 testow key isolation, potwierdzone w changelog 2026-05-24*
- [x] CALY suite `StorageQuotaGuardIntegrationTest.kt` zielony — *7 testow Testcontainers PostgreSQL*
- [x] Playwright E2E (10/10) zielony na `properbackup-test-server` — *potwierdzone 2026-05-26, nagrania w `e2e-videos/2026-05-26-fixes/`*
- [x] Manualne nagrania video kazdego z 10 testow (przechowywane w `properbackup-docs/e2e-videos/`) — *10 plikow `.webm` w `e2e-videos/2026-05-26-fixes/`*
- [x] Playwright E2E recovery (2/2) zielony — *potwierdzone 2026-05-30, nagranie w `e2e-videos/2026-05-30-recovery/`*

### 13.3. Operacyjne

> **Status: CZESCIOWO. DLQ i monitoring jeszcze nie zaimplementowane.**

- [ ] `stripe_webhook_dlq` jest pusta lub wszystkie eventy mark'owane resolved — *UWAGA: tabela DLQ jeszcze nie istnieje (patrz sekcja 3.5 / 9.1)*
- [x] `subscription_audit_log` ma sensowne wpisy dla wszystkich aktywnych userow — *tabela istnieje, append-only, wpisy generowane przy kazdym zdarzeniu billingowym*
- [ ] Backup PostgreSQL dziala — `pg_dump` co 6h + retencja 30 dni
- [ ] Monitoring: alerty dla `stripe_event_idempotency.count > 10/min` (anomalia) — *wymaga wdrozenia observability (patrz `observability-and-dr-spec.md`)*
- [ ] Monitoring: alerty dla `stripe_webhook_dlq.unresolved > 0` (failure) — *zablokowane przez brak DLQ*
- [x] Procedura rollback: dokumentacja jak cofnac usera z live na test mode w razie wpadki — *udokumentowane w `stripe-key-isolation.md`: `UPDATE users SET stripe_test_mode = TRUE WHERE id = ?`*

### 13.4. Prawne i biznesowe

- [ ] Regulamin (T&C) dostepny w panelu + checkbox akceptacji przy rejestracji
- [x] Klauzula art. 38 pkt 13 (zrzeczenie prawa do odstapienia) — widoczna, NIE ukryta — *zaimplementowana, potwierdzona E2E test #6 (pl/en), spec w `legal-withdrawal-waiver.md`*
- [ ] Polityka prywatnosci dostepna
- [ ] Faktury VAT generowane automatycznie po `invoice.paid` (Stripe Invoicing)
- [ ] Email serwisowy `support@properbackup.pl` skonfigurowany i monitorowany

### 13.5. Soft launch

- [ ] Pierwszy uzytkownik live to **wlasciciel** (Daniel Niemiec). Self-test full path.
- [ ] Drugi user live to zaufany pilot (np. znajomy admin MC).
- [ ] Dopiero po 7 dniach bez incydentu — flip pozostalych uzytkownikow.

### 13.6. Podsumowanie gotowosci (dodane 2026-05-31)

| Obszar | Gotowe | Oczekuje | Blokuje live? |
|--------|--------|----------|---------------|
| Kod Stripe (checkout, webhook, key isolation, trial abuse, past_due) | 100% | — | NIE |
| Testy (unit + integration + E2E + nagrania) | 100% | — | NIE |
| Konfiguracja serwera (klucze live, webhook, price_config) | 0% | 7 punktow | TAK |
| DLQ + monitoring | 0% | 5 punktow | TAK (DLQ), mozliwe do odroczenia (monitoring) |
| Prawne (regulamin, privacy, VAT, email) | 20% | 4 punkty | TAK |
| Soft launch | 0% | 3 punkty | — (po spelnieniu powyzszych) |

---

## Dodatek A — Glosariusz pojec

| Termin | Definicja |
|--------|-----------|
| Access Boundary | Centralna polityka dostepu (`SubscriptionGuard`). Jedyne miejsce, gdzie wyliczany jest `(canUpload, canRestore, agentAuthError, uiBadge)`. |
| Audit log | Append-only tabela `subscription_audit_log` z kazdym zdarzeniem billingowym. |
| Card-first trial | Trial 30d wymagajacy podania karty w Stripe Checkout PRZED rozpoczeciem. Inaczej `subscription_status='none'`. |
| Clock Skew Tolerance | Tolerancja w Stripe signature verification dla roznicy zegara serwer Stripe vs nasz (default 5 min). |
| DLQ | Dead-Letter Queue. Tabela `stripe_webhook_dlq` z eventami, ktore nie przetwarzaja sie po N retry'ach. |
| Dunning | Sekwencja powiadomien o nieudanej platnosci (Stripe Smart Retries + nasze emaile). |
| Fail-closed | Default: odmowa dostepu. Stosujemy gdy DB/Stripe niedostepne. |
| Fingerprint | Stripe-assigned unique ID karty kredytowej. Stabilny per karta, niezalezny od email. |
| Idempotency-Key | Unikalny header per outbound Stripe call. Dedup w razie timeoutu retry. |
| Optimistic Locking | Mechanizm wykrywania konfliktu przez kolumne `version`. **My uzywamy SELECT FOR UPDATE (pessimistic)**. |
| Past Due Grace | Stan billingowy po pierwszym `invoice.payment_failed`, w trakcie Stripe Smart Retries. Dostep zachowany. |
| Past Due Suspended | Stan billingowy po wyczerpaniu Stripe retry'ow, status=`unpaid`. Upload blokowany, restore dozwolony. |
| Proration | Wyliczanie kredytu przy zmianie planu w trakcie okresu. Wzor: `(cena/30) * dni_pozostale`. |
| SELECT FOR UPDATE | Pessimistic row-level lock w PostgreSQL. Uzywany w `findByIdForUpdate`. |
| SSE | Server-Sent Events. Push z backendu do frontendu (`SseEventBus`). |
| Storage Auth Boundary | Warstwa w `StorageQuotaGuard` decydujaca czy chunk moze byc seal'owany. Zalezy od `subscription_status` i `storage_limit`. |
| Trial Abuse | Proba uzyskania wielokrotnego trialu przez tworzenie wielu kont. Blokada glownie przez `stripe_card_fingerprint` + heurystyki. |

---

## Dodatek B — Quick reference: pliki testowe

| Plik | Zakres |
|------|--------|
| `properbackup-buffer/src/test/.../payment/SubscriptionIntegrationTest.kt` | Pelen zakres TDD-A..TDD-H + edge cases |
| `properbackup-buffer/src/test/.../payment/StripePerModeIsolationTest.kt` | Test/live mode izolacja |
| `properbackup-buffer/src/test/.../flush/StorageQuotaGuardIntegrationTest.kt` | TDD-G1 (storage gate) |
| `properbackup-buffer/src/test/.../flush/BudgetGuardIntegrationTest.kt` | Rate limiting flush |
| `properbackup-buffer/src/test/.../auth/JwtServiceTest.kt` | Agent JWT (TDD-G1 czesc A) |
| `properbackup-buffer/src/test/.../logs/TokenBucketLimiterTest.kt` | Rate limiting logow |
| **NOWY:** `properbackup-buffer/src/test/.../payment/WebhookDlqIntegrationTest.kt` | TDD-B2 (DLQ) |
| **NOWY:** `properbackup-buffer/src/test/.../subscription/TrialNotifierIntegrationTest.kt` | TDD-H1 dunning emails |
| **NOWY:** `properbackup-web/tests/e2e/subscription-flow.spec.ts` | TDD-F1 (SSE), TDD-EDGE-1 (Double-click) |
| **NOWY:** `properbackup-web/tests/e2e/slow-network.spec.ts` | Filar P1 |

---

## Dodatek C — Historia decyzji architektonicznych

Dla zachowania kontekstu — co i kiedy zostalo zdecydowane:

| Data | Decyzja | Zrodlo |
|------|---------|--------|
| 2026-05-08 do 2026-05-11 | Agent backupowy z dwoma trybami (serwis / wrapper), telemetria SSE, BudgetGuard fail-safe | sesje 26ad83b, f90660b |
| 2026-05-24 | Per-user Stripe key isolation (`stripe_test_mode`) | sesja 0dd2f3c, PR buffer#19, web#28 |
| 2026-05-24 | Card-first trial (porzucenie trial-on-registration) | sesja f6c2081, fix `trial_expires_at` |
| 2026-05-24 | UI plan cards redesign — usuniecie "Best Value", aktywny plan z silnym kontrastem | sesja f6c2081, PR web#31 |
| 2026-05-24 | Klauzula art. 38 pkt 13 widoczna pod kartami planow | sesja f6c2081 |
| 2026-05-26 | Trial abuse fingerprint + past_due grace state | branch buffer `devin/1779812528-trial-abuse-pastdue` |
| 2026-05-26 | Master TDD Plan (ten dokument) | sesja b2b8ff8 |

---

## Dodatek D — Czego ten plan NIE obejmuje

Swiadomie poza scope tego dokumentu (oddzielne plany w przyszlosci):

- **Migracja na live storage OVH** — wymaga osobnego planu (klucze OVH, monitoring, koszt per GB)
- **Sklep "Open Core" / GitHub Open Source release** — strategia biznesplan sekcja 8
- **YouTube content marketing** — biznesplan sekcja 15
- **Plugin Minecraft (properbackup-mc)** — osobny PR pipeline
- **iOS/Android client** — poza MVP rok 1
- **Multi-tenant enterprise (B2B)** — biznesplan rok 2+
- **Self-hosted MinIO** — po >500 klientow

---

## Dodatek E — Indeks LLD (odpowiedź na audyt ryzyka)

> Audyt techniczny wskazał, że specy dają świetny high-level design, ale agent
> potrzebuje **Low-Level Design** (sygnatury, DDL, payloady, niezmienniki), żeby
> kodować „na krótkiej smyczy". Poniżej mapa nazwanych niezmienników dodanych do
> każdego spec — agent ma obowiązek je czytać i NIE łamać.

| Spec | Sekcja LLD | Nazwane niezmienniki / kontrakty |
|------|-----------|----------------------------------|
| `trial-abuse-prevention.md` | Threat Model v2 | AV-1..AV-7 (wektory ataku), email canonicalization, `signup_fingerprint` DDL |
| `downgrade-logic.md` | LLD kontrakt metod | I-1..I-5 (`BillingMath.newExpiresAt`, idempotencja) |
| `subscription-expiration-handling.md` | Access Boundary | `AccessState` FSM, `canRestore`=true zawsze |
| `promo-codes.md` | atomowa redempcja | `UPDATE ... WHERE used_count < max_uses RETURNING` (anty-TOCTOU) |
| `stripe-key-isolation.md` | dual-secret webhook | K-1..K-5 (fail-closed bez secret) |
| `buffer-core-master-spec.md` | Dodatek C | B-1..B-5 (fail-safe, idempotency, async cold) |
| `agent-vps-master-spec.md` | Dodatek C | A-1..A-5, Circuit Breaker, response→reakcja |
| `shared-core-architecture-spec.md` | Appendix E | S-1..S-4 (SemVer, pinning, cross-host-parity) |
| `ovh-cloud-archive-migration-spec.md` | Dodatek E | O-1 (`RestoreState` sealed — wymusza async) |
| `user-facing-recovery-spec.md` | Appendix E | R-1 (brak częściowego restore z cold) |
| `crypto-and-compliance-spec.md` | Dodatek C | C-1..C-5 (zero-knowledge, audit hash-chain) |
| `observability-and-dr-spec.md` | Dodatek D | metryki + alerty per niezmiennik |
| `ci-cd-release-pipeline-spec.md` | Dodatek D | bramki merge egzekwujące niezmienniki |
| `web-panel-master-spec.md` | Dodatek C | W-1 (`accessState` jedyne źródło), SSE katalog |
| `minecraft-plugin-master-spec.md` | Dodatek C | MC-1 (cienki host na `shared`) |
| `legal-withdrawal-waiver.md` | LLD | L-1 (checkout wymaga utrwalonej zgody) |

**Zasada smyczy:** delegując zadanie agentowi, wskaż konkretny spec + sekcję LLD
+ numery niezmienników, które kod musi spełnić (np. „zaimplementuj redeem promo
wg `promo-codes.md` §5, niezmienniki anty-TOCTOU"). Nie „napisz system promo".

---

> **Koniec dokumentu.** Wszystkie dalsze zmiany w planie billingu/subskrypcji
> **musza** byc dodawane jako PR do tego pliku z linkiem do sesji ktora
> uzasadnia zmiane. Dokumentacja zywa = dokumentacja prawdziwa.
