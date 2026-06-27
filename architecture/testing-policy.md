# ProperBackup — Polityka testowania

> **Zasada:** Każda zmiana MUSI być weryfikowana na żywym serwerze testowym,
> nie tylko lokalnie czy w CI. Testy jednostkowe/integracyjne (Testcontainers)
> to minimum — ale finalna walidacja to zawsze żywy stack na maszynie testowej.

---

## 1. Serwer testowy

| Parametr | Wartość |
|----------|---------|
| **Host** | `properbackup-test-server.softify.com.pl` |
| **Hosting** | home.pl (VPS) |
| **Dostęp SSH** | `root@properbackup-test-server.softify.com.pl` (klucz ed25519) |
| **Stack** | Docker Compose: PostgreSQL 16 + Buffer (Kotlin/Javalin) + Nginx + Web |
| **Stripe** | Tryb sandbox (klucze testowe) |
| **Baza** | PostgreSQL 16 w kontenerze `properbackup-db` |
| **Buffer** | `/opt/properbackup/buffer/properbackup-buffer.jar` na port 7100 |
| **Frontend** | Statyczne pliki w `/opt/properbackup/web/` serwowane przez Nginx :80 |

## 2. Zasady testowania

### 2.1. Każdy PR = test na żywym serwerze

1. **Unit/integracja lokalna** — `./gradlew test` z Testcontainers (minimum)
2. **Build artefaktu** — `./gradlew shadowJar` (buffer), `npm run build` (web)
3. **Deploy na serwer testowy** — SCP jar/dist + restart kontenera
4. **Smoke test** — curl endpoints, sprawdzenie logów
5. **E2E na żywo** — Playwright testy (happy path + edge cases) przeciwko `http://properbackup-test-server.softify.com.pl`
6. **Raport** — wynik testów w opisie PR lub komentarzu

### 2.2. Co testować E2E (Playwright)

**Happy paths:**
- Rejestracja użytkownika → email weryfikacja → login
- Dashboard wyświetla agenty i serwery
- Strona subskrypcji: plany widoczne, Stripe Checkout otwiera się
- Checkout z kartą testową 4242... → subskrypcja aktywna
- Agent upload → timeline pokazuje pliki
- Restore: wybór snapshotu → download → weryfikacja integralności

**Edge cases:**
- Duplikat rejestracji (ten sam email)
- Wygasły trial → blokada dostępu (402)
- Webhook replay (ten sam event 2x) → idempotentny
- DB down → StorageQuotaGuard fail-closed (blokuje upload)
- Cancel → reactivate w grace period
- Plan change (monthly ↔ annual) podczas trialu

### 2.3. Procedura deploy na testowy serwer

```bash
# Buffer (backend)
cd properbackup-buffer
./gradlew shadowJar
scp build/libs/properbackup-buffer-*-all.jar \
  root@properbackup-test-server.softify.com.pl:/opt/properbackup/buffer/properbackup-buffer.jar
ssh root@properbackup-test-server.softify.com.pl \
  "cd /opt/properbackup && docker compose restart buffer"

# Web (frontend)
cd properbackup-web
npm ci && npm run build
scp -r dist/* \
  root@properbackup-test-server.softify.com.pl:/opt/properbackup/web/
# Nginx serwuje statycznie — nie wymaga restartu

# Weryfikacja
ssh root@properbackup-test-server.softify.com.pl \
  "docker logs properbackup-buffer 2>&1 | tail -10"
curl -s http://properbackup-test-server.softify.com.pl/api/health
curl -s -o /dev/null -w '%{http_code}' http://properbackup-test-server.softify.com.pl/
```

### 2.4. Automatyczne smoke testy po deploy

Po każdym deploy na serwer testowy, uruchomić minimum:

```bash
# 1. Frontend dostępny
curl -s -o /dev/null -w '%{http_code}' http://properbackup-test-server.softify.com.pl/
# Oczekiwane: 200

# 2. API odpowiada
curl -s http://properbackup-test-server.softify.com.pl/api/health
# Oczekiwane: "ok" lub JSON z status=healthy

# 3. Baza żyje
ssh root@properbackup-test-server.softify.com.pl \
  "docker exec properbackup-db pg_isready -U properbackup"
# Oczekiwane: "accepting connections"

# 4. Brak ERRORów w logach po restarcie
ssh root@properbackup-test-server.softify.com.pl \
  "docker logs properbackup-buffer --since 2m 2>&1 | grep -i error"
# Oczekiwane: pusty output
```

## 3. Czego NIE robić

- **NIE testować tylko lokalnie** — Testcontainers to nie żywy serwer
- **NIE mergować PR bez testu na żywej maszynie** — nawet jeśli CI przechodzi
- **NIE deployować na produkcję bez przejścia testów E2E** — produkcja = klienci + pieniądze
- **NIE ignorować logów po deploy** — zawsze sprawdzić `docker logs` po restarcie
- **NIE pomijać Playwright** — manualne klikanie to nie test, bo nie jest powtarzalny

## 4. Dostęp do serwera

Klucz SSH (`TEST_SERVER_SECRET_KEY`) jest zapisany w sekretach Devina.
Połączenie: `ssh -i <key> root@properbackup-test-server.softify.com.pl`

**Uwaga:** Serwer jest współdzielony — nie kasować danych produkcyjnych/testowych
innych użytkowników. Tworzyć osobne konta testowe z prefixem `test-` lub `e2e-`.
